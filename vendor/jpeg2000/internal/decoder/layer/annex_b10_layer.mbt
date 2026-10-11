///|
// Initialize tag-tree node state arrays (low bounds + known values).
fn init_tag_tree_node_arrays(total_nodes : Int) -> (Array[Int], Array[Int?]) {
  let low : Array[Int] = []
  let known : Array[Int?] = []
  for _ in 0..<total_nodes {
    low.push(0)
    known.push(None)
  }
  (low, known)
}

///|
// Per-subband persistent state for multi-layer tag-tree decoding.
// Tag-tree state (node_low, node_known) persists across layers for
// incremental inclusion and ZBP decoding (T.800-2015 B.10.4.1).
pub(all) struct SubbandLayerStateEntry {
  pub ncbx : Int
  pub ncby : Int
  pub incl_levels : Array[@a8.PktTagTreeLevel]
  pub incl_low : Array[Int]
  pub incl_known : Array[Int?]
  pub zbp_levels : Array[@a8.PktTagTreeLevel]
  pub zbp_low : Array[Int]
  pub zbp_known : Array[Int?]
  pub lblock_by_cb : Array[Int]
  pub cb_included : Array[Bool]
  pub seg_numpasses_by_cb : Array[Int]
  pub seg_maxpasses_by_cb : Array[Int]
  pub seg_count_by_cb : Array[Int]
}

///|
// Accumulated code-block data across all layers for a single code-block.
// Contains the combined codeword bytes, total coding passes, and ZBP
// from the first inclusion layer.
pub(all) struct AccumulatedCB {
  pub subband_index : Int
  pub sb_width : Int
  pub sb_height : Int
  pub cb_x_offset : Int
  pub cb_y_offset : Int
  pub cb_width : Int
  pub cb_height : Int
  pub zero_bit_planes : Int
  pub total_coding_passes : Int
  pub all_segment_lengths : Array[Int]
  pub per_segment_passes : Array[Int]
  pub codeword : Array[Byte]
}

///|
// Spec basis (T.800-2015 B.10.4.1):
// Initialize per-subband tag-tree state for multi-layer parsing.
// T.800-2015 B.7: Tag-tree covers code-blocks that intersect the precinct.
// When precinct straddles CB boundaries, ncbx/ncby computed from pixel
// dimensions differs from actual CB count. Pass explicit ncbx_override/ncby_override
// when the correct count is known from compute_precinct_codeblock_range.
pub fn init_subband_layer_state(
  sw : Int,
  sh : Int,
  cb_w : Int,
  cb_h : Int,
  ncbx_override? : Int = -1,
  ncby_override? : Int = -1,
) -> SubbandLayerStateEntry {
  // T.800-2015 B.7: Use explicit CB counts if provided (for precinct boundaries)
  let ncbx = if ncbx_override > 0 {
    ncbx_override
  } else {
    (sw + cb_w - 1) / cb_w
  }
  let ncby = if ncby_override > 0 {
    ncby_override
  } else {
    (sh + cb_h - 1) / cb_h
  }
  let ncb = ncbx * ncby
  let incl_levels = @a8.pkt_build_tag_tree_levels(ncbx, ncby)
  let total_nodes = incl_levels[incl_levels.length() - 1].offset + 1
  let (incl_low, incl_known) = init_tag_tree_node_arrays(total_nodes)
  let zbp_levels = @a8.pkt_build_tag_tree_levels(ncbx, ncby)
  let (zbp_low, zbp_known) = init_tag_tree_node_arrays(total_nodes)
  let lblock_by_cb : Array[Int] = []
  let cb_included : Array[Bool] = []
  let seg_numpasses_by_cb : Array[Int] = []
  let seg_maxpasses_by_cb : Array[Int] = []
  let seg_count_by_cb : Array[Int] = []
  for _ in 0..<ncb {
    lblock_by_cb.push(3)
    cb_included.push(false)
    seg_numpasses_by_cb.push(0)
    seg_maxpasses_by_cb.push(0)
    seg_count_by_cb.push(0)
  }
  {
    ncbx,
    ncby,
    incl_levels,
    incl_low,
    incl_known,
    zbp_levels,
    zbp_low,
    zbp_known,
    lblock_by_cb,
    cb_included,
    seg_numpasses_by_cb,
    seg_maxpasses_by_cb,
    seg_count_by_cb,
  }
}

///|
// T.800-2015 B.7: Create placeholder state for zero-extent subband/precinct.
// Used when subband or precinct has no code-blocks (degenerate tile boundary).
pub fn init_zero_extent_layer_state() -> SubbandLayerStateEntry {
  init_subband_layer_state(1, 1, 1, 1, ncbx_override=1, ncby_override=1)
}

///|
// Spec basis (T.800-2015 B.10.4.1 / B.10.4.2):
// Parse a single layer's packet header using persistent per-subband state.
// - For layer 0: uses tag-tree inclusion with threshold=1 (T.800-2015 B.10.4.1)
// - For layer N: uses threshold=N+1 for new CBs, 1-bit flag for already-
//   included CBs (T.800-2015 B.10.4.2)
// The tag-tree state arrays (incl_low, incl_known, zbp_low, zbp_known,
// lblock_by_cb, cb_included) are updated in-place.
// sb_bounds: T.800-2015 B.7 absolute subband bounds (tbx0, tby0, tbx1, tby1)
//   for correct CB geometry calculation.
pub fn parse_layer_packet_header(
  data : Bytes,
  layer : Int,
  code_block_style : Int,
  subbands : Array[(Int, Int, Int)],
  sb_states : Array[SubbandLayerStateEntry],
  cb_w : Int,
  cb_h : Int,
  sb_bounds? : Array[(Int, Int, Int, Int)] = [],
) -> Result[(Array[@a8.SubbandCodeBlockInfo], Int), String] {
  if data.length() == 0 {
    return Err("empty packet data")
  }
  // Step 1: Read non-zero packet flag (T.800-2015 B.10.3)
  let nz = @packet.pkt_read_bit(data, 0)
  guard nz is Ok(non_zero_flag) else {
    return Err("multi-layer packet header: bitstream truncated")
  }
  if non_zero_flag == 0 {
    // Empty packet — no code-blocks have contributions in this layer
    let infos : Array[@a8.SubbandCodeBlockInfo] = []
    for sb_idx in 0..<subbands.length() {
      let (sw, sh, si) = subbands[sb_idx]
      if sw <= 0 || sh <= 0 {
        continue
      }
      let st = sb_states[sb_idx]
      // T.800-2015 B.7: Get absolute bounds for correct CB geometry
      let has_bounds = sb_idx < sb_bounds.length()
      let (tbx0, tby0, tbx1, tby1) = if has_bounds {
        sb_bounds[sb_idx]
      } else {
        (0, 0, sw, sh)
      }
      for cby in 0..<st.ncby {
        for cbx in 0..<st.ncbx {
          // T.800-2015 B.7: Use absolute bounds for correct CB geometry
          let (cb_x_off, cb_y_off, actual_w, actual_h) = if has_bounds {
            @precinct.compute_cb_geometry_from_bounds(
              tbx0, tby0, tbx1, tby1, cb_w, cb_h, cbx, cby,
            )
          } else {
            // Fallback: local coordinate calculation
            let x_off = cbx * cb_w
            let y_off = cby * cb_h
            let w = if x_off + cb_w <= sw { cb_w } else { sw - x_off }
            let h = if y_off + cb_h <= sh { cb_h } else { sh - y_off }
            (x_off, y_off, w, h)
          }
          let info : @a8.SubbandCodeBlockInfo = {
            subband_index: si,
            sb_width: sw,
            sb_height: sh,
            cb_x_index: cbx,
            cb_y_index: cby,
            cb_x_offset: cb_x_off,
            cb_y_offset: cb_y_off,
            cb_width: actual_w,
            cb_height: actual_h,
            included: false,
            zero_bit_planes: None,
            coding_passes: None,
            segment_lengths: [],
            segment_passes: [],
          }
          infos.push(info)
        }
      }
    }
    return Ok((infos, 1))
  }
  let mut bit_pos = 1
  let infos : Array[@a8.SubbandCodeBlockInfo] = []
  // T.800-2015 B.10.4.1: threshold = layer + 1 for first-inclusion test
  let threshold = layer + 1
  // Step 2-5: For each subband (T.800-2015 B.10.2 scanning order)
  for sb_idx in 0..<subbands.length() {
    let (sw, sh, si) = subbands[sb_idx]
    if sw <= 0 || sh <= 0 {
      continue
    }
    let st = sb_states[sb_idx]
    // T.800-2015 B.7: Get absolute bounds for correct CB geometry
    let has_bounds = sb_idx < sb_bounds.length()
    let (tbx0, tby0, tbx1, tby1) = if has_bounds {
      sb_bounds[sb_idx]
    } else {
      (0, 0, sw, sh)
    }
    // Process each code-block in raster order (T.800-2015 B.10.2)
    for cby in 0..<st.ncby {
      for cbx in 0..<st.ncbx {
        let cb_idx = cby * st.ncbx + cbx
        // T.800-2015 B.7: Use absolute bounds for correct CB geometry
        let (cb_x_off, cb_y_off, actual_w, actual_h) = if has_bounds {
          @precinct.compute_cb_geometry_from_bounds(
            tbx0, tby0, tbx1, tby1, cb_w, cb_h, cbx, cby,
          )
        } else {
          // Fallback: local coordinate calculation
          let x_off = cbx * cb_w
          let y_off = cby * cb_h
          let w = if x_off + cb_w <= sw { cb_w } else { sw - x_off }
          let h = if y_off + cb_h <= sh { cb_h } else { sh - y_off }
          (x_off, y_off, w, h)
        }
        let mut included_in_this_layer = false
        let mut is_first_inclusion = false
        if st.cb_included[cb_idx] {
          // T.800-2015 B.10.4.2: Already included in a previous layer.
          // Read a single bit: 1 = contributes in this layer, 0 = does not.
          let inc_bit = @packet.pkt_read_bit(data, bit_pos)
          guard inc_bit is Ok(flag) else {
            return Err(
              "multi-layer packet header: subsequent inclusion bit truncated",
            )
          }
          bit_pos += 1
          included_in_this_layer = flag == 1
        } else {
          // T.800-2015 B.10.4.1: Not yet included — use tag tree.
          let inc = @a8.pkt_tag_tree_decode_member(
            st.incl_levels,
            st.incl_low,
            st.incl_known,
            cbx,
            cby,
            threshold,
            data,
            bit_pos,
          )
          guard inc is Ok((incl, inc_next_pos)) else {
            return Err(
              "multi-layer packet header: inclusion tag-tree decode failed",
            )
          }
          bit_pos = inc_next_pos
          included_in_this_layer = incl
          is_first_inclusion = incl
        }
        if !included_in_this_layer {
          let info : @a8.SubbandCodeBlockInfo = {
            subband_index: si,
            sb_width: sw,
            sb_height: sh,
            cb_x_index: cbx,
            cb_y_index: cby,
            cb_x_offset: cb_x_off,
            cb_y_offset: cb_y_off,
            cb_width: actual_w,
            cb_height: actual_h,
            included: false,
            zero_bit_planes: None,
            coding_passes: None,
            segment_lengths: [],
            segment_passes: [],
          }
          infos.push(info)
          continue
        }
        // Mark as included for future layers
        st.cb_included[cb_idx] = true
        // T.800-2015 B.10.5: ZBP — only for first inclusion
        let zbp = if is_first_inclusion {
          let zbp_v = @a8.pkt_tag_tree_decode_value(
            st.zbp_levels,
            st.zbp_low,
            st.zbp_known,
            cbx,
            cby,
            data,
            bit_pos,
          )
          guard zbp_v is Ok((zbp_val, zbp_next_pos)) else {
            return Err("multi-layer packet header: ZBP tag-tree decode failed")
          }
          bit_pos = zbp_next_pos
          zbp_val
        } else {
          -1 // Sentinel: ZBP already known from first inclusion
        }
        // T.800-2015 B.10.6: Number of coding passes (Table B.4)
        let pass_v = @packet.pkt_decode_num_coding_passes(data, bit_pos)
        guard pass_v is Ok((passes, next_pos)) else {
          return Err("multi-layer packet header: coding passes decode failed")
        }
        bit_pos = next_pos
        // T.800-2015 B.10.7: Lblock increment and segment lengths
        let added_passes = @a8.split_packet_passes_and_advance_segment_state(
          code_block_style,
          passes,
          st.seg_numpasses_by_cb,
          st.seg_maxpasses_by_cb,
          st.seg_count_by_cb,
          cb_idx,
        )
        if added_passes.length() == 0 {
          return Err("multi-layer packet header: invalid segment pass split")
        }
        let mut lblock = st.lblock_by_cb[cb_idx]
        let mut lblock_inc = 0
        while true {
          let lb = @packet.pkt_read_bit(data, bit_pos)
          guard lb is Ok(lbit) else {
            return Err("multi-layer packet header: Lblock increment truncated")
          }
          bit_pos += 1
          if lbit == 0 {
            break
          }
          lblock_inc += 1
        }
        lblock += lblock_inc
        let segment_lengths : Array[Int] = []
        for seg_passes in added_passes {
          let seg_bits = lblock + @math.floor_log2(seg_passes)
          let seg_v = @packet.pkt_read_bits(data, bit_pos, seg_bits)
          guard seg_v is Ok((seg_len, next_seg_pos)) else {
            return Err("multi-layer packet header: segment length truncated")
          }
          bit_pos = next_seg_pos
          segment_lengths.push(seg_len)
        }
        st.lblock_by_cb[cb_idx] = lblock
        let info : @a8.SubbandCodeBlockInfo = {
          subband_index: si,
          sb_width: sw,
          sb_height: sh,
          cb_x_index: cbx,
          cb_y_index: cby,
          cb_x_offset: cb_x_off,
          cb_y_offset: cb_y_off,
          cb_width: actual_w,
          cb_height: actual_h,
          included: true,
          zero_bit_planes: if zbp >= 0 {
            Some(zbp)
          } else {
            None
          },
          coding_passes: Some(passes),
          segment_lengths,
          segment_passes: added_passes,
        }
        infos.push(info)
      }
    }
  }
  Ok((infos, bit_pos))
}

///|
// Spec basis (T.800-2015 B.10 / B.5 / B.6):
// Split SOD payload into per-component per-resolution accumulated code-block
// data, correctly handling multi-layer packet parsing with persistent tag-tree
// state.
//
// For multi-layer codestreams, the tag-tree inclusion state (T.800-2015
// B.10.4.1) and Lblock state persist across layers within each resolution.
// Code-block contributions are accumulated: codeword bytes are concatenated,
// coding passes are summed, and ZBP is from first inclusion.
//
// T.800-2015 B.6: When uses_precincts is true, precinct_size_bytes contains
// one byte per resolution encoding (PPy << 4) | PPx. Each precinct has its
// own tag-tree state.
//
// Returns [component][resolution] -> Array of AccumulatedCB.

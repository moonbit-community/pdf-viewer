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
pub(all) struct SubbandCodeBlockInfo {
  pub subband_index : Int // 0=HL, 1=LH, 2=HH (or 0=LL for res 0)
  pub sb_width : Int // subband pixel width
  pub sb_height : Int // subband pixel height
  pub cb_x_index : Int // T.800-2015 B.7: CB grid index m (relative to subband)
  pub cb_y_index : Int // T.800-2015 B.7: CB grid index n (relative to subband)
  pub cb_x_offset : Int // code-block x offset within subband (pixels)
  pub cb_y_offset : Int // code-block y offset within subband (pixels)
  pub cb_width : Int // actual code-block width (may be smaller at edge)
  pub cb_height : Int // actual code-block height (may be smaller at edge)
  pub included : Bool
  pub zero_bit_planes : Int?
  pub coding_passes : Int?
  pub segment_lengths : Array[Int]
  pub segment_passes : Array[Int]
}

///|
// T.800-2015 B.10.6:
// Determine max passes for the current segment based on code-block style.
pub fn codeblock_segment_maxpasses(
  code_block_style : Int,
  first_segment : Bool,
  prev_maxpasses : Int,
) -> Int {
  if (code_block_style & 0x40) != 0 {
    // T.814 Annex B.2/B.3: HT segments alternate cleanup(1) and refinement(2).
    if first_segment || prev_maxpasses == 2 {
      return 1
    }
    return 2
  }
  if (code_block_style & 0x04) != 0 {
    // TERMALL: one pass per segment
    return 1
  }
  if (code_block_style & 0x01) != 0 {
    // BYPASS/LAZY: first segment=10, then 2/1 alternating
    if first_segment {
      return 10
    }
    if prev_maxpasses == 1 || prev_maxpasses == 10 {
      return 2
    }
    return 1
  }
  // Default non-terminated style
  109
}

///|
// T.800-2015 B.10.7:
// Split added coding passes for one packet contribution into per-segment
// pass counts while carrying segment state across packets/layers.
pub fn split_packet_passes_and_advance_segment_state(
  code_block_style : Int,
  coding_passes : Int,
  seg_numpasses_by_cb : Array[Int],
  seg_maxpasses_by_cb : Array[Int],
  seg_count_by_cb : Array[Int],
  cb_idx : Int,
) -> Array[Int] {
  let out : Array[Int] = []
  if coding_passes <= 0 ||
    cb_idx < 0 ||
    cb_idx >= seg_numpasses_by_cb.length() ||
    cb_idx >= seg_maxpasses_by_cb.length() ||
    cb_idx >= seg_count_by_cb.length() {
    return out
  }
  let mut seg_numpasses = seg_numpasses_by_cb[cb_idx]
  let mut seg_maxpasses = seg_maxpasses_by_cb[cb_idx]
  let mut seg_count = seg_count_by_cb[cb_idx]
  if seg_count <= 0 || seg_maxpasses <= 0 {
    seg_maxpasses = codeblock_segment_maxpasses(code_block_style, true, 0)
    seg_numpasses = 0
    seg_count = 1
  } else if seg_numpasses >= seg_maxpasses {
    seg_maxpasses = codeblock_segment_maxpasses(
      code_block_style, false, seg_maxpasses,
    )
    seg_numpasses = 0
    seg_count += 1
  }
  let mut remaining = coding_passes
  while remaining > 0 {
    let room = seg_maxpasses - seg_numpasses
    if room <= 0 {
      seg_maxpasses = codeblock_segment_maxpasses(
        code_block_style, false, seg_maxpasses,
      )
      seg_numpasses = 0
      seg_count += 1
      continue
    }
    let add = if room < remaining { room } else { remaining }
    out.push(add)
    seg_numpasses += add
    remaining -= add
    if remaining > 0 {
      seg_maxpasses = codeblock_segment_maxpasses(
        code_block_style, false, seg_maxpasses,
      )
      seg_numpasses = 0
      seg_count += 1
    }
  }
  seg_numpasses_by_cb[cb_idx] = seg_numpasses
  seg_maxpasses_by_cb[cb_idx] = seg_maxpasses
  seg_count_by_cb[cb_idx] = seg_count
  out
}

///|
// Spec basis (T.800-2015 B.10.4.1):
// Tag-tree level metadata for multi-codeblock packet header parsing.
pub(all) struct PktTagTreeLevel {
  pub width : Int
  pub height : Int
  pub offset : Int
}

///|
// Spec basis (T.800-2015 B.10.4.1):
// Build tag-tree level hierarchy for a code-block grid of given dimensions.
pub fn pkt_build_tag_tree_levels(
  width : Int,
  height : Int,
) -> Array[PktTagTreeLevel] {
  let levels : Array[PktTagTreeLevel] = []
  let mut w = width
  let mut h = height
  let mut offset = 0
  while true {
    levels.push({ width: w, height: h, offset, })
    if w == 1 && h == 1 {
      break
    }
    offset += w * h
    w = (w + 1) / 2
    h = (h + 1) / 2
  }
  levels
}

///|
// Spec basis (T.800-2015 B.10.4.1):
// Decode a single tag-tree member (inclusion test against threshold).
// Returns (included, next_bit_pos).
pub fn pkt_tag_tree_decode_member(
  levels : Array[PktTagTreeLevel],
  node_low : Array[Int],
  node_known : Array[Int?],
  x : Int,
  y : Int,
  threshold : Int,
  data : Bytes,
  start_bit_pos : Int,
) -> Result[(Bool, Int), String] {
  let root_level = levels.length() - 1
  let path : Array[Int] = []
  let mut px = x
  let mut py = y
  let mut level = 0
  while level < levels.length() {
    let meta = levels[level]
    let idx = meta.offset + py * meta.width + px
    path.push(idx)
    if level == root_level {
      break
    }
    px = px / 2
    py = py / 2
    level = level + 1
  }
  let mut bit_pos = start_bit_pos
  let mut low = 0
  let mut rev = path.length() - 1
  while rev >= 0 {
    let idx = path[rev]
    if node_low[idx] < low {
      node_low[idx] = low
    } else {
      low = node_low[idx]
    }
    while node_low[idx] < threshold && node_known[idx] is None {
      let bit = @packet.pkt_read_bit(data, bit_pos)
      guard bit is Ok(v) else { return Err("tag-tree bitstream truncated") }
      bit_pos += 1
      if v == 0 {
        node_low[idx] += 1
      } else {
        node_known[idx] = Some(node_low[idx])
      }
    }
    if node_known[idx] is Some(v) {
      low = v
    } else {
      low = node_low[idx]
    }
    rev = rev - 1
  }
  Ok((low < threshold, bit_pos))
}

///|
// Spec basis (T.800-2015 B.10.5):
// Decode a tag-tree value (ZBP) by incrementally testing thresholds.
// Returns (value, next_bit_pos).
pub fn pkt_tag_tree_decode_value(
  levels : Array[PktTagTreeLevel],
  node_low : Array[Int],
  node_known : Array[Int?],
  x : Int,
  y : Int,
  data : Bytes,
  start_bit_pos : Int,
) -> Result[(Int, Int), String] {
  let mut bit_pos = start_bit_pos
  let mut threshold = 1
  while threshold <= 128 {
    let step = pkt_tag_tree_decode_member(
      levels, node_low, node_known, x, y, threshold, data, bit_pos,
    )
    guard step is Ok((included, next_pos)) else {
      return Err("failed to decode tag-tree value")
    }
    bit_pos = next_pos
    if included {
      return Ok((threshold - 1, bit_pos))
    }
    threshold += 1
  }
  Err("tag-tree value exceeds supported range")
}

///|
// Spec basis (T.800-2015 B.10.4.1 / B.10.5):
// Parse a packet header with per-subband tag-trees supporting multi-codeblock
// subbands. T.800-2015 B.10.4.1: "There is one tag tree per subband for
// inclusion information and one tag tree per subband for zero bit-plane
// information."
//
// Parameters:
//   subbands: (sb_width, sb_height, subband_index) per subband
//   cb_width, cb_height: nominal code-block dimensions (from COD)
//   code_block_style: COD code-block style flags
//
// Returns (code_block_infos, consumed_bits).
pub fn parse_per_subband_packet_header(
  data : Bytes,
  subbands : Array[(Int, Int, Int)],
  code_block_style : Int,
  cb_width? : Int = 64,
  cb_height? : Int = 64,
) -> Result[(Array[SubbandCodeBlockInfo], Int), String] {
  if data.length() == 0 {
    return Err("empty packet data")
  }
  // Step 1: Read non-zero packet flag (T.800-2015 B.10.3)
  let nz = @packet.pkt_read_bit(data, 0)
  guard nz is Ok(non_zero_flag) else {
    return Err("packet header bitstream truncated")
  }
  if non_zero_flag == 0 {
    // Empty packet - no code-blocks have contributions
    let infos : Array[SubbandCodeBlockInfo] = []
    for sb in subbands {
      let (sw, sh, si) = sb
      if sw > 0 && sh > 0 {
        infos.push({
          subband_index: si,
          sb_width: sw,
          sb_height: sh,
          cb_x_index: 0,
          cb_y_index: 0,
          cb_x_offset: 0,
          cb_y_offset: 0,
          cb_width: sw,
          cb_height: sh,
          included: false,
          zero_bit_planes: None,
          coding_passes: None,
          segment_lengths: [],
          segment_passes: [],
        })
      }
    }
    return Ok((infos, 1))
  }
  let mut bit_pos = 1
  let infos : Array[SubbandCodeBlockInfo] = []
  // Step 2-5: For each subband (T.800-2015 B.10.2 scanning order)
  for sb in subbands {
    let (sw, sh, si) = sb
    if sw <= 0 || sh <= 0 {
      continue
    }
    // Compute code-block grid dimensions (T.800-2015 B.7)
    let ncbx = (sw + cb_width - 1) / cb_width
    let ncby = (sh + cb_height - 1) / cb_height
    let ncb = ncbx * ncby
    // Build per-subband tag-trees (T.800-2015 B.10.4.1)
    let incl_levels = pkt_build_tag_tree_levels(ncbx, ncby)
    let total_nodes = incl_levels[incl_levels.length() - 1].offset + 1
    let (incl_low, incl_known) = init_tag_tree_node_arrays(total_nodes)
    let zbp_levels = pkt_build_tag_tree_levels(ncbx, ncby)
    let (zbp_low, zbp_known) = init_tag_tree_node_arrays(total_nodes)
    let lblock_by_cb : Array[Int] = []
    let seg_numpasses_by_cb : Array[Int] = []
    let seg_maxpasses_by_cb : Array[Int] = []
    let seg_count_by_cb : Array[Int] = []
    for _ in 0..<ncb {
      lblock_by_cb.push(3)
      seg_numpasses_by_cb.push(0)
      seg_maxpasses_by_cb.push(0)
      seg_count_by_cb.push(0)
    }
    // Process each code-block in raster order (T.800-2015 B.10.2)
    for cby in 0..<ncby {
      for cbx in 0..<ncbx {
        let cb_idx = cby * ncbx + cbx
        let cb_x_off = cbx * cb_width
        let cb_y_off = cby * cb_height
        let actual_w = if cb_x_off + cb_width <= sw {
          cb_width
        } else {
          sw - cb_x_off
        }
        let actual_h = if cb_y_off + cb_height <= sh {
          cb_height
        } else {
          sh - cb_y_off
        }
        // T.800-2015 B.10.4.1: Inclusion via tag-tree (threshold = layer + 1)
        // For first packet (layer 0), threshold = 1
        let inc = pkt_tag_tree_decode_member(
          incl_levels, incl_low, incl_known, cbx, cby, 1, data, bit_pos,
        )
        guard inc is Ok((included, inc_next_pos)) else {
          return Err(
            "per-subband packet header: inclusion tag-tree decode failed",
          )
        }
        bit_pos = inc_next_pos
        if !included {
          infos.push({
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
          })
          continue
        }
        // T.800-2015 B.10.5: Zero bit-plane information via tag-tree
        let zbp_v = pkt_tag_tree_decode_value(
          zbp_levels, zbp_low, zbp_known, cbx, cby, data, bit_pos,
        )
        guard zbp_v is Ok((zbp, zbp_next_pos)) else {
          return Err("per-subband packet header: ZBP tag-tree decode failed")
        }
        bit_pos = zbp_next_pos
        // T.800-2015 B.10.6: Number of coding passes (Table B.4)
        let pass_v = @packet.pkt_decode_num_coding_passes(data, bit_pos)
        guard pass_v is Ok((passes, next_pos)) else {
          return Err("per-subband packet header: coding passes decode failed")
        }
        bit_pos = next_pos
        // T.800-2015 B.10.7: Lblock increment and segment lengths
        let added_passes = split_packet_passes_and_advance_segment_state(
          code_block_style, passes, seg_numpasses_by_cb, seg_maxpasses_by_cb, seg_count_by_cb,
          cb_idx,
        )
        if added_passes.length() == 0 {
          return Err("per-subband packet header: invalid segment pass split")
        }
        let mut lblock = lblock_by_cb[cb_idx]
        while true {
          let lb = @packet.pkt_read_bit(data, bit_pos)
          guard lb is Ok(lbit) else {
            return Err("per-subband packet header: Lblock increment truncated")
          }
          bit_pos += 1
          if lbit == 0 {
            break
          }
          lblock += 1
        }
        let segment_lengths : Array[Int] = []
        for seg_passes in added_passes {
          let seg_bits = lblock + @math.floor_log2(seg_passes)
          let seg_v = @packet.pkt_read_bits(data, bit_pos, seg_bits)
          guard seg_v is Ok((seg_len, next_seg_pos)) else {
            return Err("per-subband packet header: segment length truncated")
          }
          bit_pos = next_seg_pos
          segment_lengths.push(seg_len)
        }
        lblock_by_cb[cb_idx] = lblock
        infos.push({
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
          zero_bit_planes: Some(zbp),
          coding_passes: Some(passes),
          segment_lengths,
          segment_passes: added_passes,
        })
      }
    }
  }
  Ok((infos, bit_pos))
}

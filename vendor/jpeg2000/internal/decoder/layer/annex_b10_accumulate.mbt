///|
pub fn split_sod_accumulate_multi_layer(
  payload : Bytes,
  c0_width : Int,
  c0_height : Int,
  decomp_levels : Int,
  num_components : Int,
  num_layers : Int,
  progression : Int,
  code_block_style : Int,
  cb_width? : Int = 64,
  cb_height? : Int = 64,
  comp_widths? : Array[Int] = [],
  comp_heights? : Array[Int] = [],
  comp_decomp_levels? : Array[Int] = [],
  comp_cb_widths? : Array[Int] = [],
  comp_cb_heights? : Array[Int] = [],
  comp_xrsizs? : Array[Int] = [],
  comp_yrsizs? : Array[Int] = [],
  comp_tcx0s? : Array[Int] = [],
  comp_tcy0s? : Array[Int] = [],
  comp_code_block_styles? : Array[Int] = [],
  comp_precinct_size_bytes? : Array[Array[Int]] = [],
  precinct_size_bytes? : Array[Int] = [],
  tcx0? : Int = 0,
  tcy0? : Int = 0,
  uses_sop? : Bool = false,
  uses_eph? : Bool = false,
  poc_entries? : Array[@core.PocMetadata] = [],
  relocated_packet_headers? : Bytes = b"",
  packet_audit? : Bool = false,
  audit_label? : String = "",
  packet_audit_limit? : Int = 300,
) -> Result[(Array[Array[Array[AccumulatedCB]]], Int), String] {
  // T.800-2015 A.6.2: Per-component decomposition levels and code-block sizes from COC
  let comp_num_resolutions : Array[Int] = []
  let comp_cbw : Array[Int] = []
  let comp_cbh : Array[Int] = []
  let mut max_resolutions = 0
  for c in 0..<num_components {
    let c_decomp = if c < comp_decomp_levels.length() {
      comp_decomp_levels[c]
    } else {
      decomp_levels
    }
    let c_num_res = c_decomp + 1
    comp_num_resolutions.push(c_num_res)
    if c_num_res > max_resolutions {
      max_resolutions = c_num_res
    }
    // T.800-2015 A.6.2: Per-component code-block sizes from COC
    let c_cbw = if c < comp_cb_widths.length() {
      comp_cb_widths[c]
    } else {
      cb_width
    }
    let c_cbh = if c < comp_cb_heights.length() {
      comp_cb_heights[c]
    } else {
      cb_height
    }
    comp_cbw.push(c_cbw)
    comp_cbh.push(c_cbh)
  }
  let num_resolutions = max_resolutions
  // Pre-compute subbands for each component and resolution
  // T.800-2015 B.3/B.5: each component may have different dimensions due to XRsiz/YRsiz.
  // Subband dimensions depend on absolute tile-component coordinates (T.800-2015 B.5).
  let comp_resolution_subbands : Array[Array[Array[(Int, Int, Int)]]] = []
  // T.800-2015 B.5 Eq. B-15: Absolute subband bounds for precinct calculations
  // comp_subband_bounds[c][r][sb] = (tbx0, tby0, tbx1, tby1)
  let comp_subband_bounds : Array[Array[Array[(Int, Int, Int, Int)]]] = []
  for c in 0..<num_components {
    let cw = if c < comp_widths.length() { comp_widths[c] } else { c0_width }
    let ch = if c < comp_heights.length() { comp_heights[c] } else { c0_height }
    let c_tcx0 = if c < comp_tcx0s.length() { comp_tcx0s[c] } else { tcx0 }
    let c_tcy0 = if c < comp_tcy0s.length() { comp_tcy0s[c] } else { tcy0 }
    // T.800-2015 A.6.2: Use per-component decomposition levels
    let c_decomp = if c < comp_decomp_levels.length() {
      comp_decomp_levels[c]
    } else {
      decomp_levels
    }
    let c_num_res = c_decomp + 1
    // Compute absolute tile-component bounds (tcx0, tcy0, tcx1, tcy1)
    let tcx1 = c_tcx0 + cw
    let tcy1 = c_tcy0 + ch
    let res_subbands : Array[Array[(Int, Int, Int)]] = []
    let res_sb_bounds : Array[Array[(Int, Int, Int, Int)]] = []
    for res in 0..<c_num_res {
      if res == 0 {
        // T.800-2015 B.5: LL at deepest level has nb = c_decomp
        let nb = c_decomp
        let (tbx0_ll, tby0_ll, tbx1_ll, tby1_ll) = @subband.subband_bounds(
          c_tcx0, c_tcy0, tcx1, tcy1, nb, 0,
        )
        let ll_w = tbx1_ll - tbx0_ll
        let ll_h = tby1_ll - tby0_ll
        res_subbands.push([(ll_w, ll_h, 0)])
        res_sb_bounds.push([(tbx0_ll, tby0_ll, tbx1_ll, tby1_ll)])
      } else {
        // T.800-2015 B.5: Detail subbands at res have nb = c_decomp - res + 1
        let nb = c_decomp - res + 1
        let (tbx0_hl, tby0_hl, tbx1_hl, tby1_hl) = @subband.subband_bounds(
          c_tcx0, c_tcy0, tcx1, tcy1, nb, 1,
        )
        let (tbx0_lh, tby0_lh, tbx1_lh, tby1_lh) = @subband.subband_bounds(
          c_tcx0, c_tcy0, tcx1, tcy1, nb, 2,
        )
        let (tbx0_hh, tby0_hh, tbx1_hh, tby1_hh) = @subband.subband_bounds(
          c_tcx0, c_tcy0, tcx1, tcy1, nb, 3,
        )
        let hl_w = tbx1_hl - tbx0_hl
        let hl_h = tby1_hl - tby0_hl
        let lh_w = tbx1_lh - tbx0_lh
        let lh_h = tby1_lh - tby0_lh
        let hh_w = tbx1_hh - tbx0_hh
        let hh_h = tby1_hh - tby0_hh
        res_subbands.push([(hl_w, hl_h, 0), (lh_w, lh_h, 1), (hh_w, hh_h, 2)])
        res_sb_bounds.push([
          (tbx0_hl, tby0_hl, tbx1_hl, tby1_hl),
          (tbx0_lh, tby0_lh, tbx1_lh, tby1_lh),
          (tbx0_hh, tby0_hh, tbx1_hh, tby1_hh),
        ])
      }
    }
    comp_resolution_subbands.push(res_subbands)
    comp_subband_bounds.push(res_sb_bounds)
  }
  // T.800-2015 B.5/B.6: Compute resolution bounds and precinct counts.
  // comp_res_bounds[c][r] = (trx0, try0, trx1, try1) absolute coordinates
  // comp_res_dims[c][r] = (width, height) dimensions
  // comp_res_num_precincts[c][r] = (npx, npy) precinct grid
  let comp_res_bounds : Array[Array[(Int, Int, Int, Int)]] = []
  let comp_res_dims : Array[Array[(Int, Int)]] = []
  let comp_res_num_precincts : Array[Array[(Int, Int)]] = []
  for c in 0..<num_components {
    let cw = if c < comp_widths.length() { comp_widths[c] } else { c0_width }
    let ch = if c < comp_heights.length() { comp_heights[c] } else { c0_height }
    let c_tcx0 = if c < comp_tcx0s.length() { comp_tcx0s[c] } else { tcx0 }
    let c_tcy0 = if c < comp_tcy0s.length() { comp_tcy0s[c] } else { tcy0 }
    let c_precinct_size_bytes : Array[Int] = if c <
      comp_precinct_size_bytes.length() {
      comp_precinct_size_bytes[c]
    } else {
      precinct_size_bytes
    }
    let c_decomp = if c < comp_decomp_levels.length() {
      comp_decomp_levels[c]
    } else {
      decomp_levels
    }
    let c_num_res = c_decomp + 1
    // T.800-2015 B.5: Compute absolute resolution bounds
    let bounds = @subband.resolution_bounds(cw, ch, c_tcx0, c_tcy0, c_decomp)
    let res_bounds : Array[(Int, Int, Int, Int)] = []
    let res_dims : Array[(Int, Int)] = []
    let res_nprec : Array[(Int, Int)] = []
    for r in 0..<c_num_res {
      let (trx0, try0, trx1, try1) = bounds[r]
      res_bounds.push((trx0, try0, trx1, try1))
      let rw = trx1 - trx0
      let rh = try1 - try0
      res_dims.push((rw, rh))
      // T.800-2015 B.6: Compute precinct counts using absolute coordinates
      let (ppx_exp, ppy_exp) = @precinct.get_precinct_exponents(
        c_precinct_size_bytes, r,
      )
      let (npx, npy) = @precinct.compute_num_precincts_with_origin(
        trx0, try0, trx1, try1, ppx_exp, ppy_exp,
      )
      res_nprec.push((npx, npy))
    }
    comp_res_bounds.push(res_bounds)
    comp_res_dims.push(res_dims)
    comp_res_num_precincts.push(res_nprec)
  }
  // Initialize per-component per-resolution per-precinct per-subband tag-tree state
  // T.800-2015 B.7: Each precinct has independent tag trees.
  // Structure: comp_res_prec_sb_states[comp][res][precinct_flat][subband]
  // precinct_flat = py * npx + px
  let comp_res_prec_sb_states : Array[
    Array[Array[Array[SubbandLayerStateEntry]]],
  ] = []
  // Precinct-local CB indexing metadata:
  // comp_res_prec_sb_offsets[comp][res][prec][sb] = start offset in CB arrays
  let comp_res_prec_sb_offsets : Array[Array[Array[Array[Int]]]] = []
  // comp_res_prec_sb_ncbx[comp][res][prec][sb] = subband-global ncbx for CB flattening
  let comp_res_prec_sb_ncbx : Array[Array[Array[Array[Int]]]] = []
  // Per-component per-resolution unique global CB count.
  let comp_res_cb_counts : Array[Array[Int]] = []
  for c in 0..<num_components {
    let comp_states : Array[Array[Array[SubbandLayerStateEntry]]] = []
    let comp_offsets : Array[Array[Array[Int]]] = []
    let comp_ncbx : Array[Array[Array[Int]]] = []
    let comp_counts : Array[Int] = []
    let c_num_res = comp_num_resolutions[c]
    let c_cbw = comp_cbw[c]
    let c_cbh = comp_cbh[c]
    for res in 0..<c_num_res {
      let (npx, npy) = comp_res_num_precincts[c][res]
      let num_prec = npx * npy
      let prec_states : Array[Array[SubbandLayerStateEntry]] = []
      let prec_offsets : Array[Array[Int]] = []
      let prec_ncbx : Array[Array[Int]] = []
      let (ppx_exp, ppy_exp) = @precinct.get_component_precinct_exponents(
        precinct_size_bytes, comp_precinct_size_bytes, c, res,
      )
      let c_eff_cbw = @precinct.effective_cb_dim_for_res(c_cbw, ppx_exp, res)
      let c_eff_cbh = @precinct.effective_cb_dim_for_res(c_cbh, ppy_exp, res)
      let subbands = comp_resolution_subbands[c][res]
      let sb_bounds = comp_subband_bounds[c][res]
      let sb_global_offsets : Array[Int] = []
      let sb_global_ncbx : Array[Int] = []
      let mut res_cb_count = 0
      for sb_idx in 0..<subbands.length() {
        sb_global_offsets.push(res_cb_count)
        let (sw, sh, _) = subbands[sb_idx]
        if sw > 0 && sh > 0 {
          let (tbx0, tby0, tbx1, tby1) = sb_bounds[sb_idx]
          let (global_ncbx, global_ncby) = @precinct.compute_cb_count_from_bounds(
            tbx0, tby0, tbx1, tby1, c_eff_cbw, c_eff_cbh,
          )
          sb_global_ncbx.push(global_ncbx)
          res_cb_count += global_ncbx * global_ncby
        } else {
          sb_global_ncbx.push(0)
        }
      }
      for prec_idx in 0..<num_prec {
        let px = prec_idx % npx
        let py = prec_idx / npx
        let sb_states : Array[SubbandLayerStateEntry] = []
        let sb_offsets : Array[Int] = []
        let sb_ncbx : Array[Int] = []
        for sb_idx in 0..<subbands.length() {
          let (sw, sh, _) = subbands[sb_idx]
          let sb_base_offset = sb_global_offsets[sb_idx]
          let sb_flat_ncbx = sb_global_ncbx[sb_idx]
          if sw > 0 && sh > 0 {
            // T.800-2015 B.5/B.7: Use absolute subband bounds for precinct calculation
            let (trx0, try0, _, _) = comp_res_bounds[c][res]
            let (tbx0, tby0, tbx1, tby1) = sb_bounds[sb_idx]
            let (ncbx, ncby, cb_x_start, cb_y_start, prec_pw, prec_ph) = @precinct.compute_precinct_codeblock_range_abs(
              trx0, try0, tbx0, tby0, tbx1, tby1, c_eff_cbw, c_eff_cbh, px, py, ppx_exp,
              ppy_exp, res,
            )
            sb_offsets.push(
              sb_base_offset + cb_y_start * sb_flat_ncbx + cb_x_start,
            )
            sb_ncbx.push(sb_flat_ncbx)
            if ncbx > 0 && ncby > 0 {
              // T.800-2015 B.7: Use actual CB counts for tag-tree, not pixel-derived
              // When precinct straddles CB boundaries, pixel dimensions give wrong count
              sb_states.push(
                init_subband_layer_state(
                  prec_pw,
                  prec_ph,
                  c_eff_cbw,
                  c_eff_cbh,
                  ncbx_override=ncbx,
                  ncby_override=ncby,
                ),
              )
            } else {
              sb_states.push(init_zero_extent_layer_state())
            }
          } else {
            sb_offsets.push(sb_base_offset)
            sb_ncbx.push(0)
            sb_states.push(init_zero_extent_layer_state())
          }
        }
        prec_states.push(sb_states)
        prec_offsets.push(sb_offsets)
        prec_ncbx.push(sb_ncbx)
      }
      // Handle case where num_prec == 0 (zero-extent resolution)
      if num_prec == 0 {
        prec_states.push([])
        prec_offsets.push([])
        prec_ncbx.push([])
      }
      comp_states.push(prec_states)
      comp_offsets.push(prec_offsets)
      comp_ncbx.push(prec_ncbx)
      comp_counts.push(res_cb_count)
    }
    comp_res_prec_sb_states.push(comp_states)
    comp_res_prec_sb_offsets.push(comp_offsets)
    comp_res_prec_sb_ncbx.push(comp_ncbx)
    comp_res_cb_counts.push(comp_counts)
  }
  // Per-component per-resolution per-CB accumulated data
  // [comp][resolution][cb_flat_index]
  let comp_res_cb_zbp : Array[Array[Array[Int]]] = []
  let comp_res_cb_passes : Array[Array[Array[Int]]] = []
  let comp_res_cb_seglens : Array[Array[Array[Array[Int]]]] = []
  let comp_res_cb_seg_passes : Array[Array[Array[Array[Int]]]] = []
  let comp_res_cb_codeword : Array[Array[Array[Array[Byte]]]] = []
  let comp_res_cb_geom : Array[
    Array[Array[(Int, Int, Int, Int, Int, Int, Int)]],
  ] = []
  let comp_res_cb_geom_set : Array[Array[Array[Bool]]] = []
  for c_alloc in 0..<num_components {
    let c_zbp : Array[Array[Int]] = []
    let c_passes : Array[Array[Int]] = []
    let c_seglens : Array[Array[Array[Int]]] = []
    let c_seg_passes : Array[Array[Array[Int]]] = []
    let c_codeword : Array[Array[Array[Byte]]] = []
    let c_geom : Array[Array[(Int, Int, Int, Int, Int, Int, Int)]] = []
    let c_gset : Array[Array[Bool]] = []
    // T.800-2015 A.6.2: Use per-component resolution count
    let c_alloc_num_res = comp_num_resolutions[c_alloc]
    for res in 0..<c_alloc_num_res {
      let n = if res < comp_res_cb_counts[c_alloc].length() {
        comp_res_cb_counts[c_alloc][res]
      } else {
        0
      }
      let zbps : Array[Int] = []
      let passes : Array[Int] = []
      let seglens : Array[Array[Int]] = []
      let seg_passes : Array[Array[Int]] = []
      let codewords : Array[Array[Byte]] = []
      let geoms : Array[(Int, Int, Int, Int, Int, Int, Int)] = []
      let flags : Array[Bool] = []
      for _ in 0..<n {
        zbps.push(0)
        passes.push(0)
        seglens.push([])
        seg_passes.push([])
        codewords.push([])
        geoms.push((0, 0, 0, 0, 0, 0, 0))
        flags.push(false)
      }
      c_zbp.push(zbps)
      c_passes.push(passes)
      c_seglens.push(seglens)
      c_seg_passes.push(seg_passes)
      c_codeword.push(codewords)
      c_geom.push(geoms)
      c_gset.push(flags)
    }
    comp_res_cb_zbp.push(c_zbp)
    comp_res_cb_passes.push(c_passes)
    comp_res_cb_seglens.push(c_seglens)
    comp_res_cb_seg_passes.push(c_seg_passes)
    comp_res_cb_codeword.push(c_codeword)
    comp_res_cb_geom.push(c_geom)
    comp_res_cb_geom_set.push(c_gset)
  }
  let poc_order_entries : Array[(Int, Int, Int, Int, Int, Int)] = []
  for entry in poc_entries {
    poc_order_entries.push(
      (
        entry.rspoc,
        entry.cspoc,
        entry.lyepoc,
        entry.repoc,
        entry.cepoc,
        entry.ppoc,
      ),
    )
  }
  let packet_order = @precinct.build_packet_order_with_poc(
    progression,
    num_layers,
    num_resolutions,
    num_components,
    comp_num_resolutions,
    comp_decomp_levels,
    comp_res_num_precincts,
    comp_res_bounds,
    comp_precinct_size_bytes,
    tcx0,
    tcy0,
    poc_order_entries,
    comp_xrsiz=comp_xrsizs,
    comp_yrsiz=comp_yrsizs,
  )
  // Find the next SOP marker start offset (FF91 0004 ...) at/after `start`.
  // Returns payload.length() when no further SOP is found.
  fn find_next_sop_offset(
    payload : Bytes,
    start : Int,
    expected_nsop : Int,
  ) -> Int {
    if start < 0 || start >= payload.length() {
      return payload.length()
    }
    let mut i = start
    while i + 6 <= payload.length() {
      if payload[i].to_int() == 0xFF &&
        payload[i + 1].to_int() == 0x91 &&
        payload[i + 2].to_int() == 0x00 &&
        payload[i + 3].to_int() == 0x04 {
        if expected_nsop >= 0 {
          let nsop = (payload[i + 4].to_int() << 8) | payload[i + 5].to_int()
          if nsop != expected_nsop {
            i += 1
            continue
          }
        }
        return i
      }
      i += 1
    }
    payload.length()
  }
  // Find the next EPH marker (FF92) at/after `start` in relocated header stream.
  // Returns headers.length() when no further EPH is found.
  fn find_next_eph_offset(headers : Bytes, start : Int) -> Int {
    if start < 0 || start >= headers.length() {
      return headers.length()
    }
    let mut i = start
    while i + 2 <= headers.length() {
      if headers[i].to_int() == 0xFF && headers[i + 1].to_int() == 0x92 {
        return i
      }
      i += 1
    }
    headers.length()
  }
  fn consume_empty_packet_header_bytes(
    data : Bytes,
    uses_eph : Bool,
  ) -> Result[Int, String] {
    let empty_flag = @packet.pkt_read_bit(data, 0)
    guard empty_flag is Ok(non_zero_flag) else {
      return Err("packet header bitstream truncated")
    }
    if non_zero_flag != 0 {
      return Err("expected empty packet header")
    }
    let mut header_bytes = @packet.pkt_body_start_offset(data, 1)
    if uses_eph &&
      header_bytes + 2 <= data.length() &&
      data[header_bytes].to_int() == 0xFF &&
      data[header_bytes + 1].to_int() == 0x92 {
      header_bytes += 2
    }
    Ok(header_bytes)
  }
  // Process packets in order
  let mut offset = 0
  let has_relocated_headers = relocated_packet_headers.length() > 0
  let mut header_offset = 0
  let mut audit_count = 0
  for packet_idx in 0..<packet_order.length() {
    if offset >= payload.length() {
      if packet_audit && audit_count < packet_audit_limit {
        println(
          "pkt-audit:break label=\{audit_label} idx=\{packet_idx} reason=payload_eof off=\{offset} hoff=\{header_offset} relocated=\{has_relocated_headers}",
        )
        audit_count += 1
      }
      if !has_relocated_headers ||
        header_offset >= relocated_packet_headers.length() {
        break
      }
    }
    let mut order_idx = packet_idx
    let mut nsop_seen = -1
    // T.800-2015 A.6.2: Skip resolutions beyond component's decomposition level.
    // T.800-2015 A.8.1: Skip SOP marker if present (FF 91 00 04 Nsop[2])
    if uses_sop && offset + 6 <= payload.length() {
      if payload[offset].to_int() == 0xFF &&
        payload[offset + 1].to_int() == 0x91 {
        let nsop = (payload[offset + 4].to_int() << 8) |
          payload[offset + 5].to_int()
        nsop_seen = nsop
        if nsop >= 0 && nsop < packet_order.length() {
          order_idx = nsop
        }
        offset += 6
      }
    }
    let next_nsop_expected = if nsop_seen >= 0 {
      (nsop_seen + 1) & 0xFFFF
    } else {
      -1
    }
    if offset >= payload.length() {
      if packet_audit && audit_count < packet_audit_limit {
        println(
          "pkt-audit:break label=\{audit_label} idx=\{packet_idx} reason=payload_eof_after_sop off=\{offset} hoff=\{header_offset} relocated=\{has_relocated_headers}",
        )
        audit_count += 1
      }
      if !has_relocated_headers ||
        header_offset >= relocated_packet_headers.length() {
        break
      }
    }
    let (res, layer, comp, prec) = packet_order[order_idx]
    let mut audit_npx = -1
    let mut audit_npy = -1
    let mut audit_px = -1
    let mut audit_py = -1
    if comp >= 0 &&
      comp < comp_res_num_precincts.length() &&
      res >= 0 &&
      res < comp_res_num_precincts[comp].length() {
      let (npx_a, npy_a) = comp_res_num_precincts[comp][res]
      audit_npx = npx_a
      audit_npy = npy_a
      if npx_a > 0 {
        audit_px = prec % npx_a
        audit_py = prec / npx_a
      }
    }
    if packet_audit && audit_count < packet_audit_limit {
      println(
        "pkt-audit:start label=\{audit_label} idx=\{packet_idx} ord=\{order_idx} nsop=\{nsop_seen} off=\{offset} hoff=\{header_offset} relocated=\{has_relocated_headers} r=\{res} l=\{layer} c=\{comp} p=\{prec} npx=\{audit_npx} npy=\{audit_npy} px=\{audit_px} py=\{audit_py}",
      )
      audit_count += 1
    }
    // SOP streams may contain zero-length packets where two SOP markers are
    // contiguous. In that case, skip header/body parsing for this packet and
    // keep the body cursor at the next SOP start.
    if uses_sop &&
      !has_relocated_headers &&
      nsop_seen >= 0 &&
      find_next_sop_offset(payload, offset, next_nsop_expected) == offset {
      if packet_audit && audit_count < packet_audit_limit {
        println(
          "pkt-audit:skip label=\{audit_label} idx=\{packet_idx} reason=sop_empty off=\{offset} hoff=\{header_offset}",
        )
        audit_count += 1
      }
      continue
    }
    // T.800-2015 A.6.2: Skip resolutions beyond component's decomposition level.
    if comp < comp_num_resolutions.length() && res >= comp_num_resolutions[comp] {
      if packet_audit && audit_count < packet_audit_limit {
        println(
          "pkt-audit:skip label=\{audit_label} idx=\{packet_idx} reason=res_oob off=\{offset} hoff=\{header_offset}",
        )
        audit_count += 1
      }
      if has_relocated_headers && uses_eph {
        let next_eph = find_next_eph_offset(
          relocated_packet_headers, header_offset,
        )
        header_offset = if next_eph < relocated_packet_headers.length() {
          next_eph + 2
        } else {
          relocated_packet_headers.length()
        }
      }
      if uses_sop {
        if has_relocated_headers {
          // With relocated headers, packet body can be empty and have no SOP.
          // Keep current body offset and continue consuming header stream.
        } else {
          let next_sop = find_next_sop_offset(payload, offset, -1)
          if next_sop > offset {
            offset = next_sop
          } else {
            break
          }
        }
      } else if has_relocated_headers &&
        !uses_eph &&
        header_offset < relocated_packet_headers.length() {
        let remaining_header = if header_offset == 0 {
          relocated_packet_headers
        } else {
          relocated_packet_headers[header_offset:relocated_packet_headers.length()].to_bytes()
        }
        let empty_header_v = consume_empty_packet_header_bytes(
          remaining_header, false,
        )
        if empty_header_v is Ok(header_bytes) {
          header_offset += header_bytes
        } else {
          break
        }
      } else if !has_relocated_headers && offset < payload.length() {
        let remaining_payload = if offset == 0 {
          payload
        } else {
          payload[offset:payload.length()].to_bytes()
        }
        let empty_header_v = consume_empty_packet_header_bytes(
          remaining_payload, uses_eph,
        )
        if empty_header_v is Ok(header_bytes) {
          offset += header_bytes
        } else {
          break
        }
      }
      continue
    }
    // T.800-2015 B.6: Skip resolutions with no codeblocks (zero-extent subbands).
    if comp < comp_res_cb_counts.length() &&
      res < comp_res_cb_counts[comp].length() &&
      comp_res_cb_counts[comp][res] == 0 {
      if packet_audit && audit_count < packet_audit_limit {
        println(
          "pkt-audit:skip label=\{audit_label} idx=\{packet_idx} reason=zero_cb off=\{offset} hoff=\{header_offset}",
        )
        audit_count += 1
      }
      if has_relocated_headers && uses_eph {
        let next_eph = find_next_eph_offset(
          relocated_packet_headers, header_offset,
        )
        header_offset = if next_eph < relocated_packet_headers.length() {
          next_eph + 2
        } else {
          relocated_packet_headers.length()
        }
      }
      if uses_sop {
        if has_relocated_headers {
          // With relocated headers, packet body can be empty and have no SOP.
          // Keep current body offset and continue consuming header stream.
        } else {
          let next_sop = find_next_sop_offset(payload, offset, -1)
          if next_sop > offset {
            offset = next_sop
          } else {
            break
          }
        }
      } else if has_relocated_headers &&
        !uses_eph &&
        header_offset < relocated_packet_headers.length() {
        let remaining_header = if header_offset == 0 {
          relocated_packet_headers
        } else {
          relocated_packet_headers[header_offset:relocated_packet_headers.length()].to_bytes()
        }
        let empty_header_v = consume_empty_packet_header_bytes(
          remaining_header, false,
        )
        if empty_header_v is Ok(header_bytes) {
          header_offset += header_bytes
        } else {
          break
        }
      } else if !has_relocated_headers && offset < payload.length() {
        let remaining_payload = if offset == 0 {
          payload
        } else {
          payload[offset:payload.length()].to_bytes()
        }
        let empty_header_v = consume_empty_packet_header_bytes(
          remaining_payload, uses_eph,
        )
        if empty_header_v is Ok(header_bytes) {
          offset += header_bytes
        } else {
          break
        }
      }
      continue
    }
    // Parse packet from current offset.
    // With PPT relocation, parse header from `relocated_packet_headers` and
    // treat `payload` as body stream only.
    let packet_end = payload.length()
    let remaining_payload : Bytes = if offset == 0 &&
      packet_end == payload.length() {
      payload
    } else {
      payload[offset:packet_end].to_bytes()
    }
    let mut relocated_packet_eph = -1
    if has_relocated_headers &&
      header_offset >= relocated_packet_headers.length() {
      break
    }
    let header_end = if has_relocated_headers {
      if uses_eph {
        let next_eph = find_next_eph_offset(
          relocated_packet_headers, header_offset,
        )
        if next_eph >= relocated_packet_headers.length() {
          break
        }
        relocated_packet_eph = next_eph
        next_eph
      } else {
        relocated_packet_headers.length()
      }
    } else {
      0
    }
    let remaining_header : Bytes = if has_relocated_headers {
      if header_offset == 0 && header_end == relocated_packet_headers.length() {
        relocated_packet_headers
      } else {
        relocated_packet_headers[header_offset:header_end].to_bytes()
      }
    } else {
      remaining_payload
    }
    if comp >= num_components {
      if packet_audit && audit_count < packet_audit_limit {
        println(
          "pkt-audit:break label=\{audit_label} idx=\{packet_idx} reason=comp_oob comp=\{comp} num_components=\{num_components} off=\{offset} hoff=\{header_offset}",
        )
        audit_count += 1
      }
      break
    }
    // T.800-2015 B.7: Get precinct-specific tag-tree state
    let prec_sb_states = comp_res_prec_sb_states[comp][res][prec]
    if packet_audit && audit_count < packet_audit_limit {
      for sbi in 0..<prec_sb_states.length() {
        let sbst = prec_sb_states[sbi]
        println(
          "pkt-audit:sb label=\{audit_label} idx=\{packet_idx} sb=\{sbi} ncbx=\{sbst.ncbx} ncby=\{sbst.ncby}",
        )
        audit_count += 1
        if audit_count >= packet_audit_limit {
          break
        }
      }
    }
    // T.800-2015 B.7: Build subband info for this precinct only
    let c_cbw = comp_cbw[comp]
    let c_cbh = comp_cbh[comp]
    let c_code_block_style = if comp < comp_code_block_styles.length() {
      comp_code_block_styles[comp]
    } else {
      code_block_style
    }
    let (ppx_exp, ppy_exp) = @precinct.get_component_precinct_exponents(
      precinct_size_bytes, comp_precinct_size_bytes, comp, res,
    )
    let c_eff_cbw = @precinct.effective_cb_dim_for_res(c_cbw, ppx_exp, res)
    let c_eff_cbh = @precinct.effective_cb_dim_for_res(c_cbh, ppy_exp, res)
    let (npx, _) = comp_res_num_precincts[comp][res]
    let px = prec % npx
    let py = prec / npx
    // Build precinct subbands and retain absolute precinct bounds per subband.
    let prec_subbands : Array[(Int, Int, Int)] = []
    let prec_sb_bounds : Array[(Int, Int, Int, Int)] = []
    let subbands = comp_resolution_subbands[comp][res]
    let sb_bounds = comp_subband_bounds[comp][res]
    let (trx0, try0, _, _) = comp_res_bounds[comp][res]
    for sb_idx in 0..<subbands.length() {
      let (sw, sh, si) = subbands[sb_idx]
      if sw > 0 && sh > 0 {
        // T.800-2015 B.5/B.7: Use absolute subband bounds for precinct calculation
        let (tbx0, tby0, tbx1, tby1) = sb_bounds[sb_idx]
        let (prec_x0, prec_y0, prec_x1, prec_y1) = @precinct.compute_precinct_bounds_abs(
          trx0, try0, tbx0, tby0, tbx1, tby1, px, py, ppx_exp, ppy_exp, res,
        )
        let (ncbx, ncby, cb_x_start, cb_y_start, prec_pw, prec_ph) = @precinct.compute_precinct_codeblock_range_abs(
          trx0, try0, tbx0, tby0, tbx1, tby1, c_eff_cbw, c_eff_cbh, px, py, ppx_exp,
          ppy_exp, res,
        )
        if packet_audit && audit_count < packet_audit_limit {
          println(
            "pkt-audit:sbcalc label=\{audit_label} idx=\{packet_idx} sb=\{sb_idx} px=\{px} py=\{py} ppx=\{ppx_exp} ppy=\{ppy_exp} tbx0=\{tbx0} tby0=\{tby0} tbx1=\{tbx1} tby1=\{tby1} prx0=\{prec_x0} pry0=\{prec_y0} prx1=\{prec_x1} pry1=\{prec_y1} ncbx=\{ncbx} ncby=\{ncby} cbx0=\{cb_x_start} cby0=\{cb_y_start}",
          )
          audit_count += 1
        }
        // Use actual pixel dimensions, not rounded-up CB dimensions
        prec_subbands.push((prec_pw, prec_ph, si))
        prec_sb_bounds.push((prec_x0, prec_y0, prec_x1, prec_y1))
      } else {
        prec_subbands.push((0, 0, si))
        prec_sb_bounds.push((0, 0, 0, 0))
      }
    }
    let header_v = parse_layer_packet_header(
      remaining_header,
      layer,
      c_code_block_style,
      prec_subbands,
      prec_sb_states,
      c_eff_cbw,
      c_eff_cbh,
      sb_bounds~,
    )
    guard header_v is Ok((cb_infos, consumed_bits)) else {
      if packet_audit && audit_count < packet_audit_limit {
        let header_err = if header_v is Err(msg) { msg } else { "unknown" }
        println(
          "pkt-audit:header_fail label=\{audit_label} idx=\{packet_idx} ord=\{order_idx} off=\{offset} hoff=\{header_offset} err=\{header_err}",
        )
        audit_count += 1
      }
      if has_relocated_headers && uses_eph {
        let next_eph = find_next_eph_offset(
          relocated_packet_headers, header_offset,
        )
        header_offset = if next_eph < relocated_packet_headers.length() {
          next_eph + 2
        } else {
          relocated_packet_headers.length()
        }
      }
      // SOP streams: keep scanning subsequent packets even if one header parse fails.
      // This avoids discarding all remaining tile-part payload due a single mismatch.
      if uses_sop {
        let next_sop = find_next_sop_offset(
          payload,
          offset + 1,
          next_nsop_expected,
        )
        if has_relocated_headers {
          if next_sop > offset {
            offset = next_sop
          }
          continue
        }
        if next_sop <= offset {
          break
        }
        offset = next_sop
        continue
      }
      break
    }
    // Compute body offset and body size
    let mut header_bytes = @packet.pkt_body_start_offset(
      remaining_header, consumed_bits,
    )
    let mut body_offset = if has_relocated_headers { 0 } else { header_bytes }
    let mut eph_ok = true
    if has_relocated_headers &&
      uses_eph &&
      relocated_packet_eph >= header_offset {
      header_bytes = relocated_packet_eph - header_offset + 2
      eph_ok = true
    }
    // T.800-2015 A.8.2: EPH marker may follow packet header, before body
    if uses_eph &&
      !(has_relocated_headers && relocated_packet_eph >= header_offset) {
      if has_relocated_headers {
        if header_bytes + 2 <= remaining_header.length() &&
          remaining_header[header_bytes].to_int() == 0xFF &&
          remaining_header[header_bytes + 1].to_int() == 0x92 {
          header_bytes += 2
        } else {
          eph_ok = false
        }
      } else if body_offset + 2 <= remaining_payload.length() &&
        remaining_payload[body_offset].to_int() == 0xFF &&
        remaining_payload[body_offset + 1].to_int() == 0x92 {
        body_offset += 2
      }
    }
    if has_relocated_headers && uses_eph && !eph_ok {
      if packet_audit && audit_count < packet_audit_limit {
        println(
          "pkt-audit:eph_fail label=\{audit_label} idx=\{packet_idx} ord=\{order_idx} off=\{offset} hoff=\{header_offset} hbytes=\{header_bytes}",
        )
        audit_count += 1
      }
      if has_relocated_headers && uses_eph {
        let next_eph = find_next_eph_offset(
          relocated_packet_headers, header_offset,
        )
        header_offset = if next_eph < relocated_packet_headers.length() {
          next_eph + 2
        } else {
          relocated_packet_headers.length()
        }
      }
      if uses_sop {
        let next_sop = find_next_sop_offset(
          payload,
          offset + 1,
          next_nsop_expected,
        )
        if has_relocated_headers {
          if next_sop > offset {
            offset = next_sop
          }
          continue
        }
        if next_sop <= offset {
          break
        }
        offset = next_sop
        continue
      }
      break
    }
    let mut body_size = 0
    for info in cb_infos {
      body_size += @math.sum_ints(info.segment_lengths)
    }
    let mut packet_size = if has_relocated_headers {
      body_size
    } else {
      body_offset + body_size
    }
    // SOP streams carry explicit packet boundaries. When header-derived
    // packet_size drifts from the next SOP marker, trust SOP boundary.
    if uses_sop && !has_relocated_headers {
      let expected_next = offset + packet_size
      let expected_is_sop = expected_next + 2 <= payload.length() &&
        payload[expected_next].to_int() == 0xFF &&
        payload[expected_next + 1].to_int() == 0x91
      if !expected_is_sop {
        let sop_next = find_next_sop_offset(
          payload,
          offset + 1,
          next_nsop_expected,
        )
        if sop_next > offset {
          packet_size = sop_next - offset
        }
      }
    }
    let size_invalid = if has_relocated_headers {
      packet_size < 0 || packet_size > remaining_payload.length()
    } else {
      packet_size <= 0 || packet_size > remaining_payload.length()
    }
    if size_invalid {
      if packet_audit && audit_count < packet_audit_limit {
        println(
          "pkt-audit:size_invalid label=\{audit_label} idx=\{packet_idx} ord=\{order_idx} off=\{offset} hoff=\{header_offset} body_size=\{body_size} packet_size=\{packet_size} remain=\{remaining_payload.length()}",
        )
        audit_count += 1
      }
      if has_relocated_headers && uses_eph {
        let next_eph = find_next_eph_offset(
          relocated_packet_headers, header_offset,
        )
        header_offset = if next_eph < relocated_packet_headers.length() {
          next_eph + 2
        } else {
          relocated_packet_headers.length()
        }
      }
      if uses_sop {
        let next_sop = find_next_sop_offset(
          payload,
          offset + 1,
          next_nsop_expected,
        )
        if has_relocated_headers {
          if next_sop > offset {
            offset = next_sop
          }
          continue
        }
        if next_sop <= offset {
          break
        }
        offset = next_sop
        continue
      }
      break
    }
    // Keep body consumption inside this packet boundary for SOP streams.
    // packet_size is already reconciled against the next SOP marker above.
    let packet_payload_limit = if uses_sop && !has_relocated_headers {
      if packet_size < remaining_payload.length() {
        packet_size
      } else {
        remaining_payload.length()
      }
    } else {
      remaining_payload.length()
    }
    if uses_sop && !has_relocated_headers {
      let body_capacity = if body_offset <= packet_payload_limit {
        packet_payload_limit - body_offset
      } else {
        -1
      }
      if body_capacity < 0 || body_size > body_capacity {
        if packet_audit && audit_count < packet_audit_limit {
          println(
            "pkt-audit:body_overflow label=\{audit_label} idx=\{packet_idx} ord=\{order_idx} off=\{offset} hbytes=\{header_bytes} body_size=\{body_size} packet_size=\{packet_size} cap=\{body_capacity}",
          )
          audit_count += 1
        }
        let next_sop = find_next_sop_offset(
          payload,
          offset + 1,
          next_nsop_expected,
        )
        if next_sop <= offset {
          break
        }
        offset = next_sop
        continue
      }
    }
    // Extract codeword bytes and accumulate for this component
    let mut body_cursor = body_offset
    for info in cb_infos {
      let sb_idx = info.subband_index
      let local_cbx = info.cb_x_index
      let local_cby = info.cb_y_index
      let prec_offsets = comp_res_prec_sb_offsets[comp][res][prec]
      let prec_ncbx = comp_res_prec_sb_ncbx[comp][res][prec]
      let sb_offset = if sb_idx < prec_offsets.length() {
        prec_offsets[sb_idx]
      } else {
        0
      }
      let sb_ncbx = if sb_idx < prec_ncbx.length() {
        prec_ncbx[sb_idx]
      } else {
        0
      }
      let global_cb_idx = sb_offset + local_cby * sb_ncbx + local_cbx
      let (sb_tbx0, sb_tby0, _, _) = sb_bounds[sb_idx]
      let (prec_x0, prec_y0, prec_x1, prec_y1) = prec_sb_bounds[sb_idx]
      let (
        correct_cb_x_offset,
        correct_cb_y_offset,
        correct_cb_width,
        correct_cb_height,
      ) = @precinct.compute_precinct_local_cb_geometry(
        sb_tbx0, sb_tby0, prec_x0, prec_y0, prec_x1, prec_y1, c_eff_cbw, c_eff_cbh,
        local_cbx, local_cby,
      )
      // Get actual subband dimensions for geometry
      let (sb_w, sb_h, _) = comp_resolution_subbands[comp][res][sb_idx]
      let valid_cb_idx = global_cb_idx >= 0 &&
        global_cb_idx < comp_res_cb_passes[comp][res].length()
      // Set geometry on first encounter
      if valid_cb_idx &&
        global_cb_idx < comp_res_cb_geom_set[comp][res].length() &&
        !comp_res_cb_geom_set[comp][res][global_cb_idx] {
        comp_res_cb_geom[comp][res][global_cb_idx] = (
          info.subband_index,
          sb_w,
          sb_h,
          correct_cb_x_offset,
          correct_cb_y_offset,
          correct_cb_width,
          correct_cb_height,
        )
        comp_res_cb_geom_set[comp][res][global_cb_idx] = true
      }
      if info.included {
        // Always consume body bytes for included code-blocks to keep packet
        // cursor synchronized, even when CB mapping is out-of-range.
        let seg_total = @math.sum_ints(info.segment_lengths)
        let avail = if body_cursor < packet_payload_limit {
          packet_payload_limit - body_cursor
        } else {
          0
        }
        let cw_len = if seg_total <= avail { seg_total } else { avail }
        let is_target_cblk = packet_audit &&
          audit_label == "single" &&
          comp == 0 &&
          res == 3 &&
          sb_idx == 0 &&
          correct_cb_x_offset == 0 &&
          correct_cb_y_offset == 0
        if packet_audit && audit_count < packet_audit_limit {
          let passes_dbg = if info.coding_passes is Some(p) { p } else { 0 }
          println(
            "pkt-audit:cb label=\{audit_label} idx=\{packet_idx} sb=\{sb_idx} lcx=\{local_cbx} lcy=\{local_cby} gidx=\{global_cb_idx} ncbx=\{sb_ncbx} included=\{info.included} passes=\{passes_dbg} seg_lens=\{info.segment_lengths} seg_passes=\{info.segment_passes} seg_total=\{seg_total} cw_len=\{cw_len}",
          )
          audit_count += 1
        }
        if is_target_cblk {
          let preview_count = if cw_len < 8 { cw_len } else { 8 }
          let preview_parts : Array[String] = []
          for k in 0..<preview_count {
            preview_parts.push(
              "\{body_cursor + k}=\{remaining_payload[body_cursor + k].to_int()}",
            )
          }
          let accum_before = if valid_cb_idx {
            comp_res_cb_codeword[comp][res][global_cb_idx].length()
          } else {
            -1
          }
          println(
            "pkt-audit:target-cblk-body label=\{audit_label} idx=\{packet_idx} ord=\{order_idx} r=\{res} l=\{layer} c=\{comp} p=\{prec} sb=\{sb_idx} lcx=\{local_cbx} lcy=\{local_cby} gidx=\{global_cb_idx} body_cursor=\{body_cursor} avail=\{avail} seg_total=\{seg_total} cw_len=\{cw_len} accum_before=\{accum_before} preview=\{preview_parts}",
          )
        }
        if valid_cb_idx {
          // Set ZBP from first inclusion
          if info.zero_bit_planes is Some(zbp) {
            comp_res_cb_zbp[comp][res][global_cb_idx] = zbp
          }
          // Accumulate coding passes and track per-segment pass counts
          if info.coding_passes is Some(passes) {
            comp_res_cb_passes[comp][res][global_cb_idx] += passes
            if info.segment_passes.length() > 0 {
              for sp in info.segment_passes {
                comp_res_cb_seg_passes[comp][res][global_cb_idx].push(sp)
              }
            } else {
              comp_res_cb_seg_passes[comp][res][global_cb_idx].push(passes)
            }
          }
          // Accumulate segment lengths
          for sl in info.segment_lengths {
            comp_res_cb_seglens[comp][res][global_cb_idx].push(sl)
          }
          // Extract and accumulate codeword bytes
          for j in body_cursor..<(body_cursor + cw_len) {
            comp_res_cb_codeword[comp][res][global_cb_idx].push(
              remaining_payload[j],
            )
          }
        }
        body_cursor += cw_len
      }
    }
    if has_relocated_headers {
      header_offset += header_bytes
    }
    if packet_audit && audit_count < packet_audit_limit {
      println(
        "pkt-audit:ok label=\{audit_label} idx=\{packet_idx} ord=\{order_idx} off=\{offset} hoff=\{header_offset} hbytes=\{header_bytes} body_size=\{body_size} packet_size=\{packet_size} body_cursor=\{body_cursor}",
      )
      audit_count += 1
    }
    if uses_sop {
      if has_relocated_headers {
        let mut next_offset = offset + packet_size
        if packet_audit && audit_count < packet_audit_limit {
          println(
            "pkt-audit:advance label=\{audit_label} idx=\{packet_idx} mode=relocated off=\{offset} packet_size=\{packet_size} next0=\{next_offset} nsop_next=\{next_nsop_expected}",
          )
          audit_count += 1
        }
        if next_offset < offset || next_offset > payload.length() {
          if packet_audit && audit_count < packet_audit_limit {
            println(
              "pkt-audit:break label=\{audit_label} idx=\{packet_idx} reason=next_offset_invalid off=\{offset} next=\{next_offset} payload_len=\{payload.length()}",
            )
            audit_count += 1
          }
          break
        }
        if next_offset + 2 <= payload.length() &&
          !(payload[next_offset].to_int() == 0xFF &&
          payload[next_offset + 1].to_int() == 0x91) {
          let sop_next = find_next_sop_offset(
            payload, next_offset, next_nsop_expected,
          )
          if packet_audit && audit_count < packet_audit_limit {
            println(
              "pkt-audit:advance_scan label=\{audit_label} idx=\{packet_idx} from=\{next_offset} sop_next=\{sop_next} nsop_next=\{next_nsop_expected}",
            )
            audit_count += 1
          }
          if sop_next > next_offset {
            next_offset = sop_next
          }
        }
        if next_offset == offset &&
          packet_size != 0 &&
          !(offset + 2 <= payload.length() &&
          payload[offset].to_int() == 0xFF &&
          payload[offset + 1].to_int() == 0x91) {
          if packet_audit && audit_count < packet_audit_limit {
            println(
              "pkt-audit:break label=\{audit_label} idx=\{packet_idx} reason=stalled_offset off=\{offset} packet_size=\{packet_size} next=\{next_offset}",
            )
            audit_count += 1
          }
          break
        }
        offset = next_offset
      } else {
        let mut next_offset = offset + packet_size
        if packet_audit && audit_count < packet_audit_limit {
          println(
            "pkt-audit:advance label=\{audit_label} idx=\{packet_idx} mode=inline off=\{offset} packet_size=\{packet_size} next0=\{next_offset} nsop_next=\{-1}",
          )
          audit_count += 1
        }
        if next_offset + 2 <= payload.length() &&
          !(payload[next_offset].to_int() == 0xFF &&
          payload[next_offset + 1].to_int() == 0x91) {
          let sop_next = find_next_sop_offset(payload, next_offset, -1)
          if packet_audit && audit_count < packet_audit_limit {
            println(
              "pkt-audit:advance_scan label=\{audit_label} idx=\{packet_idx} from=\{next_offset} sop_next=\{sop_next} nsop_next=\{-1}",
            )
            audit_count += 1
          }
          next_offset = sop_next
        }
        if next_offset < offset {
          if packet_audit && audit_count < packet_audit_limit {
            println(
              "pkt-audit:break label=\{audit_label} idx=\{packet_idx} reason=next_offset_backwards off=\{offset} next=\{next_offset}",
            )
            audit_count += 1
          }
          break
        }
        if next_offset == offset &&
          !(offset + 2 <= payload.length() &&
          payload[offset].to_int() == 0xFF &&
          payload[offset + 1].to_int() == 0x91) {
          if packet_audit && audit_count < packet_audit_limit {
            println(
              "pkt-audit:break label=\{audit_label} idx=\{packet_idx} reason=stalled_offset off=\{offset} packet_size=\{packet_size} next=\{next_offset}",
            )
            audit_count += 1
          }
          break
        }
        offset = next_offset
      }
    } else {
      offset += packet_size
    }
  }
  // Build result: [component][resolution] -> Array[AccumulatedCB]
  // T.800-2015 A.6.2: Each component may have different resolution counts.
  // Result arrays have comp_num_resolutions[comp] entries per component.
  let result : Array[Array[Array[AccumulatedCB]]] = []
  for comp in 0..<num_components {
    let comp_data : Array[Array[AccumulatedCB]] = []
    let c_num_res = comp_num_resolutions[comp]
    for res in 0..<c_num_res {
      let res_cbs : Array[AccumulatedCB] = []
      for cb_idx in 0..<comp_res_cb_counts[comp][res] {
        let total_passes = comp_res_cb_passes[comp][res][cb_idx]
        if total_passes > 0 {
          let (si, sw, sh, cx, cy, cw, ch) = comp_res_cb_geom[comp][res][cb_idx]
          res_cbs.push({
            subband_index: si,
            sb_width: sw,
            sb_height: sh,
            cb_x_offset: cx,
            cb_y_offset: cy,
            cb_width: cw,
            cb_height: ch,
            zero_bit_planes: comp_res_cb_zbp[comp][res][cb_idx],
            total_coding_passes: total_passes,
            all_segment_lengths: comp_res_cb_seglens[comp][res][cb_idx],
            per_segment_passes: comp_res_cb_seg_passes[comp][res][cb_idx],
            codeword: comp_res_cb_codeword[comp][res][cb_idx],
          })
        }
      }
      comp_data.push(res_cbs)
    }
    result.push(comp_data)
  }
  Ok((result, header_offset))
}

///|
// Spec basis (T.800-2015 B.5/B.10/F.3):
// Decode one component's DWT coefficients from accumulated multi-layer
// code-block data, apply inverse DWT, and return reconstructed samples.

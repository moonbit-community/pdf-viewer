///|
pub fn htj2k_decode_not_supported_error(stream : @core.Codestream) -> String {
  "decode_samples unsupported HTJ2K (\{@profile.htj2k_not_supported_reason(stream)})"
}

///|
// Spec basis (T.800-2015 B.3):
// Decode multiple code-blocks and combine coefficients into output array.
// grid_w, grid_h: number of code-blocks in each dimension
// cbw, cbh: nominal code-block dimensions (from COD exponents)
// img_w, img_h: actual image dimensions
pub fn decode_multi_codeblock_coefficients(
  multi_parts : Array[@a8.MultiCodeblockPacketParts],
  grid_w : Int,
  grid_h : Int,
  cbw : Int,
  cbh : Int,
  img_w : Int,
  img_h : Int,
  precision_bits : Int,
  code_block_style : Int,
  subband_max_bit_planes? : Int = 0,
  quantization_style? : Int = 0,
  roishift? : Int = 0,
) -> Result[Array[Int], String] {
  let accumulated_v = accumulate_multi_codeblock_packet_parts(multi_parts)
  guard accumulated_v is Ok(accumulated_parts) else {
    return Err("multi-cb decode: accumulation failed")
  }
  if accumulated_parts.parts.length() != grid_w * grid_h {
    return Err(
      "code-block count mismatch: expected \{grid_w * grid_h}, got \{accumulated_parts.parts.length()}",
    )
  }
  // Initialize output with zeros
  let output : Array[Int] = []
  for _ in 0..<(img_w * img_h) {
    output.push(0)
  }
  let mut decoded_codeblock_count = 0
  for cy in 0..<grid_h {
    for cx in 0..<grid_w {
      let cb_index = cy * grid_w + cx
      let parts = accumulated_parts.parts[cb_index]
      if !parts.included {
        continue
      }
      let passes = match parts.coding_passes {
        Some(p) => p
        None => continue
      }
      let zbp = match parts.zero_bit_planes {
        Some(z) => z
        None => continue
      }
      // Calculate actual code-block dimensions (clamped to image boundary)
      let cb_x0 = cx * cbw
      let cb_y0 = cy * cbh
      let cb_actual_w = if cb_x0 + cbw > img_w { img_w - cb_x0 } else { cbw }
      let cb_actual_h = if cb_y0 + cbh > img_h { img_h - cb_y0 } else { cbh }
      if cb_actual_w <= 0 || cb_actual_h <= 0 {
        continue
      }
      if code_block_style_is_ht(code_block_style) {
        let ht_block_v = decode_single_codeblock_coefficients(
          parts.codeword,
          cb_actual_w,
          cb_actual_h,
          passes,
          zbp,
          precision_bits,
          code_block_style,
          segment_lengths=parts.segment_lengths,
          per_segment_passes=parts.segment_passes,
          subband_max_bit_planes~,
          quantization_style~,
          roishift~,
        )
        guard ht_block_v is Ok(ht_values) else {
          if ht_block_v is Err(msg) {
            return Err(
              "multi-cb decode: HT code-block decode failed for cb(\{cx},\{cy}): \{msg}",
            )
          }
          return Err(
            "multi-cb decode: HT code-block decode failed for cb(\{cx},\{cy})",
          )
        }
        for by in 0..<cb_actual_h {
          for bx in 0..<cb_actual_w {
            let dst_x = cb_x0 + bx
            let dst_y = cb_y0 + by
            let dst_index = dst_y * img_w + dst_x
            let src_index = by * cb_actual_w + bx
            if dst_index < output.length() && src_index < ht_values.length() {
              output[dst_index] = ht_values[src_index]
            }
          }
        }
        decoded_codeblock_count += 1
        continue
      }
      // Get pass segments
      let pass_segments_v = tier1_codeword_pass_segments(parts)
      let pass_segments = match pass_segments_v {
        Ok(segs) => segs
        Err(e) =>
          return Err(
            "multi-cb decode: pass segments failed for cb(\{cx},\{cy}): \{e}",
          )
      }
      // Initialize MQ contexts for this code-block
      let contexts_v = @mq.tier1_annex_c_reset_contexts(
        @mq.TIER1_ANNEX_C_DEFAULT_CONTEXT_COUNT,
      )
      guard contexts_v is Ok(contexts0) else {
        return Err("multi-cb decode: context reset failed for cb(\{cx},\{cy})")
      }
      // Decode MQ decisions for this code-block
      let decode_v = if code_block_style == 4 && pass_segments.length() > 0 {
        @mq.tier1_annex_c_decode_mini_block_pass_segments(
          pass_segments,
          contexts0,
          cb_actual_w,
          cb_actual_h,
          passes,
          true,
          code_block_style~,
        )
      } else {
        // For non-TERMALL, need to bootstrap from codeword
        let codewords : Array[Bytes] = [parts.codeword]
        let boot_v = @mq.tier1_annex_c_bootstrap_from_codewords(codewords)
        guard boot_v is Ok(boot) else {
          return Err(
            "multi-cb decode: bootstrap failed for cb(\{cx},\{cy}), codeword_len=\{parts.codeword.length()}",
          )
        }
        @mq.tier1_annex_c_decode_mini_block_passes(
          boot,
          codewords,
          contexts0,
          cb_actual_w,
          cb_actual_h,
          passes,
          true,
          code_block_style~,
        )
      }
      guard decode_v is Ok((_, norm_decisions, _)) else {
        return Err(
          "multi-cb decode: MQ decode failed for cb(\{cx},\{cy}), passes=\{passes}, dims=\{cb_actual_w}x\{cb_actual_h}",
        )
      }
      // Get coefficient values for this code-block
      let block_v = @t1.tier1_normative_preview_sample_values_mini_block(
        cb_actual_w, cb_actual_h, passes, zbp, norm_decisions,
      )
      guard block_v is Ok((values, _)) else {
        return Err(
          "multi-cb decode: coeff extraction failed for cb(\{cx},\{cy})",
        )
      }
      // Apply bit-plane scaling: shift = precision_bits - zbp - num_decoded_bp
      let num_bp = (passes + 2) / 3
      let shift = precision_bits - zbp - num_bp
      // Copy coefficients to output at correct position
      for by in 0..<cb_actual_h {
        for bx in 0..<cb_actual_w {
          let block_idx = by * cb_actual_w + bx
          let img_x = cb_x0 + bx
          let img_y = cb_y0 + by
          let img_idx = img_y * img_w + img_x
          if block_idx < values.length() && img_idx < output.length() {
            let v = values[block_idx]
            output[img_idx] = if shift > 0 { v << shift } else { v }
          }
        }
      }
      decoded_codeblock_count += 1
    }
  }
  if decoded_codeblock_count == 0 {
    return Err("multi-cb decode: no code-blocks were decoded")
  }
  Ok(output)
}

///|
// Bridging path for synthetic/simple no-DWT HT multi-codeblock tiles whose
// packet headers are expressible as a flat packet series but not as full
// B.10 tag-tree state. The primary sequential tile decoder remains first.
pub fn decode_nodwt_ht_multi_codeblock_tile_bridge(
  stream : @core.Codestream,
  payload : Bytes,
  tile_width : Int,
  tile_height : Int,
  precision_bits : Int,
  is_signed : Bool,
  tile_index : Int,
  roishift : Int,
  fallback_cod : @core.CodMetadata,
  fallback_qcd? : @core.QcdMetadata? = None,
) -> Result[Array[Int], String] {
  let (decomp_levels, cbw, cbh, code_block_style, transformation, qcd_opt) = @geometry.get_component_decode_context(
    stream,
    0,
    fallback_cod,
    fallback_qcd~,
    tile_index~,
  )
  if decomp_levels != 0 {
    return Err("tile HT multi-codeblock bridge not applicable: dwt")
  }
  if !code_block_style_is_ht(code_block_style) {
    return Err("tile HT multi-codeblock bridge not applicable: not ht")
  }
  let grid_w = @math.ceil_div(tile_width, cbw)
  let grid_h = @math.ceil_div(tile_height, cbh)
  let code_block_count = grid_w * grid_h
  if code_block_count <= 1 {
    return Err(
      "tile HT multi-codeblock bridge not applicable: single code-block",
    )
  }
  let series_v = @a8.extract_multi_codeblock_packet_parts_series(
    payload, code_block_count, code_block_style,
  )
  guard series_v is Ok(multi_parts_list) else {
    return Err("tile HT multi-codeblock bridge parse failed")
  }
  let mut has_included = false
  for packet_parts in multi_parts_list {
    for parts in packet_parts.parts {
      if parts.included {
        has_included = true
        break
      }
    }
    if has_included {
      break
    }
  }
  if !has_included {
    return Err("tile HT multi-codeblock bridge found no included code-blocks")
  }
  let ll_kmax = if qcd_opt is Some(qcd_mc) {
    @quant.qcd_subband_max_bit_planes(
      qcd_mc,
      0,
      precision_bits~,
      transformation~,
      decomposition_levels=decomp_levels,
    )
  } else {
    0
  }
  let quantization_style = if qcd_opt is Some(qcd_mc) {
    qcd_mc.quantization_style
  } else {
    0
  }
  let coeffs_v = decode_multi_codeblock_coefficients(
    multi_parts_list,
    grid_w,
    grid_h,
    cbw,
    cbh,
    tile_width,
    tile_height,
    precision_bits,
    code_block_style,
    subband_max_bit_planes=ll_kmax,
    quantization_style~,
    roishift~,
  )
  guard coeffs_v is Ok(coefficients) else {
    if coeffs_v is Err(msg) {
      return Err("tile HT multi-codeblock bridge decode failed: \{msg}")
    }
    return Err("tile HT multi-codeblock bridge decode failed")
  }
  let dc_offset = if is_signed { 0 } else { 1 << (precision_bits - 1) }
  let clamped_values : Array[Int] = []
  for v in coefficients {
    clamped_values.push(
      clamp_sample_for_signedness(v + dc_offset, is_signed, precision_bits~),
    )
  }
  Ok(clamped_values)
}

///|
/// Spec basis (T.800-2015 Table E.1):
/// For reversible (qntsty=0), K_max = epsilon_b + guard_bits - 1.
/// The subband_max_bit_planes parameter provides K_max when available from QCD,
/// falling back to precision_bits when QCD is not parsed.
pub fn decode_single_codeblock_coefficients(
  codeword : Bytes,
  cb_w : Int,
  cb_h : Int,
  passes : Int,
  zbp : Int,
  precision_bits : Int,
  code_block_style : Int,
  segment_lengths? : Array[Int] = [],
  per_segment_passes? : Array[Int] = [],
  subband_max_bit_planes? : Int = 0,
  subband_type? : Int = 0,
  quantization_style? : Int = 0,
  roishift? : Int = 0,
  packet_audit? : Bool = false,
  audit_label? : String = "",
  audit_comp? : Int = 0,
  audit_res? : Int = 0,
  audit_sb? : Int = 0,
  audit_cbx? : Int = 0,
  audit_cby? : Int = 0,
) -> Result[Array[Int], String] {
  if cb_w <= 0 || cb_h <= 0 {
    return Ok([])
  }
  if codeword.length() == 0 {
    let zeros : Array[Int] = []
    for _ in 0..<(cb_w * cb_h) {
      zeros.push(0)
    }
    return Ok(zeros)
  }
  let (effective_segment_lengths, effective_segment_passes) = if segment_lengths.length() >
    0 &&
    per_segment_passes.length() > 0 {
    tier1_merge_packet_contributions_into_final_segments(
      segment_lengths, per_segment_passes, code_block_style,
    )
  } else {
    (segment_lengths, per_segment_passes)
  }
  if packet_audit {
    println(
      "recon-audit:cblk-segs:label=\{audit_label} c=\{audit_comp} r=\{audit_res} sb=\{audit_sb} cbx=\{audit_cbx} cby=\{audit_cby} cblksty=\{code_block_style} contrib_lens=\{segment_lengths} contrib_passes=\{per_segment_passes} final_lens=\{effective_segment_lengths} final_passes=\{effective_segment_passes}",
    )
  }
  if code_block_style_is_ht(code_block_style) {
    let ht_bitplanes = if subband_max_bit_planes > 0 {
      subband_max_bit_planes + roishift - zbp
    } else {
      precision_bits + roishift - zbp
    }
    let ht_values_v = @ht.htj2k_decode_single_set_fixedpoint(
      codeword, passes, effective_segment_lengths, effective_segment_passes, cb_w,
      cb_h, ht_bitplanes, zbp, code_block_style,
    )
    guard ht_values_v is Ok(ht_values) else {
      if ht_values_v is Err(msg) {
        if packet_audit {
          let bytes_dbg : Array[Int] = []
          for b in codeword {
            bytes_dbg.push(b.to_int())
          }
          println(
            "recon-audit:ht-codeword-error:label=\{audit_label} c=\{audit_comp} r=\{audit_res} sb=\{audit_sb} cbx=\{audit_cbx} cby=\{audit_cby} len=\{codeword.length()} bytes=\{bytes_dbg} msg=\{msg}",
          )
        }
        return Err(msg)
      }
      return Err("htj2k staged decode failed")
    }
    let normalized : Array[Int] = []
    for fixed0 in ht_values {
      let fixed = htj2k_roi_descaled_fixedpoint(fixed0, roishift)
      if quantization_style == 0 {
        normalized.push(fixed / 2)
      } else {
        normalized.push(fixed)
      }
    }
    return Ok(normalized)
  }
  // Build per-pass segments from codeword using segment lengths from packet header.
  // For TERMALL (0x04): each pass has its own segment with independent MQ init.
  // For non-TERMALL multi-segment: re-init MQ at each final segment boundary.
  // For non-TERMALL single-segment: single segment containing all passes.
  let has_termall = (code_block_style & 0x04) != 0
  let has_multi_segments = not(has_termall) &&
    effective_segment_lengths.length() > 1 &&
    effective_segment_passes.length() > 1
  let pass_segments : Array[Bytes] = []
  let pass_segment_starts : Array[Bool] = []
  if has_termall && effective_segment_lengths.length() > 1 {
    // Split codeword into per-pass segments using lengths from packet header
    let mut offset = 0
    for slen in effective_segment_lengths {
      pass_segment_starts.push(true)
      if slen > 0 && offset + slen <= codeword.length() {
        let seg_bytes : Array[Byte] = []
        for j in offset..<(offset + slen) {
          seg_bytes.push(codeword[j])
        }
        pass_segments.push(Bytes::from_iter(seg_bytes.iter()))
      } else {
        // Empty segment (zero-length pass)
        pass_segments.push(Bytes::new(0))
      }
      offset += slen
    }
  } else if has_multi_segments {
    // T.800-2015 B.10.7:
    // segment_lengths carry packet contributions, but MQ re-init happens on
    // final code-block segments. effective_segment_* merges contributions that
    // continue an existing segment before building pass-level boundaries.
    let mut byte_offset = 0
    for seg_idx in 0..<effective_segment_passes.length() {
      let seg_len = effective_segment_lengths[seg_idx]
      let seg_passes = effective_segment_passes[seg_idx]
      // First pass of this segment: extract segment bytes for MQ re-init
      pass_segment_starts.push(true)
      if seg_len > 0 && byte_offset + seg_len <= codeword.length() {
        let seg_bytes : Array[Byte] = []
        for j in byte_offset..<(byte_offset + seg_len) {
          seg_bytes.push(codeword[j])
        }
        pass_segments.push(Bytes::from_iter(seg_bytes.iter()))
      } else {
        pass_segments.push(Bytes::new(0))
      }
      // Remaining passes in this segment: empty (no re-init)
      for _ in 1..<seg_passes {
        pass_segment_starts.push(false)
        pass_segments.push(Bytes::new(0))
      }
      byte_offset += seg_len
    }
  } else {
    pass_segment_starts.push(true)
    pass_segments.push(codeword)
  }
  // Initialize MQ contexts
  let contexts_v = @mq.tier1_annex_c_reset_contexts(
    @mq.TIER1_ANNEX_C_DEFAULT_CONTEXT_COUNT,
  )
  guard contexts_v is Ok(contexts0) else {
    return Err("codeblock decode: context reset failed")
  }
  let k_max_base = if subband_max_bit_planes > 0 {
    subband_max_bit_planes
  } else {
    precision_bits
  }
  let k_max = k_max_base + roishift
  // T.800-2015 D.3.1: Tier-1 start bit-plane:
  // bpno_plus_one = k_max + 1 - zbp.
  let initial_bpno_plus_one = k_max + 1 - zbp
  // T.800-2015 D.6: RAW/MQ mode is selected at each segment start,
  // including zero-length BYPASS segments. pass_segment_starts preserves
  // those boundaries explicitly so mode switches stay synchronized.
  // Decode MQ decisions
  let decode_v = if has_termall && pass_segments.length() > 1 {
    @mq.tier1_annex_c_decode_mini_block_pass_segments(
      pass_segments,
      contexts0,
      cb_w,
      cb_h,
      passes,
      false,
      code_block_style~,
      subband_type~,
      initial_bpno_plus_one~,
      roishift~,
    )
  } else if has_multi_segments && pass_segments.length() > 1 {
    // T.800-2015 B.10.7: Multi-segment codeblocks from either:
    // - BYPASS (0x01): separate MQ/RAW segments
    // - Multi-layer accumulation: each layer is a segment requiring MQ re-init
    // Must pass segment boundaries for proper MQ initialization.
    let codewords : Array[Bytes] = [codeword]
    let boot_v = @mq.tier1_annex_c_bootstrap_from_codewords(codewords)
    guard boot_v is Ok(boot) else {
      return Err("codeblock decode: bootstrap failed")
    }
    @mq.tier1_annex_c_decode_mini_block_passes(
      boot,
      codewords,
      contexts0,
      cb_w,
      cb_h,
      passes,
      false,
      code_block_style~,
      pass_segments~,
      pass_segment_starts~,
      subband_type~,
      initial_bpno_plus_one~,
      roishift~,
    )
  } else {
    let codewords : Array[Bytes] = [codeword]
    let boot_v = @mq.tier1_annex_c_bootstrap_from_codewords(codewords)
    guard boot_v is Ok(boot) else {
      return Err("codeblock decode: bootstrap failed")
    }
    @mq.tier1_annex_c_decode_mini_block_passes(
      boot,
      codewords,
      contexts0,
      cb_w,
      cb_h,
      passes,
      false,
      code_block_style~,
      subband_type~,
      initial_bpno_plus_one~,
      roishift~,
    )
  }
  guard decode_v is Ok((norm_contexts, norm_decisions, _)) else {
    return Err("codeblock decode: MQ decode failed")
  }
  // Extract coefficient values
  let block_v = @t1.tier1_normative_preview_sample_values_mini_block(
    cb_w,
    cb_h,
    passes,
    zbp,
    norm_decisions,
    code_block_style~,
  )
  guard block_v is Ok((values, _)) else {
    return Err("codeblock decode: coeff extraction failed")
  }
  let helper_postroi : Array[Int]? = if packet_audit &&
    quantization_style != 0 &&
    roishift > 0 {
    let helper_v = @t1.tier1_fixedpoint_sample_values_mini_block(
      cb_w,
      cb_h,
      passes,
      initial_bpno_plus_one,
      norm_decisions,
      code_block_style~,
    )
    if helper_v is Ok((helper_values, _)) {
      let postroi : Array[Int] = []
      for v in helper_values {
        let positioned_descaled = if roishift > 0 {
          let mag = if v >= 0 { v } else { -v }
          let thresh = 1 << roishift
          if mag >= thresh {
            let descaled = mag >> roishift
            if v < 0 {
              -descaled
            } else {
              descaled
            }
          } else {
            v
          }
        } else {
          v
        }
        postroi.push(positioned_descaled)
      }
      Some(postroi)
    } else {
      None
    }
  } else {
    None
  }
  let helper_postroi_bpminus1 : Array[Int]? = if packet_audit &&
    quantization_style != 0 &&
    roishift > 0 &&
    initial_bpno_plus_one > 0 {
    let helper_v = @t1.tier1_fixedpoint_sample_values_mini_block(
      cb_w,
      cb_h,
      passes,
      initial_bpno_plus_one - 1,
      norm_decisions,
      code_block_style~,
    )
    if helper_v is Ok((helper_values, _)) {
      let postroi : Array[Int] = []
      for v in helper_values {
        let positioned_descaled = if roishift > 0 {
          let mag = if v >= 0 { v } else { -v }
          let thresh = 1 << roishift
          if mag >= thresh {
            let descaled = mag >> roishift
            if v < 0 {
              -descaled
            } else {
              descaled
            }
          } else {
            v
          }
        } else {
          v
        }
        postroi.push(positioned_descaled)
      }
      Some(postroi)
    } else {
      None
    }
  } else {
    None
  }
  let reversible_helper_raw_values : Array[Int]? = if packet_audit &&
    quantization_style == 0 {
    let helper_v = @t1.tier1_fixedpoint_sample_values_mini_block(
      cb_w,
      cb_h,
      passes,
      if initial_bpno_plus_one > 0 {
        initial_bpno_plus_one - 1
      } else {
        initial_bpno_plus_one
      },
      norm_decisions,
      code_block_style~,
    )
    if helper_v is Ok((helper_values, _)) &&
      helper_values.length() == values.length() {
      Some(helper_values)
    } else {
      None
    }
  } else {
    None
  }
  let reversible_helper_values : Array[Int]? = if quantization_style == 0 {
    let helper_v = @t1.tier1_fixedpoint_sample_values_mini_block(
      cb_w,
      cb_h,
      passes,
      if initial_bpno_plus_one > 0 {
        initial_bpno_plus_one - 1
      } else {
        initial_bpno_plus_one
      },
      norm_decisions,
      code_block_style~,
    )
    if helper_v is Ok((helper_values, _)) &&
      helper_values.length() == values.length() {
      let normalized_values : Array[Int] = []
      for v in helper_values {
        normalized_values.push(v / 2)
      }
      Some(normalized_values)
    } else {
      None
    }
  } else {
    None
  }
  let roi_helper_values : Array[Int]? = if quantization_style != 0 &&
    roishift > 0 &&
    initial_bpno_plus_one > 0 {
    let helper_v = @t1.tier1_fixedpoint_sample_values_mini_block(
      cb_w,
      cb_h,
      passes,
      initial_bpno_plus_one - 1,
      norm_decisions,
      code_block_style~,
    )
    if helper_v is Ok((helper_values, _)) &&
      helper_values.length() == values.length() {
      Some(helper_values)
    } else {
      None
    }
  } else {
    None
  }
  let lossy_bpminus1_helper_values : Array[Int]? = if quantization_style != 0 &&
    roishift == 0 &&
    (
      code_block_style == 0x19 ||
      (quantization_style == 2 && code_block_style == 0)
    ) &&
    initial_bpno_plus_one > 0 {
    // Expounded quantization can require the helper's lower start plane to
    // Expounded quantization may require lower start plane for correct fixed-point values.
    let helper_v = @t1.tier1_fixedpoint_sample_values_mini_block(
      cb_w,
      cb_h,
      passes,
      initial_bpno_plus_one - 1,
      norm_decisions,
      code_block_style~,
    )
    if helper_v is Ok((helper_values, _)) &&
      helper_values.length() == values.length() {
      Some(helper_values)
    } else {
      None
    }
  } else {
    None
  }
  // Apply bit-plane scaling (T.800-2015 D.3.1)
  // K_max from QCD gives the total magnitude bit-planes for this subband.
  // T.800-2015 H.1: When ROI shift is present, the effective bit-plane count
  // is K_max + roishift (ROI coefficients are shifted up by roishift).
  // shift = K_max_effective - zbp - num_decoded_bp positions decoded bits correctly.
  // num_bp counts reconstructed bit-planes for shift positioning.
  // Baseline uses complete bit-planes, but some lossy paths need one extra
  // touched plane to ensure correct fixed-point positioning after Tier-1 decode.
  let num_bp = tier1_lossy_positioned_bitplane_count(
    passes, quantization_style, code_block_style, cb_w, cb_h,
  )
  let shift = k_max - zbp - num_bp
  // Mid-point reconstruction for irreversible (9/7) path:
  // For qstyle != 0, add half the LSB (1 << (shift-1)) to non-zero coefficients
  // so the reconstructed value sits at the midpoint of the quantization interval,
  // T.800-2015 D.3.1/H.1: midpoint reconstruction with ROI descaling.
  let midpoint = if quantization_style != 0 && shift >= 1 {
    1 << (shift - 1)
  } else {
    0
  }
  let scaled : Array[Int] = []
  for i in 0..<values.length() {
    let v = values[i]
    // T.800-2015 D.3.1: Position decoded bits at correct magnitude
    // shift > 0: left-shift to place MSB at K_max position
    // shift < 0: right-shift when more precision decoded than K_max allows
    // shift = 0: no adjustment needed
    let positioned = if reversible_helper_values is Some(helper_values) {
      helper_values[i]
    } else if roi_helper_values is Some(helper_values) {
      helper_values[i]
    } else if lossy_bpminus1_helper_values is Some(helper_values) {
      helper_values[i]
    } else if shift > 0 {
      let shifted = v << shift
      if midpoint > 0 && v != 0 {
        if shifted > 0 {
          shifted + midpoint
        } else {
          shifted - midpoint
        }
      } else {
        shifted
      }
    } else if shift < 0 {
      // Right-shift for negative shift (more precision than needed)
      v >> -shift
    } else {
      v
    }
    // T.800-2015 H.1: ROI descaling (maxshift method).
    // Coefficients with magnitude >= 2^roishift are ROI: right-shift by roishift.
    // Coefficients below threshold are background: keep as-is.
    let positioned_descaled = if roishift > 0 {
      let mag = if positioned >= 0 { positioned } else { -positioned }
      let thresh = 1 << roishift
      if mag >= thresh {
        let descaled = mag >> roishift
        if positioned < 0 {
          -descaled
        } else {
          descaled
        }
      } else {
        positioned
      }
    } else {
      positioned
    }
    // Lossy path keeps coefficients in x2 fixed-point so that shift==0
    // can still preserve the 0.5 LSB midpoint before dequantization.
    if quantization_style != 0 {
      if roi_helper_values is Some(_) || lossy_bpminus1_helper_values is Some(_) {
        scaled.push(positioned_descaled)
        continue
      }
      let mut lossy_fp2 = positioned_descaled << 1
      if shift == 0 && roishift == 0 && positioned_descaled != 0 {
        lossy_fp2 += if positioned_descaled > 0 { 1 } else { -1 }
      }
      scaled.push(lossy_fp2)
    } else {
      scaled.push(positioned_descaled)
    }
  }
  if reversible_helper_raw_values is Some(helper_vals) {
    print_audit_cblk_stats(
      "recon-audit:cblk-helper-reversible-raw", audit_label, audit_comp, audit_res,
      audit_sb, audit_cbx, audit_cby, helper_vals,
    )
    if audit_label == "single" &&
      audit_comp == 0 &&
      audit_res == 3 &&
      audit_sb == 1 &&
      audit_cbx == 0 &&
      audit_cby == 0 {
      let byte_preview_offsets = [1519, 1520, 1521, 1522, 1523, 1524]
      let byte_preview_parts : Array[String] = []
      for off in byte_preview_offsets {
        let byte_v = if off < codeword.length() {
          codeword[off].to_int()
        } else {
          -1
        }
        byte_preview_parts.push("\{off}=\{byte_v}")
      }
      println(
        "recon-audit:cblk-bytes:label=\{audit_label} c=\{audit_comp} r=\{audit_res} sb=\{audit_sb} cbx=\{audit_cbx} cby=\{audit_cby} \{byte_preview_parts}",
      )
      let pass_v = @t1.tier1_fixedpoint_sample_values_mini_block_pass_snapshots(
        cb_w,
        cb_h,
        passes,
        initial_bpno_plus_one,
        norm_decisions,
        code_block_style~,
      )
      if pass_v is Ok((snapshots, _)) {
        for pass_idx in 0..<snapshots.length() {
          let snapshot_values : Array[Int] = if quantization_style == 0 {
            let normalized : Array[Int] = []
            for v in snapshots[pass_idx] {
              normalized.push(v / 2)
            }
            normalized
          } else {
            snapshots[pass_idx]
          }
          print_audit_cblk_stats(
            "recon-audit:cblk-helper-pass-\{pass_idx}",
            audit_label,
            audit_comp,
            audit_res,
            audit_sb,
            audit_cbx,
            audit_cby,
            snapshot_values,
          )
        }
      }
      for target_pass in [22, 23] {
        let event_v = @t1.tier1_fixedpoint_sample_values_mini_block_target_pass_events(
          cb_w,
          cb_h,
          passes,
          initial_bpno_plus_one,
          norm_decisions,
          norm_contexts,
          target_pass,
          code_block_style~,
        )
        if event_v is Ok((events, event_indices, _)) {
          for event in events {
            println(
              "recon-audit:cblk-helper-pass-event:label=\{audit_label} c=\{audit_comp} r=\{audit_res} sb=\{audit_sb} cbx=\{audit_cbx} cby=\{audit_cby} \{event}",
            )
          }
          if event_indices.length() > 0 {
            let audit_contexts_v = @mq.tier1_annex_c_reset_contexts(
              @mq.TIER1_ANNEX_C_DEFAULT_CONTEXT_COUNT,
            )
            let audit_contexts0 = if audit_contexts_v is Ok(fresh) {
              fresh
            } else {
              []
            }
            if pass_segments.length() > 0 {
              let codewords : Array[Bytes] = pass_segments
              let boot_v = @mq.tier1_annex_c_bootstrap_from_codewords(codewords)
              if boot_v is Ok(boot) && audit_contexts0.length() > 0 {
                ignore(
                  @mq.tier1_annex_c_decode_mini_block_passes(
                    boot,
                    codewords,
                    audit_contexts0,
                    cb_w,
                    cb_h,
                    passes,
                    false,
                    code_block_style~,
                    pass_segments~,
                    pass_segment_starts~,
                    subband_type~,
                    initial_bpno_plus_one~,
                    roishift~,
                    trace_target_pass=target_pass,
                    trace_max_events=512,
                  ),
                )
              }
            } else {
              let codewords : Array[Bytes] = [codeword]
              let boot_v = @mq.tier1_annex_c_bootstrap_from_codewords(codewords)
              if boot_v is Ok(boot) && audit_contexts0.length() > 0 {
                ignore(
                  @mq.tier1_annex_c_decode_mini_block_passes(
                    boot,
                    codewords,
                    audit_contexts0,
                    cb_w,
                    cb_h,
                    passes,
                    false,
                    code_block_style~,
                    subband_type~,
                    initial_bpno_plus_one~,
                    roishift~,
                    trace_target_pass=target_pass,
                    trace_max_events=512,
                  ),
                )
              }
            }
          }
        }
      }
    }
  }
  if helper_postroi is Some(helper_vals) {
    print_audit_cblk_stats(
      "recon-audit:cblk-helper-postroi", audit_label, audit_comp, audit_res, audit_sb,
      audit_cbx, audit_cby, helper_vals,
    )
  }
  if helper_postroi_bpminus1 is Some(helper_vals) {
    print_audit_cblk_stats(
      "recon-audit:cblk-helper-postroi-bpminus1", audit_label, audit_comp, audit_res,
      audit_sb, audit_cbx, audit_cby, helper_vals,
    )
  }
  Ok(scaled)
}

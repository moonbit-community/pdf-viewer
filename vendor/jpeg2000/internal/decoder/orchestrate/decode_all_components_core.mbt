///|
fn decode_output_component_from_accumulated(
  accumulated : Array[Array[@layer.AccumulatedCB]],
  width : Int,
  height : Int,
  decomp_levels : Int,
  bits_per_component : Int,
  is_signed : Bool,
  pkt_hdr_style : Int,
  qcd : @core.QcdMetadata,
  transformation : Int,
  tcx0 : Int,
  tcy0 : Int,
  roishift : Int,
  component_index : Int,
  packet_audit? : Bool = false,
  audit_label? : String = "",
) -> Result[Array[Int], String] {
  if transformation == 0 {
    let comp_vf = @layer.decode_component_dwt_from_accumulated_float(
      accumulated,
      width,
      height,
      decomp_levels,
      bits_per_component,
      pkt_hdr_style,
      qcd,
      transformation~,
      tcx0~,
      tcy0~,
      roishift~,
      packet_audit~,
      audit_label~,
      audit_comp=component_index,
    )
    guard comp_vf is Ok(reconstructed_f) else {
      return Err("seq-dwt decode: component \{component_index} decode failed")
    }
    if packet_audit {
      print_audit_sample_stats_float_exact(
        "recon-audit:final-float", audit_label, component_index, reconstructed_f,
      )
      print_audit_sample_stats_float(
        "recon-audit", audit_label, component_index, reconstructed_f,
      )
    }
    return Ok(
      clamp_float_component_output(
        reconstructed_f, bits_per_component, is_signed,
      ),
    )
  }
  let comp_v = @layer.decode_component_dwt_from_accumulated(
    accumulated,
    width,
    height,
    decomp_levels,
    bits_per_component,
    pkt_hdr_style,
    qcd,
    transformation~,
    tcx0~,
    tcy0~,
    roishift~,
    packet_audit~,
    audit_label~,
    audit_comp=component_index,
  )
  guard comp_v is Ok(reconstructed) else {
    return Err("seq-dwt decode: component \{component_index} decode failed")
  }
  if packet_audit {
    print_audit_sample_stats(
      "recon-audit", audit_label, component_index, reconstructed,
    )
  }
  Ok(clamp_int_component_output(reconstructed, bits_per_component, is_signed))
}

///|
fn decode_dwt_component_planes_from_sequential_packets(
  stream : @core.Codestream,
  sod_payloads : Array[Bytes],
  c0_width : Int,
  c0_height : Int,
  precision_bits : Int,
  is_signed : Bool,
  num_components : Int,
  tcx0? : Int = 0,
  tcy0? : Int = 0,
  tile_index? : Int = -1,
  comp_roishifts? : Array[Int] = [],
  tile_cod? : @core.CodMetadata? = None,
  tile_qcd? : @core.QcdMetadata? = None,
  poc_entries? : Array[@core.PocMetadata] = [],
  relocated_packet_headers? : Bytes = b"",
  packet_audit? : Bool = false,
  audit_label? : String = "",
  packet_audit_limit? : Int = 300,
) -> Result[(Array[DecodeComponentPlaneInternal], Int), String] {
  let cod : @core.CodMetadata = match tile_cod {
    Some(tc) => tc
    None =>
      match stream.metadata.cod {
        Some(c) => c
        None => return Err("seq-dwt decode: missing COD")
      }
  }
  let qcd : @core.QcdMetadata = match tile_qcd {
    Some(tq) => tq
    None =>
      match stream.metadata.qcd {
        Some(q) => q
        None => return Err("seq-dwt decode: missing QCD")
      }
  }
  let decomp_levels = cod.decomposition_levels
  if sod_payloads.length() == 0 {
    return Err("seq-dwt decode: no SOD payloads")
  }
  let merged_parts : Array[Byte] = []
  for sod_part in sod_payloads {
    for byte in sod_part {
      merged_parts.push(byte)
    }
  }
  let merged_sod_payload = Bytes::from_iter(merged_parts.iter())
  if merged_sod_payload.length() == 0 {
    return Err("seq-dwt decode: empty SOD payload stream")
  }
  let pkt_hdr_style = cod.code_block_style
  let uses_mct = cod.multiple_component_transform == 1 && num_components >= 3
  let nom_cb_w = 1 << cod.code_block_width_exponent
  let nom_cb_h = 1 << cod.code_block_height_exponent
  let tile_dims = @geometry.collect_per_component_tile_dimensions(
    stream, num_components, c0_width, c0_height, tcx0, tcy0, tile_index,
  )
  let per_comp_w = tile_dims.per_comp_w
  let per_comp_h = tile_dims.per_comp_h
  let per_comp_xrsiz = tile_dims.per_comp_xrsiz
  let per_comp_yrsiz = tile_dims.per_comp_yrsiz
  let per_comp_tcx0 = tile_dims.per_comp_tcx0
  let per_comp_tcy0 = tile_dims.per_comp_tcy0
  let effective_tile_index = tile_dims.effective_tile_index
  let per_comp_bits = collect_component_precision_bits(
    stream, num_components, precision_bits,
  )
  let per_comp_signed = collect_component_signed_flags(
    stream, num_components, is_signed,
  )
  @geometry.fill_remaining_component_dimensions(
    tile_dims, stream, num_components, c0_width, c0_height, tcx0, tcy0,
  )
  let codec_meta = @geometry.collect_per_component_codec_metadata(
    stream, num_components, cod, effective_tile_index,
  )
  let per_comp_decomp = codec_meta.per_comp_decomp
  let per_comp_cbw = codec_meta.per_comp_cbw
  let per_comp_cbh = codec_meta.per_comp_cbh
  let per_comp_cblk_style = codec_meta.per_comp_cblk_style
  let per_comp_precinct_size_bytes = codec_meta.per_comp_precinct_size_bytes
  let effective_poc : Array[@core.PocMetadata] = []
  if poc_entries.length() > 0 {
    for poc in poc_entries {
      effective_poc.push(poc)
    }
  } else {
    for poc in stream.metadata.poc {
      if poc.in_main_header {
        effective_poc.push(poc)
      }
    }
  }
  let packet_tcx0 = if per_comp_tcx0.length() > 0 {
    per_comp_tcx0[0]
  } else {
    tcx0
  }
  let packet_tcy0 = if per_comp_tcy0.length() > 0 {
    per_comp_tcy0[0]
  } else {
    tcy0
  }
  let accum_v = @layer.split_sod_accumulate_multi_layer(
    merged_sod_payload,
    c0_width,
    c0_height,
    decomp_levels,
    num_components,
    cod.layers,
    cod.progression_order,
    pkt_hdr_style,
    cb_width=nom_cb_w,
    cb_height=nom_cb_h,
    comp_widths=per_comp_w,
    comp_heights=per_comp_h,
    comp_decomp_levels=per_comp_decomp,
    comp_cb_widths=per_comp_cbw,
    comp_cb_heights=per_comp_cbh,
    comp_xrsizs=per_comp_xrsiz,
    comp_yrsizs=per_comp_yrsiz,
    comp_tcx0s=per_comp_tcx0,
    comp_tcy0s=per_comp_tcy0,
    comp_code_block_styles=per_comp_cblk_style,
    comp_precinct_size_bytes=per_comp_precinct_size_bytes,
    precinct_size_bytes=cod.precinct_size_bytes,
    tcx0=packet_tcx0,
    tcy0=packet_tcy0,
    uses_sop=cod.uses_sop,
    uses_eph=cod.uses_eph,
    poc_entries=effective_poc,
    relocated_packet_headers~,
    packet_audit~,
    audit_label~,
    packet_audit_limit~,
  )
  guard accum_v is Ok((all_comp_accum, relocated_header_consumed)) else {
    return Err("seq-dwt decode: multi-layer accumulation failed")
  }
  let planes : Array[DecodeComponentPlaneInternal] = []
  if uses_mct {
    if all_comp_accum.length() < 3 {
      return Err(
        "seq-dwt decode: inverse MCT requires 3 accumulated components",
      )
    }
    let trans0 = @geometry.get_component_transformation(
      stream,
      0,
      fallback_cod=Some(cod),
      tile_index=effective_tile_index,
    )
    let trans1 = @geometry.get_component_transformation(
      stream,
      1,
      fallback_cod=Some(cod),
      tile_index=effective_tile_index,
    )
    let trans2 = @geometry.get_component_transformation(
      stream,
      2,
      fallback_cod=Some(cod),
      tile_index=effective_tile_index,
    )
    let decomp0 = @geometry.get_component_decomposition_levels(
      stream,
      0,
      fallback_cod=Some(cod),
      tile_index=effective_tile_index,
    )
    let decomp1 = @geometry.get_component_decomposition_levels(
      stream,
      1,
      fallback_cod=Some(cod),
      tile_index=effective_tile_index,
    )
    let decomp2 = @geometry.get_component_decomposition_levels(
      stream,
      2,
      fallback_cod=Some(cod),
      tile_index=effective_tile_index,
    )
    let qcd0 = @geometry.get_component_qcd_with_fallback(
      stream,
      0,
      qcd,
      tile_index=effective_tile_index,
    )
    let qcd1 = @geometry.get_component_qcd_with_fallback(
      stream,
      1,
      qcd,
      tile_index=effective_tile_index,
    )
    let qcd2 = @geometry.get_component_qcd_with_fallback(
      stream,
      2,
      qcd,
      tile_index=effective_tile_index,
    )
    let c0_tcx0 = component_int_at(per_comp_tcx0, 0, tcx0)
    let c0_tcy0 = component_int_at(per_comp_tcy0, 0, tcy0)
    let c1_w = component_int_at(per_comp_w, 1, c0_width)
    let c1_h = component_int_at(per_comp_h, 1, c0_height)
    let c1_tcx0 = component_int_at(per_comp_tcx0, 1, tcx0)
    let c1_tcy0 = component_int_at(per_comp_tcy0, 1, tcy0)
    let c2_w = component_int_at(per_comp_w, 2, c0_width)
    let c2_h = component_int_at(per_comp_h, 2, c0_height)
    let c2_tcx0 = component_int_at(per_comp_tcx0, 2, tcx0)
    let c2_tcy0 = component_int_at(per_comp_tcy0, 2, tcy0)
    let roi0 = component_int_at(comp_roishifts, 0, 0)
    let roi1 = component_int_at(comp_roishifts, 1, 0)
    let roi2 = component_int_at(comp_roishifts, 2, 0)
    let c0_pkt_hdr_style = component_int_at(
      per_comp_cblk_style, 0, pkt_hdr_style,
    )
    let c1_pkt_hdr_style = component_int_at(
      per_comp_cblk_style, 1, pkt_hdr_style,
    )
    let c2_pkt_hdr_style = component_int_at(
      per_comp_cblk_style, 2, pkt_hdr_style,
    )
    if trans0 == 0 {
      let y_vf = @layer.decode_component_dwt_from_accumulated_float(
        all_comp_accum[0],
        c0_width,
        c0_height,
        decomp0,
        component_int_at(per_comp_bits, 0, precision_bits),
        c0_pkt_hdr_style,
        qcd0,
        transformation=trans0,
        tcx0=c0_tcx0,
        tcy0=c0_tcy0,
        roishift=roi0,
        packet_audit~,
        audit_label~,
        audit_comp=0,
      )
      guard y_vf is Ok(y_samples_f) else {
        return Err("seq-dwt decode: component 0 (Y) failed")
      }
      let cb_vf = @layer.decode_component_dwt_from_accumulated_float(
        all_comp_accum[1],
        c1_w,
        c1_h,
        decomp1,
        component_int_at(per_comp_bits, 1, precision_bits),
        c1_pkt_hdr_style,
        qcd1,
        transformation=trans1,
        tcx0=c1_tcx0,
        tcy0=c1_tcy0,
        roishift=roi1,
        packet_audit~,
        audit_label~,
        audit_comp=1,
      )
      guard cb_vf is Ok(cb_samples_f) else {
        return Err("seq-dwt decode: component 1 (Cb/Db) failed")
      }
      let cr_vf = @layer.decode_component_dwt_from_accumulated_float(
        all_comp_accum[2],
        c2_w,
        c2_h,
        decomp2,
        component_int_at(per_comp_bits, 2, precision_bits),
        c2_pkt_hdr_style,
        qcd2,
        transformation=trans2,
        tcx0=c2_tcx0,
        tcy0=c2_tcy0,
        roishift=roi2,
        packet_audit~,
        audit_label~,
        audit_comp=2,
      )
      guard cr_vf is Ok(cr_samples_f) else {
        return Err("seq-dwt decode: component 2 (Cr/Dr) failed")
      }
      let mct_vf = @mct.tier1_annex_g_inverse_ict_components_float(
        y_samples_f, cb_samples_f, cr_samples_f,
      )
      guard mct_vf is Ok((r_comp_f, g_comp_f, b_comp_f)) else {
        return Err("seq-dwt decode: inverse MCT failed")
      }
      planes.push({
        component_index: 0,
        width: c0_width,
        height: c0_height,
        bits_per_component: component_int_at(per_comp_bits, 0, precision_bits),
        is_signed: component_bool_at(per_comp_signed, 0, is_signed),
        samples: clamp_float_component_output(
          r_comp_f,
          component_int_at(per_comp_bits, 0, precision_bits),
          component_bool_at(per_comp_signed, 0, is_signed),
        ),
      })
      planes.push({
        component_index: 1,
        width: c1_w,
        height: c1_h,
        bits_per_component: component_int_at(per_comp_bits, 1, precision_bits),
        is_signed: component_bool_at(per_comp_signed, 1, is_signed),
        samples: clamp_float_component_output(
          g_comp_f,
          component_int_at(per_comp_bits, 1, precision_bits),
          component_bool_at(per_comp_signed, 1, is_signed),
        ),
      })
      planes.push({
        component_index: 2,
        width: c2_w,
        height: c2_h,
        bits_per_component: component_int_at(per_comp_bits, 2, precision_bits),
        is_signed: component_bool_at(per_comp_signed, 2, is_signed),
        samples: clamp_float_component_output(
          b_comp_f,
          component_int_at(per_comp_bits, 2, precision_bits),
          component_bool_at(per_comp_signed, 2, is_signed),
        ),
      })
    } else {
      let y_v = @layer.decode_component_dwt_from_accumulated(
        all_comp_accum[0],
        c0_width,
        c0_height,
        decomp0,
        component_int_at(per_comp_bits, 0, precision_bits),
        c0_pkt_hdr_style,
        qcd0,
        transformation=trans0,
        tcx0=c0_tcx0,
        tcy0=c0_tcy0,
        roishift=roi0,
        packet_audit~,
        audit_label~,
        audit_comp=0,
      )
      guard y_v is Ok(y_samples) else {
        return Err("seq-dwt decode: component 0 (Y) failed")
      }
      let cb_v = @layer.decode_component_dwt_from_accumulated(
        all_comp_accum[1],
        c1_w,
        c1_h,
        decomp1,
        component_int_at(per_comp_bits, 1, precision_bits),
        c1_pkt_hdr_style,
        qcd1,
        transformation=trans1,
        tcx0=c1_tcx0,
        tcy0=c1_tcy0,
        roishift=roi1,
        packet_audit~,
        audit_label~,
        audit_comp=1,
      )
      guard cb_v is Ok(cb_samples) else {
        return Err("seq-dwt decode: component 1 (Cb/Db) failed")
      }
      let cr_v = @layer.decode_component_dwt_from_accumulated(
        all_comp_accum[2],
        c2_w,
        c2_h,
        decomp2,
        component_int_at(per_comp_bits, 2, precision_bits),
        c2_pkt_hdr_style,
        qcd2,
        transformation=trans2,
        tcx0=c2_tcx0,
        tcy0=c2_tcy0,
        roishift=roi2,
        packet_audit~,
        audit_label~,
        audit_comp=2,
      )
      guard cr_v is Ok(cr_samples) else {
        return Err("seq-dwt decode: component 2 (Cr/Dr) failed")
      }
      let mct_v = @mct.tier1_annex_g_inverse_rct_components(
        y_samples, cb_samples, cr_samples,
      )
      guard mct_v is Ok((r_comp, g_comp, b_comp)) else {
        return Err("seq-dwt decode: inverse MCT failed")
      }
      planes.push({
        component_index: 0,
        width: c0_width,
        height: c0_height,
        bits_per_component: component_int_at(per_comp_bits, 0, precision_bits),
        is_signed: component_bool_at(per_comp_signed, 0, is_signed),
        samples: clamp_int_component_output(
          r_comp,
          component_int_at(per_comp_bits, 0, precision_bits),
          component_bool_at(per_comp_signed, 0, is_signed),
        ),
      })
      planes.push({
        component_index: 1,
        width: c1_w,
        height: c1_h,
        bits_per_component: component_int_at(per_comp_bits, 1, precision_bits),
        is_signed: component_bool_at(per_comp_signed, 1, is_signed),
        samples: clamp_int_component_output(
          g_comp,
          component_int_at(per_comp_bits, 1, precision_bits),
          component_bool_at(per_comp_signed, 1, is_signed),
        ),
      })
      planes.push({
        component_index: 2,
        width: c2_w,
        height: c2_h,
        bits_per_component: component_int_at(per_comp_bits, 2, precision_bits),
        is_signed: component_bool_at(per_comp_signed, 2, is_signed),
        samples: clamp_int_component_output(
          b_comp,
          component_int_at(per_comp_bits, 2, precision_bits),
          component_bool_at(per_comp_signed, 2, is_signed),
        ),
      })
    }
    for ci in 3..<num_components {
      if ci >= all_comp_accum.length() {
        return Err("seq-dwt decode: component \{ci} accumulation missing")
      }
      let trans = @geometry.get_component_transformation(
        stream,
        ci,
        fallback_cod=Some(cod),
        tile_index=effective_tile_index,
      )
      let decomp = @geometry.get_component_decomposition_levels(
        stream,
        ci,
        fallback_cod=Some(cod),
        tile_index=effective_tile_index,
      )
      let comp_qcd = @geometry.get_component_qcd_with_fallback(
        stream,
        ci,
        qcd,
        tile_index=effective_tile_index,
      )
      let samples_v = decode_output_component_from_accumulated(
        all_comp_accum[ci],
        component_int_at(per_comp_w, ci, c0_width),
        component_int_at(per_comp_h, ci, c0_height),
        decomp,
        component_int_at(per_comp_bits, ci, precision_bits),
        component_bool_at(per_comp_signed, ci, is_signed),
        component_int_at(per_comp_cblk_style, ci, pkt_hdr_style),
        comp_qcd,
        trans,
        component_int_at(per_comp_tcx0, ci, tcx0),
        component_int_at(per_comp_tcy0, ci, tcy0),
        component_int_at(comp_roishifts, ci, 0),
        ci,
        packet_audit~,
        audit_label~,
      )
      guard samples_v is Ok(samples) else {
        return Err("seq-dwt decode: component \{ci} decode failed")
      }
      planes.push({
        component_index: ci,
        width: component_int_at(per_comp_w, ci, c0_width),
        height: component_int_at(per_comp_h, ci, c0_height),
        bits_per_component: component_int_at(per_comp_bits, ci, precision_bits),
        is_signed: component_bool_at(per_comp_signed, ci, is_signed),
        samples,
      })
    }
    return Ok((planes, relocated_header_consumed))
  }
  for ci in 0..<num_components {
    if ci >= all_comp_accum.length() {
      return Err("seq-dwt decode: component \{ci} accumulation missing")
    }
    let trans = @geometry.get_component_transformation(
      stream,
      ci,
      fallback_cod=Some(cod),
      tile_index=effective_tile_index,
    )
    let decomp = @geometry.get_component_decomposition_levels(
      stream,
      ci,
      fallback_cod=Some(cod),
      tile_index=effective_tile_index,
    )
    let comp_qcd = @geometry.get_component_qcd_with_fallback(
      stream,
      ci,
      qcd,
      tile_index=effective_tile_index,
    )
    let samples_v = decode_output_component_from_accumulated(
      all_comp_accum[ci],
      component_int_at(per_comp_w, ci, c0_width),
      component_int_at(per_comp_h, ci, c0_height),
      decomp,
      component_int_at(per_comp_bits, ci, precision_bits),
      component_bool_at(per_comp_signed, ci, is_signed),
      component_int_at(per_comp_cblk_style, ci, pkt_hdr_style),
      comp_qcd,
      trans,
      component_int_at(per_comp_tcx0, ci, tcx0),
      component_int_at(per_comp_tcy0, ci, tcy0),
      component_int_at(comp_roishifts, ci, 0),
      ci,
      packet_audit~,
      audit_label~,
    )
    guard samples_v is Ok(samples) else {
      return Err("seq-dwt decode: component \{ci} decode failed")
    }
    planes.push({
      component_index: ci,
      width: component_int_at(per_comp_w, ci, c0_width),
      height: component_int_at(per_comp_h, ci, c0_height),
      bits_per_component: component_int_at(per_comp_bits, ci, precision_bits),
      is_signed: component_bool_at(per_comp_signed, ci, is_signed),
      samples,
    })
  }
  Ok((planes, relocated_header_consumed))
}

///|

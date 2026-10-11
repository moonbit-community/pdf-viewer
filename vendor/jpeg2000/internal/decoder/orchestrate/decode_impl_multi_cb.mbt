///|
// Multi-codeblock no-DWT decode path.
// Extracted from decode_samples_impl to reduce monolithic function size.
fn try_decode_multi_codeblock(
  stream : @core.Codestream,
  simple_payloads : Array[Bytes],
  siz : @core.SizMetadata,
  c0 : @core.SizComponentMetadata,
  sample_count : Int,
  c0_width : Int,
  c0_height : Int,
  root_tile_index : Int,
) -> Result[DecodeSamplesInternalResult?, String] {
  guard stream.metadata.cod is Some(cod) else { return Ok(None) }
  let (
    c0_decomp_levels,
    cbw,
    cbh,
    code_block_style,
    c0_transformation,
    c0_qcd_opt,
  ) = @geometry.get_component_decode_context(
    stream,
    0,
    cod,
    fallback_qcd=stream.metadata.qcd,
    tile_index=root_tile_index,
  )
  if c0_decomp_levels != 0 {
    return Ok(None)
  }
  let grid_w = (c0_width + cbw - 1) / cbw
  let grid_h = (c0_height + cbh - 1) / cbh
  if grid_w * grid_h <= 1 {
    return Ok(None)
  }
  let multi_extract_v = if @profile.htj2k_signalled(stream) && cod.layers > 1 {
    let series_v = @a8.extract_multi_codeblock_packet_parts_series_if_plausible(
      stream, simple_payloads,
    )
    if series_v is Ok(_) {
      series_v
    } else {
      @a8.extract_multi_codeblock_first_packet_parts(stream, simple_payloads)
    }
  } else {
    @a8.extract_multi_codeblock_first_packet_parts(stream, simple_payloads)
  }
  if multi_extract_v is Err(_) {
    return Ok(None)
  }
  guard multi_extract_v is Ok((multi_parts_list, _, _)) else { return Ok(None) }
  if @profile.htj2k_signalled(stream) &&
    !@profile.htj2k_cleanup_only_subset_enabled(stream) {
    return Err(@codeblock.htj2k_decode_not_supported_error(stream))
  }
  if !@profile.tier1_minimal_reversible_subset_enabled(stream) {
    return Err("decode_samples tier1 subset rejected (multi-codeblock path)")
  }
  let ll_kmax = if c0_qcd_opt is Some(qcd_mc) {
    @quant.qcd_subband_max_bit_planes(
      qcd_mc,
      0,
      precision_bits=c0.precision_bits,
      transformation=c0_transformation,
      decomposition_levels=c0_decomp_levels,
    )
  } else {
    0
  }
  let quantization_style = if c0_qcd_opt is Some(qcd_mc) {
    qcd_mc.quantization_style
  } else {
    0
  }
  let roi_tile_index = if root_tile_index >= 0 { root_tile_index } else { 0 }
  let roi0 = if @profile.htj2k_signalled(stream) ||
    stream.metadata.rgn.length() > 0 {
    let roi_map = @roi.extract_roi_shift_per_tile_component(stream)
    @roi.get_roi_shift(roi_map, roi_tile_index, 0)
  } else {
    0
  }
  let coeffs_v = @codeblock.decode_multi_codeblock_coefficients(
    multi_parts_list,
    grid_w,
    grid_h,
    cbw,
    cbh,
    c0_width,
    c0_height,
    c0.precision_bits,
    code_block_style,
    subband_max_bit_planes=ll_kmax,
    quantization_style~,
    roishift=roi0,
  )
  if coeffs_v is Err(e) {
    return Err("multi-codeblock decode failed: \{e}")
  }
  guard coeffs_v is Ok(coefficients) else { return Ok(None) }
  let reconstructed = if c0_decomp_levels > 0 && c0_qcd_opt is Some(qcd_mc) {
    let idwt_v = @dwt.apply_inverse_dwt(
      coefficients,
      c0_width,
      c0_height,
      c0_decomp_levels,
      qcd_mc,
      c0.precision_bits,
      transformation=c0_transformation,
    )
    match idwt_v {
      Ok(r) => r
      Err(_) => coefficients
    }
  } else {
    coefficients
  }
  let dc_offset = if c0.is_signed { 0 } else { 1 << (c0.precision_bits - 1) }
  let clamped_values : Array[Int] = []
  for v in reconstructed {
    clamped_values.push(
      clamp_sample_for_signedness(
        v + dc_offset,
        c0.is_signed,
        precision_bits=c0.precision_bits,
      ),
    )
  }
  let sample_v = @input.make_sample_array_bytes_le(
    clamped_values,
    c0.precision_bits,
  )
  guard sample_v is Ok(sample_bytes) else {
    return Err("failed to build multi-codeblock sample buffer")
  }
  Ok(
    Some(
      make_decode_samples_result(
        sample_bytes,
        c0.precision_bits,
        c0.is_signed,
        sample_count,
        c0_width,
        c0_height,
        siz.csiz,
        "component0:raster:le:real_decode:DS-MULTI-CODEBLOCK-DECODE:grid_\{grid_w}x\{grid_h}",
      ),
    ),
  )
}

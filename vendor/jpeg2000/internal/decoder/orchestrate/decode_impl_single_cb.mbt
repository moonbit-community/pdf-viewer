///|
// Single-codeblock Tier-1 decode gates (HT and validation).
// Extracted from decode_samples_impl to reduce monolithic function size.
fn try_decode_single_codeblock_tier1(
  parts_list : Array[@a8.SingleCodeblockPacketParts],
  stream : @core.Codestream,
  siz : @core.SizMetadata,
  c0 : @core.SizComponentMetadata,
  sample_count : Int,
  c0_width : Int,
  c0_height : Int,
  root_tile_index : Int,
) -> Result[DecodeSamplesInternalResult?, String] {
  let mut total_codeword_bytes = 0
  for parts in parts_list {
    total_codeword_bytes += parts.codeword.length()
  }
  if total_codeword_bytes > 0 &&
    @a8.parts_are_minimal_zero_tier1_subset(parts_list) {
    return Err(
      "decode_samples minimal zero Tier-1 subset is not accepted as decoded output (DS-ZERO-PACKET-RECON:minimal_zero_tier1_subset)",
    )
  }
  if @profile.htj2k_signalled(stream) &&
    !@profile.htj2k_cleanup_only_subset_enabled(stream) {
    return Err(@codeblock.htj2k_decode_not_supported_error(stream))
  }
  if !@profile.tier1_minimal_reversible_subset_enabled(stream) {
    let codewords : Array[Bytes] = []
    for parts in parts_list {
      codewords.push(parts.codeword)
    }
    let preview_hex = @mq.tier1_preview_hex(codewords, 8)
    let first_debug = @a8.first_packet_parts_debug(parts_list)
    return Err(
      "decode_samples tier1 subset rejected (\{@profile.tier1_minimal_reversible_subset_reason(stream)}, preview=\{preview_hex}, \{first_debug})",
    )
  }
  // DS-SINGLE-CODEBLOCK-HT: HTJ2K no-DWT single-codeblock path
  if @profile.htj2k_signalled(stream) &&
    stream.metadata.cod is Some(cod) &&
    c0_width > 0 &&
    c0_height > 0 {
    let (
      c0_decomp_levels,
      _,
      _,
      c0_code_block_style,
      c0_transformation,
      c0_qcd_opt,
    ) = @geometry.get_component_decode_context(
      stream,
      0,
      cod,
      fallback_qcd=stream.metadata.qcd,
      tile_index=root_tile_index,
    )
    if c0_decomp_levels == 0 {
      let accum_v = @codeblock.htj2k_accumulate_single_codeblock_packet_parts(
        parts_list,
      )
      guard accum_v
        is Ok(
          (ht_codeword, ht_passes, zbp, ht_segment_lengths, ht_segment_passes)
        ) else {
        return Err("decode_samples single-codeblock HT accumulation failed")
      }
      let ll_kmax = if c0_qcd_opt is Some(qcd_ht) {
        let kmax = @quant.qcd_subband_max_bit_planes(
          qcd_ht,
          0,
          precision_bits=c0.precision_bits,
          transformation=c0_transformation,
          decomposition_levels=c0_decomp_levels,
        )
        if kmax > 0 {
          kmax
        } else {
          0
        }
      } else {
        0
      }
      let quantization_style = if c0_qcd_opt is Some(qcd_ht) {
        qcd_ht.quantization_style
      } else {
        0
      }
      let roi_tile_index = if root_tile_index >= 0 {
        root_tile_index
      } else {
        0
      }
      let roi0 = if @profile.htj2k_signalled(stream) ||
        stream.metadata.rgn.length() > 0 {
        let roi_map = @roi.extract_roi_shift_per_tile_component(stream)
        @roi.get_roi_shift(roi_map, roi_tile_index, 0)
      } else {
        0
      }
      let coeffs_v = @codeblock.decode_single_codeblock_coefficients(
        ht_codeword,
        c0_width,
        c0_height,
        ht_passes,
        zbp,
        c0.precision_bits,
        c0_code_block_style,
        segment_lengths=ht_segment_lengths,
        per_segment_passes=ht_segment_passes,
        subband_max_bit_planes=ll_kmax,
        quantization_style~,
        roishift=roi0,
      )
      guard coeffs_v is Ok(coeffs) else {
        if coeffs_v is Err(msg) {
          return Err(
            "decode_samples single-codeblock HT decode failed (\{msg})",
          )
        }
        return Err("decode_samples single-codeblock HT decode failed")
      }
      let dc_offset = if c0.is_signed {
        0
      } else {
        1 << (c0.precision_bits - 1)
      }
      let clamped_values : Array[Int] = []
      for v in coeffs {
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
        return Err("failed to build single-codeblock HT sample buffer")
      }
      return Ok(
        Some(
          make_decode_samples_result(
            sample_bytes,
            c0.precision_bits,
            c0.is_signed,
            sample_count,
            c0_width,
            c0_height,
            siz.csiz,
            "component0:raster:le:real_decode:DS-SINGLE-CODEBLOCK-HT:packets_\{parts_list.length()}",
          ),
        ),
      )
    }
  }
  Ok(None)
}

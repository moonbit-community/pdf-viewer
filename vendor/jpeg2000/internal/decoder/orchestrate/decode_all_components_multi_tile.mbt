///|
fn decode_multi_tile_all_components(
  stream : @core.Codestream,
  sod_payloads : Array[Bytes],
  siz : @core.SizMetadata,
  precision_bits : Int,
  is_signed : Bool,
  packet_audit? : Bool = false,
  packet_audit_limit? : Int = 300,
) -> Result[DecodeAllComponentsResult, String] {
  guard stream.metadata.cod is Some(_) else {
    return Err(
      "decode_samples_all_components multi-tile decode requires COD metadata",
    )
  }
  let num_tiles_x = (siz.xsiz - siz.xtosiz + siz.xtsiz - 1) / siz.xtsiz
  let num_tiles_y = (siz.ysiz - siz.ytosiz + siz.ytsiz - 1) / siz.ytsiz
  let num_tiles = num_tiles_x * num_tiles_y
  let tile_payloads_by_idx : Map[Int, Bytes] = {}
  match @input.collect_sod_payloads_by_tile(stream) {
    Some(grouped) =>
      for entry in grouped {
        let (idx, data) = entry
        tile_payloads_by_idx[idx] = data
      }
    _ =>
      for i in 0..<sod_payloads.length() {
        tile_payloads_by_idx[i] = sod_payloads[i]
      }
  }
  let relocated = collect_relocated_headers(stream)
  let tile_ppt_headers_by_idx = relocated.tile_ppt_headers_by_idx
  let global_ppm_headers = relocated.global_ppm_headers
  let tile_poc_by_idx = @geometry.collect_tile_part_poc_by_tile(
    stream,
    siz.csiz,
  )
  let per_comp_bits = collect_component_precision_bits(
    stream,
    siz.csiz,
    precision_bits,
  )
  let per_comp_signed = collect_component_signed_flags(
    stream,
    siz.csiz,
    is_signed,
  )
  let full_comp_widths : Array[Int] = []
  let full_comp_heights : Array[Int] = []
  let component_outputs : Array[Array[Int]] = []
  for ci in 0..<siz.csiz {
    let dims_v = @input.component_dimensions_from_siz(siz, ci)
    guard dims_v is Ok((comp_w, comp_h)) else {
      return Err(
        "decode_samples_all_components failed to determine component dimensions",
      )
    }
    full_comp_widths.push(comp_w)
    full_comp_heights.push(comp_h)
    let dc_init = if component_bool_at(per_comp_signed, ci, is_signed) {
      0
    } else {
      1 << (component_int_at(per_comp_bits, ci, precision_bits) - 1)
    }
    let output : Array[Int] = []
    for _ in 0..<(comp_w * comp_h) {
      output.push(dc_init)
    }
    component_outputs.push(output)
  }
  let use_relocated_ppt = relocated.has_ppt_headers
  let use_relocated_ppm = !use_relocated_ppt && relocated.has_ppm_headers
  let mut ppm_header_cursor = 0
  let roi_map = @roi.extract_roi_shift_per_tile_component(stream)
  for tile_row in 0..<num_tiles_y {
    for tile_col in 0..<num_tiles_x {
      let tile_idx = tile_row * num_tiles_x + tile_col
      guard tile_payloads_by_idx.get(tile_idx) is Some(raw_tile_payload) else {
        continue
      }
      let (_, _, tw, th, tcx0, tcy0) = @input.tile_component0_dims_and_origin_from_siz(
        siz, tile_col, tile_row,
      )
      if tw <= 0 || th <= 0 {
        continue
      }
      let tile_roi : Array[Int] = []
      for ci in 0..<siz.csiz {
        tile_roi.push(@roi.get_roi_shift(roi_map, tile_idx, ci))
      }
      let tile_relocated_headers : Bytes = if use_relocated_ppt {
        match tile_ppt_headers_by_idx.get(tile_idx) {
          Some(headers) => headers
          None => b""
        }
      } else if use_relocated_ppm {
        let len = global_ppm_headers.length()
        if ppm_header_cursor < len {
          global_ppm_headers[ppm_header_cursor:len].to_bytes()
        } else {
          b""
        }
      } else {
        b""
      }
      let tile_specific_cod = @geometry.get_tile_cod(stream, tile_idx)
      let tile_specific_qcd = @geometry.get_tile_qcd(stream, tile_idx)
      let tile_specific_poc : Array[@core.PocMetadata] = match
        tile_poc_by_idx.get(tile_idx) {
        Some(pocs) => pocs
        None => []
      }
      let tile_v = decode_dwt_component_planes_from_sequential_packets(
        stream,
        [raw_tile_payload],
        tw,
        th,
        precision_bits,
        is_signed,
        siz.csiz,
        tcx0~,
        tcy0~,
        tile_index=tile_idx,
        comp_roishifts=tile_roi,
        tile_cod=tile_specific_cod,
        tile_qcd=tile_specific_qcd,
        poc_entries=tile_specific_poc,
        relocated_packet_headers=tile_relocated_headers,
        packet_audit~,
        audit_label="tile\{tile_idx}",
        packet_audit_limit~,
      )
      if tile_v is Ok((tile_planes, consumed_headers)) {
        if use_relocated_ppm && consumed_headers > 0 {
          ppm_header_cursor += consumed_headers
          if ppm_header_cursor > global_ppm_headers.length() {
            ppm_header_cursor = global_ppm_headers.length()
          }
        }
        for plane in tile_planes {
          let ci = plane.component_index
          if ci < 0 || ci >= component_outputs.length() {
            continue
          }
          let (comp_x, comp_y, comp_w, comp_h, _, _) = @geometry.tile_component_dims_and_origin_from_siz(
            siz, tile_col, tile_row, ci,
          )
          let dst_width = full_comp_widths[ci]
          let dst_height = full_comp_heights[ci]
          let dst_output = component_outputs[ci]
          for sy in 0..<comp_h {
            for sx in 0..<comp_w {
              let src_index = sy * comp_w + sx
              let dst_x = comp_x + sx
              let dst_y = comp_y + sy
              if src_index < plane.samples.length() &&
                dst_x < dst_width &&
                dst_y < dst_height {
                dst_output[dst_y * dst_width + dst_x] = plane.samples[src_index]
              }
            }
          }
        }
      } else {
        for ci in 0..<siz.csiz {
          let (comp_x, comp_y, comp_w, comp_h, _, _) = @geometry.tile_component_dims_and_origin_from_siz(
            siz, tile_col, tile_row, ci,
          )
          let dst_width = full_comp_widths[ci]
          let dst_height = full_comp_heights[ci]
          let dc_fill = if component_bool_at(per_comp_signed, ci, is_signed) {
            0
          } else {
            1 << (component_int_at(per_comp_bits, ci, precision_bits) - 1)
          }
          let dst_output = component_outputs[ci]
          for sy in 0..<comp_h {
            for sx in 0..<comp_w {
              let dst_x = comp_x + sx
              let dst_y = comp_y + sy
              if dst_x < dst_width && dst_y < dst_height {
                dst_output[dst_y * dst_width + dst_x] = dc_fill
              }
            }
          }
        }
      }
    }
  }
  let planes : Array[DecodeComponentPlaneInternal] = []
  for ci in 0..<siz.csiz {
    planes.push({
      component_index: ci,
      width: full_comp_widths[ci],
      height: full_comp_heights[ci],
      bits_per_component: component_int_at(per_comp_bits, ci, precision_bits),
      is_signed: component_bool_at(per_comp_signed, ci, is_signed),
      samples: component_outputs[ci],
    })
  }
  finalize_component_planes_result(
    planes,
    "real_decode:DS-DWT-ALL-COMPONENTS:tiles\{num_tiles}",
  )
}

///|
fn build_zero_component_result(
  siz : @core.SizMetadata,
) -> Result[DecodeAllComponentsResult, String] {
  let components : Array[DecodeSamplesComponentResult] = []
  for ci in 0..<siz.csiz {
    let comp = siz.components[ci]
    let dims_v = @input.component_dimensions_from_siz(siz, ci)
    guard dims_v is Ok((comp_w, comp_h)) else {
      return Err(
        "decode_samples_all_components failed to determine component dimensions",
      )
    }
    let sample_count_v = @input.component_sample_count_from_siz(siz, ci)
    guard sample_count_v is Ok(sample_count) else {
      return Err(
        "decode_samples_all_components failed to determine component sample count",
      )
    }
    let zero_v = @input.make_zero_sample_bytes(
      sample_count,
      comp.precision_bits,
    )
    guard zero_v is Ok(zero_samples) else {
      return Err(
        "decode_samples_all_components failed to build zero sample buffer",
      )
    }
    components.push({
      component_index: ci,
      width: comp_w,
      height: comp_h,
      bits_per_component: comp.precision_bits,
      is_signed: comp.is_signed,
      sample_layout: "component\{ci}:raster:le:zero_recon:DS-ZERO-PACKET-RECON:empty_sod_payload",
      samples: zero_samples,
    })
  }
  Ok({
    num_components: components.length(),
    sample_layout: "components:planar:le:zero_recon:DS-ZERO-PACKET-RECON:empty_sod_payload",
    components,
  })
}

///|
pub fn decode_samples_all_components_impl(
  data : Bytes,
  packet_audit? : Bool = false,
  packet_audit_limit? : Int = 300,
) -> Result[DecodeAllComponentsResult, String] {
  if data.length() <= 0 {
    return Err("empty JPEG2000 input")
  }
  let codestream = @input.extract_decode_input_codestream(data)
  guard codestream is Ok(raw_codestream) else {
    if codestream is Err(msg) {
      return Err("invalid JPEG2000 input: \{msg}")
    }
    return Err("invalid JPEG2000 input")
  }
  let parsed = @core.parse_codestream_bytes(raw_codestream)
  guard parsed is Ok(stream) else {
    if parsed is Err(msg) {
      return Err("invalid JPEG2000 codestream: \{msg}")
    }
    return Err("invalid JPEG2000 codestream")
  }
  guard stream.metadata.siz is Some(siz) else {
    return Err("decode_samples_all_components requires SIZ metadata")
  }
  if siz.components.length() <= 0 {
    return Err("decode_samples_all_components requires at least one component")
  }
  if siz.csiz <= 1 {
    let decoded_impl_v = decode_samples_impl(data)
    guard decoded_impl_v is Ok(internal_result) else {
      if decoded_impl_v is Err(msg) {
        return Err(msg)
      }
      return Err("decode_samples_all_components failed")
    }
    return Ok(
      wrap_single_component_decode(
        decode_samples_from_internal(internal_result),
      ),
    )
  }
  guard stream.metadata.cod is Some(cod) else {
    return Err("decode_samples_all_components requires COD metadata")
  }
  if !(cod.multiple_component_transform == 0 ||
    cod.multiple_component_transform == 1) {
    return Err(
      "decode_samples_all_components unsupported profile (\{@profile.non_simple_profile_reason(stream, siz)})",
    )
  }
  let c0 = siz.components[0]
  let c0_dims_v = @input.component_dimensions_from_siz(siz, 0)
  guard c0_dims_v is Ok((c0_width, c0_height)) else {
    return Err(
      "decode_samples_all_components failed to determine component dimensions",
    )
  }
  let sod_payloads = @input.collect_sod_payloads(stream)
  if sod_payloads.length() <= 0 {
    return Err("decode_samples_all_components requires SOD payload")
  }
  if @input.codestream_payload_is_empty(stream) {
    return build_zero_component_result(siz)
  }
  if @profile.htj2k_signalled(stream) &&
    !@profile.htj2k_cleanup_only_subset_enabled(stream) {
    return Err(@codeblock.htj2k_decode_not_supported_error(stream))
  }
  let num_tiles_x = (siz.xsiz - siz.xtosiz + siz.xtsiz - 1) / siz.xtsiz
  let num_tiles_y = (siz.ysiz - siz.ytosiz + siz.ytsiz - 1) / siz.ytsiz
  let num_tiles = num_tiles_x * num_tiles_y
  if num_tiles > 1 {
    return decode_multi_tile_all_components(
      stream,
      sod_payloads,
      siz,
      c0.precision_bits,
      c0.is_signed,
      packet_audit~,
      packet_audit_limit~,
    )
  }
  let relocated2 = collect_relocated_headers(stream)
  let tile_poc_by_idx = @geometry.collect_tile_part_poc_by_tile(
    stream,
    siz.csiz,
  )
  let use_relocated_ppt = relocated2.has_ppt_headers
  let single_roi_map = @roi.extract_roi_shift_per_tile_component(stream)
  let single_roi : Array[Int] = []
  for ci in 0..<siz.csiz {
    single_roi.push(@roi.get_roi_shift(single_roi_map, 0, ci))
  }
  let single_relocated_headers : Bytes = if use_relocated_ppt {
    match relocated2.tile_ppt_headers_by_idx.get(0) {
      Some(headers) => headers
      None => b""
    }
  } else if relocated2.has_ppm_headers {
    relocated2.global_ppm_headers
  } else {
    b""
  }
  let single_tile_poc : Array[@core.PocMetadata] = match
    tile_poc_by_idx.get(0) {
    Some(pocs) => pocs
    None => []
  }
  let single_tile_cod = @geometry.get_tile_cod(stream, 0)
  let single_tile_qcd = @geometry.get_tile_qcd(stream, 0)
  let (_, _, _, _, single_tcx0, single_tcy0) = @input.tile_component0_dims_and_origin_from_siz(
    siz, 0, 0,
  )
  let planes_v = decode_dwt_component_planes_from_sequential_packets(
    stream,
    sod_payloads,
    c0_width,
    c0_height,
    c0.precision_bits,
    c0.is_signed,
    siz.csiz,
    tcx0=single_tcx0,
    tcy0=single_tcy0,
    tile_index=0,
    comp_roishifts=single_roi,
    tile_cod=single_tile_cod,
    tile_qcd=single_tile_qcd,
    poc_entries=single_tile_poc,
    relocated_packet_headers=single_relocated_headers,
    packet_audit~,
    audit_label="single",
    packet_audit_limit~,
  )
  guard planes_v is Ok((planes, _)) else {
    if planes_v is Err(msg) {
      return Err(msg)
    }
    return Err("decode_samples_all_components failed")
  }
  finalize_component_planes_result(
    planes, "real_decode:DS-DWT-ALL-COMPONENTS:single",
  )
}

///|
pub fn decode_samples_all_components(
  data : Bytes,
) -> Result[DecodeAllComponentsResult, String] {
  decode_samples_all_components_impl(data)
}

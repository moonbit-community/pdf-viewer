///|
fn decode_multi_tile_sequential_image(
  stream : @core.Codestream,
  sod_payloads : Array[Bytes],
  siz : @core.SizMetadata,
  sample_count : Int,
  precision_bits : Int,
  is_signed : Bool,
  c0_width : Int,
  c0_height : Int,
  decode_mode : String,
  force_relocated_ppt : Bool,
  packet_audit? : Bool = false,
  packet_audit_limit? : Int = 300,
) -> Result[DecodeSamplesInternalResult, String] {
  guard stream.metadata.cod is Some(cod) else {
    return Err("decode_samples multi-tile decode requires COD metadata")
  }
  let uses_sop = cod.uses_sop
  let num_tiles_x = (siz.xsiz - siz.xtosiz + siz.xtsiz - 1) / siz.xtsiz
  let num_tiles_y = (siz.ysiz - siz.ytosiz + siz.ytsiz - 1) / siz.ytsiz
  let num_tiles = num_tiles_x * num_tiles_y
  if num_tiles <= 1 {
    return Err("decode_samples multi-tile decode requires more than one tile")
  }
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
  if tile_payloads_by_idx.length() <= 0 {
    return Err("decode_samples multi-tile decode found no tile payloads")
  }
  let relocated = collect_relocated_headers(stream)
  let tile_ppt_headers_by_idx = relocated.tile_ppt_headers_by_idx
  let global_ppm_headers = relocated.global_ppm_headers
  let tile_poc_by_idx = @geometry.collect_tile_part_poc_by_tile(
    stream,
    siz.csiz,
  )
  let use_relocated_ppt = force_relocated_ppt || relocated.has_ppt_headers
  let use_relocated_ppm = !use_relocated_ppt && relocated.has_ppm_headers
  let roi_map = @roi.extract_roi_shift_per_tile_component(stream)
  let mut tile_decode_ok = 0
  let mut tile_decode_fail = 0
  let mut tile_fail_no_cb = 0
  let mut tile_fail_accum = 0
  let mut tile_fail_c0 = 0
  let mut tile_fail_c1 = 0
  let mut tile_fail_c2 = 0
  let mut tile_fail_other = 0
  let dc_init = if is_signed { 0 } else { 1 << (precision_bits - 1) }
  let output : Array[Int] = []
  for _ in 0..<(c0_width * c0_height) {
    output.push(dc_init)
  }
  let mut ppm_header_cursor = 0
  for tile_row in 0..<num_tiles_y {
    for tile_col in 0..<num_tiles_x {
      let tile_idx = tile_row * num_tiles_x + tile_col
      guard tile_payloads_by_idx.get(tile_idx) is Some(raw_tile_payload) else {
        continue
      }
      let (tpos_x, tpos_y, tw, th, tcx0, tcy0) = @input.tile_component0_dims_and_origin_from_siz(
        siz, tile_col, tile_row,
      )
      if tw <= 0 || th <= 0 {
        continue
      }
      let tile_roi : Array[Int] = []
      for ci in 0..<siz.csiz {
        let shift = @roi.get_roi_shift(roi_map, tile_idx, ci)
        tile_roi.push(shift)
        if packet_audit && shift > 0 {
          println(
            "recon-audit:component-roi:label=tile\{tile_idx} c=\{ci} roi=\{shift}",
          )
        }
      }
      let tile_relocated_headers : Bytes = if use_relocated_ppt {
        match tile_ppt_headers_by_idx.get(tile_idx) {
          Some(h) => h
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
      if @profile.htj2k_signalled(stream) &&
        !@profile.htj2k_cleanup_only_subset_enabled(stream) {
        return Err(@codeblock.htj2k_decode_not_supported_error(stream))
      }
      let tile_v = decode_dwt_image_from_sequential_packets(
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
      let effective_tile_cod = match tile_specific_cod {
        Some(tc) => tc
        None => cod
      }
      let bridge_v = if effective_tile_cod.layers > 1 {
        @codeblock.decode_nodwt_ht_multi_codeblock_tile_bridge(
          stream,
          raw_tile_payload,
          tw,
          th,
          precision_bits,
          is_signed,
          tile_idx,
          if tile_roi.length() > 0 {
            tile_roi[0]
          } else {
            0
          },
          effective_tile_cod,
          fallback_qcd=tile_specific_qcd,
        )
      } else {
        Err("tile HT multi-codeblock bridge not applicable: layers")
      }
      let bridged_tile_v = match (tile_v, bridge_v) {
        (Ok((tile_pixels, consumed_headers)), Ok(bridge_pixels)) => {
          let dc_fill = if is_signed { 0 } else { 1 << (precision_bits - 1) }
          let (sel, sel_hdr) = tile_bridge_selection(
            tile_pixels, consumed_headers, bridge_pixels, dc_fill,
          )
          Ok((sel, sel_hdr))
        }
        (Err(_), Ok(bridge_pixels)) => Ok((bridge_pixels, 0))
        (Ok(ok_tile), _) => Ok(ok_tile)
        (Err(tile_err), _) => Err(tile_err)
      }
      if bridged_tile_v is Ok((tile_pixels, consumed_headers)) {
        tile_decode_ok += 1
        if packet_audit {
          println(
            "tile-audit:label=tile\{tile_idx} relocated_headers=\{tile_relocated_headers.length()} consumed_headers=\{consumed_headers} bytes=\{raw_tile_payload.length()}",
          )
        }
        if use_relocated_ppm && consumed_headers > 0 {
          ppm_header_cursor += consumed_headers
          if ppm_header_cursor > global_ppm_headers.length() {
            ppm_header_cursor = global_ppm_headers.length()
          }
        }
        for ty in 0..<th {
          for tx in 0..<tw {
            let src = ty * tw + tx
            let dst_y = tpos_y + ty
            let dst_x = tpos_x + tx
            if dst_y < c0_height &&
              dst_x < c0_width &&
              src < tile_pixels.length() {
              output[dst_y * c0_width + dst_x] = tile_pixels[src]
            }
          }
        }
      } else {
        tile_decode_fail += 1
        if bridged_tile_v is Err(tile_err) {
          if tile_err.contains("no decodable code-blocks") {
            tile_fail_no_cb += 1
          } else if tile_err.contains("multi-layer accumulation failed") {
            tile_fail_accum += 1
          } else if tile_err.contains("component 0 (Y) failed") ||
            tile_err.contains("component 0 decode failed") {
            tile_fail_c0 += 1
          } else if tile_err.contains("component 1 (Cb/Db) failed") {
            tile_fail_c1 += 1
          } else if tile_err.contains("component 2 (Cr/Dr) failed") {
            tile_fail_c2 += 1
          } else {
            tile_fail_other += 1
          }
        } else {
          tile_fail_other += 1
        }
        let dc_fill = if is_signed { 0 } else { 1 << (precision_bits - 1) }
        for ty in 0..<th {
          for tx in 0..<tw {
            let dst_y = tpos_y + ty
            let dst_x = tpos_x + tx
            if dst_y < c0_height && dst_x < c0_width {
              output[dst_y * c0_width + dst_x] = dc_fill
            }
          }
        }
      }
    }
  }
  let sample_v = @input.make_sample_array_bytes_le(output, precision_bits)
  guard sample_v is Ok(sample_bytes) else {
    return Err("failed to build multi-tile sample buffer")
  }
  let tag = if uses_sop { "sop" } else { "seq" }
  Ok(
    make_decode_samples_result(
      sample_bytes,
      precision_bits,
      is_signed,
      sample_count,
      c0_width,
      c0_height,
      siz.csiz,
      "component0:raster:le:real_decode:\{decode_mode}_\{tag}_tiles\{num_tiles}_ok\{tile_decode_ok}_fail\{tile_decode_fail}_fcb\{tile_fail_no_cb}_fac\{tile_fail_accum}_fc0\{tile_fail_c0}_fc1\{tile_fail_c1}_fc2\{tile_fail_c2}_fot\{tile_fail_other}",
    ),
  )
}

///|
fn try_decode_simple_profile_dwt_or_multi_tile(
  stream : @core.Codestream,
  sod_payloads : Array[Bytes],
  siz : @core.SizMetadata,
  sample_count : Int,
  precision_bits : Int,
  is_signed : Bool,
  c0_width : Int,
  c0_height : Int,
  force_relocated_ppt : Bool,
  packet_audit? : Bool = false,
  packet_audit_limit? : Int = 0,
) -> Result[DecodeSamplesInternalResult?, String] {
  guard stream.metadata.cod is Some(cod) else { return Ok(None) }
  if c0_width * c0_height <= 1 ||
    !@profile.tier1_minimal_reversible_subset_enabled(stream) {
    return Ok(None)
  }
  let num_tiles_x = (siz.xsiz - siz.xtosiz + siz.xtsiz - 1) / siz.xtsiz
  let num_tiles_y = (siz.ysiz - siz.ytosiz + siz.ytsiz - 1) / siz.ytsiz
  let num_tiles = num_tiles_x * num_tiles_y
  if cod.decomposition_levels <= 0 && num_tiles <= 1 {
    return Ok(None)
  }
  let decode_mode = if cod.decomposition_levels > 0 {
    "DS-DWT-SUBBAND-DECODE:dwt_\{cod.decomposition_levels}"
  } else {
    "DS-TILE-SEQUENTIAL-DECODE:nodwt"
  }
  if num_tiles > 1 {
    let multi_tile_v = decode_multi_tile_sequential_image(
      stream,
      sod_payloads,
      siz,
      sample_count,
      precision_bits,
      is_signed,
      c0_width,
      c0_height,
      decode_mode,
      force_relocated_ppt,
      packet_audit~,
      packet_audit_limit~,
    )
    if multi_tile_v is Ok(result) {
      return Ok(Some(result))
    }
    if cod.decomposition_levels <= 0 {
      return Err("decode_samples no-dwt multi-tile tile assembly failed")
    }
  }
  let relocated2 = collect_relocated_headers(stream)
  let tile_poc_by_idx = @geometry.collect_tile_part_poc_by_tile(
    stream,
    siz.csiz,
  )
  let use_relocated_ppt = force_relocated_ppt || relocated2.has_ppt_headers
  let single_roi_map = @roi.extract_roi_shift_per_tile_component(stream)
  let single_roi : Array[Int] = []
  for ci in 0..<siz.csiz {
    let shift = @roi.get_roi_shift(single_roi_map, 0, ci)
    single_roi.push(shift)
    if packet_audit && shift > 0 {
      println("recon-audit:component-roi:label=single c=\{ci} roi=\{shift}")
    }
  }
  let single_relocated_headers : Bytes = if use_relocated_ppt {
    match relocated2.tile_ppt_headers_by_idx.get(0) {
      Some(h) => h
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
  if @profile.htj2k_signalled(stream) &&
    !@profile.htj2k_cleanup_only_subset_enabled(stream) {
    return Err(@codeblock.htj2k_decode_not_supported_error(stream))
  }
  let dwt_v = decode_dwt_image_from_sequential_packets(
    stream,
    sod_payloads,
    c0_width,
    c0_height,
    precision_bits,
    is_signed,
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
  if dwt_v is Ok((pixel_values, _)) {
    let sample_v = @input.make_sample_array_bytes_le(
      pixel_values, precision_bits,
    )
    if sample_v is Ok(sample_bytes) {
      let tag = if cod.uses_sop { "sop" } else { "seq" }
      return Ok(
        Some(
          make_decode_samples_result(
            sample_bytes,
            precision_bits,
            is_signed,
            sample_count,
            c0_width,
            c0_height,
            siz.csiz,
            "component0:raster:le:real_decode:\{decode_mode}_\{tag}",
          ),
        ),
      )
    }
  }
  Ok(None)
}

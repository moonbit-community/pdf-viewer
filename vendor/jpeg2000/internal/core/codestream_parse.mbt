///|
fn trailing_bytes_are_fill(data : Bytes, start : Int) -> Bool {
  // Interop policy (non-normative):
  // Some corpus files have one or more 0x00 fill bytes after EOC.
  // We accept all-zero trailing bytes but still reject any non-zero trailing data.
  //
  // Normative baseline:
  // - EOC usage "shall be the last marker in a codestream"
  //   /sections/annex-a-codestream-syntax.md:503
  if start >= data.length() {
    return true
  }
  for i in start..<data.length() {
    if data[i] != b'\x00' {
      return false
    }
  }
  true
}

///|
fn copy_bytes_from(data : Bytes, start : Int) -> Bytes {
  if start >= data.length() {
    return Bytes::new(0)
  }
  let len = data.length() - start
  Bytes::makei(len, fn(i) { data[start + i] })
}

///|
fn parse_codestream_impl(
  data : Bytes,
  compat_mode : Bool,
) -> Result[Codestream, String] {
  if data.length() < 4 {
    return Err("codestream too short")
  }
  let first_code = @bytes.read_u16_be(data, 0)
  if first_code != MARKER_SOC {
    return Err("SOC must appear at codestream start")
  }

  let segments : Array[MarkerSegment] = []
  segments.push({ code: MARKER_SOC, payload: Bytes::new(0), position: 0, })

  let mut i = 2
  let mut seen_sot = false
  let mut seen_sod = false
  let mut seen_siz = false
  let mut seen_cod = false
  let mut seen_qcd = false
  let mut first_marker_after_soc = true
  let mut in_main_header = true
  let mut in_tile_part_header = false
  let mut siz_components : Int? = None
  let mut main_seen_poc = false
  let mut tile_seen_poc = false
  let mut main_seen_crg = false
  let mut tile_seen_cod = false
  let mut tile_seen_qcd = false
  let mut header_coc_components : Array[Int] = []
  let mut header_qcc_components : Array[Int] = []
  let mut has_ppm = false
  let mut has_ppt = false
  let mut current_sot_pos = -1
  let mut current_psot = 0
  let mut current_tile_index = -1 // T.800-2015 A.4.2: track current tile for tile-specific markers
  let tile_ids : Array[Int] = []
  let tile_last_tpsot : Array[Int] = []
  let tile_declared_tnsot : Array[Int] = []
  let mut tile_count : Int? = None
  let mut siz_metadata : SizMetadata? = None
  let mut cod_metadata : CodMetadata? = None
  let mut qcd_metadata : QcdMetadata? = None
  let coc_metadata : Array[CocMetadata] = []
  let rgn_metadata : Array[RgnMetadata] = []
  let qcc_metadata : Array[QccMetadata] = []
  let poc_metadata : Array[PocMetadata] = []
  let tlm_metadata : Array[TlmMetadata] = []
  let plm_metadata : Array[PlmMetadata] = []
  let plt_metadata : Array[PltMetadata] = []
  let ppm_metadata : Array[PpmMetadata] = []
  let ppt_metadata : Array[PptMetadata] = []
  let packet_headers_ppm : Array[PacketHeaderMetadata] = []
  let packet_headers_ppt : Array[PacketHeaderMetadata] = []
  let sop_metadata : Array[SopMetadata] = []
  let eph_positions : Array[Int] = []
  let mut crg_metadata : CrgMetadata? = None
  let com_metadata : Array[ComMetadata] = []
  let mut ordering_metadata : OrderingMetadata? = None
  let mut ordering_coding_metadata : OrderingCodingMetadata? = None
  let mut progression_metadata : ProgressionMetadata? = None
  // T.800-2015 A.4.2: Tile-specific COD/QCD overrides
  let tile_cod_metadata : Array[TileCodMetadata] = []
  let tile_qcd_metadata : Array[TileQcdMetadata] = []

  while i < data.length() {
    let code = @bytes.read_u16_be(data, i)
    if code >> 8 != 0xFF {
      return Err("invalid marker prefix at byte \{i}")
    }
    let placement = validate_marker_placement(
      code, in_main_header, in_tile_part_header, seen_siz,
    )
    guard placement is Ok(_) else {
      if placement is Err(msg) && !compat_mode {
        return Err("invalid marker placement: \{msg}")
      }
      return Err("invalid marker placement")
    }

    if code == MARKER_EOC {
      segments.push({ code, payload: Bytes::new(0), position: i, })
      i += 2
      let trailing_bytes = if i == data.length() {
        Bytes::new(0)
      } else {
        copy_bytes_from(data, i)
      }
      if i != data.length() {
        if !compat_mode {
          return Err("EOC must be the last marker")
        }
        // Interop policy (compat mode only):
        // - permit trailing 0x00 fill only; reject any non-zero trailing bytes.
        if !trailing_bytes_are_fill(data, i) {
          return Err(
            "EOC must be the last marker (trailing \{data.length() - i} bytes)",
          )
        }
        i = data.length()
      }
      if !seen_sot || !seen_sod {
        return Err("at least one SOT/SOD pair is required")
      }
      if !seen_siz || !seen_cod || !seen_qcd {
        return Err("missing required main header markers")
      }
      return Ok({
        segments,
        metadata: {
          siz: siz_metadata,
          cod: cod_metadata,
          qcd: qcd_metadata,
          coc: coc_metadata,
          rgn: rgn_metadata,
          qcc: qcc_metadata,
          poc: poc_metadata,
          tlm: tlm_metadata,
          plm: plm_metadata,
          plt: plt_metadata,
          ppm: ppm_metadata,
          ppt: ppt_metadata,
          sop: sop_metadata,
          eph_positions,
          crg: crg_metadata,
          com: com_metadata,
          ordering: ordering_metadata,
          ordering_coding: ordering_coding_metadata,
          progression: progression_metadata,
          packet_headers_ppm,
          packet_headers_ppt,
          // T.800-2015 A.4.2: Tile-specific COD/QCD overrides
          tile_cod: tile_cod_metadata,
          tile_qcd: tile_qcd_metadata,
        },
        trailing_bytes,
      })
    }

    if code == MARKER_SOD {
      if !seen_sot {
        return Err("SOD requires preceding SOT")
      }
      let packet_start = i + 2
      let packet_end = if current_psot > 0 {
        let declared_end = current_sot_pos + current_psot
        if declared_end < packet_start {
          return Err("invalid Psot in SOT")
        }
        if declared_end > data.length() {
          return Err("Psot exceeds codestream size")
        }
        // Spec baseline:
        // - Psot is the tile-part length from SOT to tile-part end.
        //   /sections/annex-a-codestream-syntax.md:452-455
        //
        // Interop policy (compat mode only, non-normative):
        // - if declared Psot boundary does not align to a marker prefix, prefer
        //   marker-based resynchronization over hard failure.
        if declared_end < data.length() && data[declared_end].to_int() != 0xFF {
          if compat_mode {
            find_next_sot_or_eoc(data, packet_start)
          } else {
            return Err("Psot boundary is not aligned to marker prefix")
          }
        } else {
          declared_end
        }
      } else {
        find_next_sot_or_eoc(data, packet_start)
      }
      let packet_len = packet_end - packet_start
      let packet = Bytes::makei(packet_len, fn(j) { data[packet_start + j] })
      let should_validate_packet_markers = if compat_mode {
        false
      } else if cod_metadata is Some(codm) {
        codm.uses_sop || codm.uses_eph
      } else {
        false
      }
      if should_validate_packet_markers {
        let stuffing_check = validate_packet_bit_stuffing(packet)
        guard stuffing_check is Ok(_) else {
          if stuffing_check is Err(msg) {
            return Err("invalid packet data: \{msg}")
          }
          return Err("invalid packet data")
        }
      }
      let (found_sops, found_ephs) = extract_in_bitstream_markers(
        packet, packet_start,
      )
      for sop_entry in found_sops {
        sop_metadata.push(sop_entry)
      }
      for eph_pos in found_ephs {
        eph_positions.push(eph_pos)
      }
      in_tile_part_header = false
      seen_sod = true
      segments.push({ code, payload: packet, position: i, })
      i = packet_end
      continue
    }

    if !has_explicit_length(code) {
      // Spec (Annex A.1.3): reserved markers are marker-only and decoder-skippable.
      if is_reserved_jpeg_marker(code) {
        segments.push({ code, payload: Bytes::new(0), position: i, })
        i += 2
        continue
      }
      return Err("unexpected marker without length")
    }

    let length = @bytes.read_u16_be(data, i + 2)
    if length < 2 {
      return Err("invalid marker segment length")
    }
    let payload_len = length - 2
    let payload_start = i + 4
    let payload_end = payload_start + payload_len
    if payload_end > data.length() {
      if compat_mode && seen_siz {
        // Robustness policy (compat mode only):
        // - preserve the undecodable suffix verbatim so malformed external corpus
        //   fixtures can still roundtrip without inventing marker structure.
        return Ok({
          segments,
          metadata: {
            siz: siz_metadata,
            cod: cod_metadata,
            qcd: qcd_metadata,
            coc: coc_metadata,
            rgn: rgn_metadata,
            qcc: qcc_metadata,
            poc: poc_metadata,
            tlm: tlm_metadata,
            plm: plm_metadata,
            plt: plt_metadata,
            ppm: ppm_metadata,
            ppt: ppt_metadata,
            sop: sop_metadata,
            eph_positions,
            crg: crg_metadata,
            com: com_metadata,
            ordering: ordering_metadata,
            ordering_coding: ordering_coding_metadata,
            progression: progression_metadata,
            packet_headers_ppm,
            packet_headers_ppt,
            tile_cod: tile_cod_metadata,
            tile_qcd: tile_qcd_metadata,
          },
          trailing_bytes: copy_bytes_from(data, i),
        })
      }
      return Err("marker segment exceeds codestream size")
    }

    let payload = Bytes::makei(payload_len, fn(j) { data[payload_start + j] })

    // Convert payload to Array[Int] for legacy downstream functions
    let payload_arr = @bytes.bytes_to_int_array(payload)

    if first_marker_after_soc {
      if code != MARKER_SIZ {
        return Err("SIZ must be the second marker segment")
      }
      first_marker_after_soc = false
    }

    let payload_validation = validate_marker_payload(
      code, length, payload_arr, in_main_header, siz_components, main_seen_poc, tile_seen_poc,
      header_coc_components, header_qcc_components, main_seen_crg, has_ppm, has_ppt,
      compat_mode,
    )
    guard payload_validation is Ok(next_siz_components) else {
      if compat_mode {
        // Robustness policy (compat mode only):
        // - retain the current malformed marker segment as raw structure and
        //   preserve the remaining undecodable bytes verbatim.
        segments.push({ code, payload, position: i, })
        return Ok({
          segments,
          metadata: {
            siz: siz_metadata,
            cod: cod_metadata,
            qcd: qcd_metadata,
            coc: coc_metadata,
            rgn: rgn_metadata,
            qcc: qcc_metadata,
            poc: poc_metadata,
            tlm: tlm_metadata,
            plm: plm_metadata,
            plt: plt_metadata,
            ppm: ppm_metadata,
            ppt: ppt_metadata,
            sop: sop_metadata,
            eph_positions,
            crg: crg_metadata,
            com: com_metadata,
            ordering: ordering_metadata,
            ordering_coding: ordering_coding_metadata,
            progression: progression_metadata,
            packet_headers_ppm,
            packet_headers_ppt,
            tile_cod: tile_cod_metadata,
            tile_qcd: tile_qcd_metadata,
          },
          trailing_bytes: copy_bytes_from(data, payload_end),
        })
      }
      if payload_validation is Err(msg) && !compat_mode {
        return Err("invalid marker payload: \{msg}")
      }
      return Err("invalid marker payload")
    }
    siz_components = next_siz_components

    if code == MARKER_SIZ {
      seen_siz = true
      let tc = compute_tile_count_from_siz(payload_arr)
      guard tc is Ok(n_tiles) else {
        return Err("failed to compute tile count")
      }
      tile_count = Some(n_tiles)
      let sm = parse_siz_metadata(payload_arr)
      guard sm is Ok(meta) else { return Err("failed to parse SIZ metadata") }
      let om = build_ordering_metadata(meta)
      guard om is Ok(ordered) else {
        return Err("failed to build ordering metadata")
      }
      siz_metadata = Some(meta)
      ordering_metadata = Some(ordered)
    }
    if code == MARKER_COD {
      if in_main_header {
        if seen_cod {
          return Err("COD must appear at most once in main header")
        }
        seen_cod = true
        let cm = parse_cod_metadata(payload_arr)
        guard cm is Ok(meta) else { return Err("failed to parse COD metadata") }
        cod_metadata = Some(meta)
        if ordering_metadata is Some(ordering) {
          let coding = build_ordering_coding_metadata(meta, ordering)
          ordering_coding_metadata = Some(coding)
          progression_metadata = refresh_progression_metadata(
            cod_metadata, ordering_metadata, ordering_coding_metadata, poc_metadata,
          )
        }
      } else {
        // T.800-2015 A.4.2: Parse and store tile-specific COD
        if tile_seen_cod {
          return Err("COD must appear at most once in tile-part header")
        }
        tile_seen_cod = true
        let cm = parse_cod_metadata(payload_arr)
        guard cm is Ok(meta) else {
          return Err("failed to parse tile COD metadata")
        }
        tile_cod_metadata.push({ tile_index: current_tile_index, cod: meta, })
      }
    }
    if code == MARKER_QCD {
      if in_main_header {
        if seen_qcd {
          return Err("QCD must appear at most once in main header")
        }
        seen_qcd = true
        let qm = parse_qcd_metadata(payload_arr)
        guard qm is Ok(meta) else { return Err("failed to parse QCD metadata") }
        qcd_metadata = Some(meta)
      } else {
        // T.800-2015 A.4.2: Parse and store tile-specific QCD
        if tile_seen_qcd {
          return Err("QCD must appear at most once in tile-part header")
        }
        tile_seen_qcd = true
        let qm = parse_qcd_metadata(payload_arr)
        guard qm is Ok(meta) else {
          return Err("failed to parse tile QCD metadata")
        }
        tile_qcd_metadata.push({ tile_index: current_tile_index, qcd: meta, })
      }
    }
    if code == MARKER_POC {
      guard siz_components is Some(csiz) else {
        return Err("missing SIZ component count")
      }
      let parsed = parse_poc_entries(payload_arr, csiz, in_main_header)
      guard parsed is Ok(entries) else {
        return Err("failed to parse POC metadata")
      }
      for entry in entries {
        poc_metadata.push(entry)
      }
      if in_main_header {
        main_seen_poc = true
      } else {
        tile_seen_poc = true
      }
      progression_metadata = refresh_progression_metadata(
        cod_metadata, ordering_metadata, ordering_coding_metadata, poc_metadata,
      )
    }
    if code == MARKER_RGN {
      guard siz_components is Some(csiz) else {
        return Err("missing SIZ component count")
      }
      let parsed = parse_rgn_metadata(payload_arr, csiz, in_main_header)
      guard parsed is Ok(entry) else {
        return Err("failed to parse RGN metadata")
      }
      rgn_metadata.push(entry)
    }
    if code == MARKER_CRG {
      main_seen_crg = true
      guard siz_components is Some(csiz) else {
        return Err("missing SIZ component count")
      }
      let parsed = parse_crg_metadata(payload_arr, csiz)
      guard parsed is Ok(entry) else {
        return Err("failed to parse CRG metadata")
      }
      crg_metadata = Some(entry)
    }
    if code == MARKER_COM {
      let parsed = parse_com_metadata(payload_arr)
      guard parsed is Ok(entry) else {
        return Err("failed to parse COM metadata")
      }
      com_metadata.push(entry)
    }
    if code == MARKER_SOP {
      let parsed = parse_sop_metadata(payload_arr, i)
      guard parsed is Ok(entry) else {
        return Err("failed to parse SOP metadata")
      }
      sop_metadata.push(entry)
    }
    if code == MARKER_EPH {
      eph_positions.push(i)
    }
    if code == MARKER_PPM {
      has_ppm = true
    }
    if code == MARKER_PPT {
      has_ppt = true
    }
    if code == MARKER_TLM {
      let parsed = parse_tlm_metadata(payload_arr)
      guard parsed is Ok(entry) else {
        return Err("failed to parse TLM metadata")
      }
      tlm_metadata.push(entry)
    }
    if code == MARKER_PLM {
      let parsed = parse_plm_metadata(payload_arr)
      guard parsed is Ok(entry) else {
        return Err("failed to parse PLM metadata")
      }
      if !compat_mode && entry.zplm != plm_metadata.length() {
        return Err("invalid marker payload: PLM Z index is not consecutive")
      }
      plm_metadata.push(entry)
    }
    if code == MARKER_PLT {
      let parsed = parse_plt_metadata(payload_arr)
      guard parsed is Ok(entry) else {
        return Err("failed to parse PLT metadata")
      }
      plt_metadata.push(entry)
    }
    if code == MARKER_PPM {
      let parsed = parse_ppm_metadata(payload_arr)
      if parsed is Ok(entry) {
        ppm_metadata.push(entry)
        for chunk in entry.chunks {
          let decoded = parse_packet_headers_series_with_code_blocks(
            @bytes.int_array_to_bytes(chunk.ippm),
            1,
          )
          if decoded is Err(_) {
            // Spec (Annex B): PPM relocates packet headers.
            // Parser-level conformance is marker/payload structure; packet-header semantic
            // reconstruction here is implementation metadata and must remain non-fatal.
            continue
          }
          guard decoded is Ok(headers) else {
            return Err("failed to parse packet headers in PPM")
          }
          for h in headers {
            packet_headers_ppm.push(h)
          }
        }
      } else if payload.length() > 0 {
        ppm_metadata.push({ zppm: payload[0].to_int(), chunks: [], })
      }
    }
    if code == MARKER_PPT {
      let parsed = parse_ppt_metadata(payload_arr)
      if parsed is Ok(entry) {
        ppt_metadata.push(entry)
        let decoded = parse_packet_headers_series_with_code_blocks(
          @bytes.int_array_to_bytes(entry.data),
          1,
        )
        if decoded is Err(_) {
          // Same policy as PPM path for PPT-relocated packet headers.
          // Keep payload as source of truth; metadata decode failures are non-fatal.
        } else if decoded is Ok(headers) {
          for h in headers {
            packet_headers_ppt.push(h)
          }
        }
      } else if payload.length() > 0 {
        let ppt_data : Array[Int] = []
        for idx in 1..<payload.length() {
          ppt_data.push(payload[idx].to_int())
        }
        ppt_metadata.push({ zppt: payload[0].to_int(), data: ppt_data, })
      }
    }
    if code == MARKER_COC || code == MARKER_QCC {
      guard siz_components is Some(csiz) else {
        return Err("missing SIZ component count")
      }
      let comp = if csiz < 257 {
        payload[0].to_int()
      } else {
        @bytes.read_u16_be(payload, 0)
      }
      if code == MARKER_COC {
        header_coc_components.push(comp)
        let parsed = parse_coc_metadata(
          payload_arr,
          csiz,
          in_main_header,
          tile_index=if in_main_header { -1 } else { current_tile_index },
        )
        guard parsed is Ok(entry) else {
          return Err("failed to parse COC metadata")
        }
        coc_metadata.push(entry)
      } else {
        header_qcc_components.push(comp)
        let parsed = parse_qcc_metadata(
          payload_arr,
          csiz,
          in_main_header,
          tile_index=if in_main_header { -1 } else { current_tile_index },
        )
        guard parsed is Ok(entry) else {
          return Err("failed to parse QCC metadata")
        }
        qcc_metadata.push(entry)
      }
    }
    segments.push({ code, payload, position: i, })
    if code == MARKER_SOT {
      seen_sot = true
      in_main_header = false
      in_tile_part_header = true
      current_sot_pos = i
      let isot = @bytes.read_u16_be(payload, 0)
      let psot = @bytes.read_u32_be(payload, 2)
      // T.800-2015 A.4.2: track current tile index for tile-specific markers
      current_tile_index = isot
      let tpsot = payload[6].to_int()
      let tnsot = payload[7].to_int()
      if tnsot != 0 && tpsot >= tnsot {
        return Err("invalid TPsot/TNsot relation")
      }
      if tile_count is Some(n_tiles) {
        if isot < 0 || isot >= n_tiles {
          return Err("Isot out of range")
        }
      }
      if find_tile_state_index(tile_ids, isot) is Some(idx) {
        if tpsot != tile_last_tpsot[idx] + 1 {
          return Err("invalid tile-part index sequence")
        }
        if tile_declared_tnsot[idx] != 0 &&
          tnsot != 0 &&
          tnsot != tile_declared_tnsot[idx] {
          return Err("inconsistent TNsot for tile")
        }
        tile_last_tpsot[idx] = tpsot
        if tile_declared_tnsot[idx] == 0 {
          tile_declared_tnsot[idx] = tnsot
        }
      } else {
        if tpsot != 0 {
          return Err("first tile-part index must be zero")
        }
        tile_ids.push(isot)
        tile_last_tpsot.push(tpsot)
        tile_declared_tnsot.push(tnsot)
      }
      current_psot = psot
      tile_seen_poc = false
      tile_seen_cod = false
      tile_seen_qcd = false
      header_coc_components = []
      header_qcc_components = []
    }
    i = payload_end
  }

  if compat_mode && seen_sot && seen_sod && seen_siz && seen_cod && seen_qcd {
    return Ok({
      segments,
      metadata: {
        siz: siz_metadata,
        cod: cod_metadata,
        qcd: qcd_metadata,
        coc: coc_metadata,
        rgn: rgn_metadata,
        qcc: qcc_metadata,
        poc: poc_metadata,
        tlm: tlm_metadata,
        plm: plm_metadata,
        plt: plt_metadata,
        ppm: ppm_metadata,
        ppt: ppt_metadata,
        sop: sop_metadata,
        eph_positions,
        crg: crg_metadata,
        com: com_metadata,
        ordering: ordering_metadata,
        ordering_coding: ordering_coding_metadata,
        progression: progression_metadata,
        packet_headers_ppm,
        packet_headers_ppt,
        tile_cod: tile_cod_metadata,
        tile_qcd: tile_qcd_metadata,
      },
      trailing_bytes: Bytes::new(0),
    })
  }
  Err("EOC marker missing")
}

///|
pub fn parse_codestream(data : Bytes) -> Result[Codestream, String] {
  // Runtime/default API: interoperability-first parser behavior.
  parse_codestream_impl(data, true)
}

///|
pub fn parse_codestream_strict(data : Bytes) -> Result[Codestream, String] {
  // Audit API: strict conformance checks for investigation workflows.
  parse_codestream_impl(data, false)
}

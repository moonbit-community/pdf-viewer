///|
// Spec grouping:
// - Annex A.8 (SOP/EPH handling)
// - packet-header / first-packet part extraction for the staged profile

///|
// Spec basis (T.800-2015 A.8 / B.10):
// - SOP/EPH are packet signalling markers and packet headers define
//   code-block contribution lengths before packet body consumption.
pub fn strip_in_bitstream_markers_for_simple_profile(
  payload : Bytes,
) -> Result[Bytes, String] {
  // Spec basis (T.800-2015):
  // - SOP (A.8.1) and EPH (A.8.2) are in-bitstream packet structure markers.
  // - They are signalling markers, not tier-1 codeword bytes.
  // Decode policy for simple-profile analysis:
  // - remove SOP/EPH before packet-header/codeword analysis.
  // - preserve all non-marker bytes as packet payload source of truth.
  let out : Array[Byte] = []
  let mut i = 0
  while i < payload.length() {
    if i + 1 < payload.length() && payload[i].to_int() == 0xFF {
      let n = payload[i + 1].to_int()
      if n == 0x91 {
        if i + 5 >= payload.length() {
          return Err("truncated SOP marker in SOD payload")
        }
        if payload[i + 2].to_int() != 0x00 || payload[i + 3].to_int() != 0x04 {
          return Err("invalid SOP marker length in SOD payload")
        }
        i += 6
        continue
      }
      if n == 0x92 {
        i += 2
        continue
      }
    }
    out.push(payload[i])
    i += 1
  }
  Ok(Bytes::from_iter(out.iter()))
}

///|
// Spec basis (T.800-2015 A.8.1):
// Split SOD payload into individual packets using SOP markers (FF91).
// Each SOP marker delimits the start of a new packet.
// Returns array of (sequence_number, packet_payload) pairs.
// Packet payload has SOP and EPH markers stripped.
pub fn split_sod_payload_by_sop(
  payload : Bytes,
) -> Result[Array[(Int, Bytes)], String] {
  let packets : Array[(Int, Bytes)] = []
  let mut i = 0
  let mut current_seq = -1
  let mut current_data : Array[Byte] = []
  while i < payload.length() {
    if i + 5 < payload.length() &&
      payload[i].to_int() == 0xFF &&
      payload[i + 1].to_int() == 0x91 &&
      payload[i + 2].to_int() == 0x00 &&
      payload[i + 3].to_int() == 0x04 {
      // SOP marker found - save previous packet if any
      if current_seq >= 0 {
        packets.push((current_seq, Bytes::from_iter(current_data.iter())))
      }
      // Start new packet
      current_seq = (payload[i + 4].to_int() << 8) | payload[i + 5].to_int()
      current_data = []
      i += 6
      continue
    }
    // Skip EPH markers (FF92)
    if i + 1 < payload.length() &&
      payload[i].to_int() == 0xFF &&
      payload[i + 1].to_int() == 0x92 {
      i += 2
      continue
    }
    if current_seq >= 0 {
      current_data.push(payload[i])
    }
    i += 1
  }
  // Save last packet
  if current_seq >= 0 {
    packets.push((current_seq, Bytes::from_iter(current_data.iter())))
  }
  Ok(packets)
}

///|
// Spec basis (T.800-2015 B.10/B.12):
// Split SOD payload into per-component, per-resolution packets by
// sequentially parsing packet headers (no SOP markers needed).
// Returns [component][resolution] -> packets.
fn split_sod_payload_sequential_all(
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
) -> Result[Array[Array[Array[(Int, Bytes)]]], String] {
  let num_resolutions = decomp_levels + 1
  // [component][resolution] -> packets
  let all_packets : Array[Array[Array[(Int, Bytes)]]] = []
  for _ in 0..<num_components {
    let comp_packets : Array[Array[(Int, Bytes)]] = []
    for _ in 0..<num_resolutions {
      comp_packets.push([])
    }
    all_packets.push(comp_packets)
  }
  let mut offset = 0
  let mut seq = 0
  let packet_order : Array[(Int, Int)] = []
  if progression == 0 {
    for _ in 0..<num_layers {
      for r in 0..<num_resolutions {
        for c in 0..<num_components {
          packet_order.push((r, c))
        }
      }
    }
  } else if progression == 1 {
    for r in 0..<num_resolutions {
      for _ in 0..<num_layers {
        for c in 0..<num_components {
          packet_order.push((r, c))
        }
      }
    }
  } else {
    for _ in 0..<num_layers {
      for r in 0..<num_resolutions {
        for c in 0..<num_components {
          packet_order.push((r, c))
        }
      }
    }
  }
  for entry in packet_order {
    let (res, comp) = entry
    if offset >= payload.length() {
      break
    }
    let remaining = payload[offset:payload.length()].to_bytes()
    let subbands : Array[(Int, Int, Int)] = if res == 0 {
      let (ll_w, ll_h) = @subband.subband_ll_dims(
        c0_width, c0_height, decomp_levels,
      )
      [(ll_w, ll_h, 0)]
    } else {
      let parent_level = decomp_levels - res
      let (pw, ph) = @subband.subband_ll_dims(c0_width, c0_height, parent_level)
      let (hl_w, hl_h, lh_w, lh_h, hh_w, hh_h) = @subband.subband_detail_dims(
        pw, ph,
      )
      [(hl_w, hl_h, 0), (lh_w, lh_h, 1), (hh_w, hh_h, 2)]
    }
    let header_v = parse_per_subband_packet_header(
      remaining,
      subbands,
      code_block_style,
      cb_width~,
      cb_height~,
    )
    guard header_v is Ok((cb_infos, consumed_bits)) else { break }
    let body_offset = @packet.pkt_body_start_offset(remaining, consumed_bits)
    let mut body_size = 0
    for info in cb_infos {
      body_size += @math.sum_ints(info.segment_lengths)
    }
    let packet_size = body_offset + body_size
    let end = if packet_size < remaining.length() {
      packet_size
    } else {
      remaining.length()
    }
    let pkt_data = remaining[0:end].to_bytes()
    if comp < num_components {
      all_packets[comp][res].push((seq, pkt_data))
    }
    offset += packet_size
    seq += 1
  }
  Ok(all_packets)
}

///|
// Backward-compatible wrapper: returns component 0 packets only.
fn split_sod_payload_sequential(
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
) -> Result[Array[Array[(Int, Bytes)]], String] {
  let all_v = split_sod_payload_sequential_all(
    payload,
    c0_width,
    c0_height,
    decomp_levels,
    num_components,
    num_layers,
    progression,
    code_block_style,
    cb_width~,
    cb_height~,
  )
  guard all_v is Ok(all_packets) else { return Err("sequential split failed") }
  Ok(all_packets[0])
}

///|
// Spec basis (T.800-2015 A.8 / B.10):
// - SOP/EPH are packet signalling markers and packet headers define
//   code-block contribution lengths before packet body consumption.
pub fn prepare_sod_payloads_for_simple_profile(
  payloads : Array[Bytes],
) -> Result[Array[Bytes], String] {
  let out : Array[Bytes] = []
  for payload in payloads {
    let stripped = strip_in_bitstream_markers_for_simple_profile(payload)
    guard stripped is Ok(cleaned) else {
      return Err("failed to strip SOP/EPH markers from SOD payload")
    }
    out.push(cleaned)
  }
  Ok(out)
}

///|
pub(all) struct SingleCodeblockPacketParts {
  pub segment_total : Int
  pub segment_lengths : Array[Int]
  pub segment_passes : Array[Int]
  pub non_zero_packet : Bool
  pub included : Bool
  pub zero_bit_planes : Int?
  pub coding_passes : Int?
  pub codeword : Bytes
}

///|
// Spec basis (T.800-2015 B.10):
// Multi-codeblock packet parts structure for images with multiple code-blocks.
pub(all) struct MultiCodeblockPacketParts {
  pub non_zero_packet : Bool
  pub code_block_count : Int
  pub parts : Array[SingleCodeblockPacketParts]
}

///|
// Spec basis (T.800-2015 A.8 / B.10):
// - SOP/EPH are packet signalling markers and packet headers define
//   code-block contribution lengths before packet body consumption.
fn packet_header_codeblock_to_parts(
  header : @core.PacketHeaderMetadata,
  payload : Bytes,
) -> Result[SingleCodeblockPacketParts, String] {
  if header.code_blocks.length() != 1 {
    return Err("packet header is not single-codeblock")
  }
  let cb = header.code_blocks[0]
  let segment_total = @math.sum_ints(cb.segment_lengths)
  let body_start = @packet.pkt_body_start_offset(payload, header.consumed_bits)
  let body_end = body_start + segment_total
  if body_end > payload.length() {
    return Err("packet body truncated for declared segment lengths")
  }
  let codeword_bytes : Array[Byte] = []
  for i in body_start..<body_end {
    codeword_bytes.push(payload[i])
  }
  Ok({
    segment_total,
    segment_lengths: cb.segment_lengths,
    segment_passes: cb.segment_passes,
    non_zero_packet: !header.zero_length,
    included: cb.included,
    zero_bit_planes: cb.zero_bit_planes,
    coding_passes: cb.coding_passes,
    codeword: Bytes::from_iter(codeword_bytes.iter()),
  })
}

///|
// Spec basis (T.800-2015 A.8 / B.10):
// - SOP/EPH are packet signalling markers and packet headers define
//   code-block contribution lengths before packet body consumption.
fn packet_header_first_included_codeblock_to_parts(
  header : @core.PacketHeaderMetadata,
  payload : Bytes,
) -> Result[SingleCodeblockPacketParts, String] {
  if header.code_blocks.length() <= 0 {
    return Err("packet header has no code-block entries")
  }
  let mut selected_index = -1
  for i in 0..<header.code_blocks.length() {
    if header.code_blocks[i].included {
      selected_index = i
      break
    }
  }
  if selected_index < 0 {
    return Ok({
      segment_total: 0,
      segment_lengths: [],
      segment_passes: [],
      non_zero_packet: !header.zero_length,
      included: false,
      zero_bit_planes: None,
      coding_passes: None,
      codeword: b"",
    })
  }
  let cb = header.code_blocks[selected_index]
  let mut body_offset = 0
  for i in 0..<selected_index {
    body_offset += @math.sum_ints(header.code_blocks[i].segment_lengths)
  }
  let segment_total = @math.sum_ints(cb.segment_lengths)
  let body_start = @packet.pkt_body_start_offset(payload, header.consumed_bits) +
    body_offset
  let body_end = body_start + segment_total
  if body_end > payload.length() {
    return Err("packet body truncated for declared segment lengths")
  }
  let codeword_bytes : Array[Byte] = []
  for i in body_start..<body_end {
    codeword_bytes.push(payload[i])
  }
  Ok({
    segment_total,
    segment_lengths: cb.segment_lengths,
    segment_passes: cb.segment_passes,
    non_zero_packet: !header.zero_length,
    included: cb.included,
    zero_bit_planes: cb.zero_bit_planes,
    coding_passes: cb.coding_passes,
    codeword: Bytes::from_iter(codeword_bytes.iter()),
  })
}

///|
// Spec basis (T.800-2015 B.10):
// Extract all code-blocks from a packet header into MultiCodeblockPacketParts.
// Codeword bytes are concatenated in code-block order in the packet body.
fn packet_header_all_codeblocks_to_multi_parts(
  header : @core.PacketHeaderMetadata,
  payload : Bytes,
) -> Result[MultiCodeblockPacketParts, String] {
  if header.code_blocks.length() <= 0 {
    return Err("packet header has no code-block entries")
  }
  let body_start = @packet.pkt_body_start_offset(payload, header.consumed_bits)
  let mut body_offset = body_start
  let parts : Array[SingleCodeblockPacketParts] = []
  for cb in header.code_blocks {
    let segment_total = @math.sum_ints(cb.segment_lengths)
    let body_end = body_offset + segment_total
    if body_end > payload.length() {
      return Err("packet body truncated for code-block segment lengths")
    }
    let codeword_bytes : Array[Byte] = []
    for i in body_offset..<body_end {
      codeword_bytes.push(payload[i])
    }
    parts.push({
      segment_total,
      segment_lengths: cb.segment_lengths,
      segment_passes: cb.segment_passes,
      non_zero_packet: !header.zero_length,
      included: cb.included,
      zero_bit_planes: cb.zero_bit_planes,
      coding_passes: cb.coding_passes,
      codeword: Bytes::from_iter(codeword_bytes.iter()),
    })
    body_offset = body_end
  }
  Ok({
    non_zero_packet: !header.zero_length,
    code_block_count: header.code_blocks.length(),
    parts,
  })
}

///|
// Spec basis (T.800-2015 A.8 / B.10):
// - SOP/EPH are packet signalling markers and packet headers define
//   code-block contribution lengths before packet body consumption.
fn parse_first_packet_multi_parts_with_code_block_count(
  payload : Bytes,
  code_block_count : Int,
  code_block_style : Int,
) -> Result[MultiCodeblockPacketParts, String] {
  let header_v = @core.parse_packet_header_first_packet_with_code_blocks_and_style(
    payload, code_block_count, code_block_style,
  )
  guard header_v is Ok(header) else {
    return Err(
      "packet header parse failed for code-block-count=\{code_block_count}",
    )
  }
  packet_header_all_codeblocks_to_multi_parts(header, payload)
}

///|
// Spec basis (T.800-2015 A.8 / B.10):
// - SOP/EPH are packet signalling markers and packet headers define
//   code-block contribution lengths before packet body consumption.
fn parse_first_packet_parts_with_code_block_count(
  payload : Bytes,
  code_block_count : Int,
  code_block_style : Int,
) -> Result[SingleCodeblockPacketParts, String] {
  // Spec basis (T.800-2015):
  // - B.10.6/B.10.7: first packet header decodes coding-pass count and segment lengths.
  // - A.6.1 Table A.19: code-block style (e.g. termination-on-pass) affects segments.
  let header_v = @core.parse_packet_header_first_packet_with_code_blocks_and_style(
    payload, code_block_count, code_block_style,
  )
  guard header_v is Ok(header) else {
    return Err(
      "packet header parse failed for code-block-count=\{code_block_count}",
    )
  }
  packet_header_first_included_codeblock_to_parts(header, payload)
}

///|
// Spec basis (T.800-2015 A.8 / B.10):
// - SOP/EPH are packet signalling markers and packet headers define
//   code-block contribution lengths before packet body consumption.
fn parse_first_packet_parts_with_tag_tree_size(
  payload : Bytes,
  width : Int,
  height : Int,
) -> Result[SingleCodeblockPacketParts, String] {
  // Spec basis (T.800-2015 B.10.4/B.10.5):
  // - first inclusion and zero-bitplane signalling for not-yet-included blocks
  //   use tag trees with causal state across packet headers.
  let header_v = @core.parse_packet_header_single_packet_with_tag_tree(
    payload, width, height, 0,
  )
  guard header_v is Ok(header) else {
    return Err("tag-tree packet header parse failed")
  }
  packet_header_first_included_codeblock_to_parts(header, payload)
}

///|
// Spec basis (T.800-2015 B.10.4/B.10.5):
// Parse multi-codeblock first packet using tag-tree coding for inclusion/zbp.
// T.800-2015 B.10.4.1: "For initial code-block contributions, inclusion is
// decoded using the tag tree method."
fn parse_first_packet_multi_parts_with_tag_tree_size(
  payload : Bytes,
  width : Int,
  height : Int,
  code_block_style : Int,
) -> Result[MultiCodeblockPacketParts, String] {
  // Spec basis (T.800-2015 B.10.4/B.10.5):
  // - first inclusion uses tag-tree; zbp uses tag-tree for first-included blocks
  // - pass splits depend on code_block_style (e.g., TERMALL)
  let added_passes : Array[Array[Int]] = []
  // For first packet, we don't know passes yet - they're decoded from header
  // Use empty override to let the parser decode segment lengths normally
  let header_v = @core.parse_packet_header_single_packet_with_tag_tree_and_pass_splits(
    payload, width, height, 0, added_passes,
  )
  guard header_v is Ok(header) else {
    return Err("tag-tree multi-codeblock packet header parse failed")
  }
  // Apply code-block style for segment parsing if TERMALL
  // (The header already parsed segment lengths; we just convert to parts)
  let _ = code_block_style // May be used in future for verification
  packet_header_all_codeblocks_to_multi_parts(header, payload)
}

///|
// Spec basis (T.800-2015 A.8 / B.10):
// - SOP/EPH are packet signalling markers and packet headers define
//   code-block contribution lengths before packet body consumption.
fn is_plausible_first_packet_fallback(
  parts : SingleCodeblockPacketParts,
) -> Bool {
  if parts.segment_total > 0 {
    return true
  }
  if !parts.non_zero_packet {
    return true
  }
  parts.included
}

///|
pub(all) struct PacketHeaderShapeCandidate {
  pub code_block_count : Int
  pub width : Int
  pub height : Int
}

///|
// Spec basis (T.800-2015 A.8 / B.10):
// - SOP/EPH are packet signalling markers and packet headers define
//   code-block contribution lengths before packet body consumption.
pub fn parse_single_codeblock_first_packet_parts_with_candidates(
  payload : Bytes,
  code_block_style : Int,
  candidates : Array[PacketHeaderShapeCandidate],
) -> Result[SingleCodeblockPacketParts, String] {
  // Spec basis (T.800-2015):
  // - B.10 packet-header decode order governs first-packet extraction.
  // - A.6.1 Table A.19 style flags are consumed via core style-aware parser.
  // Policy:
  // - only spec-derived shape candidates are probed (no broad brute-force).
  if payload.length() <= 0 {
    return Ok({
      segment_total: 0,
      segment_lengths: [],
      segment_passes: [],
      non_zero_packet: false,
      included: false,
      zero_bit_planes: None,
      coding_passes: None,
      codeword: b"",
    })
  }
  let header_v = @core.parse_packet_header_first_packet_with_code_blocks_and_style(
    payload, 1, code_block_style,
  )
  let mut single_err : String? = None
  if header_v is Ok(header) {
    let single_v = packet_header_codeblock_to_parts(header, payload)
    if single_v is Ok(parts) {
      return Ok(parts)
    } else if single_v is Err(msg) {
      single_err = Some(msg)
    }
  }
  for candidate in candidates {
    let fallback_v = parse_first_packet_parts_with_code_block_count(
      payload,
      candidate.code_block_count,
      code_block_style,
    )
    if fallback_v is Ok(parts) && is_plausible_first_packet_fallback(parts) {
      return Ok(parts)
    }
    let tag_tree_v = parse_first_packet_parts_with_tag_tree_size(
      payload,
      candidate.width,
      candidate.height,
    )
    if tag_tree_v is Ok(parts) && is_plausible_first_packet_fallback(parts) {
      return Ok(parts)
    }
  }
  if single_err is Some(msg) {
    return Err(msg)
  }
  Err("single-codeblock first packet codeword extraction failed")
}

///|
// Spec basis (T.800-2015 A.8 / B.10):
// - SOP/EPH are packet signalling markers and packet headers define
//   code-block contribution lengths before packet body consumption.
pub fn parse_single_codeblock_first_packet_parts(
  payload : Bytes,
) -> Result[SingleCodeblockPacketParts, String] {
  parse_single_codeblock_first_packet_parts_with_candidates(payload, 0, [])
}

///|
// Spec basis (T.800-2015 A.8 / B.10):
// Parse multi-codeblock packet parts using candidate shapes.
// Returns all code-blocks for images with multiple code-blocks.
// T.800-2015 B.10.4.1: "For initial code-block contributions, inclusion is
// decoded using the tag tree method." - Try tag-tree parsing first.
pub fn parse_multi_codeblock_first_packet_parts_with_candidates(
  payload : Bytes,
  code_block_style : Int,
  candidates : Array[PacketHeaderShapeCandidate],
) -> Result[MultiCodeblockPacketParts, String] {
  if payload.length() <= 0 {
    return Ok({ non_zero_packet: false, code_block_count: 0, parts: [], })
  }
  let prefer_simple_ht = (code_block_style & 0x40) != 0
  for candidate in candidates {
    if candidate.code_block_count <= 1 {
      continue // Only interested in multi-codeblock cases
    }
    let ordered_attempts = if prefer_simple_ht {
      [
        parse_first_packet_multi_parts_with_code_block_count(
          payload,
          candidate.code_block_count,
          code_block_style,
        ),
        parse_first_packet_multi_parts_with_tag_tree_size(
          payload,
          candidate.width,
          candidate.height,
          code_block_style,
        ),
      ]
    } else {
      [
        parse_first_packet_multi_parts_with_tag_tree_size(
          payload,
          candidate.width,
          candidate.height,
          code_block_style,
        ),
        parse_first_packet_multi_parts_with_code_block_count(
          payload,
          candidate.code_block_count,
          code_block_style,
        ),
      ]
    }
    for candidate_v in ordered_attempts {
      if candidate_v is Ok(multi_parts) {
        let mut has_included = false
        for p in multi_parts.parts {
          if p.included {
            has_included = true
            break
          }
        }
        if has_included || !multi_parts.non_zero_packet {
          return Ok(multi_parts)
        }
      }
    }
  }
  Err("multi-codeblock first packet extraction failed")
}

///|
// Spec basis (T.800-2015 A.8 / B.10):
// - SOP/EPH are packet signalling markers and packet headers define
//   code-block contribution lengths before packet body consumption.
pub fn is_single_packet_simple_profile(
  stream : @core.Codestream,
  siz : @core.SizMetadata,
) -> Bool {
  // Spec basis (T.800-2015 A.6.1 Table A.17):
  // staged bridge allows component-0 decode for csiz>1 when MCT is not used.
  if siz.csiz <= 0 {
    return false
  }
  // Spec basis (T.800-2015 A.5/A.6.3/A.6.5):
  // component-specific marker segments are signalled by COC/QCC/RGN.
  // Staged bridge currently decodes component-0 path.
  // Current policy:
  // - csiz=1: component-0 overrides are accepted.
  // - csiz>1: override presence itself is tolerated, but component index must
  //   be valid.
  if siz.csiz != 1 &&
    (
      stream.metadata.coc.length() > 0 ||
      stream.metadata.qcc.length() > 0 ||
      stream.metadata.rgn.length() > 0
    ) {
    for coc in stream.metadata.coc {
      if coc.component < 0 || coc.component >= siz.csiz {
        return false
      }
    }
    for qcc in stream.metadata.qcc {
      if qcc.component < 0 || qcc.component >= siz.csiz {
        return false
      }
    }
    for rgn in stream.metadata.rgn {
      if rgn.component < 0 || rgn.component >= siz.csiz {
        return false
      }
    }
  }
  if siz.csiz == 1 {
    for coc in stream.metadata.coc {
      if coc.component != 0 {
        return false
      }
    }
    for qcc in stream.metadata.qcc {
      if qcc.component != 0 {
        return false
      }
    }
    for rgn in stream.metadata.rgn {
      if rgn.component != 0 {
        return false
      }
    }
  }
  if stream.metadata.cod is None {
    return false
  }
  // Spec basis (T.800-2015 B.6/B.10):
  // precinct partitioning and packet-ordering are resolution-domain concepts;
  // staged tier2 extraction accepts precinct signalling and consumes
  // first-packet parts from available packet payloads.
  let precinct_supported = true
  // Staged profile gate:
  // allow layers/decomposition variation while we still require in-band
  // simple packet signaling, including precinct-signalled codestreams.
  if !precinct_supported {
    return false
  }
  true
}

///|
pub fn simple_profile_component0_decode_context(
  stream : @core.Codestream,
) -> (Int, Int, Int, Int) {
  guard stream.metadata.cod is Some(cod) else { return (0, 64, 64, 0) }
  let tile_index = match stream.metadata.siz {
    Some(siz) => if siz.tile_count <= 1 { 0 } else { -1 }
    None => -1
  }
  let (decomp_levels, cbw, cbh, code_block_style, _, _) = @geometry.get_component_decode_context(
    stream,
    0,
    cod,
    tile_index~,
  )
  (decomp_levels, cbw, cbh, code_block_style)
}

///|
// Spec basis (T.800-2015 A.8 / B.10):
// - SOP/EPH are packet signalling markers and packet headers define
//   code-block contribution lengths before packet body consumption.
pub fn extract_all_single_codeblock_first_packet_parts(
  stream : @core.Codestream,
  payloads : Array[Bytes],
) -> Result[Array[SingleCodeblockPacketParts], String] {
  // Spec basis (T.800-2015):
  // - B.10: packet header precedes packet body and determines contribution lengths.
  // - A.6.1 Table A.19: code-block style semantics are part of header decode.
  // Decoder policy:
  // - consume core style-aware parser with SIZ/COD-derived shape candidates.
  let out : Array[SingleCodeblockPacketParts] = []
  let candidates = simple_profile_packet_header_shape_candidates(stream)
  let (decomp_levels, _, _, code_block_style) = simple_profile_component0_decode_context(
    stream,
  )
  if decomp_levels == 0 && (code_block_style & 0x40) != 0 {
    for payload in payloads {
      let extracted_v = extract_single_codeblock_packet_parts_series(
        payload, code_block_style,
      )
      guard extracted_v is Ok(series_parts) else {
        return Err("single-codeblock sequential packet split failed")
      }
      for parts in series_parts {
        out.push(parts)
      }
    }
    return Ok(out)
  }
  let packet_payloads = if decomp_levels == 0 {
    payloads
  } else {
    let payload_packets = sequential_single_codeblock_packet_payloads(
      stream, payloads,
    )
    guard payload_packets is Ok(packet_payloads) else {
      return Err("single-codeblock sequential packet split failed")
    }
    packet_payloads
  }
  for payload in packet_payloads {
    let extracted = if candidates.length() > 0 {
      parse_single_codeblock_first_packet_parts_with_candidates(
        payload, code_block_style, candidates,
      )
    } else {
      parse_single_codeblock_first_packet_parts(payload)
    }
    guard extracted is Ok(parts) else {
      return Err("single-codeblock first packet codeword extraction failed")
    }
    // Staged tier2 policy:
    // accept first-packet extraction even when trailing bytes remain.
    // trailing bytes may belong to following packets/tile-parts.
    out.push(parts)
  }
  Ok(out)
}

///|
fn sequential_single_codeblock_packet_payloads(
  stream : @core.Codestream,
  payloads : Array[Bytes],
) -> Result[Array[Bytes], String] {
  guard stream.metadata.cod is Some(cod) else {
    return Err("missing COD metadata")
  }
  let (decomp_levels, cb_width, cb_height, code_block_style) = simple_profile_component0_decode_context(
    stream,
  )
  let out : Array[Bytes] = []
  for payload in payloads {
    let split_v = if decomp_levels == 0 {
      split_sod_payload_single_codeblock_series(payload, code_block_style)
    } else {
      guard stream.metadata.siz is Some(siz) else {
        return Err("missing SIZ metadata")
      }
      let dims_v = @input.component_dimensions_from_siz(siz, 0)
      guard dims_v is Ok((c0_width, c0_height)) else {
        return Err("component 0 dimensions unavailable")
      }
      let res_v = split_sod_payload_sequential(
        payload,
        c0_width,
        c0_height,
        decomp_levels,
        siz.csiz,
        cod.layers,
        cod.progression_order,
        code_block_style,
        cb_width~,
        cb_height~,
      )
      if res_v is Ok(res_packets) {
        let flattened : Array[Bytes] = []
        for packets in res_packets {
          for packet in packets {
            flattened.push(packet.1)
          }
        }
        Ok(flattened)
      } else {
        Err("sequential split failed")
      }
    }
    guard split_v is Ok(res_packets) else {
      return Err("sequential split failed")
    }
    let mut pushed = false
    for packets in res_packets {
      out.push(packets)
      pushed = true
    }
    if !pushed {
      out.push(payload)
    }
  }
  Ok(out)
}

///|
pub fn split_sod_payload_single_codeblock_series(
  payload : Bytes,
  code_block_style : Int,
) -> Result[Array[Bytes], String] {
  let out : Array[Bytes] = []
  let mut offset = 0
  let included_before = [false]
  let lblock_by_cb = [3]
  let seg_numpasses_by_cb = [0]
  let seg_maxpasses_by_cb = [0]
  let seg_count_by_cb = [0]
  while offset < payload.length() {
    let remaining = payload[offset:payload.length()].to_bytes()
    let nz_v = @packet.pkt_read_bit(remaining, 0)
    guard nz_v is Ok(non_zero_flag) else {
      return Err("single-codeblock packet header series parse failed")
    }
    let mut bit_pos = 1
    let mut body_size = 0
    if non_zero_flag == 1 {
      let inc_v = @packet.pkt_read_bit(remaining, bit_pos)
      guard inc_v is Ok(included_bit) else {
        return Err("single-codeblock packet header inclusion truncated")
      }
      bit_pos += 1
      if included_bit == 1 {
        if !included_before[0] {
          while true {
            let z_v = @packet.pkt_read_bit(remaining, bit_pos)
            guard z_v is Ok(z_bit) else {
              return Err("unterminated zero bit-plane code")
            }
            bit_pos += 1
            if z_bit == 1 {
              break
            }
          }
          included_before[0] = true
        }
        let pass_v = @packet.pkt_decode_num_coding_passes(remaining, bit_pos)
        guard pass_v is Ok((coding_passes, next_pass_pos)) else {
          return Err("failed to decode number of coding passes")
        }
        bit_pos = next_pass_pos
        let added_passes = split_packet_passes_and_advance_segment_state(
          code_block_style, coding_passes, seg_numpasses_by_cb, seg_maxpasses_by_cb,
          seg_count_by_cb, 0,
        )
        let lengths_v = decode_lengths_for_single_codeblock_series(
          remaining,
          bit_pos,
          lblock_by_cb[0],
          coding_passes,
          added_passes,
        )
        guard lengths_v is Ok((segment_lengths, next_len_pos, next_lblock)) else {
          return Err("failed to decode code-block segment length")
        }
        bit_pos = next_len_pos
        lblock_by_cb[0] = next_lblock
        body_size = @math.sum_ints(segment_lengths)
      }
    }
    let header_bytes = @packet.pkt_body_start_offset(remaining, bit_pos)
    let packet_size = header_bytes + body_size
    if packet_size < 0 || offset + packet_size > payload.length() {
      return Err("single-codeblock packet payload truncated")
    }
    let packet_payload = payload[offset:offset + packet_size].to_bytes()
    out.push(packet_payload)
    offset += packet_size
  }
  if out.length() == 0 {
    return Err("single-codeblock packet header series parse failed")
  }
  Ok(out)
}

///|
fn extract_single_codeblock_packet_parts_series(
  payload : Bytes,
  code_block_style : Int,
) -> Result[Array[SingleCodeblockPacketParts], String] {
  let out : Array[SingleCodeblockPacketParts] = []
  let mut offset = 0
  let included_before = [false]
  let lblock_by_cb = [3]
  let seg_numpasses_by_cb = [0]
  let seg_maxpasses_by_cb = [0]
  let seg_count_by_cb = [0]
  while offset < payload.length() {
    let remaining = payload[offset:payload.length()].to_bytes()
    let nz_v = @packet.pkt_read_bit(remaining, 0)
    guard nz_v is Ok(non_zero_flag) else {
      return Err("single-codeblock packet header series parse failed")
    }
    let mut bit_pos = 1
    let mut body_size = 0
    let mut included = false
    let mut zero_bit_planes : Int? = None
    let mut coding_passes : Int? = None
    let segment_lengths : Array[Int] = []
    let segment_passes : Array[Int] = []
    if non_zero_flag == 1 {
      let inc_v = @packet.pkt_read_bit(remaining, bit_pos)
      guard inc_v is Ok(included_bit) else {
        return Err("single-codeblock packet header inclusion truncated")
      }
      bit_pos += 1
      if included_bit == 1 {
        included = true
        if !included_before[0] {
          let mut zbp = 0
          while true {
            let z_v = @packet.pkt_read_bit(remaining, bit_pos)
            guard z_v is Ok(z_bit) else {
              return Err("unterminated zero bit-plane code")
            }
            bit_pos += 1
            if z_bit == 1 {
              break
            }
            zbp += 1
          }
          zero_bit_planes = Some(zbp)
          included_before[0] = true
        }
        let pass_v = @packet.pkt_decode_num_coding_passes(remaining, bit_pos)
        guard pass_v is Ok((packet_passes, next_pass_pos)) else {
          return Err("failed to decode number of coding passes")
        }
        coding_passes = Some(packet_passes)
        bit_pos = next_pass_pos
        let added_passes = split_packet_passes_and_advance_segment_state(
          code_block_style, packet_passes, seg_numpasses_by_cb, seg_maxpasses_by_cb,
          seg_count_by_cb, 0,
        )
        let lengths_v = decode_lengths_for_single_codeblock_series(
          remaining,
          bit_pos,
          lblock_by_cb[0],
          packet_passes,
          added_passes,
        )
        guard lengths_v is Ok((decoded_lengths, next_len_pos, next_lblock)) else {
          return Err("failed to decode code-block segment length")
        }
        bit_pos = next_len_pos
        lblock_by_cb[0] = next_lblock
        for sl in decoded_lengths {
          segment_lengths.push(sl)
          body_size += sl
        }
        for sp in added_passes {
          segment_passes.push(sp)
        }
      }
    }
    let header_bytes = @packet.pkt_body_start_offset(remaining, bit_pos)
    let packet_size = header_bytes + body_size
    if packet_size < 0 || offset + packet_size > payload.length() {
      return Err("single-codeblock packet payload truncated")
    }
    let codeword_bytes : Array[Byte] = []
    for i in (offset + header_bytes)..<(offset + packet_size) {
      codeword_bytes.push(payload[i])
    }
    out.push({
      segment_total: body_size,
      segment_lengths,
      segment_passes,
      non_zero_packet: non_zero_flag == 1,
      included,
      zero_bit_planes,
      coding_passes,
      codeword: Bytes::from_iter(codeword_bytes.iter()),
    })
    offset += packet_size
  }
  if out.length() == 0 {
    return Err("single-codeblock packet header series parse failed")
  }
  Ok(out)
}

///|
fn decode_lengths_for_single_codeblock_series(
  data : Bytes,
  bit_pos : Int,
  lblock_current : Int,
  coding_passes : Int,
  added_passes : Array[Int],
) -> Result[(Array[Int], Int, Int), String] {
  let expected = if added_passes.length() == 0 {
    coding_passes
  } else {
    @math.sum_ints(added_passes)
  }
  if expected != coding_passes {
    return Err("added passes override does not match coding passes")
  }
  let lengths : Array[Int] = []
  let mut pos = bit_pos
  let mut lblock = lblock_current
  let effective_added = if added_passes.length() == 0 {
    [coding_passes]
  } else {
    added_passes
  }
  let mut lblock_increment = 0
  while true {
    let bit_v = @packet.pkt_read_bit(data, pos)
    guard bit_v is Ok(bit) else {
      return Err("unterminated Lblock increment code")
    }
    pos += 1
    if bit == 0 {
      break
    }
    lblock_increment += 1
  }
  lblock += lblock_increment
  for passes in effective_added {
    let width = lblock + @math.floor_log2(passes)
    let len_v = @packet.pkt_read_bits(data, pos, width)
    guard len_v is Ok((segment_length, next_pos)) else {
      return Err("failed to decode code-block segment length")
    }
    lengths.push(segment_length)
    pos = next_pos
  }
  Ok((lengths, pos, lblock))
}

///|
pub fn extract_multi_codeblock_packet_parts_series(
  payload : Bytes,
  code_block_count : Int,
  code_block_style : Int,
) -> Result[Array[MultiCodeblockPacketParts], String] {
  if code_block_count <= 0 {
    return Err(
      "multi-codeblock packet series requires positive code-block count",
    )
  }
  let out : Array[MultiCodeblockPacketParts] = []
  let mut offset = 0
  let included_before : Array[Bool] = []
  let lblock_by_cb : Array[Int] = []
  let seg_numpasses_by_cb : Array[Int] = []
  let seg_maxpasses_by_cb : Array[Int] = []
  let seg_count_by_cb : Array[Int] = []
  for _ in 0..<code_block_count {
    included_before.push(false)
    lblock_by_cb.push(3)
    seg_numpasses_by_cb.push(0)
    seg_maxpasses_by_cb.push(0)
    seg_count_by_cb.push(0)
  }
  while offset < payload.length() {
    let remaining = payload[offset:payload.length()].to_bytes()
    let nz_v = @packet.pkt_read_bit(remaining, 0)
    guard nz_v is Ok(non_zero_flag) else {
      return Err("multi-codeblock packet header series parse failed")
    }
    let mut bit_pos = 1
    let parsed_parts : Array[SingleCodeblockPacketParts] = []
    let mut total_body_size = 0
    if non_zero_flag == 0 {
      for _ in 0..<code_block_count {
        parsed_parts.push({
          segment_total: 0,
          segment_lengths: [],
          segment_passes: [],
          non_zero_packet: false,
          included: false,
          zero_bit_planes: None,
          coding_passes: None,
          codeword: b"",
        })
      }
    } else {
      for cb in 0..<code_block_count {
        let inc_v = @packet.pkt_read_bit(remaining, bit_pos)
        guard inc_v is Ok(included_bit) else {
          return Err("multi-codeblock packet header inclusion truncated")
        }
        bit_pos += 1
        if included_bit == 0 {
          parsed_parts.push({
            segment_total: 0,
            segment_lengths: [],
            segment_passes: [],
            non_zero_packet: true,
            included: false,
            zero_bit_planes: None,
            coding_passes: None,
            codeword: b"",
          })
          continue
        }
        let mut zero_bit_planes : Int? = None
        if !included_before[cb] {
          let mut zbp = 0
          while true {
            let z_v = @packet.pkt_read_bit(remaining, bit_pos)
            guard z_v is Ok(z_bit) else {
              return Err("unterminated zero bit-plane code")
            }
            bit_pos += 1
            if z_bit == 1 {
              break
            }
            zbp += 1
          }
          zero_bit_planes = Some(zbp)
          included_before[cb] = true
        }
        let pass_v = @packet.pkt_decode_num_coding_passes(remaining, bit_pos)
        guard pass_v is Ok((packet_passes, next_pass_pos)) else {
          return Err("failed to decode number of coding passes")
        }
        bit_pos = next_pass_pos
        let added_passes = split_packet_passes_and_advance_segment_state(
          code_block_style, packet_passes, seg_numpasses_by_cb, seg_maxpasses_by_cb,
          seg_count_by_cb, cb,
        )
        let lengths_v = decode_lengths_for_single_codeblock_series(
          remaining,
          bit_pos,
          lblock_by_cb[cb],
          packet_passes,
          added_passes,
        )
        guard lengths_v is Ok((decoded_lengths, next_len_pos, next_lblock)) else {
          return Err("failed to decode code-block segment length")
        }
        bit_pos = next_len_pos
        lblock_by_cb[cb] = next_lblock
        let mut segment_total = 0
        let segment_lengths : Array[Int] = []
        let segment_passes : Array[Int] = []
        for sl in decoded_lengths {
          segment_lengths.push(sl)
          segment_total += sl
        }
        for sp in added_passes {
          segment_passes.push(sp)
        }
        total_body_size += segment_total
        parsed_parts.push({
          segment_total,
          segment_lengths,
          segment_passes,
          non_zero_packet: true,
          included: true,
          zero_bit_planes,
          coding_passes: Some(packet_passes),
          codeword: b"",
        })
      }
    }
    let header_bytes = @packet.pkt_body_start_offset(remaining, bit_pos)
    let packet_size = header_bytes + total_body_size
    if packet_size < 0 || offset + packet_size > payload.length() {
      return Err("multi-codeblock packet payload truncated")
    }
    let mut body_cursor = offset + header_bytes
    let filled_parts : Array[SingleCodeblockPacketParts] = []
    for parts in parsed_parts {
      let codeword_bytes : Array[Byte] = []
      if parts.segment_total > 0 {
        let body_end = body_cursor + parts.segment_total
        if body_end > offset + packet_size {
          return Err("multi-codeblock packet body truncated")
        }
        for i in body_cursor..<body_end {
          codeword_bytes.push(payload[i])
        }
        body_cursor = body_end
      }
      filled_parts.push({
        segment_total: parts.segment_total,
        segment_lengths: parts.segment_lengths,
        segment_passes: parts.segment_passes,
        non_zero_packet: parts.non_zero_packet,
        included: parts.included,
        zero_bit_planes: parts.zero_bit_planes,
        coding_passes: parts.coding_passes,
        codeword: Bytes::from_iter(codeword_bytes.iter()),
      })
    }
    out.push({
      non_zero_packet: non_zero_flag == 1,
      code_block_count,
      parts: filled_parts,
    })
    offset += packet_size
  }
  if out.length() == 0 {
    return Err("multi-codeblock packet header series parse failed")
  }
  Ok(out)
}

///|
// Spec basis (T.800-2015 A.8 / B.10):
// Extract multi-codeblock parts from all payloads.
// Returns (multi_parts, code_block_width, code_block_height) if successful.
pub fn extract_multi_codeblock_first_packet_parts(
  stream : @core.Codestream,
  payloads : Array[Bytes],
) -> Result[(Array[MultiCodeblockPacketParts], Int, Int), String] {
  let candidates = simple_profile_packet_header_shape_candidates(stream)
  let (_, _, _, code_block_style) = simple_profile_component0_decode_context(
    stream,
  )
  // Find the candidate with >1 code-blocks
  let mut cb_width = 1
  let mut cb_height = 1
  for c in candidates {
    if c.code_block_count > 1 {
      cb_width = c.width
      cb_height = c.height
      break
    }
  }
  if cb_width * cb_height <= 1 {
    return Err("no multi-codeblock candidate found")
  }
  let out : Array[MultiCodeblockPacketParts] = []
  for payload in payloads {
    let extracted = parse_multi_codeblock_first_packet_parts_with_candidates(
      payload, code_block_style, candidates,
    )
    guard extracted is Ok(parts) else {
      return Err("multi-codeblock first packet extraction failed")
    }
    out.push(parts)
  }
  Ok((out, cb_width, cb_height))
}

///|
fn single_codeblock_packet_parts_equal(
  lhs : SingleCodeblockPacketParts,
  rhs : SingleCodeblockPacketParts,
) -> Bool {
  lhs.segment_total == rhs.segment_total &&
  lhs.segment_lengths == rhs.segment_lengths &&
  lhs.segment_passes == rhs.segment_passes &&
  lhs.non_zero_packet == rhs.non_zero_packet &&
  lhs.included == rhs.included &&
  lhs.zero_bit_planes == rhs.zero_bit_planes &&
  lhs.coding_passes == rhs.coding_passes &&
  lhs.codeword == rhs.codeword
}

///|
fn multi_codeblock_packet_parts_equal(
  lhs : MultiCodeblockPacketParts,
  rhs : MultiCodeblockPacketParts,
) -> Bool {
  if lhs.non_zero_packet != rhs.non_zero_packet ||
    lhs.parts.length() != rhs.parts.length() {
    return false
  }
  for i in 0..<lhs.parts.length() {
    if !single_codeblock_packet_parts_equal(lhs.parts[i], rhs.parts[i]) {
      return false
    }
  }
  true
}

///|
pub fn extract_multi_codeblock_packet_parts_series_if_plausible(
  stream : @core.Codestream,
  payloads : Array[Bytes],
) -> Result[(Array[MultiCodeblockPacketParts], Int, Int), String] {
  let candidates = simple_profile_packet_header_shape_candidates(stream)
  let (_, _, _, code_block_style) = simple_profile_component0_decode_context(
    stream,
  )
  let mut cb_width = 1
  let mut cb_height = 1
  for c in candidates {
    if c.code_block_count > 1 {
      cb_width = c.width
      cb_height = c.height
      break
    }
  }
  if cb_width * cb_height <= 1 {
    return Err("no multi-codeblock candidate found")
  }
  let code_block_count = cb_width * cb_height
  let out : Array[MultiCodeblockPacketParts] = []
  for payload in payloads {
    let first_v = parse_multi_codeblock_first_packet_parts_with_candidates(
      payload, code_block_style, candidates,
    )
    guard first_v is Ok(first_parts) else {
      return Err("multi-codeblock first packet extraction failed")
    }
    let series_v = extract_multi_codeblock_packet_parts_series(
      payload, code_block_count, code_block_style,
    )
    guard series_v is Ok(series_parts) else {
      return Err("multi-codeblock packet header series parse failed")
    }
    if series_parts.length() <= 0 ||
      !multi_codeblock_packet_parts_equal(series_parts[0], first_parts) {
      return Err("multi-codeblock packet series parse is not plausible")
    }
    for parts in series_parts {
      out.push(parts)
    }
  }
  Ok((out, cb_width, cb_height))
}

///|
// Spec basis (T.800-2015 A.8 / B.10):
// - SOP/EPH are packet signalling markers and packet headers define
//   code-block contribution lengths before packet body consumption.
fn packet_header_codeblock_to_parts_for_relocated(
  header : @core.PacketHeaderMetadata,
  payload : Bytes,
) -> Result[SingleCodeblockPacketParts, String] {
  if header.code_blocks.length() != 1 {
    return Err("relocated packet header is not single-codeblock")
  }
  let cb = header.code_blocks[0]
  let segment_total = @math.sum_ints(cb.segment_lengths)
  if segment_total != payload.length() {
    return Err("packet body length does not match relocated segment lengths")
  }
  let codeword_bytes : Array[Byte] = []
  for i in 0..<payload.length() {
    codeword_bytes.push(payload[i])
  }
  Ok({
    segment_total,
    segment_lengths: cb.segment_lengths,
    segment_passes: cb.segment_passes,
    non_zero_packet: !header.zero_length,
    included: cb.included,
    zero_bit_planes: cb.zero_bit_planes,
    coding_passes: cb.coding_passes,
    codeword: Bytes::from_iter(codeword_bytes.iter()),
  })
}

///|
// Spec basis (T.800-2015 A.8 / B.10):
// - SOP/EPH are packet signalling markers and packet headers define
//   code-block contribution lengths before packet body consumption.
fn extract_parts_from_relocated_headers(
  payloads : Array[Bytes],
  headers : Array[@core.PacketHeaderMetadata],
) -> Result[Array[SingleCodeblockPacketParts], String] {
  if headers.length() <= 0 {
    return Err("no relocated packet headers")
  }
  if headers.length() != payloads.length() {
    return Err("relocated packet header count does not match SOD payload count")
  }
  let out : Array[SingleCodeblockPacketParts] = []
  for i in 0..<payloads.length() {
    let parts_v = packet_header_codeblock_to_parts_for_relocated(
      headers[i],
      payloads[i],
    )
    guard parts_v is Ok(parts) else {
      return Err("failed to map relocated packet header to packet body")
    }
    out.push(parts)
  }
  Ok(out)
}

///|
// Spec basis (T.800-2015 A.8 / B.10):
// - SOP/EPH are packet signalling markers and packet headers define
//   code-block contribution lengths before packet body consumption.
fn choose_relocated_single_codeblock_headers(
  stream : @core.Codestream,
) -> Array[@core.PacketHeaderMetadata]? {
  if stream.metadata.packet_headers_ppt.length() > 0 {
    return Some(stream.metadata.packet_headers_ppt)
  }
  if stream.metadata.packet_headers_ppm.length() > 0 {
    return Some(stream.metadata.packet_headers_ppm)
  }
  None
}

///|
// Spec basis (T.800-2015 A.8 / B.10):
// - SOP/EPH are packet signalling markers and packet headers define
//   code-block contribution lengths before packet body consumption.
pub fn extract_simple_profile_packet_parts(
  stream : @core.Codestream,
  payloads : Array[Bytes],
) -> Result[Array[SingleCodeblockPacketParts], String] {
  let in_band = extract_all_single_codeblock_first_packet_parts(
    stream, payloads,
  )
  if in_band is Ok(parts_list) {
    return Ok(parts_list)
  }
  if in_band is Err(msg) {
    if choose_relocated_single_codeblock_headers(stream) is Some(headers) {
      let relocated = extract_parts_from_relocated_headers(payloads, headers)
      if relocated is Ok(parts_list) {
        return Ok(parts_list)
      }
    }
    return Err(msg)
  }
  Err("single-codeblock first packet codeword extraction failed")
}

///|
// Spec basis (T.800-2015 A.8 / B.10):
// - SOP/EPH are packet signalling markers and packet headers define
//   code-block contribution lengths before packet body consumption.
pub fn sum_segment_totals(
  parts_list : Array[SingleCodeblockPacketParts],
) -> Int {
  let mut out = 0
  for parts in parts_list {
    out += parts.segment_total
  }
  out
}

///|
// Spec basis (T.800-2015 A.8 / B.10):
// - SOP/EPH are packet signalling markers and packet headers define
//   code-block contribution lengths before packet body consumption.
pub fn first_packet_parts_debug(
  parts_list : Array[SingleCodeblockPacketParts],
) -> String {
  if parts_list.length() <= 0 {
    return "none"
  }
  let p = parts_list[0]
  let passes = if p.coding_passes is Some(v) { v } else { -1 }
  let zbp = if p.zero_bit_planes is Some(v) { v } else { -1 }
  "first{included=\{p.included},passes=\{passes},zbp=\{zbp},segment-count=\{p.segment_lengths.length()},codeword=\{p.codeword.length()}}"
}

///|
// Spec basis (T.800-2015 A.8 / B.10):
// - SOP/EPH are packet signalling markers and packet headers define
//   code-block contribution lengths before packet body consumption.
pub fn parts_are_minimal_zero_tier1_subset(
  parts_list : Array[SingleCodeblockPacketParts],
) -> Bool {
  if parts_list.length() <= 0 {
    return false
  }
  for parts in parts_list {
    if !parts.included {
      continue
    }
    if parts.coding_passes != Some(1) || parts.zero_bit_planes != Some(0) {
      return false
    }
    for b in parts.codeword {
      if b != 0 {
        return false
      }
    }
  }
  true
}

///|
// Spec basis (T.800-2015 B.10.4.1 / B.10.5):
// Per-subband code-block metadata extracted from a resolution > 0 packet header.

///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn validate_packet_len_varints(
  payload : Array[Int],
  start : Int,
) -> Result[Unit, String] {
  if start >= payload.length() {
    return Err("packet length sequence missing")
  }
  let mut saw_end = false
  for i in start..<payload.length() {
    if (payload[i] & 0x80) == 0 {
      saw_end = true
    }
  }
  if !saw_end || (payload[payload.length() - 1] & 0x80) != 0 {
    return Err("unterminated packet length sequence")
  }
  Ok(())
}

///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn validate_plm_payload_chunks(payload : Array[Int]) -> Result[Unit, String] {
  let mut i = 1
  while i < payload.length() {
    let nplm = payload[i]
    i += 1
    let chunk_end = i + nplm
    if chunk_end > payload.length() {
      return Err("PLM chunk exceeds payload")
    }
    let iplm : Array[Int] = []
    for j in i..<chunk_end {
      iplm.push(payload[j])
    }
    let varint_check = validate_packet_len_varints(iplm, 0)
    guard varint_check is Ok(_) else {
      return Err("invalid PLM packet length sequence")
    }
    i = chunk_end
  }
  if i != payload.length() {
    return Err("PLM payload has trailing bytes")
  }
  Ok(())
}

///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn parse_ppm_chunks(
  payload : Array[Int],
) -> Result[Array[PpmChunkMetadata], String] {
  let chunks : Array[PpmChunkMetadata] = []
  let mut i = 1
  while i + 3 < payload.length() {
    let nppm_value = read_u32_from_payload(payload, i)
    guard nppm_value is Ok(nppm) else { return Err("failed to parse Nppm") }
    if nppm < 0 {
      return Err("Nppm is out of range")
    }
    i += 4
    let chunk_end = i + nppm
    if chunk_end < i || chunk_end > payload.length() {
      return Err("PPM chunk exceeds payload")
    }
    let ippm : Array[Int] = []
    for j in i..<chunk_end {
      ippm.push(payload[j])
    }
    chunks.push({ nppm, ippm, })
    i = chunk_end
  }
  if i != payload.length() {
    return Err("PPM payload has trailing bytes")
  }
  Ok(chunks)
}

///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn decode_packet_len_varints(
  payload : Array[Int],
  start : Int,
) -> Result[Array[Int], String] {
  if start >= payload.length() {
    return Err("packet length sequence missing")
  }
  let values : Array[Int] = []
  let mut acc = 0
  let mut in_value = false
  for i in start..<payload.length() {
    let b = payload[i]
    acc = (acc << 7) + (b & 0x7F)
    in_value = true
    if (b & 0x80) == 0 {
      values.push(acc)
      acc = 0
      in_value = false
    }
  }
  if in_value {
    return Err("unterminated packet length sequence")
  }
  Ok(values)
}

///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn parse_plm_metadata(payload : Array[Int]) -> Result[PlmMetadata, String] {
  if payload.length() < 2 {
    return Err("PLM payload too short")
  }
  let zplm = payload[0]
  let chunks : Array[PlmChunkMetadata] = []
  let mut i = 1
  while i < payload.length() {
    let nplm = payload[i]
    i += 1
    let chunk_end = i + nplm
    if chunk_end > payload.length() {
      return Err("PLM chunk exceeds payload")
    }
    let iplm : Array[Int] = []
    for j in i..<chunk_end {
      iplm.push(payload[j])
    }
    let decoded = decode_packet_len_varints(iplm, 0)
    guard decoded is Ok(packet_lengths) else {
      return Err("invalid PLM packet lengths")
    }
    chunks.push({ nplm, packet_lengths, })
    i = chunk_end
  }
  Ok({ zplm, chunks, })
}

///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn parse_plt_metadata(payload : Array[Int]) -> Result[PltMetadata, String] {
  if payload.length() < 2 {
    return Err("PLT payload too short")
  }
  let decoded = decode_packet_len_varints(payload, 1)
  guard decoded is Ok(packet_lengths) else {
    return Err("invalid PLT packet lengths")
  }
  Ok({ zplt: payload[0], packet_lengths, })
}

///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn parse_ppm_metadata(payload : Array[Int]) -> Result[PpmMetadata, String] {
  if payload.length() < 1 {
    return Err("PPM payload too short")
  }
  let zppm = payload[0]
  let parsed_chunks = parse_ppm_chunks(payload)
  if parsed_chunks is Ok(chunks) {
    return Ok({ zppm, chunks, })
  }

  // Spec A.7.4 allows Ippm continuation across PPM marker segments.
  // Fall back to best-effort segment-local extraction.
  let chunks : Array[PpmChunkMetadata] = []
  let mut i = 1
  while i + 3 < payload.length() {
    let nppm_v = read_u32_from_payload(payload, i)
    guard nppm_v is Ok(nppm) else { break }
    if nppm < 0 {
      break
    }
    i += 4
    let chunk_end = i + nppm
    let safe_end = if chunk_end > payload.length() {
      payload.length()
    } else {
      chunk_end
    }
    let ippm : Array[Int] = []
    for j in i..<safe_end {
      ippm.push(payload[j])
    }
    chunks.push({ nppm, ippm, })
    if chunk_end > payload.length() {
      break
    }
    i = chunk_end
  }
  Ok({ zppm, chunks, })
}

///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn parse_ppt_metadata(payload : Array[Int]) -> Result[PptMetadata, String] {
  if payload.length() < 1 {
    return Err("PPT payload too short")
  }
  let data : Array[Int] = []
  for i in 1..<payload.length() {
    data.push(payload[i])
  }
  Ok({ zppt: payload[0], data, })
}

///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn parse_tlm_metadata(payload : Array[Int]) -> Result[TlmMetadata, String] {
  if payload.length() < 4 {
    return Err("TLM payload too short")
  }
  let ztlm = payload[0]
  let stlm = payload[1]
  let tile_field = stlm & 0x30
  let tile_bytes = if tile_field == 0x00 {
    0
  } else if tile_field == 0x10 {
    1
  } else if tile_field == 0x20 {
    2
  } else {
    return Err("unsupported TLM tile index width")
  }
  let len_bytes = if (stlm & 0x40) == 0 { 2 } else { 4 }
  let entry_size = tile_bytes + len_bytes
  if entry_size <= 0 || (payload.length() - 2) % entry_size != 0 {
    return Err("TLM payload length is inconsistent")
  }
  let entries : Array[TlmEntryMetadata] = []
  let mut at = 2
  while at < payload.length() {
    let tile = if tile_bytes == 0 {
      None
    } else if tile_bytes == 1 {
      Some(payload[at])
    } else {
      let v = read_u16_from_payload(payload, at)
      guard v is Ok(t) else { return Err("failed to parse Ttlm") }
      Some(t)
    }
    let len_at = at + tile_bytes
    let length = if len_bytes == 2 {
      let v = read_u16_from_payload(payload, len_at)
      guard v is Ok(l) else { return Err("failed to parse Ptlm") }
      l
    } else {
      let v = read_u32_from_payload(payload, len_at)
      guard v is Ok(l) else { return Err("failed to parse Ptlm") }
      l
    }
    entries.push({ tile, length, })
    at += entry_size
  }
  Ok({ ztlm, stlm, entries, })
}

///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn parse_sop_metadata(
  payload : Array[Int],
  position : Int,
) -> Result[SopMetadata, String] {
  if payload.length() != 2 {
    return Err("SOP payload length is invalid")
  }
  let nsop_v = read_u16_from_payload(payload, 0)
  guard nsop_v is Ok(nsop) else { return Err("failed to parse Nsop") }
  Ok({ nsop, position, })
}

///|
// T.800-2015 A.8.1: Validate SOP marker Nsop sequence.
// "For every successive packet in this coded tile this number is incremented
// by one. When the maximum number is reached, the number rolls over to zero."
//
// Parameters:
// - sop_markers: Array of SopMetadata extracted from tile packets
// - tile_start_positions: Byte positions of SOT markers (for multi-tile)
//
// Returns Ok(()) if sequence is valid, Err with description otherwise.
pub fn validate_sop_nsop_sequence(
  sop_markers : Array[SopMetadata],
) -> Result[Unit, String] {
  if sop_markers.length() == 0 {
    return Ok(())
  }
  // T.800-2015 A.8.1: First packet should have Nsop = 0
  // Note: For multi-tile, each tile resets to 0, but we validate
  // the single-tile case here (sequential packets within one SOD)
  let mut expected_nsop = sop_markers[0].nsop
  for i, sop in sop_markers {
    if i == 0 {
      continue
    }
    // T.800-2015 A.8.1: Increment by 1, roll over at 65536
    expected_nsop = (expected_nsop + 1) % 65536
    if sop.nsop != expected_nsop {
      return Err(
        "SOP Nsop sequence error at packet " +
        i.to_string() +
        ": expected " +
        expected_nsop.to_string() +
        ", got " +
        sop.nsop.to_string(),
      )
    }
  }
  Ok(())
}

///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn parse_crg_metadata(
  payload : Array[Int],
  csiz : Int,
) -> Result[CrgMetadata, String] {
  if payload.length() != csiz * 4 {
    return Err("CRG payload length is invalid")
  }
  let components : Array[CrgComponentMetadata] = []
  let mut at = 0
  while at + 3 < payload.length() {
    let x_v = read_u16_from_payload(payload, at)
    let y_v = read_u16_from_payload(payload, at + 2)
    guard x_v is Ok(xcrg) else { return Err("failed to parse Xcrg") }
    guard y_v is Ok(ycrg) else { return Err("failed to parse Ycrg") }
    components.push({ xcrg, ycrg, })
    at += 4
  }
  Ok({ components, })
}

///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn parse_com_metadata(payload : Array[Int]) -> Result[ComMetadata, String] {
  if payload.length() < 2 {
    return Err("COM payload too short")
  }
  let r_v = read_u16_from_payload(payload, 0)
  guard r_v is Ok(rcom) else { return Err("failed to parse Rcom") }
  let ccom : Array[Int] = []
  for i in 2..<payload.length() {
    ccom.push(payload[i])
  }
  Ok({ rcom, ccom, })
}

///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn build_ordering_metadata(
  siz : SizMetadata,
) -> Result[OrderingMetadata, String] {
  if siz.xsiz <= siz.xosiz || siz.ysiz <= siz.yosiz {
    return Err("invalid reference grid")
  }
  let tiles_x = @math.ceil_div(siz.xsiz - siz.xtosiz, siz.xtsiz)
  let tiles_y = @math.ceil_div(siz.ysiz - siz.ytosiz, siz.ytsiz)
  if tiles_x <= 0 || tiles_y <= 0 {
    return Err("invalid tile grid")
  }
  let components : Array[ComponentGeometryMetadata] = []
  for i, c in siz.components {
    let width = @math.ceil_div(siz.xsiz - siz.xosiz, c.xrsiz)
    let height = @math.ceil_div(siz.ysiz - siz.yosiz, c.yrsiz)
    components.push({
      component: i,
      xrsiz: c.xrsiz,
      yrsiz: c.yrsiz,
      width,
      height,
    })
  }
  let tiles : Array[TileGeometryMetadata] = []
  let mut tile_index = 0
  for ty in 0..<tiles_y {
    for tx in 0..<tiles_x {
      let tx0_raw = siz.xtosiz + tx * siz.xtsiz
      let ty0_raw = siz.ytosiz + ty * siz.ytsiz
      let tx1_raw = siz.xtosiz + (tx + 1) * siz.xtsiz
      let ty1_raw = siz.ytosiz + (ty + 1) * siz.ytsiz
      let x0 = if tx0_raw > siz.xosiz { tx0_raw } else { siz.xosiz }
      let y0 = if ty0_raw > siz.yosiz { ty0_raw } else { siz.yosiz }
      let x1 = if tx1_raw < siz.xsiz { tx1_raw } else { siz.xsiz }
      let y1 = if ty1_raw < siz.ysiz { ty1_raw } else { siz.ysiz }
      tiles.push({ tile_index, tx, ty, x0, y0, x1, y1, })
      tile_index += 1
    }
  }
  let tile_components : Array[TileComponentGeometryMetadata] = []
  for tile in tiles {
    for comp in components {
      let x0 = @math.ceil_div(tile.x0 - siz.xosiz, comp.xrsiz)
      let y0 = @math.ceil_div(tile.y0 - siz.yosiz, comp.yrsiz)
      let x1 = @math.ceil_div(tile.x1 - siz.xosiz, comp.xrsiz)
      let y1 = @math.ceil_div(tile.y1 - siz.yosiz, comp.yrsiz)
      tile_components.push({
        tile_index: tile.tile_index,
        component: comp.component,
        x0,
        y0,
        x1,
        y1,
        width: x1 - x0,
        height: y1 - y0,
      })
    }
  }
  Ok({
    reference_grid: {
      x0: siz.xosiz,
      y0: siz.yosiz,
      x1: siz.xsiz,
      y1: siz.ysiz,
    },
    tiles_x,
    tiles_y,
    components,
    tiles,
    tile_components,
  })
}

///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn build_ordering_coding_metadata(
  cod : CodMetadata,
  ordering : OrderingMetadata,
) -> OrderingCodingMetadata {
  let resolution_count = cod.decomposition_levels + 1
  let subbands_per_resolution : Array[Int] = []
  let precincts : Array[PrecinctResolutionMetadata] = []
  let code_blocks : Array[CodeBlockResolutionMetadata] = []
  let packets : Array[PacketUnitMetadata] = []
  for r in 0..<resolution_count {
    subbands_per_resolution.push(if r == 0 { 1 } else { 3 })
    let mut ppx = 15
    let mut ppy = 15
    if cod.uses_precincts && r < cod.precinct_size_bytes.length() {
      let b = cod.precinct_size_bytes[r]
      ppx = b & 0x0F
      ppy = (b >> 4) & 0x0F
    }
    precincts.push({
      resolution: r,
      ppx,
      ppy,
      precinct_width: 1 << ppx,
      precinct_height: 1 << ppy,
    })
    code_blocks.push({
      resolution: r,
      nominal_width: 1 << cod.code_block_width_exponent,
      nominal_height: 1 << cod.code_block_height_exponent,
    })
  }
  for tc in ordering.tile_components {
    for r in 0..<resolution_count {
      let down = 1 << (cod.decomposition_levels - r)
      let res_w = @math.ceil_div(tc.width, down)
      let res_h = @math.ceil_div(tc.height, down)
      let precinct_w = precincts[r].precinct_width
      let precinct_h = precincts[r].precinct_height
      let precincts_x = @math.ceil_div(res_w, precinct_w)
      let precincts_y = @math.ceil_div(res_h, precinct_h)
      let packets_per_layer = precincts_x * precincts_y
      packets.push({
        tile_index: tc.tile_index,
        component: tc.component,
        resolution: r,
        precincts_x,
        precincts_y,
        packets_per_layer,
        layers: cod.layers,
        packets_total: packets_per_layer * cod.layers,
      })
    }
  }
  {
    decomposition_levels: cod.decomposition_levels,
    resolution_count,
    subbands_per_resolution,
    precincts,
    code_blocks,
    packets,
  }
}

///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn packet_count_for_step(
  coding : OrderingCodingMetadata,
  component : Int,
  resolution : Int,
) -> Int {
  let mut packet_count = 0
  for unit in coding.packets {
    if unit.component == component && unit.resolution == resolution {
      packet_count += unit.packets_per_layer
    }
  }
  packet_count
}

///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn append_progression_steps_by_order(
  steps : Array[ProgressionStepMetadata],
  order_code : Int,
  layer_start : Int,
  layer_end : Int,
  resolution_start : Int,
  resolution_end : Int,
  component_start : Int,
  component_end : Int,
  coding : OrderingCodingMetadata,
  order_index : Int,
) -> (Int, Int) {
  let mut local_index = order_index
  let mut added_packets = 0
  if order_code == 0 {
    for l in layer_start..<layer_end {
      for r in resolution_start..<resolution_end {
        for c in component_start..<component_end {
          let packet_count = packet_count_for_step(coding, c, r)
          steps.push({
            order_index: local_index,
            layer: l,
            resolution: r,
            component: c,
            packet_count,
          })
          local_index += 1
          added_packets += packet_count
        }
      }
    }
    return (local_index, added_packets)
  }
  if order_code == 1 {
    for r in resolution_start..<resolution_end {
      for l in layer_start..<layer_end {
        for c in component_start..<component_end {
          let packet_count = packet_count_for_step(coding, c, r)
          steps.push({
            order_index: local_index,
            layer: l,
            resolution: r,
            component: c,
            packet_count,
          })
          local_index += 1
          added_packets += packet_count
        }
      }
    }
    return (local_index, added_packets)
  }
  if order_code == 2 {
    for r in resolution_start..<resolution_end {
      for c in component_start..<component_end {
        for l in layer_start..<layer_end {
          let packet_count = packet_count_for_step(coding, c, r)
          steps.push({
            order_index: local_index,
            layer: l,
            resolution: r,
            component: c,
            packet_count,
          })
          local_index += 1
          added_packets += packet_count
        }
      }
    }
    return (local_index, added_packets)
  }
  if order_code == 3 {
    for c in component_start..<component_end {
      for r in resolution_start..<resolution_end {
        for l in layer_start..<layer_end {
          let packet_count = packet_count_for_step(coding, c, r)
          steps.push({
            order_index: local_index,
            layer: l,
            resolution: r,
            component: c,
            packet_count,
          })
          local_index += 1
          added_packets += packet_count
        }
      }
    }
    return (local_index, added_packets)
  }
  for c in component_start..<component_end {
    for l in layer_start..<layer_end {
      for r in resolution_start..<resolution_end {
        let packet_count = packet_count_for_step(coding, c, r)
        steps.push({
          order_index: local_index,
          layer: l,
          resolution: r,
          component: c,
          packet_count,
        })
        local_index += 1
        added_packets += packet_count
      }
    }
  }
  (local_index, added_packets)
}

///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn build_progression_metadata(
  cod : CodMetadata,
  ordering : OrderingMetadata,
  coding : OrderingCodingMetadata,
  poc : Array[PocMetadata],
) -> ProgressionMetadata {
  let component_count = ordering.components.length()
  let resolution_count = coding.resolution_count
  let volumes : Array[ProgressionVolumeMetadata] = []
  if poc.length() == 0 {
    volumes.push({
      source_poc_index: -1,
      order_code: cod.progression_order,
      layer_start: 0,
      layer_end: cod.layers,
      resolution_start: 0,
      resolution_end: resolution_count,
      component_start: 0,
      component_end: component_count,
    })
  } else {
    for idx, entry in poc {
      volumes.push({
        source_poc_index: idx,
        order_code: entry.ppoc,
        layer_start: 0,
        layer_end: entry.lyepoc,
        resolution_start: entry.rspoc,
        resolution_end: entry.repoc,
        component_start: entry.cspoc,
        component_end: entry.cepoc,
      })
    }
  }
  let steps : Array[ProgressionStepMetadata] = []
  let mut order_index = 0
  let mut total_packets = 0
  for v in volumes {
    let layer_start = if v.layer_start > 0 { v.layer_start } else { 0 }
    let layer_end = if v.layer_end < cod.layers {
      v.layer_end
    } else {
      cod.layers
    }
    let resolution_start = if v.resolution_start > 0 {
      v.resolution_start
    } else {
      0
    }
    let resolution_end = if v.resolution_end < resolution_count {
      v.resolution_end
    } else {
      resolution_count
    }
    let component_start = if v.component_start > 0 {
      v.component_start
    } else {
      0
    }
    let component_end = if v.component_end < component_count {
      v.component_end
    } else {
      component_count
    }
    if layer_start >= layer_end ||
      resolution_start >= resolution_end ||
      component_start >= component_end {
      continue
    }
    let (next_index, added_packets) = append_progression_steps_by_order(
      steps,
      v.order_code,
      layer_start,
      layer_end,
      resolution_start,
      resolution_end,
      component_start,
      component_end,
      coding,
      order_index,
    )
    order_index = next_index
    total_packets += added_packets
  }
  { order_code: cod.progression_order, volumes, steps, total_packets, }
}

///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn refresh_progression_metadata(
  cod : CodMetadata?,
  ordering : OrderingMetadata?,
  coding : OrderingCodingMetadata?,
  poc : Array[PocMetadata],
) -> ProgressionMetadata? {
  guard cod is Some(cod_meta) else { return None }
  guard ordering is Some(ordering_meta) else { return None }
  guard coding is Some(coding_meta) else { return None }
  Some(build_progression_metadata(cod_meta, ordering_meta, coding_meta, poc))
}

///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn validate_marker_payload(
  code : Int,
  length : Int,
  payload : Array[Int],
  in_main_header : Bool,
  siz_components : Int?,
  main_seen_poc : Bool,
  tile_seen_poc : Bool,
  header_coc_components : Array[Int],
  header_qcc_components : Array[Int],
  seen_crg : Bool,
  has_ppm : Bool,
  has_ppt : Bool,
  compat_mode : Bool,
) -> Result[Int?, String] {
  let mut next_siz_components = siz_components
  if code == MARKER_SOT && length != 10 {
    return Err("SOT marker segment length must be 10")
  }
  if code == MARKER_SIZ {
    if length < 41 {
      return Err("SIZ marker segment length is too short")
    }
    let csiz_value = read_u16_from_payload(payload, 34)
    guard csiz_value is Ok(csiz) else {
      return Err("failed to parse SIZ component count")
    }
    if csiz <= 0 {
      return Err("SIZ component count must be positive")
    }
    if length != 38 + csiz * 3 {
      return Err("SIZ marker segment length does not match component count")
    }
    let xtsiz_value = read_u32_from_payload(payload, 18)
    let ytsiz_value = read_u32_from_payload(payload, 22)
    guard xtsiz_value is Ok(xtsiz) else { return Err("failed to parse XTsiz") }
    guard ytsiz_value is Ok(ytsiz) else { return Err("failed to parse YTsiz") }
    if xtsiz <= 0 || ytsiz <= 0 {
      return Err("SIZ tile size must be positive")
    }
    for i in 0..<csiz {
      let xrsiz = payload[37 + i * 3]
      let yrsiz = payload[38 + i * 3]
      if xrsiz <= 0 || yrsiz <= 0 {
        return Err("SIZ component sampling must be positive")
      }
    }
    next_siz_components = Some(csiz)
  }
  if code == MARKER_COD && length < 12 {
    return Err("COD marker segment length is too short")
  }
  if code == MARKER_COD {
    let progression_order = payload[1]
    let layers_v = read_u16_from_payload(payload, 2)
    guard layers_v is Ok(layers) else {
      return Err("failed to parse COD layers")
    }
    let multiple_component_transform = payload[4]
    let decomposition_levels = payload[5]
    let cblk_width_minus2 = payload[6]
    let cblk_height_minus2 = payload[7]
    let transformation = payload[9]
    if progression_order < 0 || progression_order > 4 {
      return Err("COD progression order is out of range")
    }
    if layers <= 0 {
      return Err("COD number of layers must be positive")
    }
    if multiple_component_transform != 0 && multiple_component_transform != 1 {
      return Err("COD multiple component transform is invalid")
    }
    if cblk_width_minus2 < 0 ||
      cblk_width_minus2 > 8 ||
      cblk_height_minus2 < 0 ||
      cblk_height_minus2 > 8 ||
      cblk_width_minus2 + cblk_height_minus2 > 8 {
      return Err("COD code-block size exponents are invalid")
    }
    if transformation != 0 && transformation != 1 {
      return Err("COD transformation is invalid")
    }
    let uses_precincts = (payload[0] & 0x01) != 0
    let expected_len = if uses_precincts {
      13 + decomposition_levels
    } else {
      12
    }
    if length != expected_len {
      return Err(
        "COD marker segment length is inconsistent with precinct settings",
      )
    }
  }
  if code == MARKER_QCD && length < 4 {
    return Err("QCD marker segment length is too short")
  }
  if code == MARKER_QCD {
    let sqcd = payload[0]
    let qstyle = sqcd & 0x1F
    if qstyle < 0 || qstyle > 2 {
      return Err("QCD quantization style is invalid")
    }
    let param_bytes = payload.length() - 1
    if param_bytes <= 0 {
      return Err("QCD quantization parameters are missing")
    }
    if (qstyle == 1 || qstyle == 2) && param_bytes % 2 != 0 {
      return Err("QCD quantization parameters have invalid byte count")
    }
  }
  if code == MARKER_SOP && length != 4 {
    return Err("SOP marker segment length must be 4")
  }
  if code == MARKER_COM && length < 4 {
    return Err("COM marker segment length is too short")
  }
  if code == MARKER_TLM && length < 5 {
    return Err("TLM marker segment length is too short")
  }
  if code == MARKER_PLM && length < 5 {
    return Err("PLM marker segment length is too short")
  }
  if code == MARKER_PLT && length < 4 {
    return Err("PLT marker segment length is too short")
  }
  if code == MARKER_PPM && length < 3 {
    return Err("PPM marker segment length is too short")
  }
  if code == MARKER_PPT && length < 3 {
    return Err("PPT marker segment length is too short")
  }
  if code == MARKER_PLM {
    let plm_structure = validate_plm_payload_chunks(payload)
    guard plm_structure is Ok(_) else {
      return Err("invalid PLM chunk bookkeeping")
    }
  }
  if code == MARKER_PLT {
    let plt_check = validate_packet_len_varints(payload, 1)
    guard plt_check is Ok(_) else {
      return Err("invalid PLT packet length sequence")
    }
  }
  if code == MARKER_PPM {
    // Spec A.7.4 permits Ippm continuation across marker segments.
    // Segment-local bookkeeping is therefore not a strict conformance check.
  }
  if code == MARKER_CRG {
    if seen_crg {
      return Err("CRG must appear at most once")
    }
    guard siz_components is Some(csiz) else {
      return Err("CRG requires SIZ component count")
    }
    if length != 2 + csiz * 4 {
      return Err("CRG marker segment length does not match component count")
    }
  }
  if code == MARKER_POC {
    if in_main_header {
      if main_seen_poc {
        return Err("POC must appear at most once per header")
      }
    } else if tile_seen_poc {
      return Err("POC must appear at most once per header")
    }
    guard siz_components is Some(csiz) else {
      return Err("POC requires SIZ component count")
    }
    let unit = if csiz < 257 { 7 } else { 9 }
    if length < 2 + unit || (length - 2) % unit != 0 {
      return Err("POC marker segment length is invalid")
    }
    let entries = parse_poc_entries(payload, csiz, in_main_header)
    guard entries is Ok(poc_entries) else {
      return Err("failed to parse POC entries")
    }
    for entry in poc_entries {
      if entry.ppoc < 0 || entry.ppoc > 4 {
        return Err("POC progression order is out of range")
      }
      if entry.cspoc < 0 || entry.cspoc >= csiz {
        return Err("POC CSpoc is out of range")
      }
      // Spec (Annex A.6.6 / Table A.32):
      // CEpoc allows "... 255, 0" for Csiz<257, and "0 is interpreted as 256".
      let cepoc_upper = if csiz < 257 { 256 } else { 16384 }
      let cepoc = if entry.cepoc == 0 { cepoc_upper } else { entry.cepoc }
      if compat_mode && cepoc > csiz {
        // Compatibility policy for external corpora with broad progression volumes.
        // This is intentionally broader than strict conformance checking.
        continue
      }
      if cepoc <= entry.cspoc || cepoc > cepoc_upper {
        return Err("POC CEpoc is out of range")
      }
    }
  }
  if code == MARKER_PPM && has_ppt {
    return Err("PPM and PPT cannot be mixed")
  }
  if code == MARKER_PPT && has_ppm {
    return Err("PPM and PPT cannot be mixed")
  }
  if code == MARKER_COC || code == MARKER_QCC || code == MARKER_RGN {
    guard siz_components is Some(csiz) else {
      return Err("component-specific marker requires SIZ component count")
    }
    let cbytes = if csiz < 257 { 1 } else { 2 }
    let min_len = if code == MARKER_RGN { 4 + cbytes } else { 4 + cbytes }
    if length < min_len {
      return Err("component-specific marker segment length is too short")
    }
    let comp = if cbytes == 1 {
      payload[0]
    } else {
      let comp_value = read_u16_from_payload(payload, 0)
      guard comp_value is Ok(cno) else {
        return Err("failed to parse component index")
      }
      cno
    }
    if comp < 0 || comp >= csiz {
      return Err("component index out of range")
    }
    if code == MARKER_COC && contains_int(header_coc_components, comp) {
      return Err("COC duplicated for component in same header")
    }
    if code == MARKER_QCC && contains_int(header_qcc_components, comp) {
      return Err("QCC duplicated for component in same header")
    }
    if code == MARKER_RGN && payload[cbytes] != 0 {
      return Err("RGN style is invalid")
    }
  }
  Ok(next_siz_components)
}

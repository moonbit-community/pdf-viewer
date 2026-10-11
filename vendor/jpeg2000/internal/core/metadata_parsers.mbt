///|
fn find_tile_state_index(tile_ids : Array[Int], isot : Int) -> Int? {
  for i, t in tile_ids {
    if t == isot {
      return Some(i)
    }
  }
  None
}

///|
fn compute_tile_count_from_siz(payload : Array[Int]) -> Result[Int, String] {
  let xsiz_v = read_u32_from_payload(payload, 2)
  let ysiz_v = read_u32_from_payload(payload, 6)
  // T.800-2015 A.5.1: Order is XTsiz, YTsiz, XTOsiz, YTOsiz
  let xtsiz_v = read_u32_from_payload(payload, 18)
  let ytsiz_v = read_u32_from_payload(payload, 22)
  let xtosiz_v = read_u32_from_payload(payload, 26)
  let ytosiz_v = read_u32_from_payload(payload, 30)
  guard xsiz_v is Ok(xsiz) else { return Err("failed to parse Xsiz") }
  guard ysiz_v is Ok(ysiz) else { return Err("failed to parse Ysiz") }
  guard xtsiz_v is Ok(xtsiz) else { return Err("failed to parse XTsiz") }
  guard ytsiz_v is Ok(ytsiz) else { return Err("failed to parse YTsiz") }
  guard xtosiz_v is Ok(xtosiz) else { return Err("failed to parse XTOsiz") }
  guard ytosiz_v is Ok(ytosiz) else { return Err("failed to parse YTOsiz") }
  if xsiz <= xtosiz || ysiz <= ytosiz {
    return Err("invalid SIZ image/tile origin relation")
  }
  let nx = @math.ceil_div(xsiz - xtosiz, xtsiz)
  let ny = @math.ceil_div(ysiz - ytosiz, ytsiz)
  let tiles = nx * ny
  if tiles <= 0 {
    return Err("invalid tile count derived from SIZ")
  }
  Ok(tiles)
}

///|
fn parse_siz_metadata(payload : Array[Int]) -> Result[SizMetadata, String] {
  if payload.length() < 36 {
    return Err("SIZ payload too short")
  }
  let rsiz_v = read_u16_from_payload(payload, 0)
  let xsiz_v = read_u32_from_payload(payload, 2)
  let ysiz_v = read_u32_from_payload(payload, 6)
  let xosiz_v = read_u32_from_payload(payload, 10)
  let yosiz_v = read_u32_from_payload(payload, 14)
  // T.800-2015 A.5.1: Order is XTsiz, YTsiz, XTOsiz, YTOsiz
  let xtsiz_v = read_u32_from_payload(payload, 18)
  let ytsiz_v = read_u32_from_payload(payload, 22)
  let xtosiz_v = read_u32_from_payload(payload, 26)
  let ytosiz_v = read_u32_from_payload(payload, 30)
  let csiz_v = read_u16_from_payload(payload, 34)
  let tile_count_v = compute_tile_count_from_siz(payload)
  guard rsiz_v is Ok(rsiz) else { return Err("failed to parse Rsiz") }
  guard xsiz_v is Ok(xsiz) else { return Err("failed to parse Xsiz") }
  guard ysiz_v is Ok(ysiz) else { return Err("failed to parse Ysiz") }
  guard xosiz_v is Ok(xosiz) else { return Err("failed to parse XOsiz") }
  guard yosiz_v is Ok(yosiz) else { return Err("failed to parse YOsiz") }
  guard xtsiz_v is Ok(xtsiz) else { return Err("failed to parse XTsiz") }
  guard ytsiz_v is Ok(ytsiz) else { return Err("failed to parse YTsiz") }
  guard xtosiz_v is Ok(xtosiz) else { return Err("failed to parse XTOsiz") }
  guard ytosiz_v is Ok(ytosiz) else { return Err("failed to parse YTOsiz") }
  guard csiz_v is Ok(csiz) else { return Err("failed to parse Csiz") }
  guard tile_count_v is Ok(tile_count) else {
    return Err("failed to parse tile count")
  }

  if csiz <= 0 {
    return Err("invalid Csiz")
  }
  if payload.length() != 36 + csiz * 3 {
    return Err("invalid SIZ payload length")
  }
  let components : Array[SizComponentMetadata] = []
  for i in 0..<csiz {
    let ssiz = payload[36 + i * 3]
    let xrsiz = payload[37 + i * 3]
    let yrsiz = payload[38 + i * 3]
    components.push({
      precision_bits: (ssiz & 0x7F) + 1,
      is_signed: (ssiz & 0x80) != 0,
      xrsiz,
      yrsiz,
    })
  }
  Ok({
    rsiz,
    xsiz,
    ysiz,
    xosiz,
    yosiz,
    xtsiz,
    ytsiz,
    xtosiz,
    ytosiz,
    csiz,
    tile_count,
    components,
  })
}

///|
fn parse_cod_metadata(payload : Array[Int]) -> Result[CodMetadata, String] {
  if payload.length() < 10 {
    return Err("COD payload too short")
  }
  let layers_v = read_u16_from_payload(payload, 2)
  guard layers_v is Ok(layers) else { return Err("failed to parse layers") }
  let scod = payload[0]
  let uses_precincts = (scod & 0x01) != 0
  let uses_sop = (scod & 0x02) != 0
  let uses_eph = (scod & 0x04) != 0
  let precinct_size_bytes : Array[Int] = []
  if uses_precincts {
    for i in 10..<payload.length() {
      precinct_size_bytes.push(payload[i])
    }
  }
  Ok({
    scod,
    progression_order: payload[1],
    layers,
    multiple_component_transform: payload[4],
    decomposition_levels: payload[5],
    code_block_width_exponent: payload[6] + 2,
    code_block_height_exponent: payload[7] + 2,
    code_block_style: payload[8],
    transformation: payload[9],
    uses_precincts,
    uses_sop,
    uses_eph,
    precinct_size_bytes,
  })
}

///|
fn parse_qcd_metadata(payload : Array[Int]) -> Result[QcdMetadata, String] {
  if payload.length() < 2 {
    return Err("QCD payload too short")
  }
  let parameters : Array[Int] = []
  for i in 1..<payload.length() {
    parameters.push(payload[i])
  }
  let sqcd = payload[0]
  Ok({
    sqcd,
    guard_bits: (sqcd >> 5) & 0x07,
    quantization_style: sqcd & 0x1F,
    parameters,
  })
}

///|
/// T.800-2015 A.6.5: Create QcdMetadata from QCC marker parameters.
/// Used when QCC overrides QCD for a specific component.
pub fn make_qcd_from_qcc(qcc : QccMetadata) -> QcdMetadata {
  {
    sqcd: qcc.sqcc,
    guard_bits: (qcc.sqcc >> 5) & 0x07,
    quantization_style: qcc.sqcc & 0x1F,
    parameters: qcc.parameters,
  }
}

///|
fn parse_component_index(
  payload : Array[Int],
  csiz : Int,
) -> Result[(Int, Int), String] {
  let cbytes = if csiz < 257 { 1 } else { 2 }
  if payload.length() < cbytes {
    return Err("component index payload too short")
  }
  if cbytes == 1 {
    Ok((payload[0], 1))
  } else {
    let comp_v = read_u16_from_payload(payload, 0)
    guard comp_v is Ok(comp) else {
      return Err("failed to parse component index")
    }
    Ok((comp, 2))
  }
}

///|
fn parse_coc_metadata(
  payload : Array[Int],
  csiz : Int,
  in_main_header : Bool,
  tile_index? : Int = -1,
) -> Result[CocMetadata, String] {
  let comp_v = parse_component_index(payload, csiz)
  guard comp_v is Ok((component, at)) else {
    return Err("failed to parse COC component")
  }
  if payload.length() < at + 1 {
    return Err("COC payload too short")
  }
  let parameters : Array[Int] = []
  for i in (at + 1)..<payload.length() {
    parameters.push(payload[i])
  }
  Ok({ component, scoc: payload[at], parameters, in_main_header, tile_index, })
}

///|
fn parse_rgn_metadata(
  payload : Array[Int],
  csiz : Int,
  in_main_header : Bool,
) -> Result[RgnMetadata, String] {
  let comp_v = parse_component_index(payload, csiz)
  guard comp_v is Ok((component, at)) else {
    return Err("failed to parse RGN component")
  }
  if payload.length() < at + 2 {
    return Err("RGN payload too short")
  }
  Ok({ component, style: payload[at], shift: payload[at + 1], in_main_header, })
}

///|
fn parse_qcc_metadata(
  payload : Array[Int],
  csiz : Int,
  in_main_header : Bool,
  tile_index? : Int = -1,
) -> Result[QccMetadata, String] {
  let comp_v = parse_component_index(payload, csiz)
  guard comp_v is Ok((component, at)) else {
    return Err("failed to parse QCC component")
  }
  if payload.length() < at + 1 {
    return Err("QCC payload too short")
  }
  let parameters : Array[Int] = []
  for i in (at + 1)..<payload.length() {
    parameters.push(payload[i])
  }
  Ok({ component, sqcc: payload[at], parameters, in_main_header, tile_index, })
}

///|
fn parse_poc_entries(
  payload : Array[Int],
  csiz : Int,
  in_main_header : Bool,
) -> Result[Array[PocMetadata], String] {
  let entries : Array[PocMetadata] = []
  let cbytes = if csiz < 257 { 1 } else { 2 }
  let unit = if csiz < 257 { 7 } else { 9 }
  let mut at = 0
  while at + unit <= payload.length() {
    let rspoc = payload[at]
    let cspoc = if cbytes == 1 {
      payload[at + 1]
    } else {
      let v = read_u16_from_payload(payload, at + 1)
      guard v is Ok(c) else { return Err("failed to parse CSpoc") }
      c
    }
    let lyepoc_at = at + 1 + cbytes
    let lyepoc_v = read_u16_from_payload(payload, lyepoc_at)
    guard lyepoc_v is Ok(lyepoc) else { return Err("failed to parse LYEpoc") }
    let repoc = payload[lyepoc_at + 2]
    let cepoc = if cbytes == 1 {
      payload[lyepoc_at + 3]
    } else {
      let v = read_u16_from_payload(payload, lyepoc_at + 3)
      guard v is Ok(c) else { return Err("failed to parse CEpoc") }
      c
    }
    let ppoc = payload[lyepoc_at + 3 + cbytes]
    entries.push({ rspoc, cspoc, lyepoc, repoc, cepoc, ppoc, in_main_header, })
    at += unit
  }
  if at != payload.length() {
    return Err("POC payload trailing bytes")
  }
  Ok(entries)
}

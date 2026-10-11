///|
// Spec grouping:
// - Annex I (JP2 contiguous codestream extraction)
// - DS-INPUT-RAW-JP2 input acceptance

///|
// Spec basis (T.800-2015 Annex I / Annex A):
// - JP2 wrapping and codestream marker framing (SOC/SOD/EOC) define
//   decode input extraction and payload traversal.
fn is_soc_at(data : Bytes, offset : Int) -> Bool {
  if offset + 1 >= data.length() {
    return false
  }
  @bytes.read_u16_be(data, offset) == 0xFF4F
}

///|
// Spec basis (T.800-2015 Annex I / Annex A):
// - JP2 wrapping and codestream marker framing (SOC/SOD/EOC) define
//   decode input extraction and payload traversal.
fn extract_codestream_from_jp2(data : Bytes) -> Result[Bytes, String] {
  let mut offset = 0
  while offset + 8 <= data.length() {
    let lbox = @bytes.read_u32_be(data, offset)
    let t0 = data[offset + 4].to_int()
    let t1 = data[offset + 5].to_int()
    let t2 = data[offset + 6].to_int()
    let t3 = data[offset + 7].to_int()

    let mut header_size = 8
    let box_size = if lbox == 0 {
      data.length() - offset
    } else if lbox == 1 {
      if offset + 16 > data.length() {
        return Err("invalid JP2 box: truncated XLBox")
      }
      let hi = @bytes.read_u32_be(data, offset + 8)
      let lo = @bytes.read_u32_be(data, offset + 12)
      if hi != 0 {
        return Err("invalid JP2 box: XLBox too large")
      }
      header_size = 16
      lo
    } else {
      lbox
    }

    if box_size < header_size || offset + box_size > data.length() {
      return Err("invalid JP2 box size")
    }

    if t0 == b'j'.to_int() &&
      t1 == b'p'.to_int() &&
      t2 == b'2'.to_int() &&
      t3 == b'c'.to_int() {
      let payload_start = offset + header_size
      let payload_end = offset + box_size
      if payload_start >= payload_end {
        return Err("invalid JP2 jp2c box: empty payload")
      }
      if !is_soc_at(data, payload_start) {
        return Err("invalid JP2 jp2c box: SOC not found at payload start")
      }
      return Ok(data[payload_start:payload_end].to_bytes())
    }

    offset += box_size
  }
  Err("JP2 jp2c box not found")
}

///|
// Spec basis (T.800-2015 Annex I / Annex A):
// - JP2 wrapping and codestream marker framing (SOC/SOD/EOC) define
//   decode input extraction and payload traversal.
pub fn extract_decode_input_codestream(data : Bytes) -> Result[Bytes, String] {
  if is_soc_at(data, 0) {
    return Ok(data)
  }
  extract_codestream_from_jp2(data)
}

///|
pub fn parse_decode_input_codestream(
  data : Bytes,
) -> Result[@core.Codestream, String] {
  let extracted_v = extract_decode_input_codestream(data)
  guard extracted_v is Ok(extracted) else {
    if extracted_v is Err(msg) {
      return Err(msg)
    }
    return Err("failed to extract decode input codestream")
  }
  @core.parse_codestream_bytes(extracted)
}

///|
pub fn parse_decode_input_codestream_strict(
  data : Bytes,
) -> Result[@core.Codestream, String] {
  let extracted_v = extract_decode_input_codestream(data)
  guard extracted_v is Ok(extracted) else {
    if extracted_v is Err(msg) {
      return Err(msg)
    }
    return Err("failed to extract decode input codestream")
  }
  @core.parse_codestream_strict(extracted)
}

///|
pub fn roundtrip_decode_input_bytes(data : Bytes) -> Result[Bytes, String] {
  let extracted_v = extract_decode_input_codestream(data)
  guard extracted_v is Ok(extracted) else {
    if extracted_v is Err(msg) {
      return Err(msg)
    }
    return Err("failed to extract decode input codestream")
  }
  let roundtripped_v = @core.roundtrip_bytes(extracted)
  guard roundtripped_v is Ok(roundtripped) else {
    if roundtripped_v is Err(msg) {
      return Err(msg)
    }
    return Err("failed to roundtrip decode input codestream")
  }
  // TODO: @core.roundtrip_bytes still returns Array[Int]; update when that API migrates to Bytes.
  let extracted_arr = @bytes.bytes_to_int_array(extracted)
  if extracted == data {
    return Ok(@bytes.int_array_to_bytes(roundtripped))
  }
  if roundtripped != extracted_arr {
    return Err("wrapped codestream roundtrip mismatch")
  }
  Ok(data)
}

///|
// Spec basis (T.800-2015 Annex I / Annex A):
// - JP2 wrapping and codestream marker framing (SOC/SOD/EOC) define
//   decode input extraction and payload traversal.
pub fn component_sample_count_from_siz(
  siz : @core.SizMetadata,
  component_index : Int,
) -> Result[Int, String] {
  let dims_v = component_dimensions_from_siz(siz, component_index)
  guard dims_v is Ok((width, height)) else {
    return Err("failed to determine component dimensions")
  }
  Ok(width * height)
}

///|
// Spec basis (T.800-2015 Annex I / Annex A):
// - JP2 wrapping and codestream marker framing (SOC/SOD/EOC) define
//   decode input extraction and payload traversal.
pub fn component_dimensions_from_siz(
  siz : @core.SizMetadata,
  component_index : Int,
) -> Result[(Int, Int), String] {
  if component_index < 0 || component_index >= siz.components.length() {
    return Err("component index out of range")
  }
  let comp = siz.components[component_index]
  // T.800-2015 B.2: component extent is
  // ceil(Xsiz / XRsiz) - ceil(XOsiz / XRsiz), not ceil((Xsiz - XOsiz) / XRsiz).
  // These differ for non-zero origins with subsampling.
  let width_hi_v = @math.ceil_div_checked(siz.xsiz, comp.xrsiz)
  guard width_hi_v is Ok(width_hi) else {
    return Err("failed to compute width upper bound")
  }
  let width_lo_v = @math.ceil_div_checked(siz.xosiz, comp.xrsiz)
  guard width_lo_v is Ok(width_lo) else {
    return Err("failed to compute width lower bound")
  }
  let height_hi_v = @math.ceil_div_checked(siz.ysiz, comp.yrsiz)
  guard height_hi_v is Ok(height_hi) else {
    return Err("failed to compute height upper bound")
  }
  let height_lo_v = @math.ceil_div_checked(siz.yosiz, comp.yrsiz)
  guard height_lo_v is Ok(height_lo) else {
    return Err("failed to compute height lower bound")
  }
  let width = width_hi - width_lo
  let height = height_hi - height_lo
  if width < 0 || height < 0 {
    return Err("failed to compute component dimensions")
  }
  Ok((width, height))
}

///|
// Spec basis (T.800-2015 B.3, Eq. B.3-1 to B.3-4):
// Compute tile dimensions and position for component 0 given tile index.
// Returns (tile_x0, tile_y0, tile_width, tile_height) in component-0 coordinates.
pub fn tile_component0_dims_from_siz(
  siz : @core.SizMetadata,
  tile_col : Int,
  tile_row : Int,
) -> (Int, Int, Int, Int) {
  let (_, _, w, h, _, _) = tile_component0_dims_and_origin_from_siz(
    siz, tile_col, tile_row,
  )
  let xr = if siz.components.length() > 0 { siz.components[0].xrsiz } else { 1 }
  let yr = if siz.components.length() > 0 { siz.components[0].yrsiz } else { 1 }
  let tx0 = if siz.xtosiz + tile_col * siz.xtsiz > siz.xosiz {
    siz.xtosiz + tile_col * siz.xtsiz
  } else {
    siz.xosiz
  }
  let ty0 = if siz.ytosiz + tile_row * siz.ytsiz > siz.yosiz {
    siz.ytosiz + tile_row * siz.ytsiz
  } else {
    siz.yosiz
  }
  let cx0 = (tx0 + xr - 1) / xr
  let cy0 = (ty0 + yr - 1) / yr
  let img_x0 = (siz.xosiz + xr - 1) / xr
  let img_y0 = (siz.yosiz + yr - 1) / yr
  (cx0 - img_x0, cy0 - img_y0, w, h)
}

///|
// Spec basis (T.800-2015 B.3, Eq. B.3-1 to B.3-4):
// Returns (tile_x0_rel, tile_y0_rel, width, height, tcx0_abs, tcy0_abs).
// tcx0_abs/tcy0_abs are absolute tile-component coordinates needed for
// correct DWT subband dimension computation (T.800-2015 B.5).
pub fn tile_component0_dims_and_origin_from_siz(
  siz : @core.SizMetadata,
  tile_col : Int,
  tile_row : Int,
) -> (Int, Int, Int, Int, Int, Int) {
  let tx0 = if siz.xtosiz + tile_col * siz.xtsiz > siz.xosiz {
    siz.xtosiz + tile_col * siz.xtsiz
  } else {
    siz.xosiz
  }
  let ty0 = if siz.ytosiz + tile_row * siz.ytsiz > siz.yosiz {
    siz.ytosiz + tile_row * siz.ytsiz
  } else {
    siz.yosiz
  }
  let tx1_raw = siz.xtosiz + (tile_col + 1) * siz.xtsiz
  let tx1 = if tx1_raw < siz.xsiz { tx1_raw } else { siz.xsiz }
  let ty1_raw = siz.ytosiz + (tile_row + 1) * siz.ytsiz
  let ty1 = if ty1_raw < siz.ysiz { ty1_raw } else { siz.ysiz }
  // Convert to component-0 coordinates (XRsiz[0], YRsiz[0])
  let xr = if siz.components.length() > 0 { siz.components[0].xrsiz } else { 1 }
  let yr = if siz.components.length() > 0 { siz.components[0].yrsiz } else { 1 }
  let cx0 = (tx0 + xr - 1) / xr
  let cy0 = (ty0 + yr - 1) / yr
  let cx1 = (tx1 + xr - 1) / xr
  let cy1 = (ty1 + yr - 1) / yr
  let img_x0 = (siz.xosiz + xr - 1) / xr
  let img_y0 = (siz.yosiz + yr - 1) / yr
  (cx0 - img_x0, cy0 - img_y0, cx1 - cx0, cy1 - cy0, cx0, cy0)
}

///|
// Spec basis (T.800-2015 Annex I / Annex A):
// - JP2 wrapping and codestream marker framing (SOC/SOD/EOC) define
//   decode input extraction and payload traversal.
pub fn codestream_payload_is_empty(stream : @core.Codestream) -> Bool {
  for segment in stream.segments {
    if segment.code == 0xFF93 && segment.payload.length() > 0 {
      return false
    }
  }
  true
}

///|
// Spec basis (T.800-2015 Annex I / Annex A):
// - JP2 wrapping and codestream marker framing (SOC/SOD/EOC) define
//   decode input extraction and payload traversal.
pub fn make_zero_sample_bytes(
  sample_count : Int,
  bits_per_sample : Int,
) -> Result[Bytes, String] {
  if sample_count < 0 {
    return Err("sample_count must be >= 0")
  }
  if bits_per_sample <= 0 || bits_per_sample > 32 {
    return Err("bits_per_sample must be in 1..32")
  }
  let bytes_per_sample = (bits_per_sample + 7) / 8
  let total_bytes = sample_count * bytes_per_sample
  let out : Array[Byte] = []
  for _ in 0..<total_bytes {
    out.push(0)
  }
  Ok(Bytes::from_iter(out.iter()))
}

///|
// Spec basis (T.800-2015 Annex I / Annex A):
// - JP2 wrapping and codestream marker framing (SOC/SOD/EOC) define
//   decode input extraction and payload traversal.
pub fn make_single_sample_bytes_le(
  value : Int,
  bits_per_sample : Int,
) -> Result[Bytes, String] {
  if bits_per_sample <= 0 || bits_per_sample > 32 {
    return Err("bits_per_sample must be in 1..32")
  }
  let byte_count = (bits_per_sample + 7) / 8
  let mut v = value
  let out : Array[Byte] = []
  for _ in 0..<byte_count {
    out.push((v & 0xFF).to_byte())
    v = v >> 8
  }
  Ok(Bytes::from_iter(out.iter()))
}

///|
// Spec basis (T.800-2015 Annex I / Annex A):
// - JP2 wrapping and codestream marker framing (SOC/SOD/EOC) define
//   decode input extraction and payload traversal.
pub fn make_sample_array_bytes_le(
  values : Array[Int],
  bits_per_sample : Int,
) -> Result[Bytes, String] {
  if bits_per_sample <= 0 || bits_per_sample > 32 {
    return Err("bits_per_sample must be in 1..32")
  }
  if values.length() <= 0 {
    return Err("values are empty")
  }
  let byte_count = (bits_per_sample + 7) / 8
  let out : Array[Byte] = []
  for value in values {
    let mut v = value
    for _ in 0..<byte_count {
      out.push((v & 0xFF).to_byte())
      v = v >> 8
    }
  }
  Ok(Bytes::from_iter(out.iter()))
}

///|
// Spec basis (T.800-2015 Annex I / Annex A):
// - JP2 wrapping and codestream marker framing (SOC/SOD/EOC) define
//   decode input extraction and payload traversal.
pub fn collect_sod_payloads(stream : @core.Codestream) -> Array[Bytes] {
  let payloads : Array[Bytes] = []
  for segment in stream.segments {
    if segment.code == 0xFF93 {
      payloads.push(segment.payload)
    }
  }
  payloads
}

///|
// Spec basis (T.800-2015 A.4.2):
// Collect SOD payloads grouped by tile index (Isot), concatenating all
// tile-parts for the same tile. SOT marker (0xFF90) precedes each SOD
// (0xFF93) and provides the Isot tile index in its first 2 payload bytes.
// Returns: Array of (tile_index, concatenated_payload) ordered by first
// appearance of each tile, or None if no SOT markers found.
pub fn collect_sod_payloads_by_tile(
  stream : @core.Codestream,
) -> Array[(Int, Bytes)]? {
  // Walk segments: each SOT is followed by its SOD
  let sot_isots : Array[Int] = []
  let sod_payloads : Array[Bytes] = []
  let mut last_isot = -1
  for segment in stream.segments {
    if segment.code == 0xFF90 {
      // SOT payload: Lsot(2) Isot(2) Psot(4) TPsot(1) TNsot(1)
      // After marker-code parsing, payload starts at Isot
      if segment.payload.length() >= 2 {
        last_isot = (segment.payload[0].to_int() << 8) |
          segment.payload[1].to_int()
      }
    } else if segment.code == 0xFF93 {
      // SOD: associate with the preceding SOT's Isot
      if last_isot >= 0 {
        sot_isots.push(last_isot)
        sod_payloads.push(segment.payload)
      }
    }
  }
  if sot_isots.length() == 0 {
    return None
  }
  // Group by tile index, preserving order of first appearance
  let tile_order : Array[Int] = []
  let tile_data : Map[Int, Array[Byte]] = {}
  for i in 0..<sot_isots.length() {
    let isot = sot_isots[i]
    if not(tile_data.contains(isot)) {
      tile_order.push(isot)
      tile_data[isot] = []
    }
    // Concatenate this tile-part's payload
    if tile_data.get(isot) is Some(arr) {
      for b in sod_payloads[i] {
        arr.push(b)
      }
    }
  }
  let result : Array[(Int, Bytes)] = []
  for isot in tile_order {
    if tile_data.get(isot) is Some(arr) {
      result.push((isot, Bytes::from_iter(arr.iter())))
    }
  }
  Some(result)
}

///|
// Spec basis (T.800-2015 A.7.5):
// Collect PPT packet-header bytes grouped by tile index (Isot), concatenating
// all tile-parts for the same tile. PPT payload is [Zppt(1), Ippt(...)].
// Returns: Array of (tile_index, concatenated_ippt) ordered by tile index,
// or None when no PPT markers are present.
pub fn collect_ppt_payloads_by_tile(
  stream : @core.Codestream,
) -> Array[(Int, Bytes)]? {
  let tile_order : Array[Int] = []
  let tile_data : Map[Int, Array[Byte]] = {}
  let mut current_isot = -1
  let mut current_tile_part_ppt : Map[Int, Array[Byte]] = {}
  let mut saw_ppt = false
  for segment in stream.segments {
    if segment.code == 0xFF90 {
      // New tile-part starts; reset tile-part-local PPT chunks.
      current_tile_part_ppt = {}
      // SOT payload starts with Isot (2 bytes).
      if segment.payload.length() >= 2 {
        current_isot = (segment.payload[0].to_int() << 8) |
          segment.payload[1].to_int()
      } else {
        current_isot = -1
      }
    } else if segment.code == 0xFF61 {
      if current_isot < 0 || segment.payload.length() <= 1 {
        continue
      }
      saw_ppt = true
      let zppt = segment.payload[0].to_int()
      if not(current_tile_part_ppt.contains(zppt)) {
        current_tile_part_ppt[zppt] = []
      }
      if current_tile_part_ppt.get(zppt) is Some(chunk) {
        // Skip Zppt and append Ippt bytes for this Zppt chunk.
        for i in 1..<segment.payload.length() {
          chunk.push(segment.payload[i])
        }
      }
    } else if segment.code == 0xFF93 {
      // Tile-part header ends at SOD: flush PPT chunks in Zppt order.
      if current_isot >= 0 && current_tile_part_ppt.length() > 0 {
        if not(tile_data.contains(current_isot)) {
          tile_order.push(current_isot)
          tile_data[current_isot] = []
        }
        if tile_data.get(current_isot) is Some(arr) {
          for z in 0..<=255 {
            if current_tile_part_ppt.get(z) is Some(chunk) {
              for b in chunk {
                arr.push(b)
              }
            }
          }
        }
      }
      current_tile_part_ppt = {}
    }
  }
  if !saw_ppt {
    return None
  }
  let result : Array[(Int, Bytes)] = []
  let mut max_isot = 0
  for isot in tile_order {
    if isot > max_isot {
      max_isot = isot
    }
  }
  for idx in 0..<=max_isot {
    if tile_data.get(idx) is Some(arr) {
      result.push((idx, Bytes::from_iter(arr.iter())))
    }
  }
  Some(result)
}

///|
fn ppm_length_prefix_to_int(b0 : Byte, b1 : Byte, b2 : Byte, b3 : Byte) -> Int {
  (b0.to_int() << 24) | (b1.to_int() << 16) | (b2.to_int() << 8) | b3.to_int()
}

///|
// Spec basis (T.800-2015 A.7.4):
// Reconstruct complete Ippm chunks directly from raw PPM marker segments.
// Zppm orders main-header PPM marker segments. Concatenate payload bytes after
// Zppm in ascending Zppm order, then parse the resulting byte stream as
// [Nppm(4), Ippm(...)]* so split marker fragments rejoin correctly.
fn collect_ppm_chunks_in_order(stream : @core.Codestream) -> Array[Bytes]? {
  if stream.metadata.ppm.length() <= 0 {
    return None
  }
  let bytes_by_zppm : Map[Int, Array[Byte]] = {}
  let mut saw_ppm = false
  for segment in stream.segments {
    if segment.code == 0xFF90 {
      break
    }
    if segment.code != 0xFF60 || segment.payload.length() <= 0 {
      continue
    }
    saw_ppm = true
    let zppm = segment.payload[0].to_int()
    if !bytes_by_zppm.contains(zppm) {
      bytes_by_zppm[zppm] = []
    }
    if bytes_by_zppm.get(zppm) is Some(acc) {
      for i in 1..<segment.payload.length() {
        acc.push(segment.payload[i])
      }
    }
  }
  if !saw_ppm {
    return None
  }
  let ppm_stream : Array[Byte] = []
  for zppm in 0..<=255 {
    if bytes_by_zppm.get(zppm) is Some(bytes) {
      for b in bytes {
        ppm_stream.push(b)
      }
    }
  }
  let out : Array[Bytes] = []
  let mut i = 0
  while i + 3 < ppm_stream.length() {
    let nppm = ppm_length_prefix_to_int(
      ppm_stream[i],
      ppm_stream[i + 1],
      ppm_stream[i + 2],
      ppm_stream[i + 3],
    )
    if nppm < 0 {
      break
    }
    i += 4
    let chunk_end = i + nppm
    if chunk_end < i || chunk_end > ppm_stream.length() {
      break
    }
    let chunk : Array[Byte] = []
    for j in i..<chunk_end {
      chunk.push(ppm_stream[j])
    }
    out.push(Bytes::from_iter(chunk.iter()))
    i = chunk_end
  }
  if out.length() <= 0 {
    return None
  }
  Some(out)
}

///|
// Spec basis (T.800-2015 A.7.4):
// Collect PPM packet-header bytes (Ippm) from main header markers.
// PPM payload is [Zppm(1), Nppm(4), Ippm(...)] and may be split across markers.
// Returns concatenated Ippm bytes ordered by Zppm, or None when no PPM exists.
pub fn collect_ppm_payload_bytes(stream : @core.Codestream) -> Bytes? {
  let chunks_v = collect_ppm_chunks_in_order(stream)
  guard chunks_v is Some(chunks) else { return None }
  let out : Array[Byte] = []
  for chunk in chunks {
    for b in chunk {
      out.push(b)
    }
  }
  if out.length() <= 0 {
    return None
  }
  Some(Bytes::from_iter(out.iter()))
}

///|
// Spec basis (T.800-2015 A.7.4 / A.4.2):
// Map PPM relocated packet-header chunks (Ippm) to tile indices using SOT order.
// Returns concatenated per-tile header bytes, or None when PPM/chunk mapping
// cannot be constructed.
pub fn collect_ppm_payloads_by_tile(
  stream : @core.Codestream,
) -> Array[(Int, Bytes)]? {
  let ppm_chunks_v = collect_ppm_chunks_in_order(stream)
  guard ppm_chunks_v is Some(ppm_chunks_in_order) else { return None }
  let by_tile : Map[Int, Array[Byte]] = {}
  let tile_order : Array[Int] = []
  let mut chunk_idx = 0
  for segment in stream.segments {
    if segment.code != 0xFF90 {
      continue
    }
    if chunk_idx >= ppm_chunks_in_order.length() {
      break
    }
    if segment.payload.length() < 2 {
      continue
    }
    let tile_idx = (segment.payload[0].to_int() << 8) |
      segment.payload[1].to_int()
    if !by_tile.contains(tile_idx) {
      by_tile[tile_idx] = []
      tile_order.push(tile_idx)
    }
    if by_tile.get(tile_idx) is Some(acc) {
      for b in ppm_chunks_in_order[chunk_idx] {
        acc.push(b)
      }
    }
    chunk_idx += 1
  }
  if by_tile.length() <= 0 {
    return None
  }
  let mut max_tile = 0
  for tile_idx in tile_order {
    if tile_idx > max_tile {
      max_tile = tile_idx
    }
  }
  let out : Array[(Int, Bytes)] = []
  for tile_idx in 0..<=max_tile {
    if by_tile.get(tile_idx) is Some(bytes) {
      out.push((tile_idx, Bytes::from_iter(bytes.iter())))
    }
  }
  if out.length() <= 0 {
    return None
  }
  Some(out)
}

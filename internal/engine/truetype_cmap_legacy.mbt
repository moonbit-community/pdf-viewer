///|
/// Normalize legacy mixed-byte cmap 2 to the library's cmap 12 input. The
/// shared library still owns Unicode cmap decoding; this adapter checks the
/// legacy relative offsets and retains the original platform semantics.
fn pdf_viewer_ttf_cmap2_normalize(data : BytesView) -> Bytes? {
  guard data.length() >= 526 && data.length() % 2 == 0 else { return None }
  let mut last_key = 0
  for code in 0..<256 {
    let key = pdf_viewer_ttf_u16(data, 6 + code * 2).unwrap()
    guard key % 8 == 0 else { return None }
    if key > last_key {
      last_key = key
    }
  }
  guard last_key <= data.length() - 526 else { return None }
  let glyph_start = 526 + last_key
  // Validate every subheader, including ones not referenced by a high byte.
  for index in 0..<=(last_key / 8) {
    let offset = 518 + index * 8
    let first = pdf_viewer_ttf_u16(data, offset).unwrap()
    let count = pdf_viewer_ttf_u16(data, offset + 2).unwrap()
    let range = pdf_viewer_ttf_u16(data, offset + 6).unwrap()
    let start = offset + 6 + range
    guard first <= 255 && count <= 256 - first else { return None }
    if count > 0 &&
      (
        range % 2 != 0 ||
        start < glyph_start ||
        start > data.length() ||
        count > (data.length() - start) / 2
      ) {
      return None
    }
  }
  let groups : Array[(Int, Int)] = []
  for code in 0..<65536 {
    let high = code >> 8
    let low = code & 255
    // A byte with a nonzero key is a lead byte, never a standalone code.
    if high == 0 && pdf_viewer_ttf_u16(data, 6 + low * 2) != Some(0) {
      continue
    }
    let key = pdf_viewer_ttf_u16(data, 6 + high * 2).unwrap()
    if high > 0 && key == 0 {
      continue
    }
    let offset = 518 + key
    let first = pdf_viewer_ttf_u16(data, offset).unwrap()
    let count = pdf_viewer_ttf_u16(data, offset + 2).unwrap()
    if low < first || low >= first + count {
      continue
    }
    let start = offset + 6 + pdf_viewer_ttf_u16(data, offset + 6).unwrap()
    let raw = pdf_viewer_ttf_u16(data, start + (low - first) * 2).unwrap()
    if raw != 0 {
      let gid = (raw + pdf_viewer_ttf_i16(data, offset + 4).unwrap()) & 65535
      if gid != 0 {
        groups.push((code, gid))
      }
    }
  }
  let normalized = Array::make(16 + groups.length() * 12, b'\x00')
  @font.write_be16(normalized, 0, 12)
  @font.write_be32(normalized, 4, normalized.length())
  @font.write_be32(normalized, 12, groups.length())
  for index, (code, gid) in groups {
    @font.write_be32(normalized, 16 + index * 12, code)
    @font.write_be32(normalized, 20 + index * 12, code)
    @font.write_be32(normalized, 24 + index * 12, gid)
  }
  Some(Bytes::from_array(normalized))
}

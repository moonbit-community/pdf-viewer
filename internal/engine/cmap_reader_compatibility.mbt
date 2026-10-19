///|
/// The recovery lexer pads odd hex strings. Reuse only ordinary even-length,
/// contiguous hex tokens, whose source codes agree with the strict reader.
fn pdf_cmap_reader_hex_compatible(
  bytes : BytesView,
  max_bytes? : Int = 65536,
) -> Bool {
  guard bytes.length() <= max_bytes else { return false }
  let mut index = 0
  while index < bytes.length() {
    if bytes[index] == b'%' {
      while index < bytes.length() &&
            bytes[index] != b'\r' &&
            bytes[index] != b'\n' {
        index += 1
      }
      continue
    }
    if bytes[index] == b'(' {
      let mut depth = 1
      index += 1
      while index < bytes.length() && depth > 0 {
        match bytes[index] {
          b'\\' => index += 1
          b'(' => depth += 1
          b')' => depth -= 1
          _ => ()
        }
        index += 1
      }
      guard depth == 0 else { return false }
      continue
    }
    if bytes[index] == b'<' {
      if index + 1 < bytes.length() && bytes[index + 1] == b'<' {
        index += 2
        continue
      }
      index += 1
      let start = index
      while index < bytes.length() && bytes[index] != b'>' {
        guard pdf_viewer_cmap_hex_digit(bytes[index]) is Some(_) else {
          return false
        }
        index += 1
      }
      guard index < bytes.length() && index > start && (index - start) % 2 == 0 else {
        return false
      }
    }
    index += 1
  }
  true
}

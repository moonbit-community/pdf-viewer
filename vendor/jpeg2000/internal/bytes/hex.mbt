///|
// Hex encoding/decoding utilities for byte arrays

///|
fn nibble_to_char(n : Int) -> Char {
  if n < 10 {
    ('0'.to_int() + n).unsafe_to_char()
  } else {
    ('a'.to_int() + (n - 10)).unsafe_to_char()
  }
}

///|
fn char_to_nibble(c : Char) -> Int? {
  if c is ('0'..='9') {
    Some(c.to_int() - '0'.to_int())
  } else if c is ('a'..='f') {
    Some(c.to_int() - 'a'.to_int() + 10)
  } else if c is ('A'..='F') {
    Some(c.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
/// Convert byte array to lowercase hex string.
pub fn bytes_to_hex(data : Array[Int]) -> String {
  let sb = StringBuilder::new()
  for b in data {
    let hi = (b >> 4) & 0x0F
    let lo = b & 0x0F
    sb.write_char(nibble_to_char(hi))
    sb.write_char(nibble_to_char(lo))
  }
  sb.to_string()
}

///|
/// Parse hex string to byte array.
/// Ignores whitespace (spaces, newlines, tabs).
/// Returns Err for invalid hex characters or odd-length strings.
pub fn hex_to_bytes(hex : String) -> Result[Array[Int], String] {
  let out : Array[Int] = []
  let mut high : Int? = None
  for c in hex {
    if c == ' ' || c == '\n' || c == '\r' || c == '\t' {
      continue
    }
    let nibble = char_to_nibble(c)
    guard nibble is Some(n) else { return Err("invalid hex character") }
    if high is Some(h) {
      out.push((h << 4) + n)
      high = None
    } else {
      high = Some(n)
    }
  }
  if high is Some(_) {
    return Err("hex string has odd length")
  }
  Ok(out)
}

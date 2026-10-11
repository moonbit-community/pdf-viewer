///|
pub fn encode_codestream(stream : Codestream) -> Result[Array[Int], String] {
  let out : Array[Int] = []
  for segment in stream.segments {
    if segment.code >> 8 != 0xFF {
      return Err("invalid marker value")
    }
    out.push((segment.code >> 8) & 0xFF)
    out.push(segment.code & 0xFF)

    if segment.code == MARKER_SOD {
      for i in 0..<segment.payload.length() {
        out.push(segment.payload[i].to_int())
      }
    } else if has_explicit_length(segment.code) {
      let length = segment.payload.length() + 2
      if length > 0xFFFF {
        return Err("segment payload too long")
      }
      out.push((length >> 8) & 0xFF)
      out.push(length & 0xFF)
      for i in 0..<segment.payload.length() {
        out.push(segment.payload[i].to_int())
      }
    }
  }
  for i in 0..<stream.trailing_bytes.length() {
    out.push(stream.trailing_bytes[i].to_int())
  }
  Ok(out)
}

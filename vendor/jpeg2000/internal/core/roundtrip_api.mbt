///|
pub fn roundtrip_bytes(data : Bytes) -> Result[Array[Int], String] {
  let parsed = parse_codestream(data)
  if parsed is Ok(stream) {
    return encode_codestream(stream)
  }
  if parsed is Err(msg) {
    return Err("parse failed in roundtrip: \{msg}")
  }
  Err("parse failed in roundtrip")
}

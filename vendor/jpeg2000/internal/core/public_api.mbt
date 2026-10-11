///|
pub fn bytes_to_hex(data : Array[Int]) -> String {
  @bytes.bytes_to_hex(data)
}

///|
pub fn hex_to_bytes(hex : String) -> Result[Array[Int], String] {
  @bytes.hex_to_bytes(hex)
}

///|
// Bytes-based entrypoint - parse_codestream now takes Bytes directly.
pub fn parse_codestream_bytes(data : Bytes) -> Result[Codestream, String] {
  parse_codestream(data)
}

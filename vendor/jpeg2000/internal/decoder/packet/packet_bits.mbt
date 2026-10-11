///|
// Spec grouping:
// - B.10 Packet header bit-level utilities
// - Bit reading with 0xFF stuff bit handling per B.10.1

///|
// Spec basis (T.800-2015 B.10):
// Bit-level reading helper for packet header parsing.
// Reads a single bit from a byte array at the given bit position.
pub fn pkt_read_bit(data : Bytes, logical_bit_pos : Int) -> Result[Int, String] {
  // T.800-2015 B.10.1: If any byte in the packet header has the value 0xFF,
  // the next byte begins with a stuff bit of zero that must be skipped.
  // Map logical bit position to physical (byte_index, bit_shift).
  let mut byte_idx = 0
  let mut logical_pos = 0
  while byte_idx < data.length() {
    let is_stuffed = byte_idx > 0 && data[byte_idx - 1].to_int() == 0xFF
    let bits_in_byte = if is_stuffed { 7 } else { 8 }
    if logical_pos + bits_in_byte > logical_bit_pos {
      let offset = logical_bit_pos - logical_pos
      let bit_shift = if is_stuffed { 6 - offset } else { 7 - offset }
      return Ok((data[byte_idx].to_int() >> bit_shift) & 1)
    }
    logical_pos += bits_in_byte
    byte_idx += 1
  }
  Err("packet header bitstream truncated")
}

///|
// Spec basis (T.800-2015 B.10):
// Read multiple bits from a byte array, MSB first.
pub fn pkt_read_bits(
  data : Bytes,
  bit_pos : Int,
  width : Int,
) -> Result[(Int, Int), String] {
  if width <= 0 {
    return Err("invalid bit width")
  }
  let mut v = 0
  let mut p = bit_pos
  for _ in 0..<width {
    let b = pkt_read_bit(data, p)
    guard b is Ok(bit) else { return Err("packet header bitstream truncated") }
    v = (v << 1) + bit
    p += 1
  }
  Ok((v, p))
}

///|
// T.800-2015 B.10.1: Convert consumed logical header bits to physical byte
// offset where the packet body starts, accounting for stuff bits after 0xFF.
pub fn pkt_body_start_offset(data : Bytes, consumed_logical_bits : Int) -> Int {
  let mut byte_idx = 0
  let mut logical_pos = 0
  while byte_idx < data.length() && logical_pos < consumed_logical_bits {
    let is_stuffed = byte_idx > 0 && data[byte_idx - 1].to_int() == 0xFF
    let bits_in_byte = if is_stuffed { 7 } else { 8 }
    logical_pos += bits_in_byte
    byte_idx += 1
  }
  // T.800-2015 B.10.1: if the header terminates immediately after a 0xFF
  // byte, the following stuffed byte belongs to the header coding convention
  // and must not be exposed as packet body.
  if byte_idx < data.length() &&
    byte_idx > 0 &&
    data[byte_idx - 1].to_int() == 0xFF {
    byte_idx += 1
  }
  byte_idx
}

///|
// Spec basis (T.800-2015 B.10.6):
// Decode number of coding passes using the variable-length code from Table B.4.
pub fn pkt_decode_num_coding_passes(
  data : Bytes,
  bit_pos : Int,
) -> Result[(Int, Int), String] {
  let b0 = pkt_read_bit(data, bit_pos)
  guard b0 is Ok(v0) else { return Err("packet header bitstream truncated") }
  if v0 == 0 {
    return Ok((1, bit_pos + 1))
  }
  let b1 = pkt_read_bit(data, bit_pos + 1)
  guard b1 is Ok(v1) else { return Err("packet header bitstream truncated") }
  if v1 == 0 {
    return Ok((2, bit_pos + 2))
  }
  let b2 = pkt_read_bit(data, bit_pos + 2)
  guard b2 is Ok(v2) else { return Err("packet header bitstream truncated") }
  if v2 == 0 {
    let b3 = pkt_read_bit(data, bit_pos + 3)
    guard b3 is Ok(v3) else { return Err("packet header bitstream truncated") }
    return Ok((if v3 == 0 { 3 } else { 4 }, bit_pos + 4))
  }
  let b3 = pkt_read_bit(data, bit_pos + 3)
  guard b3 is Ok(v3) else { return Err("packet header bitstream truncated") }
  if v3 == 0 {
    return Ok((5, bit_pos + 4))
  }
  let mid = pkt_read_bits(data, bit_pos + 4, 5)
  guard mid is Ok((mid5, p5)) else {
    return Err("packet header bitstream truncated")
  }
  if mid5 < 31 {
    return Ok((6 + mid5, p5))
  }
  let tail = pkt_read_bits(data, p5, 7)
  guard tail is Ok((tail7, p7)) else {
    return Err("packet header bitstream truncated")
  }
  Ok((37 + tail7, p7))
}

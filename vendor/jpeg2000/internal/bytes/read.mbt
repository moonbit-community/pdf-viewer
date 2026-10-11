///|
// Big-endian byte reading utilities for Bytes type

///|
/// Read unsigned 16-bit integer (big-endian) from Bytes at offset.
pub fn read_u16_be(data : Bytes, offset : Int) -> Int {
  (data[offset].to_int() << 8) + data[offset + 1].to_int()
}

///|
/// Read unsigned 32-bit integer (big-endian) from Bytes at offset.
pub fn read_u32_be(data : Bytes, offset : Int) -> Int {
  (data[offset].to_int() << 24) +
  (data[offset + 1].to_int() << 16) +
  (data[offset + 2].to_int() << 8) +
  data[offset + 3].to_int()
}

///|
/// Read unsigned 16-bit integer (big-endian) from Array[Int] at offset.
/// Returns Err if offset is out of bounds or bytes are out of range.
pub fn read_u16_be_arr(data : Array[Int], at : Int) -> Result[Int, String] {
  if at + 1 >= data.length() {
    Err("unexpected end while reading u16")
  } else {
    let hi = data[at]
    let lo = data[at + 1]
    if hi < 0 || hi > 0xFF || lo < 0 || lo > 0xFF {
      Err("byte out of range")
    } else {
      Ok((hi << 8) + lo)
    }
  }
}

///|
/// Read unsigned 32-bit integer (big-endian) from Array[Int] at offset.
/// Returns Err if offset is out of bounds or bytes are out of range.
pub fn read_u32_be_arr(data : Array[Int], at : Int) -> Result[Int, String] {
  if at + 3 >= data.length() {
    Err("unexpected end while reading u32")
  } else {
    let b0 = data[at]
    let b1 = data[at + 1]
    let b2 = data[at + 2]
    let b3 = data[at + 3]
    if b0 < 0 ||
      b0 > 0xFF ||
      b1 < 0 ||
      b1 > 0xFF ||
      b2 < 0 ||
      b2 > 0xFF ||
      b3 < 0 ||
      b3 > 0xFF {
      Err("byte out of range")
    } else {
      Ok((b0 << 24) + (b1 << 16) + (b2 << 8) + b3)
    }
  }
}

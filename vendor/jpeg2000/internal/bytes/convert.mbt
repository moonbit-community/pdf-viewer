///|
// Shared conversions between byte-oriented APIs and legacy Array[Int] helpers.

///|
pub fn bytes_to_int_array(data : Bytes) -> Array[Int] {
  let out : Array[Int] = []
  for b in data {
    out.push(b.to_int())
  }
  out
}

///|
pub fn int_array_to_bytes(data : Array[Int]) -> Bytes {
  Bytes::from_iter(data.iter().map(fn(i) { i.to_byte() }))
}

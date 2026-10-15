///|
test "byte copies retain surrounding bytes and accept empty boundary ranges" {
  let destination = FixedArray::make(12, b'\xCC')
  pdf_copy_bytes(destination, 3, b"0123456789", 2, 6)
  assert_eq(Bytes::from_array(destination), b"\xCC\xCC\xCC234567\xCC\xCC\xCC")
  pdf_copy_bytes(destination, 12, b"", 0, 0)
  pdf_copy_bytes(destination, 0, b"012", 3, 0)
  assert_eq(Bytes::from_array(destination), b"\xCC\xCC\xCC234567\xCC\xCC\xCC")
}

///|
#cfg(target="js")
test "byte copies preserve overlapping source ranges in both directions" {
  let right : FixedArray[Byte] = [b'0', b'1', b'2', b'3', b'4', b'5']
  let source = right.unsafe_reinterpret_as_bytes()
  pdf_copy_bytes(right, 1, source, 0, 5)
  assert_eq(Bytes::from_array(right), b"001234")
  let left : FixedArray[Byte] = [b'0', b'1', b'2', b'3', b'4', b'5']
  let source = left.unsafe_reinterpret_as_bytes()
  pdf_copy_bytes(left, 0, source, 1, 5)
  assert_eq(Bytes::from_array(left), b"123455")
}

///|
test "panic byte copy rejects a short destination" {
  pdf_copy_bytes(FixedArray::make(1, b'0'), 0, b"12", 0, 2)
}

///|
test "panic byte copy rejects a short source" {
  pdf_copy_bytes(FixedArray::make(2, b'0'), 0, b"1", 0, 2)
}

///|
test "panic byte copy rejects negative offsets" {
  pdf_copy_bytes(FixedArray::make(2, b'0'), -1, b"12", 0, 1)
}

///|
test "panic byte copy rejects overflowing offsets before copying" {
  pdf_copy_bytes(FixedArray::make(2, b'0'), 2147483647, b"12", 0, 2)
}

///|
test "panic byte copy rejects negative source offsets" {
  pdf_copy_bytes(FixedArray::make(2, b'0'), 0, b"12", -1, 1)
}

///|
test "panic byte copy rejects negative lengths" {
  pdf_copy_bytes(FixedArray::make(2, b'0'), 0, b"12", 0, -1)
}

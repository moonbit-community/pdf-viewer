///|
#cfg(target="native")
test "native JBIG2 packed luminance and stride" {
  // Page-information segment 1, 9x2 pixels, default white; generated here.
  let white = b"\x00\x00\x00\x01\x30\x00\x01\x00\x00\x00\x13\x00\x00\x00\x09\x00\x00\x00\x02\x00\x00\x00\x48\x00\x00\x00\x48\x00\x00\x00"
  let black = b"\x00\x00\x00\x01\x30\x00\x01\x00\x00\x00\x13\x00\x00\x00\x09\x00\x00\x00\x02\x00\x00\x00\x48\x00\x00\x00\x48\x04\x00\x00"
  if !@jbig2.available() {
    assert_eq(@jbig2.decode(white, None, 9, 2), None)
    return
  }
  assert_eq(@jbig2.decode(white, None, 9, 2), Some(b"\xff\xff\xff\xff"))
  assert_eq(@jbig2.decode(black, None, 9, 2), Some(b"\x00\x00\x00\x00"))
  assert_eq(@jbig2.decode(white, None, 8, 2), Some(b"\xff\xff"))
}

///|
#cfg(target="native")
test "native JBIG2 malformed is bounded and subsequent calls survive" {
  assert_eq(@jbig2.decode(b"\x00", None, 9, 2), None)
  assert_eq(
    @jbig2.decode(b"\x00\x00\x00\x01\x30\x00\x01\xff\xff\xff\xff", None, 9, 2),
    None,
  )
  assert_eq(@jbig2.decode(b"data", None, 32768, 32768), None)
}

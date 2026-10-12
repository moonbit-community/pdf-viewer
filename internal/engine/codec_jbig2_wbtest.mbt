///|
test "JBIG2 dimensions and compressed allocation guards" {
  assert_eq(pdf_jbig2_samples(b"x", None, 0, 1), None)
  assert_eq(pdf_jbig2_samples(b"x", None, -1, 1), None)
  assert_eq(pdf_jbig2_samples(b"x", None, 1, 32769), None)
  assert_eq(pdf_jbig2_samples(b"x", None, 32768, 32768), None)
  assert_eq(pdf_jbig2_samples(b"", None, 1, 1), None)
}

///|
#cfg(not(any(target="js", target="native")))
test "JBIG2 unsupported targets fail explicitly" {
  assert_eq(pdf_jbig2_samples(b"x", Some(b"y"), 8, 1), None)
}

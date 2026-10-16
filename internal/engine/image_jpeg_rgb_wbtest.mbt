///|
/// Exercise every 8-bit Y/Cb/Cr tuple, including exact half-byte boundaries.
/// Reuse small planes rather than allocating the full 16-million-pixel cube.
#cfg(target="js")
test "native JPEG clamping matches scalar rounding for every YCbCr tuple" {
  let luma = FixedArray::make(65536, b'\x00')
  let cb = FixedArray::makei(65536, index => (index >> 8).to_byte())
  let cr = FixedArray::makei(65536, index => (index & 255).to_byte())
  let actual = FixedArray::make(65536 * 3, b'\x00')
  let expected = FixedArray::make(65536 * 3, b'\x00')
  for y in 0..<256 {
    luma.fill(y.to_byte())
    pdf_jpeg_rgb_rows(
      actual, 256, 256, luma, cb, cr, 1, 1, 1, 1, 1, 1, 1, 1, 256, 256, 256, true,
    )
    for index in 0..<65536 {
      let a = y.to_double()
      let b = cb[index].to_int().to_double()
      let c = cr[index].to_int().to_double()
      expected[index * 3] = pdf_image_clamped_byte(a - 179.456 + 1.402 * c).to_byte()
      expected[index * 3 + 1] = pdf_image_clamped_byte(
        a + 135.459 - 0.344 * b - 0.714 * c,
      ).to_byte()
      expected[index * 3 + 2] = pdf_image_clamped_byte(a - 226.816 + 1.772 * b).to_byte()
    }
    assert_eq(actual, expected)
  }
}

///|
test "JPEG RGB rows respect padded planes and destination sentinels" {
  let plane = FixedArray::makei(40, index => index.to_byte())
  let output = FixedArray::make(17, b'\xff')
  pdf_jpeg_rgb_rows(
    output, 2, 2, plane, plane, plane, 1, 1, 1, 1, 1, 1, 1, 1, 8, 8, 8, false,
  )
  assert_eq(output[0:12].to_owned(), [
    b'\x00', b'\x00', b'\x00', b'\x01', b'\x01', b'\x01', b'\x08', b'\x08', b'\x08',
    b'\x09', b'\x09', b'\x09',
  ])
  for index in 12..<17 {
    assert_eq(output[index], b'\xff')
  }
}

///|
test "panic JPEG RGB rows reject short output" {
  let plane = FixedArray::make(8, b'\x00')
  pdf_jpeg_rgb_rows(
    FixedArray::make(5, b'\x00'),
    2,
    1,
    plane,
    plane,
    plane,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    8,
    8,
    8,
    true,
  )
}

///|
test "panic JPEG RGB rows reject truncated sampled plane" {
  let plane = FixedArray::make(9, b'\x00')
  pdf_jpeg_rgb_rows(
    FixedArray::make(12, b'\x00'),
    2,
    2,
    plane,
    plane,
    plane,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    8,
    8,
    8,
    true,
  )
}

///|
test "panic JPEG RGB rows reject invalid sampling factor" {
  let plane = FixedArray::make(16, b'\x00')
  pdf_jpeg_rgb_rows(
    FixedArray::make(12, b'\x00'),
    2,
    2,
    plane,
    plane,
    plane,
    0,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    8,
    8,
    8,
    true,
  )
}

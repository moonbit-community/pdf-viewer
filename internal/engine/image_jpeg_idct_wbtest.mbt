// Dense separable reference preserves the decoder's original arithmetic.

///|
// IDCT using pre-computed cosine table
fn jpeg_dense_idct_reference(
  coeff : FixedArray[Int],
  output : FixedArray[Int],
) -> Unit {
  let mut dc_only = true
  for i in 1..<64 {
    if coeff[i] != 0 {
      dc_only = false
      break
    }
  }
  if dc_only {
    let value = (coeff[0].to_double() / 8.0 + 128.5)
      .floor()
      .to_int()
      .max(0)
      .min(255)
    for i in 0..<64 {
      output[i] = value
    }
    return
  }
  let tmp = FixedArray::make(64, 0.0)
  // First pass: columns
  for x in 0..<8 {
    for y in 0..<8 {
      let mut sum = 0.0
      for u in 0..<8 {
        sum += pdf_jpeg_idct_c[u] *
          coeff[u * 8 + x].to_double() *
          pdf_jpeg_idct_cos_table[y * 8 + u]
      }
      tmp[y * 8 + x] = sum
    }
  }
  // Second pass: rows
  for y in 0..<8 {
    for x in 0..<8 {
      let mut sum = 0.0
      for v in 0..<8 {
        sum += pdf_jpeg_idct_c[v] *
          tmp[y * 8 + v] *
          pdf_jpeg_idct_cos_table[x * 8 + v]
      }
      let val = (sum / 4.0 + 128.5).floor().to_int()
      output[y * 8 + x] = if val < 0 {
        0
      } else if val > 255 {
        255
      } else {
        val
      }
    }
  }
}

///|
test "sparse JPEG IDCT matches dense rounding for every single frequency" {
  let coeff = FixedArray::make(64, 0)
  let expected = FixedArray::make(64, 0)
  let actual = FixedArray::make(64, 0)
  let scratch = PdfJpegIdctScratch::new()
  for frequency in 0..<64 {
    for amplitude in [-16384, -1024, -17, -4, -1, 0, 1, 4, 17, 1024, 16384] {
      coeff.fill(0)
      coeff[frequency] = amplitude
      jpeg_dense_idct_reference(coeff, expected)
      pdf_jpeg_idct_block(coeff, actual, scratch)
      assert_eq(actual, expected)
    }
  }
}

///|
test "JPEG IDCT scratch reuse preserves dense sparse and empty blocks" {
  let coeff = FixedArray::make(64, 0)
  let expected = FixedArray::make(64, 0)
  let actual = FixedArray::make(64, 0)
  let scratch = PdfJpegIdctScratch::new()
  let mut seed = 123456789U
  for case in 0..<512 {
    // Vary sparsity and active columns while retaining the same scratch.
    for i in 0..<64 {
      seed = seed * 1664525U + 1013904223U
      coeff[i] = if (seed >> 28).reinterpret_as_int() < case % 17 {
        ((seed >> 8) & 2047U).reinterpret_as_int() - 1024
      } else {
        0
      }
    }
    jpeg_dense_idct_reference(coeff, expected)
    pdf_jpeg_idct_block(coeff, actual, scratch)
    assert_eq(actual, expected)
  }
}

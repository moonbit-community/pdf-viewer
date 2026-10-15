// JPEG IDCT adapted from mizchi/image 0.4.3 (Apache-2.0).
// See docs/jpeg-decoder.md for provenance and the sample contract.

///|
// Pre-computed IDCT cosine table: cos((2*n+1)*k*PI/16) for n,k in 0..7
// pdf_jpeg_idct_cos_table[n * 8 + k] = cos((2*n+1)*k*PI/16)
let pdf_jpeg_idct_cos_table : FixedArray[Double] = {
  let t = FixedArray::make(64, 0.0)
  for n in 0..<8 {
    for k in 0..<8 {
      t[n * 8 + k] = @math.cos(
        (2.0 * n.to_double() + 1.0) * k.to_double() * @math.PI / 16.0,
      )
    }
  }
  t
}

///|
// C(k) scaling factor: 1/sqrt(2) for k=0, 1.0 otherwise
let pdf_jpeg_idct_c : FixedArray[Double] = {
  let c = FixedArray::make(8, 1.0)
  c[0] = 1.0 / 2.0.sqrt()
  c
}

///|
/// Scratch is owned by one decode and reused across its component blocks.
priv struct PdfJpegIdctScratch {
  rows : FixedArray[Double]
  scaled : FixedArray[Double]
  frequencies : FixedArray[Int]
  columns : FixedArray[Int]
}

///|
fn PdfJpegIdctScratch::new() -> PdfJpegIdctScratch {
  {
    rows: FixedArray::make(64, 0.0),
    scaled: FixedArray::make(8, 0.0),
    frequencies: FixedArray::make(8, 0),
    columns: FixedArray::make(8, 0),
  }
}

///|
/// Retain the dense IDCT's ascending accumulation and multiplication order.
/// Zero coefficients contribute nothing; only active columns are read back.
fn pdf_jpeg_idct_block(
  coeff : FixedArray[Int],
  output : FixedArray[Int],
  scratch : PdfJpegIdctScratch,
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
    output.fill(value)
    return
  }
  let mut column_count = 0
  for x in 0..<8 {
    let mut frequency_count = 0
    for u in 0..<8 {
      let value = coeff[u * 8 + x]
      if value != 0 {
        scratch.frequencies[frequency_count] = u
        scratch.scaled[frequency_count] = pdf_jpeg_idct_c[u] * value.to_double()
        frequency_count += 1
      }
    }
    if frequency_count == 0 {
      continue
    }
    scratch.columns[column_count] = x
    column_count += 1
    for y in 0..<8 {
      let mut sum = 0.0
      for i in 0..<frequency_count {
        sum += scratch.scaled[i] *
          pdf_jpeg_idct_cos_table[y * 8 + scratch.frequencies[i]]
      }
      scratch.rows[y * 8 + x] = sum
    }
  }
  for y in 0..<8 {
    // Each scaled term is invariant across the eight output columns.
    for i in 0..<column_count {
      let v = scratch.columns[i]
      scratch.scaled[i] = pdf_jpeg_idct_c[v] * scratch.rows[y * 8 + v]
    }
    for x in 0..<8 {
      let mut sum = 0.0
      for i in 0..<column_count {
        sum += scratch.scaled[i] *
          pdf_jpeg_idct_cos_table[x * 8 + scratch.columns[i]]
      }
      let value = (sum / 4.0 + 128.5).floor().to_int()
      output[y * 8 + x] = value.max(0).min(255)
    }
  }
}

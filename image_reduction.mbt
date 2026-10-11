///|
/// Oversized binary Gray scans must not discard strokes before the Canvas
/// minification stage. Pick whole power-of-two cells that meet the same output
/// budgets; ordinary colour/key/masked images retain their sample-domain path.
fn pdf_image_gray_reduce_dimensions(
  width : Int,
  height : Int,
  max_width : Int,
  max_height : Int,
) -> (Int, Int, Int) {
  let mut factor = 1
  while (width + factor - 1) / factor > max_width ||
        (height + factor - 1) / factor > max_height {
    factor *= 2
  }
  ((width + factor - 1) / factor, (height + factor - 1) / factor, factor)
}

///|
/// The returned coverage is an original normalized Gray component, before PDF
/// Decode. Row padding is ignored and partial edge cells use their actual area.
fn pdf_image_gray_cell_coverage(
  bytes : Bytes,
  row_bytes : Int,
  width : Int,
  height : Int,
  x : Int,
  y : Int,
  factor : Int,
) -> Double {
  let x0 = x * factor
  let y0 = y * factor
  let x1 = (x0 + factor).min(width)
  let y1 = (y0 + factor).min(height)
  let mut white = 0
  for sy in y0..<y1 {
    for sx in x0..<x1 {
      white += (bytes[sy * row_bytes + sx / 8].to_int() >> (7 - sx % 8)) & 1
    }
  }
  white.to_double() / ((x1 - x0) * (y1 - y0)).to_double()
}

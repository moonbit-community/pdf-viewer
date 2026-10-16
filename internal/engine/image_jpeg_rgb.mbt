///|
/// Validate geometry once before native sampling. Codec planes include MCU
/// padding; only the last actually sampled row/column must be present.
fn pdf_jpeg_rgb_rows(
  out : FixedArray[Byte],
  width : Int,
  height : Int,
  plane0 : FixedArray[Byte],
  plane1 : FixedArray[Byte],
  plane2 : FixedArray[Byte],
  h0 : Int,
  h1 : Int,
  h2 : Int,
  v0 : Int,
  v1 : Int,
  v2 : Int,
  max_h : Int,
  max_v : Int,
  stride0 : Int,
  stride1 : Int,
  stride2 : Int,
  transform : Bool,
) -> Unit {
  guard! width > 0 &&
    height > 0 &&
    width <= 65535 &&
    height <= 65535 &&
    max_h >= 1 &&
    max_h <= 4 &&
    max_v >= 1 &&
    max_v <= 4 &&
    height <= out.length() / 3 / width
  for
    (plane, h, v, stride) in [
      (plane0, h0, v0, stride0),
      (plane1, h1, v1, stride1),
      (plane2, h2, v2, stride2),
    ] {
    guard! h > 0 && h <= max_h && v > 0 && v <= max_v && stride > 0
    let last_x = (width - 1) * h / max_h
    let last_y = (height - 1) * v / max_v
    guard! last_x < stride &&
      last_x < plane.length() &&
      last_y <= (plane.length() - 1 - last_x) / stride
  }
  pdf_jpeg_rgb_rows_unchecked(
    out, width, height, plane0, plane1, plane2, h0, h1, h2, v0, v1, v2, max_h, max_v,
    stride0, stride1, stride2, transform,
  )
}

///|
#cfg(not(target="js"))
fn pdf_jpeg_rgb_rows_unchecked(
  out : FixedArray[Byte],
  width : Int,
  height : Int,
  plane0 : FixedArray[Byte],
  plane1 : FixedArray[Byte],
  plane2 : FixedArray[Byte],
  h0 : Int,
  h1 : Int,
  h2 : Int,
  v0 : Int,
  v1 : Int,
  v2 : Int,
  max_h : Int,
  max_v : Int,
  stride0 : Int,
  stride1 : Int,
  stride2 : Int,
  transform : Bool,
) -> Unit {
  for y in 0..<height {
    let row0 = y * v0 / max_v * stride0
    let row1 = y * v1 / max_v * stride1
    let row2 = y * v2 / max_v * stride2
    let output_row = y * width * 3
    for x in 0..<width {
      let a = plane0[row0 + x * h0 / max_h]
      let b = plane1[row1 + x * h1 / max_h]
      let c = plane2[row2 + x * h2 / max_h]
      let offset = output_row + x * 3
      if transform {
        let luma = a.to_int().to_double()
        let cb = b.to_int().to_double()
        let cr = c.to_int().to_double()
        out[offset] = pdf_image_clamped_byte(luma - 179.456 + 1.402 * cr).to_byte()
        out[offset + 1] = pdf_image_clamped_byte(
          luma + 135.459 - 0.344 * cb - 0.714 * cr,
        ).to_byte()
        out[offset + 2] = pdf_image_clamped_byte(luma - 226.816 + 1.772 * cb).to_byte()
      } else {
        out[offset] = a
        out[offset + 1] = b
        out[offset + 2] = c
      }
    }
  }
}

///|
/// The clamped view implements the same saturation and ties-to-even rounding
/// as pdf_image_clamped_byte, without three scalar conversions per pixel.
/// Keep every floating-point expression in the original evaluation order.
#cfg(target="js")
extern "js" fn pdf_jpeg_rgb_rows_unchecked(
  out : FixedArray[Byte],
  width : Int,
  height : Int,
  plane0 : FixedArray[Byte],
  plane1 : FixedArray[Byte],
  plane2 : FixedArray[Byte],
  h0 : Int,
  h1 : Int,
  h2 : Int,
  v0 : Int,
  v1 : Int,
  v2 : Int,
  max_h : Int,
  max_v : Int,
  stride0 : Int,
  stride1 : Int,
  stride2 : Int,
  transform : Bool,
) -> Unit =
  #| (out, width, height, p0, p1, p2, h0, h1, h2, v0, v1, v2,
  #|  maxH, maxV, stride0, stride1, stride2, transform) => {
  #|   const rgb = new Uint8ClampedArray(out.buffer, out.byteOffset, out.byteLength);
  #|   for (let y = 0; y < height; y++) {
  #|     const row0 = ((y * v0 / maxV) | 0) * stride0;
  #|     const row1 = ((y * v1 / maxV) | 0) * stride1;
  #|     const row2 = ((y * v2 / maxV) | 0) * stride2;
  #|     let offset = y * width * 3;
  #|     for (let x = 0; x < width; x++, offset += 3) {
  #|       const a = p0[row0 + ((x * h0 / maxH) | 0)];
  #|       const b = p1[row1 + ((x * h1 / maxH) | 0)];
  #|       const c = p2[row2 + ((x * h2 / maxH) | 0)];
  #|       if (transform) {
  #|         rgb[offset] = a - 179.456 + 1.402 * c;
  #|         rgb[offset + 1] = a + 135.459 - 0.344 * b - 0.714 * c;
  #|         rgb[offset + 2] = a - 226.816 + 1.772 * b;
  #|       } else {
  #|         out[offset] = a;
  #|         out[offset + 1] = b;
  #|         out[offset + 2] = c;
  #|       }
  #|     }
  #|   }
  #| }

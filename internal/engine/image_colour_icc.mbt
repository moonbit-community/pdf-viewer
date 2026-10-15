///|
/// Opaque, unscaled 8-bit ICC RGB rows need only their final RGB bytes. Keep
/// the same Decode, range clipping, CMM and rounding rules as the general
/// converter, with a bounded exact palette instead of per-pixel state tests.
fn pdf_image_icc_rgb_rows(
  bytes : Bytes,
  width : Int,
  height : Int,
  row_bytes : Int,
  decode : Array[(Double, Double)],
  source_ranges : Array[(Double, Double)],
  icc : PdfIccTransform,
  alternate : PdfColourTransform,
  icc_ranges : Array[(Double, Double)],
) -> Bytes {
  let stride = width * 3 + 1
  let scanlines = FixedArray::make(height * stride, b'\x00')
  let palette : Map[Int, Int] = Map([])
  let values = Array::make(3, 0.0)
  let mut previous_key = -1
  let mut previous_rgb = 0
  for y in 0..<height {
    let source_row = y * row_bytes
    let output_row = y * stride + 1
    for x in 0..<width {
      let source = source_row + x * 3
      let key = (bytes[source].to_int() << 16) |
        (bytes[source + 1].to_int() << 8) |
        bytes[source + 2].to_int()
      let rgb = if key == previous_key {
        previous_rgb
      } else {
        match palette.get(key) {
          Some(rgb) => {
            previous_key = key
            previous_rgb = rgb
            rgb
          }
          None => {
            for component in 0..<3 {
              let sample = bytes[source + component].to_int().to_double() /
                255.0
              let (lower, upper) = decode[component]
              let (minimum, maximum) = source_ranges[component]
              values[component] = (lower + sample * (upper - lower))
                .max(minimum)
                .min(maximum)
            }
            let clipped = pdf_icc_clip(values[:], icc_ranges)
            let (r, g, b) = (icc.convert)(clipped[:])
            let valid = !r.is_nan() &&
              !g.is_nan() &&
              !b.is_nan() &&
              !r.is_inf() &&
              !g.is_inf() &&
              !b.is_inf()
            let (r, g, b) = if valid {
              (r, g, b)
            } else {
              pdf_colour_rgb_of_transform(alternate, clipped[:])
            }
            let rgb = (pdf_transfer_value_to_byte(r) << 16) |
              (pdf_transfer_value_to_byte(g) << 8) |
              pdf_transfer_value_to_byte(b)
            // Palette capacity does not limit the one-entry run cache. A new
            // colour can cover a long run after the bounded palette is full.
            // Failed CMM results must remain retryable through Alternate.
            if valid {
              if palette.length() < 4096 {
                palette[key] = rgb
              }
              previous_key = key
              previous_rgb = rgb
            } else {
              previous_key = -1
            }
            rgb
          }
        }
      }
      let output = output_row + x * 3
      scanlines[output] = (rgb >> 16).to_byte()
      scanlines[output + 1] = ((rgb >> 8) & 255).to_byte()
      scanlines[output + 2] = (rgb & 255).to_byte()
    }
  }
  // This fresh buffer has no escaping mutable alias and receives no more writes.
  scanlines.unsafe_reinterpret_as_bytes()
}

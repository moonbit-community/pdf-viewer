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
  // Four recent exact colours per bucket keep photographs useful after the
  // first 4096 colours. Full keys distinguish hash collisions; failed CMM
  // results never enter the palette. Small images allocate fewer buckets.
  let mut capacity = 4
  while capacity < 4096 && capacity < width * height {
    capacity *= 2
  }
  let bucket_mask = (capacity / 4 - 1).reinterpret_as_uint()
  let palette_keys = FixedArray::make(capacity, -1)
  let palette_rgb = FixedArray::make(capacity, 0)
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
        let bucket = (((key.reinterpret_as_uint() * 0x9E3779B1U) >> 20) &
          bucket_mask).reinterpret_as_int() *
          4
        let hit = for i in 0..<4 {
          if palette_keys[bucket + i] == key {
            break i
          }
        } nobreak {
          4
        }
        let mut valid = true
        let rgb = if hit < 4 {
          palette_rgb[bucket + hit]
        } else {
          for component in 0..<3 {
            let sample = bytes[source + component].to_int().to_double() / 255.0
            let (lower, upper) = decode[component]
            let (minimum, maximum) = source_ranges[component]
            values[component] = (lower + sample * (upper - lower))
              .max(minimum)
              .min(maximum)
          }
          let clipped = pdf_icc_clip(values[:], icc_ranges)
          let (r, g, b) = (icc.convert)(clipped[:])
          valid = !r.is_nan() &&
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
          (pdf_transfer_value_to_byte(r) << 16) |
          (pdf_transfer_value_to_byte(g) << 8) |
          pdf_transfer_value_to_byte(b)
        }
        if valid {
          // Promote hits and replace the oldest colour in this bucket only.
          for i = hit.min(3); i > 0; i = i - 1 {
            palette_keys[bucket + i] = palette_keys[bucket + i - 1]
            palette_rgb[bucket + i] = palette_rgb[bucket + i - 1]
          }
          palette_keys[bucket] = key
          palette_rgb[bucket] = rgb
          previous_key = key
          previous_rgb = rgb
        } else {
          previous_key = -1
        }
        rgb
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

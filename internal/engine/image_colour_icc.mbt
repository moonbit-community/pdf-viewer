///|
#cfg(target="js")
const ICC_RGB_ROW_COPY : Bool = true

///|
#cfg(not(target="js"))
const ICC_RGB_ROW_COPY : Bool = false

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
  // Prove every source and destination offset once before the pixel loop.
  // Division precedes multiplication so malformed geometry cannot overflow.
  guard! width > 0 &&
    height > 0 &&
    width <= (67108864 - 1) / 3 &&
    row_bytes >= width * 3 &&
    row_bytes <= bytes.length() / height &&
    height <= 67108864 / (width * 3 + 1)
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
  let values_view = values[:]
  // Decode and both range clips are separable and exact for 8-bit samples.
  // Amortize the tables only over >= 4096 pixels. Small icons retain direct
  // sample preparation and do not allocate or initialize unused tables.
  let tables = if width * height < 4096 {
    None
  } else {
    let tables = FixedArray::makei(3, component => {
      let (lower, upper) = decode[component]
      let (minimum, maximum) = source_ranges[component]
      let (icc_minimum, icc_maximum) = icc_ranges[component]
      FixedArray::makei(256, sample => {
        let value = (lower + sample.to_double() / 255.0 * (upper - lower))
          .max(minimum)
          .min(maximum)
        if value.is_nan() {
          0.0.max(icc_minimum).min(icc_maximum)
        } else {
          value.max(icc_minimum).min(icc_maximum)
        }
      })
    })
    Some((tables[0], tables[1], tables[2]))
  }
  let mut previous_key = -1
  let mut previous_rgb = 0
  for y in 0..<height {
    let source_row = y * row_bytes
    let output_row = y * stride + 1
    // Copy the raw row once, then patch only pixels whose exact converted
    // bytes differ. No assumption about profile identity or Decode is needed.
    if ICC_RGB_ROW_COPY {
      pdf_copy_bytes(scanlines, output_row, bytes, source_row, width * 3)
    }
    for x in 0..<width {
      let source = source_row + x * 3
      let key = (bytes.unsafe_get(source).to_int() << 16) |
        (bytes.unsafe_get(source + 1).to_int() << 8) |
        bytes.unsafe_get(source + 2).to_int()
      let rgb = if key == previous_key {
        previous_rgb
      } else {
        let bucket = (((key.reinterpret_as_uint() * 0x9E3779B1U) >> 20) &
          bucket_mask).reinterpret_as_int() *
          4
        // Capacity is a power of two >= 4; bucket + 3 < capacity.
        let hit = if palette_keys.unsafe_get(bucket) == key {
          0
        } else if palette_keys.unsafe_get(bucket + 1) == key {
          1
        } else if palette_keys.unsafe_get(bucket + 2) == key {
          2
        } else if palette_keys.unsafe_get(bucket + 3) == key {
          3
        } else {
          4
        }
        let mut valid = true
        let rgb = if hit < 4 {
          palette_rgb.unsafe_get(bucket + hit)
        } else {
          let clipped = match tables {
            Some((red, green, blue)) => {
              // Each key lane is a byte; each table has 256 entries.
              values.unsafe_set(0, red.unsafe_get(key >> 16))
              values.unsafe_set(1, green.unsafe_get((key >> 8) & 255))
              values.unsafe_set(2, blue.unsafe_get(key & 255))
              values_view
            }
            None => {
              for component in 0..<3 {
                let sample = ((key >> ((2 - component) * 8)) & 255).to_double() /
                  255.0
                let (lower, upper) = decode[component]
                let (minimum, maximum) = source_ranges[component]
                values[component] = (lower + sample * (upper - lower))
                  .max(minimum)
                  .min(maximum)
              }
              let clipped = pdf_icc_clip(values_view, icc_ranges)
              clipped[:]
            }
          }
          let (r, g, b) = (icc.convert)(clipped)
          valid = !r.is_nan() &&
            !g.is_nan() &&
            !b.is_nan() &&
            !r.is_inf() &&
            !g.is_inf() &&
            !b.is_inf()
          let (r, g, b) = if valid {
            (r, g, b)
          } else {
            pdf_colour_rgb_of_transform(alternate, clipped)
          }
          (pdf_transfer_value_to_byte(r) << 16) |
          (pdf_transfer_value_to_byte(g) << 8) |
          pdf_transfer_value_to_byte(b)
        }
        if valid {
          // Promote hits and replace the oldest colour in this bucket only.
          // A head hit already has the required position and RGB bytes.
          if hit > 0 {
            if hit >= 3 {
              palette_keys.unsafe_set(
                bucket + 3,
                palette_keys.unsafe_get(bucket + 2),
              )
              palette_rgb.unsafe_set(
                bucket + 3,
                palette_rgb.unsafe_get(bucket + 2),
              )
            }
            if hit >= 2 {
              palette_keys.unsafe_set(
                bucket + 2,
                palette_keys.unsafe_get(bucket + 1),
              )
              palette_rgb.unsafe_set(
                bucket + 2,
                palette_rgb.unsafe_get(bucket + 1),
              )
            }
            palette_keys.unsafe_set(bucket + 1, palette_keys.unsafe_get(bucket))
            palette_rgb.unsafe_set(bucket + 1, palette_rgb.unsafe_get(bucket))
            palette_keys.unsafe_set(bucket, key)
            palette_rgb.unsafe_set(bucket, rgb)
          }
          previous_key = key
          previous_rgb = rgb
        } else {
          previous_key = -1
        }
        rgb
      }
      if !ICC_RGB_ROW_COPY || rgb != key {
        let output = output_row + x * 3
        scanlines.unsafe_set(output, (rgb >> 16).to_byte())
        scanlines.unsafe_set(output + 1, ((rgb >> 8) & 255).to_byte())
        scanlines.unsafe_set(output + 2, (rgb & 255).to_byte())
      }
    }
  }
  // This fresh buffer has no escaping mutable alias and receives no more writes.
  scanlines.unsafe_reinterpret_as_bytes()
}

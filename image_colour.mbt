///|
/// Decode supported PDF filters with pdflite, then convert the original
/// samples in the viewer. Converting pdflite's already-RGB output would lose
/// CalGray/CalRGB/Lab semantics, precision, and colour-key mask operands.
/// Encoded JPEG/JPX/JBIG2 images and ImageMask keep their existing paths.
fn pdf_image_colour_png(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  object : @syntax.PdfObject,
) -> (Int, Int, Bytes, Bool)? raise @core.PdfError {
  if pdf_image_object_is_mask(document, object) {
    return None
  }
  let decoded = document.pdf_decode_stream_until_unknown(object)
  match
    document.lookup_direct_or_else(
      pdf_image_name("/Filter"),
      pdf_image_name("/F"),
      decoded,
    ) {
    Some(@syntax.PdfArray([])) | Some(@syntax.PdfNull) | None => ()
    _ => return None
  }
  let width = pdf_image_sample_int(document, decoded, "/Width", "/W", 0)
  let height = pdf_image_sample_int(document, decoded, "/Height", "/H", 0)
  let bits = pdf_image_sample_int(
    document, decoded, "/BitsPerComponent", "/BPC", 0,
  )
  if width <= 0 || height <= 0 || !(bits is (1 | 2 | 4 | 8 | 16)) {
    return None
  }
  let object_space = document
    .lookup_direct_or_else(
      pdf_image_name("/ColorSpace"),
      pdf_image_name("/CS"),
      decoded,
    )
    .unwrap_or(@syntax.PdfNameObject(pdf_image_name("/DeviceGray")))
  let space = pdf_read_colour_space_for_viewer(
    document, resources, object_space,
  ).unwrap_or(@pdflite.PdfDeviceGray)
  let ranges = pdf_colour_component_ranges(space)
  let components = ranges.length()
  if components <= 0 ||
    components > 32 ||
    width > (2147483647 - 7) / (components * bits) {
    raise @core.PdfError::EndOfInput
  }
  let row_bytes = (width * components * bits + 7) / 8
  if height > 2147483647 / row_bytes {
    raise @core.PdfError::EndOfInput
  }
  let bytes = decoded.stream_bytes()
  if bytes.length() < row_bytes * height {
    raise @core.PdfError::EndOfInput
  }
  let max_sample = (1 << bits) - 1
  let decode = pdf_image_sample_decode(document, decoded, space, max_sample)
  let alpha = pdf_image_alpha_samples(
    document, resources, object, width, height,
  )
  let mask = pdf_image_color_key_mask(document, object)
  let has_mask = match mask {
    Some(mask) =>
      pdf_image_alpha_source(document, object) is None &&
      mask.length() == components * 2
    None => false
  }
  let (draw_width, draw_height) = match alpha {
    Some(alpha) => (width.max(alpha.width), height.max(alpha.height))
    None => (width, height)
  }
  let channels = if has_mask || alpha is Some(_) { 4 } else { 3 }
  if draw_width > (2147483647 - 1) / channels ||
    draw_height > 2147483647 / (draw_width * channels + 1) {
    raise @core.PdfError::EndOfInput
  }
  let transform = pdf_colour_transform(Some(document), space)
  let matte = match alpha {
    Some({ matte: Some(values), .. }) if values.length() == components => {
      let (red, green, blue) = pdf_colour_rgb_of_transform(transform, values[:])
      Some(
        (
          pdf_image_clamped_byte(red * 255.0),
          pdf_image_clamped_byte(green * 255.0),
          pdf_image_clamped_byte(blue * 255.0),
        ),
      )
    }
    _ => None
  }
  let values = Array::make(components, 0.0)
  let scanlines : Array[Int] = Array(
    capacity=draw_height * (draw_width * channels + 1),
  )
  for y in 0..<draw_height {
    scanlines.push(0)
    let source_y = (y.to_double() * height.to_double() / draw_height.to_double()).to_int()
    let row = bytes[source_y * row_bytes:(source_y + 1) * row_bytes]
    for x in 0..<draw_width {
      let source_x = (x.to_double() * width.to_double() / draw_width.to_double()).to_int()
      let mut transparent = has_mask
      for component in 0..<components {
        let offset = (source_x * components + component) * bits
        let sample = pdf_image_read_sample(row, offset, bits)
        match mask {
          Some(mask) if has_mask =>
            if !pdf_color_key_component_matches(
                sample,
                mask[component * 2],
                mask[component * 2 + 1],
              ) {
              transparent = false
            }
          _ => ()
        }
        let (lower, upper) = decode[component]
        let value = lower +
          sample.to_double() / max_sample.to_double() * (upper - lower)
        let (minimum, maximum) = ranges[component]
        values[component] = value.max(minimum).min(maximum)
      }
      let (red, green, blue) = pdf_colour_rgb_of_transform(transform, values[:])
      let opacity = match alpha {
        Some(alpha) => alpha.sample(x, y, draw_width, draw_height)
        None => if transparent { 0 } else { 255 }
      }
      let red = pdf_transfer_value_to_byte(red)
      let green = pdf_transfer_value_to_byte(green)
      let blue = pdf_transfer_value_to_byte(blue)
      let (red, green, blue) = match matte {
        Some((matte_r, matte_g, matte_b)) =>
          (
            pdf_image_unblend_component(red, matte_r, opacity),
            pdf_image_unblend_component(green, matte_g, opacity),
            pdf_image_unblend_component(blue, matte_b, opacity),
          )
        None => (red, green, blue)
      }
      scanlines.push(red)
      scanlines.push(green)
      scanlines.push(blue)
      if channels == 4 {
        scanlines.push(opacity)
      }
    }
  }
  Some(
    (
      draw_width,
      draw_height,
      pdf_png_of_scanlines(
        draw_width,
        draw_height,
        if channels == 4 {
          6
        } else {
          2
        },
        scanlines,
      ),
      alpha is Some(_),
    ),
  )
}

///|
fn pdf_image_sample_int(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  long_key : String,
  short_key : String,
  fallback : Int,
) -> Int {
  match
    document.lookup_direct_or_else(
      pdf_image_name(long_key),
      pdf_image_name(short_key),
      object,
    ) {
    Some(@syntax.PdfInteger(value)) => value
    _ => fallback
  }
}

///|
fn pdf_image_sample_decode(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  space : @pdflite.PdfColourSpace,
  max_sample : Int,
) -> Array[(Double, Double)] {
  let defaults = match space {
    @pdflite.PdfIndexed(_, _) => [(0.0, max_sample.to_double())]
    _ => pdf_colour_component_ranges(space)
  }
  match
    document.lookup_direct_or_else(
      pdf_image_name("/Decode"),
      pdf_image_name("/D"),
      object,
    ) {
    Some(@syntax.PdfArray(values)) if values.length() == defaults.length() * 2 => {
      let output : Array[(Double, Double)] = []
      for component in 0..<defaults.length() {
        let lower = document.get_number(values[component * 2]) catch {
          _ => return defaults
        }
        let upper = document.get_number(values[component * 2 + 1]) catch {
          _ => return defaults
        }
        if lower.is_nan() || lower.is_inf() || upper.is_nan() || upper.is_inf() {
          return defaults
        }
        output.push((lower, upper))
      }
      output
    }
    _ => defaults
  }
}

///|
/// PDF image rows are byte-aligned, with big-endian samples in each row.
fn pdf_image_read_sample(
  bytes : BytesView,
  bit_offset : Int,
  bits : Int,
) -> Int {
  let byte_offset = bit_offset / 8
  if bits == 16 {
    (bytes[byte_offset].to_int() << 8) | bytes[byte_offset + 1].to_int()
  } else {
    (bytes[byte_offset].to_int() >> (8 - bits - bit_offset % 8)) &
    ((1 << bits) - 1)
  }
}

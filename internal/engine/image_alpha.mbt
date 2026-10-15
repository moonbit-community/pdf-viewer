///|
priv struct PdfImageAlphaSamples {
  bytes : Bytes
  width : Int
  height : Int
  row_bytes : Int
  bits : Int
  decode : (Double, Double)
  invert : Bool
  matte : Array[Double]?
}

///|
/// SMask takes precedence over explicit and colour-key masks. A /Mask stream
/// must be an ImageMask; /None and null SMask values allow /Mask fallback.
fn pdf_image_alpha_source(
  document : @pdflite.PdfDocument,
  image : @syntax.PdfObject,
) -> (@syntax.PdfObject, Bool)? {
  match document.lookup_direct(pdf_image_name("/SMask"), image) {
    Some(@syntax.PdfStreamObject(_) as object) => return Some((object, false))
    Some(@syntax.PdfDictionary(_) as object) => return Some((object, false))
    _ => ()
  }
  match document.lookup_direct(pdf_image_name("/Mask"), image) {
    Some(@syntax.PdfStreamObject(_) as object) if pdf_image_object_is_mask(
        document, object,
      ) => Some((object, true))
    _ => None
  }
}

///|
/// Decode opacity from original grayscale samples, without applying a colour
/// space gamma curve. `/Matte` is expressed in the parent image colour space.
fn pdf_image_alpha_samples(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  image : @syntax.PdfObject,
  width : Int,
  height : Int,
) -> PdfImageAlphaSamples? raise @core.PdfError {
  guard pdf_image_alpha_source(document, image) is Some((source, invert)) else {
    return None
  }
  pdf_image_alpha_samples_of_source(
    document, resources, source, width, height, invert,
  )
}

///|
fn pdf_image_alpha_samples_of_source(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  source : @syntax.PdfObject,
  width : Int,
  height : Int,
  invert : Bool,
) -> PdfImageAlphaSamples? raise @core.PdfError {
  guard source is @syntax.PdfStreamObject(_) else { return None }
  let declared_width = pdf_image_sample_int(
    document, source, "/Width", "/W", width,
  )
  let declared_height = pdf_image_sample_int(
    document, source, "/Height", "/H", height,
  )
  if declared_width > 0 &&
    declared_height > 0 &&
    !pdf_image_source_dimensions_allowed(declared_width, declared_height, 1, 1) {
    raise @core.PdfError::EndOfInput
  }
  let decoded = pdf_image_decode_stream(
    document,
    resources,
    source,
    width~,
    height~,
  )
  let encoded = if pdf_image_remaining_filter(document, decoded) is Some(_) {
    match pdf_image_encoded_samples(document, decoded) {
      Some(samples) if samples.components == 1 => Some(samples)
      _ => return None
    }
  } else {
    None
  }
  if !pdf_image_object_is_mask(document, source) {
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
    if pdf_colour_component_ranges(space).length() != 1 {
      return None
    }
  }
  let mask_width = pdf_image_sample_int(
    document, decoded, "/Width", "/W", width,
  )
  let mask_height = pdf_image_sample_int(
    document, decoded, "/Height", "/H", height,
  )
  let width = match encoded {
    Some(samples) => samples.width
    None => if mask_width > 0 { mask_width } else { width }
  }
  let height = match encoded {
    Some(samples) => samples.height
    None => if mask_height > 0 { mask_height } else { height }
  }
  let bits = match encoded {
    Some(samples) => samples.bits
    None =>
      pdf_image_sample_int(
        document,
        decoded,
        "/BitsPerComponent",
        "/BPC",
        if pdf_image_object_is_mask(document, source) {
          1
        } else {
          0
        },
      )
  }
  if width <= 0 ||
    height <= 0 ||
    !(if encoded is Some(_) {
      bits >= 1 && bits <= 16
    } else {
      bits is (1 | 2 | 4 | 8 | 16)
    }) {
    return None
  }
  if !pdf_image_source_dimensions_allowed(width, height, 1, bits) ||
    width > (2147483647 - 7) / bits {
    raise @core.PdfError::EndOfInput
  }
  let minimum_row_bytes = (width * bits + 7) / 8
  let row_bytes = match encoded {
    Some(samples) => samples.row_bytes
    None => minimum_row_bytes
  }
  if row_bytes < minimum_row_bytes {
    raise @core.PdfError::EndOfInput
  }
  if height > 67108864 / row_bytes {
    raise @core.PdfError::EndOfInput
  }
  let bytes = match encoded {
    Some(samples) => samples.bytes
    None => decoded.stream_bytes()
  }
  if bytes.length() < row_bytes * height {
    raise @core.PdfError::EndOfInput
  }
  let decode = pdf_image_sample_decode(
      document,
      decoded,
      @pdflite.PdfDeviceGray,
      (1 << bits) - 1,
    )[0]
  let matte = if invert {
    None
  } else {
    pdf_image_matte_values(document, source)
  }
  Some({ bytes, width, height, row_bytes, bits, decode, invert, matte, })
}

///|
fn pdf_image_matte_values(
  document : @pdflite.PdfDocument,
  image : @syntax.PdfObject,
) -> Array[Double]? {
  match document.lookup_direct(pdf_image_name("/Matte"), image) {
    Some(@syntax.PdfArray(values)) => {
      let output : Array[Double] = []
      for value in values {
        let value = document.get_number(value) catch { _ => return None }
        if value.is_nan() || value.is_inf() {
          return None
        }
        output.push(value)
      }
      Some(output)
    }
    _ => None
  }
}

///|
/// Decoded mask resizing uses floor-based nearest neighbours before the
/// final draw, independently of the mask's own `/Interpolate` declaration.
fn PdfImageAlphaSamples::sample(
  self : PdfImageAlphaSamples,
  x : Int,
  y : Int,
  width : Int,
  height : Int,
) -> Int {
  let source_x = (x.to_double() * self.width.to_double() / width.to_double()).to_int()
  let source_y = (y.to_double() * self.height.to_double() / height.to_double()).to_int()
  let row = self.bytes[source_y * self.row_bytes:(source_y + 1) * self.row_bytes]
  let original = pdf_image_read_sample(row, source_x * self.bits, self.bits)
  let (lower, upper) = self.decode
  let value = if self.bits == 1 {
    // PDF.js treats a nondefault one-bit Decode as inversion.
    if lower == 0.0 && upper == 1.0 {
      original * 255
    } else {
      (1 - original) * 255
    }
  } else {
    let max_sample = ((1 << self.bits) - 1).to_double()
    let sample = (lower * max_sample + original.to_double() * (upper - lower))
      .max(0.0)
      .min(max_sample)
      .to_int()
    // fillGrayBuffer's XOR converts to an integer before the clamped write.
    (sample.to_double() * 255.0 / max_sample).to_int()
  }
  if self.invert {
    value ^ 255
  } else {
    value
  }
}

///|
/// Uint8ClampedArray rounding (ties to even), used after RGB unpremultiplying.
fn pdf_image_clamped_byte(value : Double) -> Int {
  if value <= 0.0 || value.is_nan() {
    return 0
  }
  if value >= 255.0 {
    return 255
  }
  let lower = value.to_int()
  let fraction = value - lower.to_double()
  if fraction > 0.5 || (fraction == 0.5 && lower % 2 == 1) {
    lower + 1
  } else {
    lower
  }
}

///|
fn pdf_image_unblend_component(value : Int, matte : Int, alpha : Int) -> Int {
  if alpha == 0 {
    return 255
  }
  pdf_image_clamped_byte(
    (value - matte).to_double() * 255.0 / alpha.to_double() + matte.to_double(),
  )
}

///|
fn PdfImageAlphaSamples::png(
  self : PdfImageAlphaSamples,
  transfer_map : Array[Int]?,
  rgb? : Bool = false,
) -> Bytes raise @core.PdfError {
  if !pdf_image_source_dimensions_allowed(self.width, self.height, 1, self.bits) {
    raise @core.PdfError::EndOfInput
  }
  let (width, height) = pdf_image_draw_dimensions(self.width, self.height)
  let channels = if rgb { 3 } else { 1 }
  let stride = width * channels + 1
  let scanlines = FixedArray::make(stride * height, b'\x00')
  for y in 0..<height {
    for x in 0..<width {
      let value = self.sample(x, y, width, height)
      let value = pdf_apply_transfer_map(value, transfer_map).to_byte()
      for channel in 0..<channels {
        scanlines[y * stride + 1 + x * channels + channel] = value
      }
    }
  }
  pdf_png_of_scanline_bytes(
    width,
    height,
    if rgb {
      2
    } else {
      0
    },
    // Freeze this call's fresh output; the mask's source samples remain separate.
    scanlines.unsafe_reinterpret_as_bytes(),
  )
}

///|
/// Explicit/color-key masks constrain shape. Soft masks supply opacity and
/// supersede the active graphics-state soft mask at this image paint site.
fn pdf_image_local_mask_flags(
  document : @pdflite.PdfDocument,
  image : @syntax.PdfObject,
) -> (Bool, Bool) {
  match pdf_image_alpha_source(document, image) {
    Some((_, explicit)) => return (true, explicit)
    None => ()
  }
  if pdf_image_color_key_mask(document, image) is Some(_) {
    return (true, true)
  }
  if pdf_image_sample_int(document, image, "/SMaskInData", "/SMaskInData", 0)
    is (1 | 2) {
    return (true, false)
  }
  (false, pdf_image_object_is_mask(document, image))
}

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
  guard source is @syntax.PdfStreamObject(_) else { return None }
  let decoded = document.pdf_decode_stream_until_unknown(source)
  match
    document.lookup_direct_or_else(
      pdf_image_name("/Filter"),
      pdf_image_name("/F"),
      decoded,
    ) {
    Some(@syntax.PdfArray([])) | Some(@syntax.PdfNull) | None => ()
    _ => return None
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
  let width = if mask_width > 0 { mask_width } else { width }
  let height = if mask_height > 0 { mask_height } else { height }
  let bits = pdf_image_sample_int(
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
  if width <= 0 || height <= 0 || !(bits is (1 | 2 | 4 | 8 | 16)) {
    return None
  }
  if width > (2147483647 - 7) / bits {
    raise @core.PdfError::EndOfInput
  }
  let row_bytes = (width * bits + 7) / 8
  if height > 2147483647 / row_bytes {
    raise @core.PdfError::EndOfInput
  }
  let bytes = decoded.stream_bytes()
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

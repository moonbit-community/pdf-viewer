///|
/// Row-aligned, interleaved integer PDF colour samples, before /Decode and
/// conversion to RGB. 16-bit samples are big-endian. Embedded opacity, when
/// present, is a separate unsigned grayscale plane, never premultiplied into
/// these bytes except when embedded_alpha_associated is explicitly true.
priv struct PdfImageDecodedSamples {
  bytes : Bytes
  width : Int
  height : Int
  bits : Int
  components : Int
  row_bytes : Int
  embedded_alpha : Bytes?
  embedded_alpha_bits : Int
  embedded_alpha_row_bytes : Int
  embedded_alpha_associated : Bool
  colour_hint : String
  embedded_icc_profile : Bytes?
}

///|
/// A per-image bound checked before codec allocation and compositing. Padded
/// codec planes must also fit. This bounds one image, not a document cache.
fn pdf_image_dimensions_allowed(
  width : Int,
  height : Int,
  channels : Int,
) -> Bool {
  width > 0 &&
  height > 0 &&
  width <= 65535 &&
  height <= 65535 &&
  channels > 0 &&
  channels <= 32 &&
  width <= 16777216 / height &&
  width * height <= 67108864 / channels
}

///|
fn pdf_image_remaining_filter(
  document : @pdflite.PdfDocument,
  decoded : @syntax.PdfObject,
) -> String? {
  let value = document.lookup_direct_or_else(
    pdf_image_name("/Filter"),
    pdf_image_name("/F"),
    decoded,
  )
  match value {
    None | Some(@syntax.PdfNull) | Some(@syntax.PdfArray([])) => None
    Some(@syntax.PdfNameObject(name))
    | Some(@syntax.PdfArray([@syntax.PdfNameObject(name)])) =>
      Some(pdf_annotation_name_text(name))
    _ => Some("unsupported")
  }
}

///|
fn pdf_image_encoded_samples(
  document : @pdflite.PdfDocument,
  decoded : @syntax.PdfObject,
) -> PdfImageDecodedSamples? raise @core.PdfError {
  let filter = pdf_image_remaining_filter(document, decoded).unwrap_or("")
  let filter = if filter.has_prefix("/") {
    filter[1:].to_owned()
  } else {
    filter
  }
  if filter == "JPXDecode" {
    let result = @jpx.decode(
      decoded.stream_bytes(),
      smask_in_data=pdf_image_sample_int(
        document, decoded, "/SMaskInData", "/SMaskInData", 0,
      ),
      use_embedded_colour=document.lookup_direct_or_else(
          pdf_image_name("/ColorSpace"),
          pdf_image_name("/CS"),
          decoded,
        )
        is None,
    )
    return match result {
      Ok(samples) =>
        Some({
          bytes: samples.bytes,
          width: samples.width,
          height: samples.height,
          bits: samples.bits,
          components: samples.components,
          row_bytes: samples.row_bytes,
          embedded_alpha: samples.embedded_alpha,
          embedded_alpha_bits: samples.embedded_alpha_bits,
          embedded_alpha_row_bytes: samples.embedded_alpha_row_bytes,
          embedded_alpha_associated: samples.embedded_alpha_associated,
          colour_hint: samples.colour_hint,
          embedded_icc_profile: samples.embedded_icc_profile,
        })
      Err(error) if error.contains("limit") ||
        error.contains("budget") ||
        error.contains("excessive") => raise @core.SoftError(error)
      Err(_) => None
    }
  }
  let parms = match
    document.lookup_direct_or_else(
      pdf_image_name("/DecodeParms"),
      pdf_image_name("/DP"),
      decoded,
    ) {
    Some(@syntax.PdfArray([value])) => Some(value)
    value => value
  }
  if filter == "JBIG2Decode" {
    let globals = match parms {
      Some(parms) =>
        match document.lookup_direct(pdf_image_name("/JBIG2Globals"), parms) {
          Some(object) =>
            Some(
              pdf_image_decode_stream(
                document,
                @syntax.pdf_dictionary([]),
                object,
                max_output=16777216,
              ).stream_bytes(),
            )
          None => None
        }
      None => None
    }
    let width = pdf_image_sample_int(document, decoded, "/Width", "/W", 0)
    let height = pdf_image_sample_int(document, decoded, "/Height", "/H", 0)
    let input_length = decoded.stream_bytes().length()
    let globals_length = match globals {
      Some(bytes) => bytes.length()
      None => 0
    }
    if width > 32768 ||
      height > 32768 ||
      input_length > 16777216 - globals_length {
      raise @core.SoftError(
        "JBIG2 dimensions or combined page/globals input exceed decode limits",
      )
    }
    return match
      pdf_jbig2_samples(decoded.stream_bytes(), globals, width, height) {
      Some(bytes) =>
        Some({
          bytes,
          width,
          height,
          bits: 1,
          components: 1,
          row_bytes: (width + 7) / 8,
          embedded_alpha: None,
          embedded_alpha_bits: 8,
          embedded_alpha_row_bytes: 0,
          embedded_alpha_associated: false,
          colour_hint: "Gray",
          embedded_icc_profile: None,
        })
      None => None
    }
  }
  if filter != "DCTDecode" && filter != "DCT" {
    return None
  }
  let transform = match parms {
    Some(parms) =>
      match document.lookup_direct(pdf_image_name("/ColorTransform"), parms) {
        Some(@syntax.PdfInteger(value)) => Some(value)
        _ => None
      }
    None => None
  }
  (pdf_jpeg_decode(decoded.stream_bytes(), transform) |> Some) catch {
    PdfJpegError::ResourceLimit =>
      raise @core.SoftError(
        "JPEG dimensions or coefficient storage exceed decode limits",
      )
    _ => None
  }
}

///|
fn PdfImageDecodedSamples::embedded_alpha_valid(
  self : PdfImageDecodedSamples,
) -> Bool {
  match self.embedded_alpha {
    None => !self.embedded_alpha_associated
    Some(alpha) =>
      self.embedded_alpha_bits >= 1 &&
      self.embedded_alpha_bits <= 16 &&
      self.embedded_alpha_row_bytes >=
      (self.width * self.embedded_alpha_bits + 7) / 8 &&
      self.embedded_alpha_row_bytes <= 67108864 / self.height &&
      alpha.length() >= self.embedded_alpha_row_bytes * self.height
  }
}

///|
fn PdfImageDecodedSamples::embedded_opacity(
  self : PdfImageDecodedSamples,
  x : Int,
  y : Int,
) -> Double {
  match self.embedded_alpha {
    None => 1.0
    Some(alpha) => {
      let row = alpha[y * self.embedded_alpha_row_bytes:(y + 1) *
        self.embedded_alpha_row_bytes]
      pdf_image_read_sample(
        row,
        x * self.embedded_alpha_bits,
        self.embedded_alpha_bits,
      ).to_double() /
      ((1 << self.embedded_alpha_bits) - 1).to_double()
    }
  }
}

///|
/// Packed monochrome scans may have more pixels than the final RGB surface.
/// Keep both a sample-plane byte budget and an independent decoded-pixel bound.
fn pdf_image_source_dimensions_allowed(
  width : Int,
  height : Int,
  components : Int,
  bits : Int,
) -> Bool {
  if width <= 0 ||
    height <= 0 ||
    width > 65535 ||
    height > 65535 ||
    components <= 0 ||
    components > 32 ||
    bits <= 0 ||
    bits > 16 ||
    width > 67108864 / height ||
    width > (67108864 - 7) / (components * bits) {
    return false
  }
  let stride = (width * components * bits + 7) / 8
  height <= 67108864 / stride
}

///|
/// Resizing happens before RGB/RGBA allocation, using the existing floor
/// nearest-neighbour sample rule. A narrow image also obeys the side limit.
fn pdf_image_draw_dimensions(width : Int, height : Int) -> (Int, Int) {
  let factor = (16777216.0 / (width.to_double() * height.to_double()))
    .sqrt()
    .min(16384.0 / width.to_double())
    .min(16384.0 / height.to_double())
    .min(1.0)
  (
    (width.to_double() * factor).floor().to_int().max(1),
    (height.to_double() * factor).floor().to_int().max(1),
  )
}

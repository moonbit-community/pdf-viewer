///|
/// Resolve an image XObject from a page and turn it into a browser data URL.
///
/// The PDF content walker intentionally gives us the resource name rather
/// than copying the stream into every display-list entry. Resolving here keeps
/// the page model self-contained while retaining a graceful placeholder for
/// image formats a browser cannot display.
fn pdf_image_resource_of(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
  name : StringView,
) -> PdfImageResource? {
  let xobject_name = pdf_image_name(name.to_owned())
  match document.lookup_direct(pdf_image_name("/XObject"), page.resources) {
    Some(xobjects) =>
      match document.lookup_direct(xobject_name, xobjects) {
        Some(xobject) =>
          try
            pdf_image_resource_of_object(
              document,
              page.resources,
              name.to_owned(),
              xobject,
            )
          catch {
            _ => None
          } noraise {
            resource => Some(resource)
          }
        None => None
      }
    None => None
  }
}

///|
fn pdf_image_resource_of_object(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : String,
  xobject : @syntax.PdfObject,
) -> PdfImageResource raise @core.PdfError {
  let width = pdf_image_dimension(document, xobject, "/Width")
  let height = pdf_image_dimension(document, xobject, "/Height")
  match document.get_image_24bpp(resources, xobject) {
    @pdflite.PdfJPEG(data, _) =>
      {
        name,
        mime_type: "image/jpeg",
        data_uri: Some(pdf_image_data_uri("image/jpeg", data)),
        width,
        height,
      }
    @pdflite.PdfJPEG2000(data, _) =>
      {
        name,
        mime_type: "image/jp2",
        data_uri: Some(pdf_image_data_uri("image/jp2", data)),
        width,
        height,
      }
    @pdflite.PdfJBIG2(data, _, _) =>
      {
        name,
        mime_type: "image/jbig2",
        data_uri: Some(pdf_image_data_uri("image/jbig2", data)),
        width,
        height,
      }
    @pdflite.PdfRawImage(raw_width, raw_height, layout, data) => {
      let png = pdf_png_of_raw_image(raw_width, raw_height, layout, data)
      {
        name,
        mime_type: "image/png",
        data_uri: Some(pdf_image_data_uri("image/png", png)),
        width: Some(raw_width),
        height: Some(raw_height),
      }
    }
  }
}

///|
fn pdf_image_name(text : String) -> @core.PdfName {
  let value = if text.has_prefix("/") { text } else { "/" + text }
  @core.pdf_name_of_bytes(@utf8.encode(value))
}

///|
fn pdf_image_dimension(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  key : String,
) -> Int? {
  match document.lookup_direct(pdf_image_name(key), object) {
    Some(@syntax.PdfInteger(value)) => Some(value)
    _ => None
  }
}

///|
fn pdf_image_data_uri(mime_type : String, data : Bytes) -> String {
  "data:" + mime_type + ";base64," + @base64.encode(data)
}

///|
/// Convert decoded PDF pixels to a simple PNG with filter type 0 scanlines.
/// This deliberately keeps the encoder small and deterministic; pdflite has
/// already handled PDF filters, colour spaces, predictors, and decode arrays.
fn pdf_png_of_raw_image(
  width : Int,
  height : Int,
  layout : @pdflite.PdfPixelLayout,
  data : Bytes,
) -> Bytes raise @core.PdfError {
  let pixels = pdf_png_rgb_pixels(width, height, layout, data)
  let scanlines : Array[Int] = Array(capacity=height * (width * 3 + 1))
  let mut position = 0
  for _ in 0..<height {
    scanlines.push(0)
    for _ in 0..<(width * 3) {
      scanlines.push(pixels[position])
      position += 1
    }
  }
  let compressed = @flate.pdf_flate_encode(
    @core.pdf_bytes_of_int_array(scanlines),
  )
  let output : Array[Int] = []
  pdf_png_append_signature(output)
  let header : Array[Int] = []
  for value in pdf_png_u32_bytes(width) {
    header.push(value)
  }
  for value in pdf_png_u32_bytes(height) {
    header.push(value)
  }
  header.push(8)
  header.push(2)
  header.push(0)
  header.push(0)
  header.push(0)
  pdf_png_append_chunk(output, [0x49, 0x48, 0x44, 0x52], header)
  pdf_png_append_chunk(
    output,
    [0x49, 0x44, 0x41, 0x54],
    @core.pdf_int_array_of_bytes(compressed),
  )
  pdf_png_append_chunk(output, [0x49, 0x45, 0x4e, 0x44], [])
  @core.pdf_bytes_of_int_array(output)
}

///|
fn pdf_png_rgb_pixels(
  width : Int,
  height : Int,
  layout : @pdflite.PdfPixelLayout,
  data : Bytes,
) -> Array[Int] raise @core.PdfError {
  let pixel_count = width * height
  let output : Array[Int] = Array(capacity=pixel_count * 3)
  match layout {
    @pdflite.PdfBPP24 => {
      if data.length() < pixel_count * 3 {
        raise @core.PdfError::EndOfInput
      }
      for index in 0..<(pixel_count * 3) {
        output.push(data[index].to_int())
      }
    }
    @pdflite.PdfBPP8 => {
      if data.length() < pixel_count {
        raise @core.PdfError::EndOfInput
      }
      for index in 0..<pixel_count {
        let value = data[index].to_int()
        output.push(value)
        output.push(value)
        output.push(value)
      }
    }
    @pdflite.PdfBPP1 => {
      let row_bytes = (width + 7) / 8
      if data.length() < row_bytes * height {
        raise @core.PdfError::EndOfInput
      }
      for y in 0..<height {
        for x in 0..<width {
          let packed = data[y * row_bytes + x / 8].to_int()
          let bit = (packed >> (7 - x % 8)) & 1
          let value = if bit == 0 { 255 } else { 0 }
          output.push(value)
          output.push(value)
          output.push(value)
        }
      }
    }
    @pdflite.PdfBPP48 => {
      if data.length() < pixel_count * 6 {
        raise @core.PdfError::EndOfInput
      }
      for index in 0..<pixel_count {
        let offset = index * 6
        output.push(data[offset].to_int())
        output.push(data[offset + 2].to_int())
        output.push(data[offset + 4].to_int())
      }
    }
  }
  output
}

///|
fn pdf_png_u32_bytes(value : Int) -> Array[Int] {
  [(value >> 24) & 255, (value >> 16) & 255, (value >> 8) & 255, value & 255]
}

///|
fn pdf_png_append_signature(output : Array[Int]) -> Unit {
  for value in [137, 80, 78, 71, 13, 10, 26, 10] {
    output.push(value)
  }
}

///|
fn pdf_png_append_chunk(
  output : Array[Int],
  kind : ArrayView[Int],
  data : ArrayView[Int],
) -> Unit {
  for value in pdf_png_u32_bytes(data.length()) {
    output.push(value)
  }
  for value in kind {
    output.push(value)
  }
  for value in data {
    output.push(value)
  }
  let crc = pdf_png_crc32(kind, data)
  for value in pdf_png_u32_bytes(crc) {
    output.push(value)
  }
}

///|
fn pdf_png_crc32(kind : ArrayView[Int], data : ArrayView[Int]) -> Int {
  let mut crc : UInt = 0xFFFFFFFFU
  for value in kind {
    crc = pdf_png_crc32_byte(crc, value)
  }
  for value in data {
    crc = pdf_png_crc32_byte(crc, value)
  }
  (crc ^ 0xFFFFFFFFU).reinterpret_as_int()
}

///|
fn pdf_png_crc32_byte(crc : UInt, value : Int) -> UInt {
  let mut current = crc ^ value.reinterpret_as_uint()
  for _ in 0..<8 {
    current = if (current & 1U) == 1U {
      (current >> 1) ^ 0xEDB88320U
    } else {
      current >> 1
    }
  }
  current
}

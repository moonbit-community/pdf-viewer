///|
test "image Flate expansion stops at caller limit using existing streaming decoder" {
  let bytes = @flate.pdf_flate_encode(Bytes::make(100000, b'\x00'))
  assert_true(
    try {
      ignore(pdf_image_inflate_limited(bytes, 99999))
      false
    } catch {
      @core.PdfError::FlateOutputLimitExceeded(99999) => true
      _ => false
    },
  )
  assert_eq(pdf_image_inflate_limited(bytes, 100000).length(), 100000)
}

///|
test "final raw Flate consumes a bounded image prefix instead of trailing expansion" {
  let bytes = @flate.pdf_flate_encode(Bytes::make(100000, b'\xFF'))
  let page = annotation_test_page(
    [],
    resources="<< /XObject << /Im1 5 0 R >> >>",
    contents="/Im1 Do",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /Filter [/ASCIIHexDecode /FlateDecode]",
        type1_test_bytes_hex(bytes) + ">",
      ),
    ],
  )
  guard page.items is [Image({ resource: Some(resource), .. }), ..] else {
    fail("failed image diagnostic missing")
  }
  assert_eq(resource.error, None)
  assert_eq(colour_image_scanlines(resource), [0, 255, 255, 255])
}

///|
test "image expanding filter preflights enforce exact boundaries" {
  pdf_image_runlength_preflight(b"\xFD\x41\x80", 4)
  assert_true(
    try {
      pdf_image_runlength_preflight(b"\xFD\x41\x80", 3)
      false
    } catch {
      @core.PdfError::FlateOutputLimitExceeded(3) => true
      _ => false
    },
  )
  pdf_image_ascii85_preflight(b"zz~>", 8)
  assert_true(
    try {
      pdf_image_ascii85_preflight(b"zz~>", 7)
      false
    } catch {
      @core.PdfError::FlateOutputLimitExceeded(7) => true
      _ => false
    },
  )
  // Nine-bit codes: Clear, 'A', nextCode258='AA',259='AAA', EOD.
  let lzw = b"\x80\x10\x60\x50\x38\x08"
  pdf_image_lzw_preflight(lzw, 6, 1)
  assert_true(
    try {
      pdf_image_lzw_preflight(lzw, 5, 1)
      false
    } catch {
      @core.PdfError::FlateOutputLimitExceeded(5) => true
      _ => false
    },
  )
}

///|
test "image None Separation yields transparent pixels" {
  let resource = colour_image_fixture(
    "[/Separation /None /DeviceRGB << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >>]",
    8, "80",
  )
  let samples = colour_image_scanlines(resource)
  assert_eq(samples.length(), 5)
  assert_eq(samples[4], 0)
}

///|
test "large packed scans resize before RGB allocation" {
  assert_true(pdf_image_source_dimensions_allowed(5188, 6930, 1, 1))
  let (w, h) = pdf_image_draw_dimensions(5188, 6930)
  assert_true(w * h <= 16777216)
  assert_true(w < 5188 && h < 6930)
  let document = @pdflite.pdf_document_empty()
  let object = @syntax.pdf_stream(
    @syntax.pdf_dictionary([(pdf_image_name("/Length"), @syntax.PdfInteger(0))]),
    StreamGot(b""),
  )
  let samples : PdfImageDecodedSamples = {
    bytes: Bytes::make(4096, b'\xAA'),
    width: 32768,
    height: 1,
    bits: 1,
    components: 1,
    row_bytes: 4096,
    embedded_alpha: None,
    embedded_alpha_bits: 8,
    embedded_alpha_row_bytes: 0,
    embedded_alpha_associated: false,
    colour_hint: "Gray",
    embedded_icc_profile: None,
  }
  guard pdf_image_colour_png(
      document,
      @syntax.pdf_dictionary([]),
      object,
      decoded_samples=Some(samples),
    )
    is Some((16384, 1, png, false)) else {
    fail("large packed source did not resize")
  }
  let data = @flate.pdf_flate_decode(@pdflite.pdf_read_png(png).idat)
  assert_eq(data.length(), 16384 * 3 + 1)
  // Every output cell includes one black and one white source sample.
  assert_eq(data[1], b'\x80')
  assert_eq(data[data.length() - 1], b'\x80')
}

///|
test "bounded filter chain accepts a smaller caller budget for profiles" {
  let bytes = @flate.pdf_flate_encode(Bytes::make(100000, b'\x00'))
  let object = @syntax.pdf_stream(
    @syntax.pdf_dictionary([
      (pdf_image_name("/Length"), @syntax.PdfInteger(bytes.length())),
      (
        pdf_image_name("/Filter"),
        @syntax.PdfNameObject(pdf_image_name("/FlateDecode")),
      ),
    ]),
    StreamGot(bytes),
  )
  assert_true(
    try {
      ignore(
        pdf_image_decode_stream(
          @pdflite.pdf_document_empty(),
          @syntax.pdf_dictionary([]),
          object,
          max_output=1024,
        ),
      )
      false
    } catch {
      @core.PdfError::FlateOutputLimitExceeded(1024) => true
      _ => false
    },
  )
}

///|
test "real malformed stencil-sized Flate keeps only required image prefix" {
  // issue17147.pdf has a 504x480 1-bit ImageMask with a 24-times-longer
  // all-zero stream. PDF.js reads the image prefix rather than requiring EOF.
  let bytes = @flate.pdf_flate_encode(Bytes::make(725760, b'\x00'))
  let object = image_ink_stream(
    [
      (pdf_image_name("/Width"), @syntax.PdfInteger(504)),
      (pdf_image_name("/Height"), @syntax.PdfInteger(480)),
      (pdf_image_name("/BitsPerComponent"), @syntax.PdfInteger(1)),
      (pdf_image_name("/ImageMask"), @syntax.PdfBoolean(true)),
      (
        pdf_image_name("/Filter"),
        @syntax.PdfNameObject(pdf_image_name("/FlateDecode")),
      ),
    ],
    bytes,
  )
  let document = @pdflite.pdf_document_empty()
  let decoded = pdf_image_decode_stream(
    document,
    @syntax.pdf_dictionary([]),
    object,
  )
  assert_eq(decoded.stream_bytes().length(), 30720)
  let resource = pdf_image_resource_of_object(
    document,
    @syntax.pdf_dictionary([]),
    "Im",
    object,
  )
  assert_eq(resource.error, None)
  assert_true(resource.mask_data_uri is Some(_))
}

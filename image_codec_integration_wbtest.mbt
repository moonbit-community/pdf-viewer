// Pinned Mozilla PDF.js fixture, Apache-2.0, revision
// 89b500f5e1d98ed89bb90211e45b28730b2d99ac, jpx_smaskindata.pdf.

///|
test "JPX real PDF embedded alpha and Matte integrate once into PNG resources" {
  let viewer = open_document(
    @base64.decode(
      "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",
    ),
  )
  guard viewer.page(1) is Some(page) else { fail("missing JPX page") }
  let images = page.items.filter_map(item => {
    match item {
      Image({ resource: Some(resource), .. }) => Some(resource)
      _ => None
    }
  })
  assert_eq(images.length(), 4)
  let expected = [
    [0, 255, 255, 255, 128, 255, 255, 255, 0],
    [0, 255, 0, 0, 128, 0, 0, 200, 255],
    [0, 255, 255, 255, 128, 255, 255, 255, 0],
    [0, 255, 0, 0, 128, 0, 255, 0, 255],
  ]
  for i, image in images {
    assert_eq(image.error, None)
    assert_eq(image.alpha_mask_data_uri, None)
    assert_eq(colour_image_scanlines(image), expected[i])
  }
}

///|
test "JPX embedded associated Matte is removed in component space" {
  let document = @pdflite.pdf_document_empty()
  let object = @syntax.pdf_stream(
    @syntax.pdf_dictionary([
      (pdf_image_name("/Length"), @syntax.PdfInteger(0)),
      (
        pdf_image_name("/Matte"),
        @syntax.PdfArray([
          @syntax.PdfInteger(0),
          @syntax.PdfInteger(1),
          @syntax.PdfInteger(0),
        ]),
      ),
    ]),
    StreamGot(b""),
  )
  let samples : PdfImageDecodedSamples = {
    bytes: b"\x80\xC0\x80",
    width: 1,
    height: 1,
    bits: 8,
    components: 3,
    row_bytes: 3,
    embedded_alpha: Some(b"\x80"),
    embedded_alpha_bits: 8,
    embedded_alpha_row_bytes: 1,
    embedded_alpha_associated: true,
    colour_hint: "RGB",
    embedded_icc_profile: None,
  }
  guard pdf_image_colour_png(
      document,
      @syntax.pdf_dictionary([]),
      object,
      decoded_samples=Some(samples),
    )
    is Some((1, 1, png, true)) else {
    fail("missing associated Matte PNG")
  }
  assert_eq(
    @core.pdf_int_array_of_bytes(
      @flate.pdf_flate_decode(@pdflite.pdf_read_png(png).idat),
    ),
    [0, 255, 129, 255, 128],
  )
}

///|
#cfg(target="native")
test "JBIG2 resource explicit mask Decode preserves stencil polarity once" {
  let black = b"\x00\x00\x00\x01\x30\x00\x01\x00\x00\x00\x13\x00\x00\x00\x09\x00\x00\x00\x02\x00\x00\x00\x48\x00\x00\x00\x48\x04\x00\x00"
  let white = b"\x00\x00\x00\x01\x30\x00\x01\x00\x00\x00\x13\x00\x00\x00\x09\x00\x00\x00\x02\x00\x00\x00\x48\x00\x00\x00\x48\x00\x00\x00"
  let page = annotation_test_page(
    [],
    resources="<< /XObject << /Im1 5 0 R >> >>",
    contents="/Im1 Do",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Image /Width 9 /Height 2 /BitsPerComponent 1 /ColorSpace /DeviceGray /Filter [/ASCIIHexDecode /JBIG2Decode] /Mask 6 0 R",
        type1_test_bytes_hex(black) + ">",
      ),
      annotation_test_stream(
        "/Type /XObject /Subtype /Image /Width 9 /Height 2 /ImageMask true /Filter [/ASCIIHexDecode /JBIG2Decode] /Decode [1 0]",
        type1_test_bytes_hex(white) + ">",
      ),
    ],
  )
  guard page.items is [Image({ resource: Some(image), .. }), ..] else {
    fail("missing JBIG2 resource")
  }
  assert_eq(image.error, None)
  assert_eq(image.alpha_mask_data_uri, None)
  let pixels = colour_image_scanlines(image)
  for y in 0..<2 {
    for x in 0..<9 {
      let i = y * 37 + x * 4 + 1
      assert_eq(pixels[i:i + 4], [0, 0, 0, 255][:])
    }
  }
}

///|
#cfg(target="native")
test "JBIG2 standalone ImageMask emits a decoded stencil PNG" {
  let black = b"\x00\x00\x00\x01\x30\x00\x01\x00\x00\x00\x13\x00\x00\x00\x09\x00\x00\x00\x02\x00\x00\x00\x48\x00\x00\x00\x48\x04\x00\x00"
  let page = annotation_test_page(
    [],
    resources="<< /XObject << /Im1 5 0 R >> >>",
    contents="1 0 0 rg /Im1 Do",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Image /Width 9 /Height 2 /ImageMask true /Filter [/ASCIIHexDecode /JBIG2Decode]",
        type1_test_bytes_hex(black) + ">",
      ),
    ],
  )
  guard page.items is [Image({ resource: Some(image), .. }), ..] else {
    fail("missing JBIG2 stencil")
  }
  assert_eq(image.error, None)
  assert_eq(image.data_uri, None)
  guard image.mask_data_uri is Some(uri) else {
    fail("missing stencil mask PNG")
  }
  let png = @pdflite.pdf_read_png(@base64.decode(uri[22:]))
  let data = @flate.pdf_flate_decode(png.idat)
  assert_eq(data.length(), 56)
  assert_eq(data[1], b'\xFF')
  assert_eq(data[19], b'\xFF')
}

///|
test "JPX allocation rejection cannot escape through an encoded browser fallback" {
  let data = b"\xFF\x4F\xFF\x51\x00\x29\x00\x00\x00\x40\x00\x01\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x40\x00\x01\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x01\x07\x01\x01"
  let page = annotation_test_page(
    [],
    resources="<< /XObject << /Im1 5 0 R >> >>",
    contents="/Im1 Do",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Image /Width 1 /Height 1 /Filter [/ASCIIHexDecode /JPXDecode]",
        type1_test_bytes_hex(data) + ">",
      ),
    ],
  )
  guard page.items is [Image({ resource: Some(image), .. }), ..] else {
    fail("missing rejected JPX diagnostic")
  }
  assert_true(image.error is Some(error) && error.contains("decode limits"))
  assert_eq(image.data_uri, None)
}

///|
test "JBIG2 adapter-specific bounds cannot escape through encoded fallback" {
  let page = annotation_test_page(
    [],
    resources="<< /XObject << /Im1 5 0 R >> >>",
    contents="/Im1 Do",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Image /Width 32769 /Height 1 /BitsPerComponent 1 /ColorSpace /DeviceGray /Filter /JBIG2Decode",
        "invalid",
      ),
    ],
  )
  guard page.items is [Image({ resource: Some(image), .. }), ..] else {
    fail("missing JBIG2 rejection")
  }
  assert_true(image.error is Some(error) && error.contains("decode limits"))
  assert_eq(image.data_uri, None)
}

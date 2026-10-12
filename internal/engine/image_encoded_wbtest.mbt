///|
fn jpeg_resource_fixture(
  bytes : Bytes,
  extra? : String = "",
  space? : String = "/DeviceRGB",
  mask? : (String, String)? = None,
) -> (PdfPageModel, PdfImageResource) raise {
  let streams = [
    annotation_test_stream(
      "/Type /XObject /Subtype /Image /Width 17 /Height 13 /BitsPerComponent 8 " +
      "/ColorSpace \{space} /Filter [/ASCIIHexDecode /DCTDecode] \{extra}",
      type1_test_bytes_hex(bytes) + ">",
    ),
  ]
  match mask {
    Some((dictionary, data)) =>
      streams.push(annotation_test_stream(dictionary, data))
    None => ()
  }
  let page = annotation_test_page(
    [],
    resources="<< /XObject << /Im1 5 0 R >> >>",
    contents="q 170 0 0 130 0 0 cm /Im1 Do Q",
    extra=streams,
  )
  guard page.items is [Image({ resource: Some(resource), .. }), ..] else {
    fail("missing JPEG image resource")
  }
  (page, resource)
}

///|
test "encoded JPEG PNG integration applies Decode and original colour-key ranges" {
  let bytes = jpeg_sample_fixture("rgb444")
  let samples = pdf_jpeg_decode(bytes, Some(0))
  let key = "\{samples.bytes[0].to_int()} \{samples.bytes[0].to_int()} \{samples.bytes[1].to_int()} \{samples.bytes[1].to_int()} \{samples.bytes[2].to_int()} \{samples.bytes[2].to_int()}"
  let (_, resource) = jpeg_resource_fixture(
    bytes,
    extra="/DecodeParms [null << /ColorTransform 0 >>] /Decode [1 0 1 0 1 0] /Mask [\{key}]",
  )
  assert_eq(resource.mime_type, "image/png")
  let data = colour_image_scanlines(resource)
  assert_eq(data[1], 255 - samples.bytes[0].to_int())
  assert_eq(data[2], 255 - samples.bytes[1].to_int())
  assert_eq(data[3], 255 - samples.bytes[2].to_int())
  assert_eq(data[4], 0)
  assert_true(data[8] == 255)
}

///|
test "encoded grayscale SMask and Matte integrate exactly once" {
  let jpeg = jpeg_sample_fixture("rgb_progressive_restart")
  let mask = jpeg_sample_fixture("gray_progressive")
  let samples = pdf_jpeg_decode(jpeg, None)
  let opacity = pdf_jpeg_decode(mask, None)
  let (page, resource) = jpeg_resource_fixture(
    jpeg,
    extra="/SMask 6 0 R",
    mask=Some(
      (
        "/Type /XObject /Subtype /Image /Width 17 /Height 13 /BitsPerComponent 8 /ColorSpace /DeviceGray /Filter [/ASCIIHexDecode /DCTDecode] /Decode [1 0] /Matte [1 1 1]",
        type1_test_bytes_hex(mask) + ">",
      ),
    ),
  )
  let scanlines = colour_image_scanlines(resource)
  for y in 0..<13 {
    for x in 0..<17 {
      let pixel = y * 17 + x
      let start = y * (17 * 4 + 1) + 1 + x * 4
      let alpha = 255 - opacity.bytes[pixel].to_int()
      assert_eq(scanlines[start + 3], alpha)
      for c in 0..<3 {
        assert_eq(
          scanlines[start + c],
          pdf_image_unblend_component(
            samples.bytes[pixel * 3 + c].to_int(),
            255,
            alpha,
          ),
        )
      }
    }
  }
  assert_eq(resource.alpha_mask_data_uri, None)
  assert_eq(resource.alpha_mask_width, None)
  assert_true(!page.render_svg().contains("pdf-alpha-mask-inner"))
}

///|
test "encoded CMYK retains four samples through PDF Decode and colour conversion" {
  let bytes = jpeg_sample_fixture("cmyk_progressive")
  let samples = pdf_jpeg_decode(bytes, None)
  let (_, resource) = jpeg_resource_fixture(
    bytes,
    space="/DeviceCMYK",
    extra="/Decode [1 0 1 0 1 0 1 0]",
  )
  let output = colour_image_scanlines(resource)
  let raw = colour_image_fixture(
    "/DeviceCMYK",
    8,
    type1_test_bytes_hex(samples.bytes),
    width=17,
    height=13,
    extra="/Decode [1 0 1 0 1 0 1 0]",
  )
  assert_eq(output, colour_image_scanlines(raw))
}

///|
test "JPEG truncation malformed metadata and allocation limits fail without traps" {
  for name in ["rgb444", "rgb_progressive", "rgb_restart"] {
    let bytes = jpeg_sample_fixture(name)
    for length in 0..<bytes.length() {
      let result = try {
        ignore(pdf_jpeg_decode(bytes[:length].to_owned(), None))
        false
      } catch {
        _ => true
      }
      assert_true(result, msg="\{name} accepted truncated prefix \{length}")
    }
  }
  for
    bytes in [
      b"\xFF\xD8\xFF\xDB\x00\x00", b"\xFF\xD8\xFF\xDB\x00\x03\xFF", b"\xFF\xD8\xFF\xC4\x00\x03\xFF",
    ] {
    assert_true(
      try {
        ignore(pdf_jpeg_decode(bytes, None))
        false
      } catch {
        _ => true
      },
    )
  }
  assert_true(pdf_image_dimensions_allowed(2996, 4256, 4))
  assert_true(!pdf_image_dimensions_allowed(65535, 65535, 4))
  assert_true(!pdf_image_dimensions_allowed(2147483647, 2, 1))
  assert_true(!pdf_image_dimensions_allowed(1, 1, 33))
  let bytes = jpeg_sample_fixture("rgb444")
  let oversized = Bytes::makei(bytes.length(), i => {
    if i >= 163 && i <= 166 {
      b'\xFF'
    } else {
      bytes[i]
    }
  })
  assert_true(
    try {
      ignore(pdf_jpeg_decode(oversized, None))
      false
    } catch {
      PdfJpegError::ResourceLimit => true
      _ => false
    },
  )
}

///|
test "encoded packed samples span byte boundaries without losing integer domain" {
  let bytes = b"\x00\x0A\xBC\xFF\xF0"
  assert_eq(pdf_image_read_sample(bytes[:], 0, 12), 0)
  assert_eq(pdf_image_read_sample(bytes[:], 12, 12), 0xABC)
  assert_eq(pdf_image_read_sample(bytes[:], 24, 12), 4095)
  for bits in 1..<=16 {
    let bytes = b"\xAA\xAA\xAA\xAA\xAA"
    for offset in 0..<8 {
      let mut expected = 0
      for i in 0..<bits {
        expected = (expected << 1) | (if (i + offset) % 2 == 0 { 1 } else { 0 })
      }
      assert_eq(pdf_image_read_sample(bytes[:], offset, bits), expected)
    }
  }
}

///|
test "encoded associated alpha unpremultiplies components once before colour conversion" {
  let document = @pdflite.pdf_document_empty()
  let resources = @syntax.pdf_dictionary([])
  let object = @syntax.pdf_stream(
    @syntax.pdf_dictionary([(pdf_image_name("/Length"), @syntax.PdfInteger(0))]),
    StreamGot(b""),
  )
  let samples : PdfImageDecodedSamples = {
    bytes: b"\x40\x20\x00\x00\x00\x00",
    width: 2,
    height: 1,
    bits: 8,
    components: 3,
    row_bytes: 6,
    embedded_alpha: Some(b"\x80\x00"),
    embedded_alpha_bits: 8,
    embedded_alpha_row_bytes: 2,
    embedded_alpha_associated: true,
    colour_hint: "RGB",
    embedded_icc_profile: None,
  }
  guard pdf_image_colour_png(
      document,
      resources,
      object,
      decoded_samples=Some(samples),
    )
    is Some((2, 1, png, true)) else {
    fail("embedded alpha was not integrated")
  }
  let scanlines = @core.pdf_int_array_of_bytes(
    @flate.pdf_flate_decode(@pdflite.pdf_read_png(png).idat),
  )
  assert_eq(scanlines, [0, 128, 64, 0, 128, 255, 255, 255, 0])
  assert_true(samples.embedded_alpha_valid())
  let malformed = { ..samples, embedded_alpha_row_bytes: 1, }
  assert_true(!malformed.embedded_alpha_valid())
}

///|
test "encoded twelve bit colour-key compares original samples before Decode" {
  let document = @pdflite.pdf_document_empty()
  let resources = @syntax.pdf_dictionary([])
  let object = @syntax.pdf_stream(
    @syntax.pdf_dictionary([
      (pdf_image_name("/Length"), @syntax.PdfInteger(0)),
      (
        pdf_image_name("/Decode"),
        @syntax.PdfArray([@syntax.PdfInteger(1), @syntax.PdfInteger(0)]),
      ),
      (
        pdf_image_name("/Mask"),
        @syntax.PdfArray([@syntax.PdfInteger(2748), @syntax.PdfInteger(2748)]),
      ),
    ]),
    StreamGot(b""),
  )
  let samples : PdfImageDecodedSamples = {
    bytes: b"\x00\x0A\xBC\xFF\xF0",
    width: 3,
    height: 1,
    bits: 12,
    components: 1,
    row_bytes: 5,
    embedded_alpha: None,
    embedded_alpha_bits: 8,
    embedded_alpha_row_bytes: 0,
    embedded_alpha_associated: false,
    colour_hint: "Gray",
    embedded_icc_profile: None,
  }
  guard pdf_image_colour_png(
      document,
      resources,
      object,
      decoded_samples=Some(samples),
    )
    is Some((3, 1, png, false)) else {
    fail("twelve bit samples failed")
  }
  let scanlines = @core.pdf_int_array_of_bytes(
    @flate.pdf_flate_decode(@pdflite.pdf_read_png(png).idat),
  )
  assert_eq(scanlines, [0, 255, 255, 255, 255, 84, 84, 84, 0, 0, 0, 0, 255])
}

///|
test "JPEG APP14 transform overrides DecodeParms and missing APP14 accepts ColorTransform" {
  let base = jpeg_sample_fixture("cmyk")
  // The fixture has APP14 at byte 2; transformCode is byte 17.
  assert_eq(base[3], b'\xEE')
  let ycck = Bytes::makei(base.length(), i => {
    if i == 17 {
      b'\x02'
    } else {
      base[i]
    }
  })
  let implicit = pdf_jpeg_decode(ycck, None)
  let explicit_zero = pdf_jpeg_decode(ycck, Some(0))
  assert_eq(implicit.bytes, explicit_zero.bytes)
  assert_true(implicit.bytes != pdf_jpeg_decode(base, None).bytes)
  let rgb = jpeg_sample_fixture("rgb444")
  assert_true(
    pdf_jpeg_decode(rgb, Some(0)).bytes != pdf_jpeg_decode(rgb, Some(1)).bytes,
  )
  let direct = jpeg_sample_fixture("rgb_direct")
  assert_eq(
    pdf_jpeg_decode(direct, None).bytes,
    pdf_jpeg_decode(direct, Some(1)).bytes,
  )
}

///|
test "image soft-mask transfer lookup has exactly 256 entries" {
  let document = @pdflite.pdf_document_empty()
  let function = @syntax.pdf_dictionary([
    (pdf_image_name("/FunctionType"), @syntax.PdfInteger(2)),
    (
      pdf_image_name("/Domain"),
      @syntax.PdfArray([@syntax.PdfInteger(0), @syntax.PdfInteger(1)]),
    ),
    (pdf_image_name("/N"), @syntax.PdfInteger(1)),
    (pdf_image_name("/C0"), @syntax.PdfArray([@syntax.PdfInteger(1)])),
    (pdf_image_name("/C1"), @syntax.PdfArray([@syntax.PdfInteger(0)])),
  ])
  let mask = @syntax.pdf_dictionary([(pdf_image_name("/TR"), function)])
  guard pdf_transfer_map_of_mask(document, mask) is Some(table) else {
    fail("missing transfer table")
  }
  assert_eq(table.length(), 256)
  assert_eq(table[0], 255)
  assert_eq(table[255], 0)
}

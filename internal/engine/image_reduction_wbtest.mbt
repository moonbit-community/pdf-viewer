///|
test "bounded binary scan reduction preserves all four stroke samples" {
  // A black pixel in any position must survive as 3/4 white, not vanish.
  for bytes in [b"\x40\xc0", b"\x80\xc0", b"\xc0\x40", b"\xc0\x80"] {
    assert_eq(pdf_image_gray_cell_coverage(bytes, 1, 2, 2, 0, 0, 2), 0.75)
  }
  assert_eq(pdf_image_gray_cell_coverage(b"\x00\x00", 1, 2, 2, 0, 0, 2), 0.0)
  assert_eq(pdf_image_gray_cell_coverage(b"\xff\xff", 1, 2, 2, 0, 0, 2), 1.0)
}

///|
test "binary reduction excludes padding and uses actual partial edge area" {
  assert_eq(
    pdf_image_gray_cell_coverage(b"\x20\x20\xff", 1, 3, 3, 0, 0, 2),
    0.0,
  )
  assert_eq(
    pdf_image_gray_cell_coverage(b"\x20\x20\xff", 1, 3, 3, 1, 0, 2),
    1.0,
  )
  assert_eq(
    pdf_image_gray_cell_coverage(b"\x20\x20\xff", 1, 3, 3, 0, 1, 2),
    1.0,
  )
  assert_eq(
    pdf_image_gray_cell_coverage(b"\x20\x20\xff", 1, 3, 3, 1, 1, 2),
    1.0,
  )
}

///|
test "binary scan cells obey display and retained component budgets" {
  assert_eq(
    pdf_image_gray_reduce_dimensions(5188, 6930, 3543, 4733),
    (2594, 3465, 2),
  )
  assert_eq(
    pdf_image_gray_reduce_dimensions(5188, 6930, 2300, 3100),
    (1297, 1733, 4),
  )
  assert_eq(pdf_image_gray_reduce_dimensions(7, 3, 7, 3), (7, 3, 1))
  assert_eq(pdf_image_gray_reduce_dimensions(32768, 1, 1000, 1), (512, 1, 64))
}

///|
test "oversized Gray image PNG and retained ink use coverage after Decode" {
  let document = @pdflite.pdf_document_empty()
  let bytes = FixedArray::make(8192, b'\xff')
  for i in 0..<4096 {
    bytes[i] = b'\x55'
  }
  let samples : PdfImageDecodedSamples = {
    bytes: Bytes::from_fixedarray(bytes),
    width: 32768,
    height: 2,
    bits: 1,
    components: 1,
    row_bytes: 4096,
    embedded_alpha: None,
    embedded_alpha_bits: 0,
    embedded_alpha_row_bytes: 0,
    embedded_alpha_associated: false,
    colour_hint: "Gray",
    embedded_icc_profile: None,
  }
  for
    (lower, upper, expected, expected_k) in [
      (0, 1, 191, 16384),
      (1, 0, 64, 49151),
      (-1, 1, 191, 16384),
      (2, -1, 64, 49151),
    ] {
    let object = @syntax.pdf_stream(
      @syntax.pdf_dictionary([
        (
          pdf_image_name("/ColorSpace"),
          @syntax.PdfNameObject(pdf_image_name("/DeviceGray")),
        ),
        (
          pdf_image_name("/Decode"),
          @syntax.PdfArray([
            @syntax.PdfInteger(lower),
            @syntax.PdfInteger(upper),
          ]),
        ),
      ]),
      StreamGot(b""),
    )
    let retained = Ref::new(None)
    guard pdf_image_colour_png(
        document,
        @syntax.pdf_dictionary([]),
        object,
        decoded_samples=Some(samples),
        ink_samples=Some(retained),
      )
      is Some((16384, 1, png, false)) else {
      fail("missing reduced binary scan")
    }
    let pixels = @flate.pdf_flate_decode(@pdflite.pdf_read_png(png).idat)
    assert_eq(pixels.length(), 16384 * 3 + 1)
    for i in 1..<pixels.length() {
      assert_eq(pixels[i].to_int(), expected)
    }
    guard retained.val is Some(ink) else {
      fail("missing scan source components")
    }
    assert_eq((ink.width, ink.height, ink.components), (16384, 1, 4))
    let components = @base64.decode(ink.data_base64)
    assert_eq(components[6].to_int(), expected_k >> 8)
    assert_eq(components[7].to_int(), expected_k & 255)
  }
}

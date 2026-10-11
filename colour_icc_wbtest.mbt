///|
test "ICC profile guards validate header component arity and tag bounds" {
  assert_true(pdf_icc_profile_valid(icc_test_srgb_matrix, 3))
  assert_true(pdf_icc_profile_valid(icc_test_gray_gamma22, 1))
  assert_true(pdf_icc_profile_valid(icc_test_cmyk, 4))
  assert_false(pdf_icc_profile_valid(icc_test_srgb_matrix, 4))
  assert_false(pdf_icc_profile_valid(b"not an ICC profile", 3))
  let corrupt = icc_test_srgb_matrix.to_array()
  corrupt[132 + 4] = b'\x7F'
  assert_false(pdf_icc_profile_valid(Bytes::from_array(corrupt), 3))
}

///|
test "ICC ranges clip samples without rescaling and recover malformed bounds" {
  let range = pdf_icc_ranges(3, [0.2, 0.8, 1.0, 0.0])
  assert_eq(range, [(0.2, 0.8), (0.0, 1.0), (0.0, 1.0)])
  assert_eq(pdf_icc_clip([-1.0, 0.5, 2.0], range), [0.2, 0.5, 1.0])
  let space = @pdflite.PdfICCBased(
    3,
    @pdflite.PdfDeviceCMYK,
    [0.2, 0.8],
    None,
    @syntax.PdfNull,
  )
  assert_eq(colour_test_hex(space, [-1.0, 0.5, 1.0]), "#3380FF")
}

///|
#cfg(target="native")
test "native LittleCMS transforms RGB Gray matrix and CMYK LUT profiles" {
  if !pdf_icc_engine_available() {
    assert_true(pdf_icc_transform(icc_test_rgb_gamma22, 3) is None)
    return
  }
  let rgb = pdf_icc_transform(icc_test_rgb_gamma22, 3).unwrap()
  let gray = pdf_icc_transform(icc_test_gray_gamma22, 1).unwrap()
  let cmyk = pdf_icc_transform(icc_test_cmyk, 4).unwrap()
  let (r, g, b) = (rgb.convert)([0.2, 0.5, 0.8])
  assert_true((r - 0.18627).abs() < 0.003)
  assert_true((g - 0.50387).abs() < 0.003)
  assert_true((b - 0.80491).abs() < 0.003)
  let (r, g, b) = (gray.convert)([0.5])
  assert_true((r - 0.50387).abs() < 0.003)
  assert_true((r - g).abs() < 0.001 && (r - b).abs() < 0.001)
  let (r, g, b) = (cmyk.convert)([0.2, 0.3, 0.4, 0.1])
  assert_true((r - 0.73129).abs() < 0.003)
  assert_true((g - 0.63175).abs() < 0.003)
  assert_true((b - 0.54293).abs() < 0.003)
}

///|
fn icc_test_stream(profile : Bytes, dictionary : String) -> String {
  let hex = StringBuilder()
  let digits = "0123456789ABCDEF"
  for byte in profile {
    hex.write_char(digits[byte.to_int() >> 4].to_char().unwrap())
    hex.write_char(digits[byte.to_int() & 15].to_char().unwrap())
  }
  hex.write_string(">")
  annotation_test_stream(
    dictionary + " /Filter /ASCIIHexDecode",
    hex.to_string(),
  )
}

///|
#cfg(target="native")
test "ICC matrix profile reaches paths text images Indexed and shading" {
  if !pdf_icc_engine_available() {
    return
  }
  let page = annotation_test_page(
    [],
    resources="<< /ColorSpace << /ICC [/ICCBased 5 0 R] /Pal [/Indexed [/ICCBased 5 0 R] 0 <3380CC>] >> " +
      "/Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> " +
      "/XObject << /Im 6 0 R >> /Shading << /S << /ShadingType 2 /ColorSpace /ICC /Coords [0 0 100 0] " +
      "/Extend [true true] /Function << /FunctionType 2 /Domain [0 1] /C0 [0.2 0.5 0.8] /C1 [0.2 0.5 0.8] /N 1 >> >> >> >>",
    contents="/ICC cs 0.2 0.5 0.8 sc 0 0 20 20 re f BT /F1 12 Tf 10 30 Td (A) Tj ET " +
      "/Im Do /Pal cs 0 sc 40 40 10 10 re f /S sh",
    extra=[
      icc_test_stream(icc_test_rgb_gamma22, "/N 3 /Alternate /DeviceRGB"),
      annotation_test_stream(
        "/Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /ICC /Filter /ASCIIHexDecode",
        "3380CC>",
      ),
    ],
  )
  guard page.items
    is [
      Path(path),
      Text(text),
      Image(image),
      Path(indexed),
      Shading(shading),
      ..,
    ] else {
    fail("ICC page consumers missing")
  }
  assert_eq(path.fill_color, "#3080CD")
  assert_eq(text.fill_color, path.fill_color)
  assert_eq(indexed.fill_color, "#3081CD")
  assert_eq(colour_image_scanlines(image.resource.unwrap()), [0, 48, 129, 205])
  assert_eq(shading.shading.unwrap().stops[0].color, path.fill_color)
}

///|
#cfg(target="native")
test "native ICC active resources are bounded and evicted references reopen safely" {
  if !pdf_icc_engine_available() {
    assert_eq(pdf_icc_active_count(), 0)
    return
  }
  clear_icc_transforms()
  let held : Array[PdfIccTransform] = []
  for i in 0..<12 {
    held.push(pdf_icc_engine_transform(icc_test_rgb_gamma22, 3, i % 4).unwrap())
    assert_true(pdf_icc_active_count() <= 8)
    assert_true(pdf_icc_allocated_bytes() <= 67108864)
  }
  let (r, _, _) = (held[0].convert)([0.2, 0.5, 0.8])
  assert_true((r - 0.18627).abs() < 0.003)
  assert_eq(pdf_icc_active_count(), 8)
  clear_icc_transforms()
  assert_eq(pdf_icc_active_count(), 0)
  assert_eq(pdf_icc_allocated_bytes(), 0)
  let (r, _, _) = (held[0].convert)([0.2, 0.5, 0.8])
  assert_true((r - 0.18627).abs() < 0.003)
  assert_eq(pdf_icc_active_count(), 1)
  clear_icc_transforms()
}

///|
#cfg(target="native")
test "native ICC rendering intent changes media-whitepoint handling" {
  if !pdf_icc_engine_available() {
    return
  }
  let relative = pdf_icc_transform(icc_test_gray_gamma22, 1, intent=1).unwrap()
  let absolute = pdf_icc_transform(icc_test_gray_gamma22, 1, intent=3).unwrap()
  let (_, _, rb) = (relative.convert)([0.5])
  let (_, _, ab) = (absolute.convert)([0.5])
  assert_true((rb - ab).abs() > 0.05)
}

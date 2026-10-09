///|
test "PDF text matrix preserves the baseline, rise, shear and horizontal scale" {
  let page = annotation_test_page(
    [],
    contents="2 0 0 3 5 7 cm BT /F1 10 Tf 50 Tz 2 Ts 1 0.5 0.25 1 20 30 Tm (Wi) Tj ET",
    resources="<< /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >>",
  )
  let text = page.text_content().items
  assert_eq(text.length(), 2)
  // CTM × text matrix × font-size/horizontal-scale/rise.
  assert_eq(text[0].glyph_transform, Some([10.0, 7.5, 5.0, 30.0, 46.0, 103.0]))
  guard text[1].glyph_transform is Some([a, b, c, d, _, _]) else {
    fail("second glyph matrix missing")
  }
  assert_eq([a, b, c, d], [10.0, 7.5, 5.0, 30.0])
  assert_true(text[0].advance_x > text[1].advance_x)
  let svg = pdf_render_page_svg(page, 1.0, 0)
  assert_true(svg.contains("transform=\"matrix(10 -7.5 -5 30 46 97)\""))
  assert_true(svg.contains("font-size=\"1\""))
  assert_true(svg.contains("dominant-baseline=\"alphabetic\""))
}

///|
test "FreeText appearance baseline remains inside the clipped BBox" {
  let page = annotation_test_page(
    ["<< /Subtype /FreeText /Rect [40 50 100 60] /AP << /N 6 0 R >> >>"],
    extra=[
      annotation_test_stream(
        "/BBox [0 0 60 10] /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >>",
        "0 0 1 rg BT /F1 9 Tf 1 2 Td (FreeText) Tj ET",
      ),
    ],
  )
  guard page.annotations[0].appearance is Some(appearance) else {
    fail("AP missing")
  }
  assert_true(appearance.svg.contains("transform=\"matrix(9 0 0 9 1 8)\""))
  assert_true(appearance.svg.contains("fill=\"#0000FF\""))
  assert_true(appearance.svg.contains("dominant-baseline=\"alphabetic\""))
  assert_true(!appearance.svg.contains("dominant-baseline=\"hanging\""))
}

///|
test "vertical CID text retains its origin offset and downward progression" {
  let page = annotation_test_page(
    [],
    contents="BT /F1 10 Tf 20 100 Td <00410042> Tj ET",
    resources="<< /Font << /F1 << /Type /Font /Subtype /Type0 /BaseFont /Vertical /Encoding /Identity-V /DescendantFonts [<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Vertical /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /DW 1000 /W [65 [1000 1000]] /W2 [65 [-1000 500 880 -1000 500 880]] /FontDescriptor << /FontBBox [0 -200 1000 800] /Ascent 800 /Descent -200 >> >>] >> >> >>",
  )
  let text = page.text_content().items
  assert_eq(text.length(), 2)
  for i, item in text {
    assert_true(item.vertical)
    guard item.glyph_transform is Some([a, b, c, d, x, y]) else {
      fail("vertical glyph transform missing")
    }
    assert_eq([a, b, c, d], [10.0, 0.0, 0.0, 10.0])
    assert_true((x - 15.0).abs() < 0.000001)
    assert_true((y - (91.2 - i.to_double() * 10.0)).abs() < 0.000001)
  }
}

///|
/// Minimal TrueType with a single rectangular glyph. It deliberately has no
/// relationship between its contour width and a PDF glyph advance width.
fn glyph_geometry_test_font() -> Bytes raise {
  let bytes : Array[Int] = Array::make(174, 0)
  fn u16(offset : Int, value : Int) -> Unit {
    bytes[offset] = (value >> 8) & 255
    bytes[offset + 1] = value & 255
  }
  fn u32(offset : Int, value : Int) -> Unit {
    u16(offset, value >> 16)
    u16(offset + 2, value)
  }
  u32(0, 0x00010000)
  u16(4, 4)
  for
    i, (tag, offset, length) in [
      ("head", 76, 54),
      ("maxp", 130, 6),
      ("loca", 136, 4),
      ("glyf", 140, 34),
    ] {
    for j, byte in @utf8.encode(tag) {
      bytes[12 + i * 16 + j] = byte.to_int()
    }
    u32(12 + i * 16 + 8, offset)
    u32(12 + i * 16 + 12, length)
  }
  u16(76 + 18, 1000)
  u16(130 + 4, 1)
  u16(138, 17)
  u16(140, 1)
  u16(146, 500)
  u16(148, 700)
  u16(150, 3)
  for i in 154..<158 {
    bytes[i] = 1
  }
  u16(160, 500)
  u16(164, -500)
  u16(170, 700)
  @core.pdf_bytes_of_int_array(bytes)
}

///|
test "TrueType outlines use the em transform without fitting the advance box" {
  let font = glyph_geometry_test_font()
  let matrix : @geometry.TransformMatrix = {
    a: 10.0,
    b: 0.0,
    c: 0.0,
    d: 10.0,
    e: 40.0,
    f: 60.0,
  }
  let path = pdf_viewer_ttf_outline_path(font, 0, matrix, 0.0, 0.0, 200.0)
  assert_eq(path, Some("M 40 140 L 45 140 L 45 133 L 40 133 L 40 140 Z"))
  // Rotating and scaling text changes the basis, not the glyph aspect ratio.
  let rotated : @geometry.TransformMatrix = {
    a: 0.0,
    b: 20.0,
    c: -20.0,
    d: 0.0,
    e: 40.0,
    f: 60.0,
  }
  assert_eq(
    pdf_viewer_ttf_outline_path(font, 0, rotated, 0.0, 0.0, 200.0),
    Some("M 40 140 L 40 130 L 26 130 L 26 140 L 40 140 Z"),
  )
}

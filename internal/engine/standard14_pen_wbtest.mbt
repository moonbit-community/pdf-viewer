///|
test "bundled Standard14 fills and independent pens reuse the same A1 glyph selector" {
  let local_matrix : @geometry.TransformMatrix = {
    a: 120.0,
    b: 12.0,
    c: 24.0,
    d: 42.0,
    e: 10.0,
    f: 30.0,
  }
  for face in standard14_test_faces() {
    let document = provenance_test_document(
      "q 1.1 .15 .2 .85 15 20 cm 3 w 0 J 0 j 4 M BT /F1 60 Tf 2 Tr 2 .2 .4 .7 10 30 Tm (A) Tj ET Q",
      font="<< /Type /Font /Subtype /Type1 /BaseFont /" + face.name() + " >>",
    )
    let page = document.page(1).unwrap()
    let item = text_stroke_test_item(page)
    let font = pdf_read_font_for_viewer(
      document.document,
      @syntax.PdfIndirect(5),
    )
    guard item.glyph_transform is Some([a, b, c, d, e, f]) else {
      fail("missing glyph transform")
    }
    let page_matrix : @geometry.TransformMatrix = { a, b, c, d, e, f, }
    let expected_fill = pdf_standard14_path_of_pdf_glyph(
      font,
      65,
      Some(page_matrix),
      0.0,
      0.0,
      200.0,
    )
    let expected_stroke = pdf_standard14_path_of_pdf_glyph(
      font,
      65,
      Some(local_matrix),
      0.0,
      0.0,
      0.0,
    )
    assert_true(expected_fill is Some(_))
    assert_true(expected_stroke is Some(_))
    assert_eq(item.fill_path, expected_fill)
    let stroke = item.stroke.unwrap()
    assert_eq(stroke.svg_path, expected_stroke)
    assert_eq(stroke.transform, [1.1, -0.15, -0.2, 0.85, 15.0, 180.0])
    assert_eq(stroke.line_width, 3.0)
    assert_eq(stroke.line_cap, 0)
    assert_eq(stroke.line_join, 0)
    assert_eq(stroke.miter_limit, 4.0)
    assert_eq(stroke.fallback_scale, None)
    assert_eq(stroke.unresolved, None)
    assert_eq(page.graphics_diagnostics(), [])
    assert_eq(page.text_diagnostics(), [])
  }
}

///|
test "bundled Standard14 paint paths follow text rendering modes" {
  for mode in 0..<8 {
    let document = provenance_test_document(
      "q 1.1 .15 .2 .85 15 20 cm 3 w BT /F1 60 Tf \{mode} Tr 2 .2 .4 .7 10 30 Tm (H) Tj ET Q",
    )
    let page = document.page(1).unwrap()
    let item = text_stroke_test_item(page)
    assert_eq(item.fill_path is Some(_), pdf_text_mode_fills(mode))
    assert_eq(item.stroke is Some(_), pdf_text_mode_strokes(mode))
    if item.stroke is Some(stroke) {
      assert_true(stroke.svg_path is Some(_))
      assert_eq(stroke.unresolved, None)
    }
    assert_eq(page.graphics_diagnostics(), [])
    assert_eq(page.text_diagnostics(), [])
  }
}

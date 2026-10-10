///|
test "missing CID descriptors recover text and widths without changing source objects" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream("", "BT /F1 10 Tf 20 100 Td <82A082A2> Tj ET"),
    "<< /Type /Font /Subtype /Type0 /BaseFont /MissingDescriptor /Encoding /90ms-RKSJ-H /DescendantFonts [6 0 R] >>",
    "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /MissingDescriptor /CIDSystemInfo << /Registry (Adobe) /Ordering (Japan1) /Supplement 2 >> /DW 1000 /W [843 [400] 845 [600]] >>",
  ])
  let before = document.document.lookup_object_or_null(6)
  assert_eq(before.lookup_immediate(pdf_name_key("/FontDescriptor")), None)
  let page = document.page(1).unwrap()
  let text = page.text_content().items
  assert_eq([ for item in text => item.text ], ["\u3042", "\u3044"])
  assert_eq([ for item in text => item.advance_x ], [4.0, 6.0])
  assert_eq(text[1].glyph_transform, Some([10.0, 0.0, 0.0, 10.0, 24.0, 100.0]))
  assert_eq(document.document.lookup_object_or_null(6), before)
  assert_true(pdf_render_page_svg(page, 1.0, 0).contains("\u3042"))
}

///|
test "partial simple font Widths recover valid entries and descriptor defaults" {
  for
    extra in [
      "/FirstChar 65 /LastChar 68 /Widths [400 (bad) 800]", "/FirstChar 65 /LastChar 66 /Widths [400 (bad) 800]",
    ] {
    let viewer = annotation_test_document([
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R " +
      "/Resources << /Font << /F1 5 0 R >> >> >>",
      annotation_test_stream("", "BT /F1 10 Tf 20 100 Td (ABCD) Tj ET"),
      "<< /Type /Font /Subtype /TrueType /BaseFont /Custom /Encoding /WinAnsiEncoding " +
      "/FontDescriptor 6 0 R \{extra} >>",
      "<< /Type /FontDescriptor /FontName /Custom /Flags 32 /FontBBox [0 -200 1000 800] " +
      "/Ascent 800 /Descent -200 /ItalicAngle 0 /StemV 80 /MissingWidth 250 >>",
    ])
    let before = viewer.document.lookup_object_or_null(5)
    let text = viewer.page(1).unwrap().text_content()
    assert_eq(text.text, "ABCD")
    assert_eq(text.items.map(item => item.advance_x), [4.0, 2.5, 8.0, 2.5])
    assert_eq(viewer.document.lookup_object_or_null(5), before)
  }
}

///|
test "missing Widths references and missing bounds do not discard a simple font page" {
  for extra in ["/FirstChar 32 /LastChar 32 /Widths 99 0 R", "/Widths [600]"] {
    let viewer = annotation_test_document([
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R " +
      "/Resources << /Font << /F1 5 0 R >> >> >>",
      annotation_test_stream("", "BT /F1 10 Tf 20 100 Td (A) Tj ET"),
      "<< /Type /Font /Subtype /Type1 /BaseFont /Custom /Encoding /WinAnsiEncoding " +
      "/FontDescriptor 6 0 R \{extra} >>",
      "<< /Type /FontDescriptor /FontName /Custom /Flags 32 /FontBBox [0 -200 1000 800] " +
      "/Ascent 800 /Descent -200 /ItalicAngle 0 /StemV 80 /MissingWidth 250 >>",
    ])
    let page = viewer.page(1).unwrap()
    assert_eq(page.text_content().text, "A")
    assert_eq(page.text_content().items[0].advance_x, 2.5)
    assert_true(page.render_svg().contains("A"))
  }
}

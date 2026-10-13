///|
#cfg(target="js")
extern "js" fn font_recovery_same_instance(
  left : @pdflite.PdfFont,
  right : @pdflite.PdfFont,
) -> Bool =
  #| (left, right) => left === right

///|
#cfg(target="js")
test "indirect font aliases share one page build and release with its context" {
  let viewer = type1_test_clip_document("")
  let context = pdf_resource_build_context()
  let first = pdf_read_font_for_viewer(
    viewer.document,
    @syntax.PdfIndirect(5),
    resource_context=Some(context),
  )
  let second = pdf_read_font_for_viewer(
    viewer.document,
    @syntax.PdfIndirect(5),
    resource_context=Some(context),
  )
  assert_true(font_recovery_same_instance(first, second))
  let other = pdf_read_font_for_viewer(
    viewer.document,
    @syntax.PdfIndirect(5),
    resource_context=Some(pdf_resource_build_context()),
  )
  assert_true(!font_recovery_same_instance(first, other))
  assert_eq(context.font_cache.length(), 1)
  // A full context still parses new fonts, without retaining more entries.
  context.font_cache.clear()
  for number in 100..<228 {
    context.font_cache[number] = first
  }
  let uncached = pdf_read_font_for_viewer(
    viewer.document,
    @syntax.PdfIndirect(5),
    resource_context=Some(context),
  )
  assert_eq(uncached, first)
  assert_true(!font_recovery_same_instance(first, uncached))
  assert_eq(context.font_cache.length(), 128)
  assert_true(!context.font_cache.contains(5))
}

///|
#cfg(target="js")
test "repeated Tf reuses its recovered font while changing text size" {
  let viewer = type1_test_clip_document("")
  let document = viewer.document
  let resources = document
    .lookup_direct(
      pdf_name_key("/Resources"),
      document.lookup_object_or_null(3),
    )
    .unwrap()
  let context = pdf_resource_build_context()
  let initial = @pdflite.pdf_content_initial_operator_state(0, 0, 200, 200)
  let (first, _) = pdf_apply_op_for_viewer(
    document,
    initial,
    resources,
    @content.Op_Tf(pdf_name_key("/F1"), 12.0),
    None,
    resource_context=Some(context),
  )
  let (second, _) = pdf_apply_op_for_viewer(
    document,
    first.state,
    resources,
    @content.Op_Tf(pdf_name_key("/F1"), 24.0),
    None,
    resource_context=Some(context),
  )
  assert_true(
    font_recovery_same_instance(
      first.state.text_state.current_font,
      second.state.text_state.current_font,
    ),
  )
  assert_eq(second.state.text_state.font_size, 24.0)
  assert_eq(second.state.text_state.font_cache.length(), 1)
}

///|
test "missing Tf always inherits the currently active font" {
  let page = annotation_test_page(
    [],
    contents="BT /F1 10 Tf /Missing 10 Tf 20 100 Td (A) Tj /F2 10 Tf /Missing 10 Tf (A) Tj /F1 20 Tf (A) Tj ET",
    resources="<< /Font << /F1 5 0 R /F2 6 0 R >> >>",
    extra=[
      "<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
    ],
  )
  let text = page.text_content().items
  assert_eq(text.length(), 3)
  assert_eq(text[0].advance_x, 6.0)
  assert_true((text[1].advance_x - 6.67).abs() < 0.000001)
  assert_eq(text[2].advance_x, 12.0)
}

///|
test "repeated Tf keeps same-named Form resources separate" {
  let page = annotation_test_page(
    [],
    contents="BT /F1 10 Tf 20 100 Td (A) Tj /F1 20 Tf (A) Tj ET /Fm Do BT /F1 10 Tf 20 80 Td (A) Tj ET",
    resources="<< /Font << /F1 5 0 R >> /XObject << /Fm 6 0 R >> >>",
    extra=[
      "<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>",
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 200 200] /Resources << /Font << /F1 7 0 R >> >>",
        "BT /F1 10 Tf 20 60 Td (A) Tj /F1 20 Tf (A) Tj ET",
      ),
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
    ],
  )
  let text = page.items.filter_map(item => {
    match item {
      Text(text) => Some(text)
      _ => None
    }
  })
  assert_eq(text.length(), 5)
  assert_eq(text[0].advance_x, 6.0)
  assert_eq(text[1].advance_x, 12.0)
  assert_true((text[2].advance_x - 6.67).abs() < 0.000001)
  assert_true((text[3].advance_x - 13.34).abs() < 0.000001)
  assert_eq(text[4].advance_x, 6.0)
}

///|
test "Form unmatched Q recovery cannot reuse an outer same-named font" {
  let page = annotation_test_page(
    [],
    contents="BT /F1 10 Tf 20 100 Td (A) Tj ET /Fm Do BT /F1 10 Tf 20 80 Td (A) Tj ET",
    resources="<< /Font << /F1 5 0 R >> /XObject << /Fm 6 0 R >> >>",
    extra=[
      "<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>",
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 200 200] /Resources << /Font << /F1 7 0 R >> >>",
        "BT /F1 10 Tf (A) Tj Q /F1 10 Tf (A) Tj ET",
      ),
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
    ],
  )
  let text = page.items.filter_map(item => {
    match item {
      Text(text) => Some(text)
      _ => None
    }
  })
  assert_eq(text.length(), 4)
  assert_eq(text[0].advance_x, 6.0)
  assert_true((text[1].advance_x - 6.67).abs() < 0.000001)
  assert_true((text[2].advance_x - 6.67).abs() < 0.000001)
  assert_eq(text[3].advance_x, 6.0)
}

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

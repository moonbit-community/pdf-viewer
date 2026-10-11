///|
test "resolved fill geometry reuses A1 path and leaves SVG and source intact" {
  let viewer = type1_test_clip_document(
    "q -2 .5 .2 1 150 20 cm BT /F1 20 Tf 10 20 Td (A) Tj ET Q",
  )
  guard viewer.page(1) is Some(page) else { fail("missing page") }
  let text = text_stroke_test_item(page)
  let path = text.fill_path.unwrap()
  assert_true(text.type3_outline.unwrap().contains(pdf_escape_xml(path)))
  assert_eq(text.stroke, None)
  assert_eq(page.text_layer().items.length(), 1)
  let plan = invisible_test_canvas_items(page)
  guard plan[0] is Object(fields) else { fail("missing paint") }
  assert_true(fields.get("text_svg") is Some(Null))
  assert_eq(text.text, "A")
  assert_true(
    pdf_render_page_svg(page, 1.0, 0).contains(
      "data-pdf-font-outline=\"type1\"",
    ),
  )
}

///|
test "native fill path only exists in visible non-Type3 fill modes" {
  for mode in 0..<8 {
    let viewer = type1_test_clip_document(
      "BT /F1 20 Tf \{mode} Tr 10 20 Td (A) Tj ET",
    )
    guard viewer.page(1) is Some(page) else { fail("missing page") }
    assert_eq(
      text_stroke_test_item(page).fill_path is Some(_),
      pdf_text_mode_fills(mode),
    )
  }
  let page = type3_scene_test_page("1000 0 d0 0 0 1000 1000 re f")
  assert_eq(text_stroke_test_item(page).fill_path, None)
}

///|
test "text fill and stroke patterns retain independent cells and stream base" {
  let page = annotation_test_page(
    [],
    contents="2 .2 .4 1 20 30 cm /Pattern cs /Fill scn /Pattern CS /Stroke SCN 2 w BT /F 20 Tf 2 Tr 10 20 Td (A) Tj ET",
    resources="<< /Font << /F << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> /Pattern << /Fill 5 0 R /Stroke 6 0 R >> >>",
    extra=[
      annotation_test_stream(
        "/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 8 8] /XStep 8 /YStep 8 /Matrix [2 0 0 2 5 7] /Resources << >>",
        "1 0 0 rg 0 0 4 8 re f",
      ),
      annotation_test_stream(
        "/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 6 6] /XStep 6 /YStep 6 /Resources << >>",
        "0 0 1 rg 0 0 6 3 re f",
      ),
    ],
  )
  let text = text_stroke_test_item(page)
  assert_eq(text.pattern.unwrap().matrix, [2, 0, 0, 2, 5, 7])
  assert_eq(text.stroke_pattern.unwrap().matrix, [1, 0, 0, 1, 0, 0])
  assert_eq(
    stroke_test_path(text.pattern.unwrap().tile_page.unwrap()).fill_color,
    "#FF0000",
  )
  assert_eq(
    stroke_test_path(text.stroke_pattern.unwrap().tile_page.unwrap()).fill_color,
    "#0000FF",
  )
  assert_true(
    !page.graphics_diagnostics().any(d => d.code == "PDF_TEXT_PATTERN_RESOURCE"),
  )
  let plan = invisible_test_canvas_items(page)
  guard plan[0] is Object(fields) else { fail("missing text") }
  assert_true(fields.get("pattern") is Some(Object(_)))
  assert_true(fields.get("stroke_pattern") is Some(Object(_)))
  // Pinned Standard14 glyphs now use independent native geometry masks.
  assert_true(text.fill_path is Some(path) && path != "")
  assert_true(text.stroke is Some({ svg_path: Some(path), .. }) && path != "")
  assert_true(fields.get("text_fill_svg") is Some(Null))
  assert_true(fields.get("text_stroke_svg") is Some(Null))
}

///|
test "text shading pattern uses enclosing page implicit scene" {
  let page = annotation_test_page(
    [],
    contents="/Pattern cs /P scn BT /F 20 Tf 10 20 Td (A) Tj ET",
    resources="<< /Font << /F << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> /Pattern << /P << /Type /Pattern /PatternType 2 /ExtGState << /ca .4 >> /Shading << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 200 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> /Extend [true true] >> >> >> >>",
  )
  let text = text_stroke_test_item(page)
  assert_true(text.pattern.unwrap().shading is Some(_))
  assert_true(page.canvas_plan().stringify().contains("pattern_plan"))
}

///|
test "invisible text does not build paint resources" {
  let page = annotation_test_page(
    [],
    contents="/Pattern cs /Missing scn BT /F 20 Tf 3 Tr (A) Tj ET",
    resources="<< /Font << /F << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >>",
  )
  let text = text_stroke_test_item(page)
  assert_eq(text.pattern, None)
  assert_eq(text.fill_path, None)
  assert_eq(invisible_test_canvas_items(page).length(), 0)
  assert_eq(page.text_layer().items.length(), 1)
}

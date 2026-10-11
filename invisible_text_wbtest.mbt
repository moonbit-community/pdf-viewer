///|
fn invisible_test_canvas_items(page : PdfPageModel) -> Array[Json] raise {
  guard page.canvas_plan() is Object(fields) else { fail("missing plan") }
  guard fields.get("items") is Some(Array(items)) else {
    fail("missing paint items")
  }
  items
}

///|
test "invisible embedded text keeps source selection and search without outlines" {
  let hidden_doc = type1_test_clip_document(
    "BT /F1 20 Tf 3 Tr 10 20 Td (AAA) Tj ET",
  )
  let visible_doc = type1_test_clip_document(
    "BT /F1 20 Tf 0 Tr 10 20 Td (AAA) Tj ET",
  )
  let hidden = hidden_doc.page(1).unwrap()
  let visible = visible_doc.page(1).unwrap()
  assert_eq(hidden.items.length(), 3)
  assert_eq(hidden.text, visible.text)
  assert_eq(hidden.text_layer(), visible.text_layer())
  for index in 0..<3 {
    let source = text_stroke_test_item(hidden, index~)
    let painted = text_stroke_test_item(visible, index~)
    assert_eq(source.type3_outline, None)
    assert_eq(source.stroke, None)
    assert_true(painted.type3_outline is Some(_))
    assert_eq(source.index, painted.index)
    assert_eq(source.charcode, painted.charcode)
    assert_eq(source.glyph_transform, painted.glyph_transform)
    assert_eq(source.quad, painted.quad)
    assert_eq(source.advance_x, painted.advance_x)
    assert_eq(source.advance_y, painted.advance_y)
  }
  let first = text_stroke_test_item(hidden)
  let last = text_stroke_test_item(hidden, index=2)
  assert_eq(
    hidden.select_text(first.index, 0, last.index, 1).unwrap().text,
    "AAA",
  )
  assert_eq(hidden_doc.search("AAA"), visible_doc.search("AAA"))
  assert_eq(invisible_test_canvas_items(hidden).length(), 0)
  let svg = hidden.render_svg()
  assert_true(!svg.contains("<text "))
  assert_true(!svg.contains("<path "))
}

///|
test "invisible fallback text does not suppress following visible text or paths" {
  let page = provenance_test_document(
      "BT /F1 20 Tf 10 20 Td 3 Tr (A) Tj 0 Tr (B) Tj ET 10 10 10 10 re f",
    )
    .with_font_fallbacks([
      { pdf_name: "/F1", family: "Test Host Sans", weight: None, style: None, },
    ])
    .page(1)
    .unwrap()
  let hidden = text_stroke_test_item(page)
  let visible = text_stroke_test_item(page, index=1)
  assert_true(hidden.index < visible.index)
  assert_eq(hidden.text_object_id, visible.text_object_id)
  assert_eq(page.text_layer().items.length(), 2)
  let paints = invisible_test_canvas_items(page)
  assert_eq(paints.length(), 2)
  let json = paints.to_json().stringify()
  assert_true(!json.contains("\"rendering_mode\":3"))
  assert_true(json.contains("\"rendering_mode\":0"))
  assert_true(page.render_svg().contains(">B</text>"))
  assert_true(!page.render_svg().contains(">A</text>"))
}

///|
test "invisible text optimization leaves Type 3 charproc lowering intact" {
  let page = annotation_test_page(
    [],
    contents="BT /F1 20 Tf 3 Tr 10 20 Td (A) Tj ET",
    resources="<< /Font << /F1 5 0 R >> >>",
    extra=[
      "<< /Type /Font /Subtype /Type3 /FontBBox [0 0 500 700] /FontMatrix [.001 0 0 .001 0 0] /FirstChar 65 /LastChar 65 /Widths [500] /Encoding << /Type /Encoding /Differences [65 /A] >> /CharProcs << /A 6 0 R >> /Resources << >> >>",
      annotation_test_stream("", "500 0 d0 0 0 400 700 re f"),
    ],
  )
  assert_true(text_stroke_test_item(page).type3_outline is Some(_))
  assert_eq(invisible_test_canvas_items(page).length(), 1)
  assert_true(page.render_svg().contains("data-pdf-type3"))
}

///|
test "clipping-only text still lowers glyph geometry and clips subsequent paint" {
  let doc = type1_test_clip_document(
    "BT /F1 20 Tf 7 Tr 10 20 Td (A) Tj ET 0 0 200 200 re f",
  )
  let page = doc.page(1).unwrap()
  assert_true(text_stroke_test_item(page).type3_outline is Some(_))
  assert_true(stroke_test_path(page).clip_path is Some(_))
  assert_eq(page.text_layer().items.length(), 1)
}

///|
test "Canvas outline fragments do not duplicate embedded font payloads" {
  let doc = type1_test_clip_document("BT /F1 20 Tf 10 20 Td (A) Tj ET")
  let outline = doc.page(1).unwrap()
  let fallback = provenance_test_document("BT /F1 20 Tf 10 20 Td (A) Tj ET")
    .with_font_fallbacks([
      { pdf_name: "/F1", family: "Test Host Sans", weight: None, style: None, },
    ])
    .page(1)
    .unwrap()
  let fonts = fallback.fonts.map(font => {
    ..font,
    data_uri: Some("data:font/ttf;base64,VGVzdA=="),
  })
  fonts.push({
    ..fonts[0],
    name: "/Unrelated",
    family: "unrelated-font",
    data_uri: Some("data:font/ttf;base64,VW51c2Vk"),
  })
  let outline_plan = invisible_test_canvas_items({ ..outline, fonts, })
    .to_json()
    .stringify()
  let fallback_plan = invisible_test_canvas_items({ ..fallback, fonts, })
    .to_json()
    .stringify()
  assert_true(!outline_plan.contains("VGVzdA=="))
  assert_true(!outline_plan.contains("@font-face"))
  assert_true(fallback_plan.contains("VGVzdA=="))
  assert_true(fallback_plan.contains("@font-face"))
  assert_true(!fallback_plan.contains("VW51c2Vk"))
  assert_true(!fallback_plan.contains("unrelated-font"))
}

///|
test "Canvas native text pens do not serialize a redundant SVG fragment" {
  let doc = type1_test_clip_document("2 w BT /F1 20 Tf 2 Tr 10 20 Td (A) Tj ET")
  let page = doc.page(1).unwrap()
  guard text_stroke_test_item(page).stroke is Some({ svg_path: Some(_), .. }) else {
    fail("missing native text pen")
  }
  let paints = invisible_test_canvas_items(page)
  assert_eq(paints.length(), 1)
  guard paints[0] is Object(fields) else { fail("missing text paint") }
  assert_true(fields.get("text_svg") is Some(Null))
  assert_true(page.render_svg().contains("<path "))
}

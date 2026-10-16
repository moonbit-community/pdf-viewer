///|
test "ordinary outlines share geometry while retaining transforms and semantics" {
  let document = type1_test_clip_document(
    "q -1 .3 .2 1 150 20 cm .2 .4 .8 rg BT /F1 20 Tf 10 20 Td (AAA) Tj ET Q",
  )
  let original = document.page(1).unwrap()
  let (page, program) = prepare_canvas_page(document, 1).unwrap()
  assert_eq(program.glyphs.length(), 3)
  assert_eq(program.resources.length(), 1)
  assert_eq(document.canvas_resources.outlines.length(), 1)
  assert_eq(document.canvas_resources.misses, 1)
  assert_eq(document.canvas_resources.hits, 2)
  assert_true(program.glyphs[0].outline)
  assert_true(program.glyphs[0].matrix != program.glyphs[1].matrix)
  assert_true(
    program.glyphs[0].resource.json is { "kind": String("outline"), .. },
  )
  assert_eq(program.text_layer(page, 1.0, 0), original.text_layer())
  assert_eq(page.annotations, original.annotations)
  let item = text_stroke_test_item(page)
  assert_eq(item.fill_path, Some(""))
  assert_eq(item.type3_outline, None)
  assert_eq(item.type3_scene, None)
  assert_eq(item.fill_color, text_stroke_test_item(original).fill_color)
  assert_true(program.canvas_plan(page, 1.0, 0) is { "version": Number(2), .. })
  let (_, again) = prepare_canvas_page(document, 1).unwrap()
  assert_eq(again.glyphs[0].resource.id, program.glyphs[0].resource.id)
  assert_eq(document.canvas_resources.hits, 5)
  // The legacy public model remains complete after a compiled preparation.
  assert_eq(document.page(1).unwrap(), original)
}

///|
test "ordinary glyph compilation retains stroke clipping and invisible paths" {
  for mode in 1..<8 {
    let document = type1_test_clip_document(
      "BT /F1 20 Tf \{mode} Tr 10 20 Td (AA) Tj ET",
    )
    let (page, program) = prepare_canvas_page(document, 1).unwrap()
    assert_eq(program.glyphs.length(), 0)
    assert_eq(page, document.page(1).unwrap())
  }
}

///|
test "ordinary outlines respect document budgets and indirect encoding identity" {
  let document = type1_test_clip_document("BT /F1 20 Tf (AA) Tj ET")
  document.canvas_resources.bytes = 8 * 1024 * 1024
  let (_, program) = prepare_canvas_page(document, 1).unwrap()
  assert_eq(document.canvas_resources.outlines.length(), 0)
  assert_eq(program.resources.length(), 1)
  assert_eq(program.glyphs.length(), 2)
  let entry = pdf_collected_entries_of_page(
      document.document,
      document.pages[0],
    )[0]
  let build = { program, cache: document.canvas_resources, outlines: Map([]), }
  let cff = Map([])
  let type1 = Map([])
  let first = pdf_canvas_outline_call(
    document.document,
    entry,
    65,
    cff,
    type1,
    build,
  ).unwrap()
  let second = pdf_canvas_outline_call(
    document.document,
    { ..entry, font_object: Some(@syntax.PdfIndirect(99)), },
    65,
    cff,
    type1,
    build,
  ).unwrap()
  assert_true(first.resource.id != second.resource.id)
  assert_true(
    pdf_canvas_outline_call(
      document.document,
      { ..entry, font_object: None, },
      65,
      cff,
      type1,
      build,
    )
    is None,
  )
  assert_eq(document.canvas_resources.bytes, 8 * 1024 * 1024)
  let other = type1_test_clip_document("BT /F1 20 Tf (A) Tj ET")
  assert_eq(other.canvas_resources.outlines.length(), 0)
  assert_eq(other.canvas_resources.bytes, 0)
}

///|
test "Prepared text operations own state independently of glyph placement" {
  let document = type1_test_clip_document(
    "BT /F1 20 Tf 10 20 Td (AA) Tj 0 0 1 rg (AA) Tj ET",
  )
  let (page, program) = prepare_canvas_page(document, 1).unwrap()
  assert_eq(program.glyphs[0].paint_run, program.glyphs[1].paint_run)
  assert_true(program.glyphs[1].paint_run != program.glyphs[2].paint_run)
  assert_eq(program.glyphs[2].paint_run, program.glyphs[3].paint_run)
  guard program.canvas_plan(page, 1.0, 0)
    is {
      "version": Number(3),
      "items": Array([first, second]),
      "text_states": Array([_, _]),
      ..
    } else {
    fail("Expected two text operations")
  }
  assert_true(
    first
    is {
      "kind": String("text_run"),
      "text": Array([String("A"), String("A")]),
      ..
    },
  )
  assert_true(second is { "kind": String("text_run"), "state": Number(1), .. })
  assert_eq(page.text_layer(), document.page(1).unwrap().text_layer())
  let public = document.page(1).unwrap()
  guard (public.items[0], public.items[1]) is (Text(a), Text(b)) else {
    fail("Expected public text")
  }
  let original = b.fill_source.components[0]
  a.fill_source.components[0] = 999.0
  assert_eq(b.fill_source.components[0], original)
}

///|
test "Text command packets split large operations without splitting their state" {
  let document = type1_test_clip_document(
    "BT /F1 1 Tf (" + "A".repeat(4100) + ") Tj ET",
  )
  let (page, program) = prepare_canvas_page(document, 1).unwrap()
  guard program.canvas_plan(page, 1.0, 0)
    is {
      "text_states": Array([_]),
      "items": Array(
        [
          {
            "kind": String("text_run"),
            "text": Array(first),
            "draws": Array(a),
            ..
          },
          {
            "kind": String("text_run"),
            "text": Array(second),
            "draws": Array(b),
            ..
          },
        ]
      ),
      ..
    } else {
    fail("Expected bounded text packets")
  }
  assert_eq(first.length(), 4096)
  assert_eq(second.length(), 4)
  assert_eq(a.length(), 4096 * 29)
  assert_eq(b.length(), 4 * 29)
}

///|
test "Invalid text rows preserve earlier and subsequent run ownership" {
  let document = type1_test_clip_document("BT /F1 20 Tf (AAA) Tj ET")
  let (page, program) = prepare_canvas_page(document, 1).unwrap()
  guard page.items[0] is Text(value) else { fail("Expected text") }
  let call = program.glyphs[value.index]
  let draws = [42.0]
  assert_true(pdf_canvas_append_text_row(draws, value, call))
  assert_eq(draws.length(), 30)
  assert_eq(draws[0], 42.0)
  let original = draws.copy()
  for matrix in [[], [1.0, 0.0, 0.0], [1.0, 0.0, 0.0, 1.0, 0.0, 1.0 / 0.0]] {
    assert_false(pdf_canvas_append_text_row(draws, value, { ..call, matrix, }))
    assert_eq(draws, original)
  }
  for
    invalid in [
      { ..value, glyph_transform: None, },
      { ..value, advance_x: 0.0 / 0.0, },
      { ..value, quad: { ..value.quad, p3: { x: 1.0, y: 1.0 / 0.0, }, }, },
    ] {
    assert_false(pdf_canvas_append_text_row(draws, invalid, call))
    assert_eq(draws, original)
  }
  guard page.items[1] is Text(middle) else { fail("Expected middle glyph") }
  program.glyphs[middle.index] = { ..program.glyphs[middle.index], matrix: [], }
  guard program.canvas_plan(page, 1.0, 0)
    is {
      "items": [
        { "kind": String("text_run"), "draws": Array(first), .. },
        { "kind": String("text"), .. },
        { "kind": String("text_run"), "draws": Array(last), .. },
      ],
      ..
    } else {
    fail("Expected a fallback paint between independent text runs")
  }
  assert_eq(first.length(), 29)
  assert_eq(last.length(), 29)
}

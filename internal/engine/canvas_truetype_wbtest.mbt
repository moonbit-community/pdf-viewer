///|
test "Prepared standard fonts share A1 outlines and respect changed host policy" {
  for face in standard14_test_faces() {
    let document = provenance_test_document(
      "q -.7 .3 .2 1 150 20 cm BT /F1 20 Tf 10 20 Td (AAA) Tj ET Q",
      font="<< /Type /Font /Subtype /Type1 /BaseFont /" + face.name() + " >>",
    )
    let original = document.page(1).unwrap()
    let (page, program) = prepare_canvas_page(document, 1).unwrap()
    assert_eq(program.glyphs.length(), 3)
    assert_eq(program.resources.length(), 1)
    assert_eq(program.text_layer(page, 1.0, 0), original.text_layer())
    assert_eq(
      program.accessibility_page_json(document, 1, page),
      document.accessibility_page_json(1),
    )
    assert_eq(document.page(1).unwrap(), original)
    let other = document.with_font_fallbacks([
      { pdf_name: "/F1", family: "HostFont", weight: None, style: None, },
    ])
    let (fallback, fallback_program) = prepare_canvas_page(other, 1).unwrap()
    assert_eq(fallback_program.glyphs.length(), 0)
    assert_eq(fallback, other.page(1).unwrap())
  }
}

///|
test "Prepared embedded TrueType retains Encoding and source geometry" {
  let document = truetype_test_document(truetype_test_fixture())
  font_scope_test_content(document, "BT /F1 18 Tf 20 100 Td (AAA) Tj ET")
  let original = document.page(1).unwrap()
  let (page, program) = prepare_canvas_page(document, 1).unwrap()
  assert_eq(program.glyphs.length(), 3)
  assert_eq(program.resources.length(), 1)
  assert_eq(program.text_layer(page, 1.0, 0), original.text_layer())
  assert_eq(document.page(1).unwrap(), original)
}

///|
fn prepared_text_test_projections(document : PdfViewerDocument) -> Unit raise {
  let (page, program) = prepare_canvas_page(document, 1).unwrap()
  let content = program.text_content.unwrap()
  assert_eq(content, page.text_content())
  assert_eq(content.text, page.text)
  assert_eq(pdf_text_structure_of_content(content), page.text_structure())
  let prepared = program.accessibility_page_json(document, 1, page)
  assert_eq(
    prepared,
    document.accessibility_page_json(1, page_model=Some(page)),
  )
  assert_eq(prepared, program.accessibility_page_json(document, 1, page))
  for rotation in [0, 90, 180, 270] {
    let layer = program.text_layer(page, 1.25, rotation)
    assert_eq(layer, page.text_layer(scale=1.25, rotation~))
    assert_eq(program.text_content, Some(content))
  }
  let fallback = pdf_canvas_program()
  assert_eq(fallback.text_layer(page, 1.0, 0), page.text_layer(rotation=0))
  assert_eq(fallback.accessibility_page_json(document, 1, page), prepared)
  assert_eq(program.accessibility_page_json(document, 0, page), None)
}

///|
test "Prepared text shares bidi columns and transformed selection projections" {
  prepared_text_test_projections(
    unicode_search_test_document(["ב", "1", "2", "א", "😀", "ﬁ"], positions=[
      (12.0, 100.0),
      (18.0, 100.0),
      (24.0, 100.0),
      (30.0, 100.0),
      (20.0, 70.0),
      (30.0, 70.0),
    ]),
  )
  let columns = unicode_search_test_document(
    ["Heading", "Right2", "Left1", "Right1", "Left2"],
    positions=[
      (20.0, 170.0),
      (120.0, 126.0),
      (20.0, 140.0),
      (120.0, 140.0),
      (20.0, 126.0),
    ],
    widths=[16000, 3000, 3000, 3000, 3000],
  )
  prepared_text_test_projections(columns)
  layout_test_transform(columns, "1 0.5 0.3 1 0 0")
  prepared_text_test_projections(columns)
}

///|
test "Prepared text preserves tagged ActualText artifacts and consumed provenance" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /Lang (fr) /StructTreeRoot 6 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> /Properties << /Heading << /MCID 0 >> >> >> >>",
    annotation_test_stream(
      "", "BT /F1 10 Tf 20 150 Td /P << /MCID 1 >> BDC (B) Tj EMC 0 -20 Td /H1 /Heading BDC (H) Tj EMC 0 -20 Td /Artifact BMC (Artifact) Tj EMC 0 -20 Td (Tail) Tj ET",
    ),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    "<< /Type /StructTreeRoot /K [7 0 R 8 0 R] >>",
    "<< /Type /StructElem /S /H1 /Pg 3 0 R /K 0 >>",
    "<< /Type /StructElem /S /P /Pg 3 0 R /ActualText (Replacement) /K 1 >>",
  ])
  prepared_text_test_projections(document)
  assert_eq(document.accessibility_sources.val, None)
  let empty = canvas_program_test_document("1000 0 d0", contents="")
  prepared_text_test_projections(empty)
}

///|
test "editor incremental save preserves original bytes and appends only edited objects" {
  let source = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Annots [4 0 R] >>", "<< /Subtype /FreeText /Rect [10 20 130 45] /Contents (Before) /DA (/Helv 12 Tf 0 g) >>",
    "<< /Untouched (original object) >>",
  ])
  let edited = source.with_editor_changes([
    { "kind": "update", "id": "object:4", "page": 1, "contents": "After" },
  ])
  let saved = edited.save_bytes()
  assert_eq(saved[:source.source_length].to_owned(), source.source_bytes)
  assert_true(saved.length() > source.source_length)
  let tail = @utf8.decode(saved[source.source_length:])
  assert_true(tail.contains("/Prev"))
  assert_true(!tail.contains("original object"))
  let reopened = open_document(saved)
  assert_eq(reopened.page(1).unwrap().annotations[0].contents, Some("After"))
  assert_eq(source.page(1).unwrap().annotations[0].contents, Some("Before"))
  let again = reopened
    .with_editor_changes([
      { "kind": "update", "id": "object:4", "page": 1, "contents": "Third" },
    ])
    .save_bytes()
  assert_eq(again[:saved.length()].to_owned(), saved)
  assert_eq(
    open_document(again).page(1).unwrap().annotations[0].contents,
    Some("Third"),
  )
  let full = edited.save_bytes(incremental=false)
  assert_eq(
    open_document(full).page(1).unwrap().annotations[0].contents,
    Some("After"),
  )
  assert_true(full != saved)
}

///|
test "editor fully rewrites a recovered source with an in-bounds invalid startxref" {
  let source = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Annots [4 0 R] >>", "<< /Subtype /FreeText /Rect [10 20 130 45] /Contents (Before) /DA (/Helv 12 Tf 0 g) >>",
  ])
  let original_xref = source.document.first_xref()
  assert_true(original_xref > 0)
  let corrupt = @utf8.encode(
    @utf8.decode(source.source_bytes).replace(
      old="\nstartxref\n\{original_xref}\n",
      new="\nstartxref\n1\n",
    ),
  )
  let recovered = open_document(corrupt)
  assert_eq(recovered.document.first_xref(), 0)
  let saved = recovered
    .with_editor_changes([
      { "kind": "update", "id": "object:4", "page": 1, "contents": "Repaired" },
    ])
    .save_bytes()
  assert_true(
    saved[:corrupt.length().min(saved.length())].to_owned() != corrupt,
  )
  let reopened = open_document(saved)
  assert_true(reopened.document.first_xref() > 0)
  assert_eq(reopened.page(1).unwrap().annotations[0].contents, Some("Repaired"))
  assert_eq(
    @reader.pdf_read_startxref_position(saved),
    reopened.document.first_xref(),
  )
}

///|
test "editor selected-text highlights preserve affine quads in appearance and after moving" {
  let source = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>",
  ])
  let quad : PdfQuad = {
    p0: { x: 20.0, y: 20.0, },
    p1: { x: 25.0, y: 40.0, },
    p2: { x: 85.0, y: 50.0, },
    p3: { x: 80.0, y: 30.0, },
  }
  let edited = source.with_editor_changes([
    {
      "kind": "add",
      "id": "new:selected",
      "page": 1,
      "subtype": "Highlight",
      "bounds": [20, 20, 85, 50],
      "quads": ToJson::to_json([quad]),
      "contents": "Selected text",
    },
  ])
  let reopened = open_document(edited.save_bytes())
  let object = pdf_edit_annots(reopened.document, reopened.pages[0].rest)[0]
  assert_eq(pdf_annotation_quad_points(reopened.document, object), [quad])
  let ap = reopened.document.lookup_direct(pdf_name_key("/AP"), object).unwrap()
  let normal = reopened.document.lookup_direct(pdf_name_key("/N"), ap).unwrap()
  let ops = @pdflite.pdf_parse_content_ops_from_bytes(normal.stream_bytes())
  assert_true(ops.contains(@content.Op_m(5.0, 20.0)))
  assert_true(ops.contains(@content.Op_l(65.0, 30.0)))
  assert_true(!ops.any(op => op is @content.Op_re(_, _, _, _)))
  guard reopened.editor_page_json(1).unwrap() is Array([entry]) else {
    fail("Expected one highlight annotation")
  }
  let id = pdf_edit_string(entry, "id")
  let moved = reopened.with_editor_changes([
    { "kind": "update", "id": id, "page": 1, "bounds": [30, 25, 95, 55] },
  ])
  let raw = pdf_edit_annots(moved.document, moved.pages[0].rest)[0]
  let quads = pdf_annotation_quad_points(moved.document, raw)
  assert_eq(quads[0].p0, { x: 30.0, y: 25.0, })
  assert_eq(quads[0].p1, { x: 35.0, y: 45.0, })
  assert_eq(quads[0].p2, { x: 95.0, y: 55.0, })
}

///|
test "editor rejects selected-text quads outside annotation bounds atomically" {
  let source = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>",
  ])
  let quad : PdfQuad = {
    p0: { x: 0.0, y: 0.0, },
    p1: { x: 0.0, y: 20.0, },
    p2: { x: 20.0, y: 20.0, },
    p3: { x: 20.0, y: 0.0, },
  }
  let result = try? source.with_editor_changes([
    {
      "kind": "add",
      "id": "new:invalid",
      "page": 1,
      "subtype": "Highlight",
      "bounds": [10, 10, 20, 20],
      "quads": ToJson::to_json([quad]),
    },
  ])
  assert_true(result is Err(_))
  assert_true(source.page(1).unwrap().annotations.is_empty())
}

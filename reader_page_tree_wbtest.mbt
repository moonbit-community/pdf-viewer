///|
test "Page tree cycles fail with the actual resource path and object number" {
  let document = provenance_test_document("BT /F1 10 Tf (A) Tj ET")
  let before = document.document.lookup_object_or_null(2)
  document.document.add_object_given_number(
    2,
    before.add_dict_entry(
      pdf_name_key("/Kids"),
      @syntax.PdfArray([@syntax.PdfIndirect(3), @syntax.PdfIndirect(2)]),
    ),
  )
  try pdf_validate_page_tree_for_viewer(document.document) catch {
    @core.SoftError(message) => {
      assert_true(message.contains("cycle"))
      assert_true(message.contains("/Root/Pages/Kids[1]"))
      assert_true(message.contains("object 2"))
    }
    _ => fail("located page tree error expected")
  } noraise {
    _ => fail("cyclic page tree accepted")
  }
}

///|
test "Page tree reference aliases and traversal depth stay bounded" {
  let document = provenance_test_document("")
  document.document.add_object_given_number(2, @syntax.PdfIndirect(6))
  document.document.add_object_given_number(6, @syntax.PdfIndirect(2))
  try pdf_validate_page_tree_for_viewer(document.document) catch {
    @core.SoftError(message) => assert_true(message.contains("object 2"))
    _ => fail("located alias error expected")
  } noraise {
    _ => fail("cyclic aliases accepted")
  }
  for index in 2..<261 {
    document.document.add_object_given_number(
      index,
      @syntax.PdfDictionary([
        (pdf_name_key("/Type"), @syntax.PdfNameObject(pdf_name_key("/Pages"))),
        (
          pdf_name_key("/Kids"),
          @syntax.PdfArray([@syntax.PdfIndirect(index + 1)]),
        ),
      ]),
    )
  }
  try pdf_validate_page_tree_for_viewer(document.document) catch {
    @core.SoftError(message) => assert_true(message.contains("Page tree limit"))
    _ => fail("bounded traversal error expected")
  } noraise {
    _ => fail("overdeep page tree accepted")
  }
}

///|
test "Reader still owns nested resource box and rotation inheritance" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 999 /Kids [6 0 R] /MediaBox [0 0 240 320] /Resources << /Font << /F1 5 0 R >> >> /Rotate 90 >>",
    "<< /Type /Page /Parent 6 0 R /Contents 4 0 R >>",
    annotation_test_stream("", "BT /F1 10 Tf 20 100 Td (Inherited) Tj ET"),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] /Parent 2 0 R >>",
  ])
  assert_eq(document.page_count(), 1)
  let page = document.page(1).unwrap()
  assert_eq((page.width, page.height, page.rotation), (240.0, 320.0, 90))
  assert_eq(page.text_content().text, "Inherited")
  assert_eq(document.text_provenance(1).unwrap()[0].font_object_number, Some(5))
}

///|
test "Reader recovery keeps good pages and original content identities beside a cyclic branch" {
  let document = provenance_test_document(
    "BT /F1 10 Tf 20 100 Td (Retained) Tj ET",
  )
  let original = document.document
  let pages = original
    .lookup_object_or_null(2)
    .add_dict_entry(
      pdf_name_key("/Kids"),
      @syntax.PdfArray([@syntax.PdfIndirect(3), @syntax.PdfIndirect(6)]),
    )
  original.add_object_given_number(2, pages)
  original.add_object_given_number(
    6,
    @syntax.PdfDictionary([
      (pdf_name_key("/Type"), @syntax.PdfNameObject(pdf_name_key("/Pages"))),
      (pdf_name_key("/Kids"), @syntax.PdfArray([@syntax.PdfIndirect(6)])),
    ]),
  )
  let recovered = pdf_viewer_document_of_parsed_document(
    document.source_bytes,
    original,
  )
  assert_eq(recovered.page_count(), 1)
  assert_eq(recovered.page(1).unwrap().text_content().text, "Retained")
  assert_eq(recovered.reader_diagnostics(), [
    {
      resource: "/Root/Pages/Kids[1]/Kids[0]",
      object_number: Some(6),
      message: "Page tree cycle",
    },
  ])
  assert_eq(original.lookup_object_or_null(2), pages)
  assert_eq(
    recovered.document.lookup_object_or_null(4),
    original.lookup_object_or_null(4),
  )
  let sources = recovered.text_provenance(1).unwrap()
  assert_eq(sources[0].font_object_number, Some(5))
  assert_eq(sources[0].string_source.unwrap().content_streams, [Some(4)])
  let spellings = recovered.text_lexical_sources(1).unwrap()
  assert_true(spellings.all(source => source.failure is None))
  assert_true(spellings[0].spans[0].file_span is Some(_))
}

///|
test "Serialized cyclic page trees reach bounded recovery before the reader probe" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 2 /Kids [3 0 R 6 0 R] /MediaBox [0 0 240 320] /Resources << /Font << /F1 5 0 R >> >> >>",
    "<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>",
    annotation_test_stream("", "BT /F1 10 Tf 20 100 Td (Retained) Tj ET"),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    "<< /Type /Pages /Count 1 /Kids [6 0 R] /Parent 2 0 R >>",
  ])
  assert_eq(document.page_count(), 1)
  assert_eq(document.page_labels(), ["1"])
  assert_eq(document.page(1).unwrap().text_content().text, "Retained")
  assert_eq(document.reader_diagnostics(), [
    {
      resource: "/Root/Pages/Kids[1]/Kids[0]",
      object_number: Some(6),
      message: "Page tree cycle",
    },
  ])
  let authenticated = open_document_with_passwords(
    document.source_bytes,
    user_password=Some(b"unused"),
  )
  assert_eq(authenticated.page_count(), 1)
  assert_eq(authenticated.reader_diagnostics(), document.reader_diagnostics())
}

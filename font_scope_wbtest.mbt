///|
fn font_scope_test_content(
  document : PdfViewerDocument,
  content : String,
) -> Unit raise {
  document.document.add_object_given_number(
    4,
    @pdflite.pdf_content_stream_of_ops(
      @pdflite.pdf_parse_content_ops_from_bytes(@utf8.encode(content)),
    ),
  )
}

///|
fn font_scope_test_child_font(
  document : PdfViewerDocument,
) -> @syntax.PdfObject raise {
  document.document
  .lookup_object_or_null(5)
  .add_dict_entry(
    pdf_name_key("/Encoding"),
    @syntax.PdfDictionary([
      (
        pdf_name_key("/Differences"),
        @syntax.PdfArray([
          @syntax.PdfInteger(65),
          @syntax.PdfNameObject(pdf_name_key("/Z")),
        ]),
      ),
    ]),
  )
}

///|
test "TrueType paint and clip retain the active font across missing Tf and ExtGState" {
  let document = truetype_test_document(truetype_test_fixture())
  let original_font = document.document.lookup_object_or_null(5)
  document.document.add_object_given_number(
    9,
    font_scope_test_child_font(document),
  )
  document.pages[0] = {
    ..document.pages[0],
    resources: @syntax.PdfDictionary([
      (
        pdf_name_key("/Font"),
        @syntax.PdfDictionary([(pdf_name_key("/F1"), @syntax.PdfIndirect(5))]),
      ),
      (
        pdf_name_key("/ExtGState"),
        @syntax.PdfDictionary([
          (
            pdf_name_key("/GS"),
            @syntax.PdfDictionary([
              (
                pdf_name_key("/Font"),
                @syntax.PdfArray([
                  @syntax.PdfIndirect(9),
                  @syntax.PdfInteger(10),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    ]),
  }
  font_scope_test_content(
    document, "BT /F1 10 Tf 4 Tr 1 0 0 1 20 100 Tm /Missing 10 Tf (A) Tj q /GS gs 1 0 0 1 30 100 Tm (A) Tj Q 1 0 0 1 40 100 Tm (A) Tj ET 0 0 200 200 re f",
  )
  let page = document.page(1).unwrap()
  let items = page.text_content().items
  assert_eq([ for item in items => item.font ], [
    "/Missing", "__EXTGSTATE__9", "/Missing",
  ])
  assert_true(items[0].type3_outline.unwrap().contains("L 21 100"))
  assert_true(items[1].type3_outline.unwrap().contains("L 32 100"))
  assert_true(items[2].type3_outline.unwrap().contains("L 41 100"))
  let clip = text_clip_test_paths(page)[0].clip_path.unwrap()
  for path in ["L 21 100", "L 32 100", "L 41 100"] {
    assert_true(clip.contains(path))
  }
  assert_eq([ for item in provenance_test_paint_order(document) => item.gid ], [
    Some(1),
    Some(2),
    Some(1),
  ])
  assert_eq(document.document.lookup_object_or_null(5), original_font)
}

///|
test "Form resource shadowing changes TrueType paint only after Tf and restores parent outside" {
  let document = truetype_test_document(truetype_test_fixture())
  document.document.add_object_given_number(
    9,
    font_scope_test_child_font(document),
  )
  let form_dictionary = @syntax.PdfDictionary([
    (pdf_name_key("/Subtype"), @syntax.PdfNameObject(pdf_name_key("/Form"))),
    (
      pdf_name_key("/BBox"),
      @syntax.PdfArray([
        @syntax.PdfInteger(0),
        @syntax.PdfInteger(0),
        @syntax.PdfInteger(200),
        @syntax.PdfInteger(200),
      ]),
    ),
    (
      pdf_name_key("/Resources"),
      @syntax.PdfDictionary([
        (
          pdf_name_key("/Font"),
          @syntax.PdfDictionary([(pdf_name_key("/F1"), @syntax.PdfIndirect(9))]),
        ),
      ]),
    ),
  ])
  let form_content = b"BT 1 0 0 1 20 100 Tm (A) Tj /F1 10 Tf 1 0 0 1 30 100 Tm (A) Tj ET"
  document.document.add_object_given_number(
    10,
    @syntax.pdf_stream(
      form_dictionary.add_dict_entry(
        pdf_name_key("/Length"),
        @syntax.PdfInteger(form_content.length()),
      ),
      @syntax.StreamGot(form_content),
    ),
  )
  document.pages[0] = {
    ..document.pages[0],
    resources: document.pages[0].resources.add_dict_entry(
      pdf_name_key("/XObject"),
      @syntax.PdfDictionary([(pdf_name_key("/Fm"), @syntax.PdfIndirect(10))]),
    ),
  }
  font_scope_test_content(
    document, "BT /F1 10 Tf ET /Fm Do BT 1 0 0 1 40 100 Tm (A) Tj ET",
  )
  let page = document.page(1).unwrap()
  let items = page.text_content().items
  assert_true(items[0].type3_outline.unwrap().contains("L 21 100"))
  assert_true(items[1].type3_outline.unwrap().contains("L 32 100"))
  assert_true(items[2].type3_outline.unwrap().contains("L 41 100"))
  assert_eq([ for item in items => item.font ], ["/F1", "/F1@font1", "/F1"])
  assert_eq(
    [
      for item in provenance_test_paint_order(document) => {
        item.font_object_number
      }
    ],
    [Some(5), Some(9), Some(5)],
  )
  assert_eq(page.fonts.length(), 2)
  assert_eq(page.text_sources()[1].font, "/F1@font1")
}

///|
test "Form host font resource identity follows Tf rather than colliding resource names" {
  let document = provenance_test_document(
    "BT /F1 10 Tf ET /Fm Do BT 1 0 0 1 30 100 Tm (C) Tj ET",
    resources="<< /Font << /F1 5 0 R >> /XObject << /Fm 6 0 R >> >>",
    extra_objects=[
      annotation_test_stream(
        "/Subtype /Form /BBox [0 0 200 200] /Resources << /Font << /F1 7 0 R >> >>",
        "BT 1 0 0 1 10 100 Tm (A) Tj /F1 10 Tf 1 0 0 1 20 100 Tm (B) Tj ET",
      ),
      "<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>",
    ],
  )
  let page = document.page(1).unwrap()
  assert_eq([ for item in page.text_content().items => item.font ], [
    "/F1", "/F1@font1", "/F1",
  ])
  assert_eq([ for font in page.fonts => font.base_name ], [
    "/Helvetica", "/Courier",
  ])
  assert_eq([ for font in page.fonts => font.standard_font ], [
    Some("Helvetica"),
    Some("Courier"),
  ])
}

///|
test "Type3 paint survives missing Tf and an ExtGState font without a named resource" {
  let document = provenance_test_document(
    "BT /F1 10 Tf 20 100 Td /Missing 10 Tf (A) Tj /GS gs (A) Tj ET",
    font="<< /Subtype /Type3 /FontBBox [0 0 500 700] /FontMatrix [0.001 0 0 0.001 0 0] /CharProcs << /A 6 0 R >> /Encoding << /Differences [65 /A] >> /FirstChar 65 /LastChar 65 /Widths [500] /Resources << >> >>",
    resources="<< /Font << /F1 5 0 R >> /ExtGState << /GS << /Font [5 0 R 10] >> >> >>",
    extra_objects=[annotation_test_stream("", "500 0 d0 0 0 500 700 re f")],
  )
  let page = document.page(1).unwrap()
  assert_eq(page.text_content().items.length(), 2)
  for glyph in page.text_content().items {
    assert_true(glyph.type3_outline.unwrap().contains("data-pdf-type3"))
  }
}

///|
test "ExtGState fonts share Tf metric and checksum ToUnicode recovery without source mutation" {
  let document = truetype_test_document(truetype_test_fixture())
  let original = document.document.lookup_object_or_null(5)
  let partial = original.add_dict_entry(
    pdf_name_key("/Widths"),
    @syntax.PdfArray([]),
  )
  document.document.add_object_given_number(5, partial)
  let damaged = font_stream_test_replace(
    document, 8, b"1 beginbfchar <41> <005A> endbfchar",
  )
  document.pages[0] = {
    ..document.pages[0],
    resources: @syntax.PdfDictionary([
      (
        pdf_name_key("/ExtGState"),
        @syntax.PdfDictionary([
          (
            pdf_name_key("/GS"),
            @syntax.PdfDictionary([
              (
                pdf_name_key("/Font"),
                @syntax.PdfArray([
                  @syntax.PdfIndirect(5),
                  @syntax.PdfInteger(10),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    ]),
  }
  font_scope_test_content(document, "BT /GS gs 20 100 Td (A) Tj ET")
  let glyph = document.page(1).unwrap().text_content().items[0]
  assert_eq(glyph.text, "Z")
  assert_true(glyph.type3_outline.unwrap().contains("L 21 100"))
  assert_eq(document.document.lookup_object_or_null(5), partial)
  assert_eq(document.document.lookup_object_or_null(8), damaged)
}

///|
test "ordinary rendering tracks active fonts without capturing string sources" {
  let document = provenance_test_document("BT /F1 10 Tf (A) Tj ET")
  let entries = pdf_collected_entries_of_page(
    document.document,
    document.pages[0],
  )
  assert_eq(entries[0].font_object, Some(@syntax.PdfIndirect(5)))
  assert_true(entries[0].text_source is None)
}

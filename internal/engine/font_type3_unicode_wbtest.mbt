///|
test "small Type3 Unicode maps match the strict reader before normalization" {
  let document = @pdflite.pdf_document_empty()
  for
    source in [
      "1 beginbfchar\n<41> <0041>\nendbfchar\n", "3 beginbfchar\n<41> <00660069>\n<42> <D83DDE00>\n<43> <FFFD>\nendbfchar\n",
      "1 beginbfrange\n<00> <FF> <0100>\nendbfrange\n", "1 beginbfrange\n<41> <43> [<0041> <00660069> <D83DDE00>]\nendbfrange\n",
      "2 beginbfchar\n<00> <0000>\n<FF> <FFFF>\nendbfchar\n",
    ] {
    let bytes = @utf8.encode(source)
    let recovered = pdf_viewer_parse_cmap(bytes[:])
    let reused = pdf_type3_reader_unicode(recovered).unwrap()
    let stream = @syntax.pdf_stream(
      @syntax.pdf_dictionary([]),
      @syntax.StreamGot(bytes),
    )
    assert_eq(reused, document.parse_cmap(stream).map)
  }
}

///|
test "Type3 Unicode reuse rejects overlap inheritance broad and incomplete data" {
  for
    source in [
      "2 beginbfchar <41> <0041> <41> <0042> endbfchar", "1 beginbfrange <00> <FF> <FFFF> endbfrange",
      "1 beginbfrange <00> <FF> <D83DDE00> endbfrange", "1 beginbfchar <0100> <0041> endbfchar",
      "1 beginbfchar <41> <0041>", "/Other usecmap 1 beginbfchar <41> <0041> endbfchar",
    ] {
    assert_true(
      pdf_type3_reader_unicode(pdf_viewer_parse_cmap(@utf8.encode(source)[:]))
      is None,
    )
  }
  let cmap = pdf_viewer_parse_cmap(b"1 beginbfchar <41> <0041> endbfchar"[:])
  assert_true(
    pdf_type3_reader_unicode({ ..cmap, source_available: false, }) is None,
  )
  assert_true(
    pdf_type3_reader_unicode({
      ..cmap,
      diagnostics: { ..cmap.diagnostics, source_unavailable: true, },
    })
    is None,
  )
}

///|
test "Type3 Unicode hex eligibility preserves strict source-code parsing" {
  for
    source in [
      "1 beginbfchar <4> <0041> endbfchar", "1 beginbfchar <41> <0 041> endbfchar",
      "1 beginbfchar <41> <041> endbfchar", "1 beginbfchar <41> <> endbfchar", "1 beginbfchar <41> <0041",
      "(unclosed string",
    ] {
    assert_true(!pdf_cmap_reader_hex_compatible(@utf8.encode(source)[:]))
  }
  assert_true(
    pdf_cmap_reader_hex_compatible(
      b"% <odd>\n<< /Registry (Adobe \\(nested\\)) >>\n1 beginbfchar <41> <0041> endbfchar"[:],
    ),
  )
  assert_true(!pdf_cmap_reader_hex_compatible(Bytes::make(65537, b' ')[:]))
}

///|
test "Type3 Unicode reuse preserves complete font metadata and source dictionaries" {
  let original = canvas_program_test_document(
    "1000 0 0 0 1000 1000 d1 0 0 1000 1000 re f",
  )
  let source = "2 beginbfchar\n<41> <00660069>\n<42> <D83DDE00>\nendbfchar\n"
  let stream = @syntax.pdf_stream(
    @syntax.pdf_dictionary([
      (pdf_name_key("/Length"), @syntax.PdfInteger(source.length())),
    ]),
    @syntax.StreamGot(@utf8.encode(source)),
  )
  let document = original.document
  document.add_object_given_number(20, stream)
  let object = document
    .lookup_object_or_null(5)
    .add_dict_entry(pdf_name_key("/ToUnicode"), @syntax.PdfIndirect(20))
  let expected = pdf_font_unicode_for_viewer(document.read_font(object))
  let (actual, diagnostics) = pdf_read_font_recovery_result(document, object)
  assert_eq(pdf_font_unicode_for_viewer(actual), expected)
  assert_true(!diagnostics.contains(CMapReaderFallback))
  let context = pdf_resource_build_context()
  let (shadow, _, limited, unicode) = pdf_font_cmap_reader_shadow(
    document,
    object,
    resource_context=Some(context),
  )
  assert_true(unicode is Some(_))
  assert_true(!limited)
  assert_eq(shadow.lookup_immediate(pdf_name_key("/ToUnicode")), None)
  assert_eq(
    object.lookup_immediate(pdf_name_key("/ToUnicode")),
    Some(@syntax.PdfIndirect(20)),
  )
  let child = @syntax.pdf_stream(
    @syntax.pdf_dictionary([
      (pdf_name_key("/Length"), @syntax.PdfInteger(source.length())),
      (pdf_name_key("/UseCMap"), @syntax.PdfIndirect(20)),
    ]),
    @syntax.StreamGot(@utf8.encode(source)),
  )
  document.add_object_given_number(21, child)
  for
    variant in [
      object.add_dict_entry(pdf_name_key("/ToUnicode"), child),
      object.add_dict_entry(pdf_name_key("/ToUnicode"), @syntax.PdfIndirect(21)),
      object.add_dict_entry(
        pdf_name_key("/Subtype"),
        @syntax.PdfNameObject(pdf_name_key("/Type1")),
      ),
    ] {
    let (_, _, _, reused) = pdf_font_cmap_reader_shadow(document, variant)
    assert_eq(reused, None)
  }
}

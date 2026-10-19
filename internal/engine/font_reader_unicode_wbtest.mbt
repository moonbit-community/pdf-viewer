///|
test "CID Unicode reuse matches strict reader for large maps and ranges" {
  let document = @pdflite.pdf_document_empty()
  let source = StringBuilder()
  source.write_string("8192 beginbfchar\n")
  for code in 0..<8192 {
    let hex = code.to_string(radix=16).pad_start(4, '0')
    source.write_string("<\{hex}> <\{hex}>\n")
  }
  source.write_string("endbfchar\n")
  for
    text in [
      source.to_string(),
      "1 beginbfrange\n<0000> <FFFF> <0000>\nendbfrange\n",
      "1 beginbfrange\n<8000> <8002> [<00660069> <D83DDE00> <FFFD>]\nendbfrange\n",
      "2 beginbfchar\n<FFFF> <D83DDE00>\n<0000> <00660069>\nendbfchar\n",
    ] {
    let bytes = @utf8.encode(text)
    let cmap = pdf_viewer_parse_cmap(bytes[:])
    let actual = pdf_font_reader_unicode(cmap).unwrap()
    let expected = document.parse_cmap(
        @syntax.pdf_stream(@syntax.pdf_dictionary([]), @syntax.StreamGot(bytes)),
      ).map
    assert_eq(actual, expected)
    assert_true(pdf_type3_reader_unicode(cmap) is None)
  }
}

///|
test "CID Unicode reuse preserves font metadata and source dictionaries" {
  let view = cid_layout_test_document(
    "BT /F1 10 Tf <00410042> Tj ET",
    tounicode="2 beginbfchar\n<0041> <00660069>\n<0042> <D83DDE00>\nendbfchar\n",
  )
  let document = view.document
  let original = document.lookup_object_or_null(5)
  let context = pdf_resource_build_context()
  let (shadow, _, limited, unicode) = pdf_font_cmap_reader_shadow(
    document,
    original,
    resource_context=Some(context),
  )
  assert_true(unicode is Some(_))
  assert_true(!limited)
  assert_eq(shadow.lookup_immediate(pdf_name_key("/ToUnicode")), None)
  let source = original.lookup_immediate(pdf_name_key("/ToUnicode"))
  assert_true(source is Some(_))
  let expected = document.read_font(original)
  let (actual, diagnostics) = pdf_read_font_recovery_result(document, original)
  assert_eq(actual, expected)
  assert_true(!diagnostics.contains(CMapReaderFallback))
  assert_eq(document.lookup_object_or_null(5), original)
  assert_eq(original.lookup_immediate(pdf_name_key("/ToUnicode")), source)
}

///|
test "CID Unicode reuse rejects ambiguous and oversized mappings" {
  for
    source in [
      "2 beginbfchar <0041> <0041> <0041> <0042> endbfchar", "1 beginbfrange <0000> <FFFF> <FFFF> endbfrange",
      "1 beginbfrange <0000> <FFFF> <D83DDE00> endbfrange", "1 beginbfchar <00010000> <0041> endbfchar",
      "1 beginbfchar <0041> <0041>", "/Other usecmap 1 beginbfchar <0041> <0041> endbfchar",
      "1 beginbfchar <004> <0041> endbfchar", "1 beginbfchar <0041> <0 041> endbfchar",
      "1 beginbfchar <0041> <> endbfchar",
    ] {
    assert_true(
      pdf_font_reader_unicode(pdf_viewer_parse_cmap(@utf8.encode(source)[:]))
      is None,
    )
  }
  let cmap = pdf_viewer_parse_cmap(
    b"1 beginbfrange <0000> <FFFF> <0000> endbfrange"[:],
  )
  assert_true(pdf_font_reader_unicode(cmap, max_entries=8) is None)
  assert_true(
    pdf_font_reader_unicode({ ..cmap, source_available: false, }) is None,
  )
  assert_true(
    !pdf_cmap_reader_hex_compatible(
      Bytes::make(1048577, b' ')[:],
      max_bytes=1048576,
    ),
  )
}

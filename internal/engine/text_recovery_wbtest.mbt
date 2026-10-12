///|
test "Text recovery retains valid Differences widths and original font dictionaries" {
  let document = truetype_test_document(
    truetype_test_fixture(),
    encoding="/Encoding << /BaseEncoding /WinAnsiEncoding /Differences [/A 65 /Z (bad) /A] >>",
  )
  let original = document.document.lookup_object_or_null(5)
  let page = document.page(1).unwrap()
  assert_eq(page.text_content().text, "Z")
  assert_eq(page.text_content().items[0].advance_x, 6.0)
  assert_true(
    page.text_content().items[0].type3_outline.unwrap().contains("L 22 100"),
  )
  let diagnostics = document.text_recovery_diagnostics(1).unwrap()
  let encoding = diagnostics.filter(item => item.kind == FontEncodingRecovered)
  assert_eq(encoding.length(), 1)
  assert_eq(encoding[0].object_number, Some(5))
  assert_eq(encoding[0].string_source.unwrap().bytes, b"A")
  assert_eq(document.document.lookup_object_or_null(5), original)
}

///|
test "Text recovery locates missing Tf requests while retaining the active glyph binding" {
  let document = truetype_test_document(truetype_test_fixture())
  font_scope_test_content(
    document, "BT /F1 10 Tf 20 100 Td /Missing 10 Tf (A) Tj ET",
  )
  let page = document.page(1).unwrap()
  assert_eq(page.text_content().text, "Z")
  let diagnostic = document
    .text_recovery_diagnostics(1)
    .unwrap()
    .filter(item => item.kind == MissingFontResource)[0]
  assert_eq(diagnostic.font, "/Missing")
  assert_eq(diagnostic.object_number, None)
  assert_eq(diagnostic.string_source.unwrap().bytes, b"A")
  assert_eq(document.text_provenance(1).unwrap()[0].font_object_number, Some(5))
}

///|
test "Text recovery keeps empty copied glyphs locatable without inventing UTF16 ranges" {
  let document = unicode_search_test_document([""])
  let map = document.document.lookup_object_or_null(6)
  let broken = @pdflite.pdf_content_stream_of_ops([])
  guard broken is @syntax.PdfStreamObject(stream) else {
    fail("stream expected")
  }
  document.document.add_object_given_number(
    6,
    @syntax.pdf_stream(
      stream.dictionary,
      @syntax.StreamGot(b"1 beginbfchar <41> <> endbfchar <GG>"),
    ),
  )
  let page = document.page(1).unwrap()
  assert_eq(page.text_content().text, "")
  assert_eq(page.text_sources(), [])
  let diagnostics = document.text_recovery_diagnostics(1).unwrap()
  assert_true(diagnostics.any(item => item.kind == CMapMalformedTokens(1)))
  for diagnostic in diagnostics {
    assert_eq(diagnostic.source, None)
    assert_eq(diagnostic.item_index, 0)
    assert_eq(diagnostic.charcode, 65)
    assert_eq(diagnostic.string_source.unwrap().bytes, b"A")
  }
  assert_true(map is @syntax.PdfStreamObject(_))
}

///|
test "Text recovery replaces cyclic font aliases without losing remaining page content" {
  let document = provenance_test_document(
    "BT /F1 10 Tf 20 100 Td (AB) Tj ET 0 0 10 10 re f",
  )
  document.document.add_object_given_number(5, @syntax.PdfIndirect(6))
  document.document.add_object_given_number(6, @syntax.PdfIndirect(5))
  let page = document.page(1).unwrap()
  assert_eq(page.text_content().text, "AB")
  assert_true(page.render_svg().contains("<path"))
  let diagnostics = document.text_recovery_diagnostics(1).unwrap()
  assert_eq(
    diagnostics.filter(item => item.kind == FontDictionaryRecovered).length(),
    2,
  )
  assert_eq(diagnostics[0].object_number, Some(5))
  assert_eq(document.text_provenance(1).unwrap().length(), 2)
}

///|
test "Text recovery diagnoses invalid CID bytes and preserves literal replacement mappings" {
  let document = cid_layout_test_document(
    "BT /F1 10 Tf 20 100 Td <004101> Tj ET",
  )
  assert_eq(document.page(1).unwrap().text_content().text, "A\uFFFD")
  let diagnostics = document.text_recovery_diagnostics(1).unwrap()
  let invalid = diagnostics.filter(item => item.kind == InvalidCharacterCode)
  assert_eq(invalid.length(), 1)
  assert_eq(invalid[0].string_source.unwrap().bytes, b"\x01")
  assert_eq(invalid[0].source.unwrap().start, 1)
  let literal = unicode_search_test_document(["\uFFFD"])
  assert_true(
    !literal
    .text_recovery_diagnostics(1)
    .unwrap()
    .any(item => {
      item.kind == UnicodeMappingFallback || item.kind == InvalidCharacterCode
    }),
  )
}

///|
test "Malformed UTF16 mappings fall back to Encoding while odd destinations remain readable" {
  let invalid = truetype_test_document(
    truetype_test_fixture(),
    encoding="/Encoding << /BaseEncoding /WinAnsiEncoding /Differences [65 /Z] >>",
    unicode="D800",
  )
  assert_eq(invalid.page(1).unwrap().text_content().text, "Z")
  assert_true(
    invalid
    .text_recovery_diagnostics(1)
    .unwrap()
    .any(item => item.kind == UnicodeMappingFallback),
  )
  assert_eq(
    invalid.text_provenance(1).unwrap()[0].string_source.unwrap().bytes,
    b"A",
  )
  let odd = truetype_test_document(truetype_test_fixture(), unicode="5A")
  assert_eq(odd.page(1).unwrap().text_content().text, "Z")
  assert_true(
    !odd
    .text_recovery_diagnostics(1)
    .unwrap()
    .any(item => item.kind == UnicodeMappingFallback),
  )
}

///|
test "Missing simple-font metrics retain explicit PDF widths and use a located fallback" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream("", "BT /F1 10 Tf 20 100 Td (AB) Tj ET"),
    "<< /Type /Font /Subtype /TrueType /BaseFont /Unknown /Encoding /WinAnsiEncoding /FirstChar 65 /LastChar 65 /Widths [725] >>",
  ])
  let page = document.page(1).unwrap()
  assert_eq(page.text_content().text, "AB")
  assert_eq(page.text_content().items.map(item => item.advance_x), [7.25, 6.0])
  let observations = document
    .text_recovery_diagnostics(1)
    .unwrap()
    .filter(item => item.kind == FontMetricsRecovered)
  assert_eq(observations.length(), 2)
  assert_eq(observations[0].object_number, Some(5))
  assert_eq(observations[1].string_source.unwrap().bytes, b"B")
}

///|
test "Damaged CID width clauses cannot expand without bounds or erase valid metrics" {
  let document = cid_layout_test_document(
    "BT /F1 10 Tf 20 100 Td <00410042> Tj ET",
  )
  let descendant = document.document
    .lookup_object_or_null(6)
    .add_dict_entry(
      pdf_name_key("/W"),
      @syntax.PdfArray([
        @syntax.PdfInteger(0),
        @syntax.PdfInteger(2147483647),
        @syntax.PdfInteger(1),
        @syntax.PdfInteger(1),
        @syntax.PdfArray([@syntax.PdfInteger(620)]),
        @syntax.PdfInteger(2),
        @syntax.PdfArray([@syntax.PdfString(b"bad")]),
      ]),
    )
    .add_dict_entry(
      pdf_name_key("/W2"),
      @syntax.PdfArray([
        @syntax.PdfInteger(0),
        @syntax.PdfInteger(2147483647),
        @syntax.PdfInteger(-1000),
        @syntax.PdfInteger(500),
        @syntax.PdfInteger(880),
      ]),
    )
  document.document.add_object_given_number(6, descendant)
  let page = document.page(1).unwrap()
  assert_eq(page.text_content().text, "AB")
  assert_eq(page.text_content().items.map(item => item.advance_x), [6.2, 7.0])
  assert_eq(document.document.lookup_object_or_null(6), descendant)
  assert_eq(
    document
    .text_recovery_diagnostics(1)
    .unwrap()
    .filter(item => item.kind == FontMetricsRecovered)
    .length(),
    2,
  )
  assert_eq(document.text_provenance(1).unwrap().map(item => item.cid), [
    Some(1),
    Some(2),
  ])
}

///|
test "Recovery diagnostics terminate on descriptor aliases and stream filter cycles" {
  let aliases = truetype_test_document(truetype_test_fixture())
  aliases.document.add_object_given_number(6, @syntax.PdfIndirect(7))
  aliases.document.add_object_given_number(7, @syntax.PdfIndirect(6))
  assert_eq(aliases.page(1).unwrap().text_content().text, "Z")
  assert_true(
    aliases
    .text_recovery_diagnostics(1)
    .unwrap()
    .any(item => item.kind == FontDictionaryRecovered),
  )
  let charset = truetype_test_document(truetype_test_fixture())
  charset.document.add_object_given_number(
    6,
    charset.document
    .lookup_object_or_null(6)
    .add_dict_entry(pdf_name_key("/CharSet"), @syntax.PdfIndirect(9)),
  )
  charset.document.add_object_given_number(9, @syntax.PdfIndirect(10))
  charset.document.add_object_given_number(10, @syntax.PdfIndirect(9))
  assert_eq(charset.page(1).unwrap().text_content().text, "Z")
  assert_true(
    charset
    .text_recovery_diagnostics(1)
    .unwrap()
    .any(item => item.kind == FontDictionaryRecovered),
  )
  let filtered = truetype_test_document(truetype_test_fixture())
  guard filtered.document.lookup_object_or_null(7)
    is @syntax.PdfStreamObject(stream) else {
    fail("stream expected")
  }
  filtered.document.add_object_given_number(
    7,
    @syntax.pdf_stream(
      stream.dictionary.add_dict_entry(
        pdf_name_key("/Filter"),
        @syntax.PdfIndirect(9),
      ),
      stream.data,
    ),
  )
  filtered.document.add_object_given_number(9, @syntax.PdfIndirect(10))
  filtered.document.add_object_given_number(10, @syntax.PdfIndirect(9))
  assert_eq(filtered.page(1).unwrap().text_content().text, "Z")
  let unavailable = filtered
    .text_recovery_diagnostics(1)
    .unwrap()
    .filter(item => item.kind == FontStreamUnavailable)
  assert_eq(unavailable.length(), 1)
  assert_eq(unavailable[0].object_number, Some(7))
  assert_eq(unavailable[0].resource, "/F1/FontDescriptor/FontFile2")
}

///|
test "Indirect simple Encoding dictionaries and legal PostScript headers are not damaged CMaps" {
  let document = truetype_test_document(truetype_test_fixture())
  document.document.add_object_given_number(
    9,
    @syntax.PdfDictionary([
      (
        pdf_name_key("/BaseEncoding"),
        @syntax.PdfNameObject(pdf_name_key("/WinAnsiEncoding")),
      ),
    ]),
  )
  document.document.add_object_given_number(
    5,
    document.document
    .lookup_object_or_null(5)
    .add_dict_entry(pdf_name_key("/Encoding"), @syntax.PdfIndirect(9)),
  )
  guard document.document.lookup_object_or_null(8)
    is @syntax.PdfStreamObject(stream) else {
    fail("stream expected")
  }
  document.document.add_object_given_number(
    8,
    @syntax.pdf_stream(
      stream.dictionary,
      @syntax.StreamGot(
        b"/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def /Notice (ignored \\(text\\) <GG> 2 begincidchar) def 1 beginbfchar <41> <005A> endbfchar",
      ),
    ),
  )
  assert_eq(document.page(1).unwrap().text_content().text, "Z")
  assert_eq(document.text_recovery_diagnostics(1).unwrap(), [])
}

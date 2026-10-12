///|
test "text source ranges preserve UTF16 positions after bidi glyph reordering" {
  let document = unicode_search_test_document(["גד", "😀", "ﬁ", "אב"], positions=[
    (12.0, 100.0),
    (24.0, 100.0),
    (18.0, 100.0),
    (30.0, 100.0),
  ])
  let page = document.page(1).unwrap()
  assert_eq(page.text_content().text, "אב😀ﬁגד")
  let sources = page.text_sources()
  assert_eq(
    [
      for source in sources => (source.item_index, source.start, source.end)
    ],
    [(3, 0, 2), (1, 2, 4), (2, 4, 5), (0, 5, 7)],
  )
  assert_eq([ for source in sources => source.charcode ], [68, 66, 67, 65])
  let hit = document.search("fi")[0]
  assert_eq((hit.index, hit.length, hit.item_indices), (4, 1, [2]))
  assert_eq(page.select_text(1, 0, 1, 2).unwrap().text, "😀")
  for source in sources {
    assert_eq(source.font, "/F1")
    assert_true(
      page.text_content().text.get_view(start=source.start, end=source.end)
      is Some(_),
    )
  }
}

///|
test "text source ranges leave inferred word and line separators without a fake glyph" {
  let page = unicode_search_test_document(
      ["One", "Two", "Three"],
      positions=[(20.0, 100.0), (70.0, 100.0), (20.0, 80.0)],
      widths=[3000, 3000, 3000],
    )
    .page(1)
    .unwrap()
  assert_eq(page.text_content().text, "One Two\nThree")
  assert_eq(
    [
      for source in page.text_sources() => (source.start, source.end)
    ],
    [(0, 3), (4, 7), (8, 13)],
  )
}

///|
test "text diagnostics identify replacement characters and selected host font fallback" {
  let page = unicode_search_test_document(["\uFFFD"]).page(1).unwrap()
  let diagnostics = page.text_diagnostics()
  assert_eq([ for diagnostic in diagnostics => diagnostic.kind ], [
    ReplacementCharacter,
    HostFontFallback,
  ])
  for diagnostic in diagnostics {
    assert_eq(diagnostic.page, 1)
    assert_eq(diagnostic.resource, "/F1")
    assert_eq(diagnostic.source.item_index, 0)
    assert_eq(diagnostic.source.charcode, 65)
    assert_eq((diagnostic.source.start, diagnostic.source.end), (0, 1))
    assert_eq(diagnostic.object_number, None)
  }
}

///|
test "text diagnostics recognize available TrueType outlines and missing clip outlines" {
  let page = truetype_test_document(truetype_test_fixture()).page(1).unwrap()
  assert_eq(page.text_diagnostics(), [])
  let glyph = page.text_content().items[0]
  let damaged = { ..page, items: [Text({ ..glyph, type3_outline: None, })], }
  assert_eq(
    [
      for diagnostic in damaged.text_diagnostics() => diagnostic.kind
    ],
    [MissingClipOutline],
  )
  let missing = { ..damaged, fonts: [], }
  assert_eq(
    [
      for diagnostic in missing.text_diagnostics() => diagnostic.kind
    ],
    [MissingClipOutline, MissingFontResource],
  )
}

///|
test "document text diagnostics expose malformed and incomplete CMap source streams" {
  let document = cid_layout_test_document(
    "BT /F1 10 Tf 20 50 Td <41> Tj ET",
    cmap="1 begincodespacerange <00> <FF> endcodespacerange 1 begincidchar <41> 1 endcidchar <GG> 1 begincidchar <42> 2",
    tounicode="1 beginbfchar <41> <0041> endbfchar",
  )
  assert_eq(document.page(1).unwrap().text_content().text, "A")
  let diagnostics = document.text_diagnostics(1).unwrap()
  assert_eq([ for diagnostic in diagnostics => diagnostic.kind ], [
    CMapMalformedTokens(1),
    CMapIncompleteSection("cidchar"),
  ])
  for diagnostic in diagnostics {
    assert_eq(diagnostic.resource, "/F1/Encoding")
    assert_eq(diagnostic.object_number, Some(8))
    assert_eq(diagnostic.source.charcode, 65)
    assert_eq(diagnostic.source.item_index, 0)
  }
  assert_eq(document.text_diagnostics(0), None)
  assert_eq(document.text_diagnostics(2), None)
}

///|
test "document text diagnostics retain UseCMap cycle observations without losing text" {
  let document = cid_layout_test_document("BT /F1 10 Tf 20 50 Td <0041> Tj ET")
  let font_cmap = document.document.lookup_object_or_null(8)
  let stream = font_cmap.add_dict_entry(
    pdf_name_key("/UseCMap"),
    @syntax.PdfIndirect(8),
  )
  document.document.add_object_given_number(8, stream)
  assert_eq(document.page(1).unwrap().text_content().text, "A")
  let diagnostics = document.text_diagnostics(1).unwrap()
  assert_eq([ for diagnostic in diagnostics => diagnostic.kind ], [CMapCycle])
  assert_eq(diagnostics[0].object_number, Some(8))
}

///|
test "document diagnostics do not label legal multi scalar ToUnicode strings as malformed" {
  let text = "a\u0301😀fi"
  let document = unicode_search_test_document([text])
  assert_eq(document.page(1).unwrap().text_content().text, text)
  assert_eq(
    [
      for diagnostic in document.text_diagnostics(1).unwrap() => diagnostic.kind
    ],
    [HostFontFallback],
  )
}

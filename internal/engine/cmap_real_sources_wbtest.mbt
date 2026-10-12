///|
test "Real Adobe vertical CMaps inherit codespaces and preserve local overrides through PDF fonts" {
  let horizontal = cmap_real_test_source("90ms-RKSJ-H")
  let vertical = cmap_real_test_source("90ms-RKSJ-V")
  for source in [vertical, vertical.replace(old="/90ms-RKSJ-H usecmap", new="")] {
    let document = cid_layout_test_document(
      "BT /F1 10 Tf 20 100 Td <814182A0> Tj ET",
      cmap=source,
      cmap_parent=horizontal,
      tounicode="2 beginbfchar <8141> <3001> <82A0> <3042> endbfchar",
    )
    let page = document.page(1).unwrap()
    assert_eq(page.text_content().text, "、あ")
    assert_true(page.text_content().items.all(item => item.vertical))
    let provenance = document.text_provenance(1).unwrap()
    assert_eq(provenance.map(item => item.cid), [Some(7887), Some(843)])
    assert_eq(provenance.map(item => item.string_source.unwrap().bytes), [
      b"\x81\x41", b"\x82\xA0",
    ])
    assert_true(
      !document
      .text_recovery_diagnostics(1)
      .unwrap()
      .any(item => item.kind == CMapSourceUnavailable || item.kind == CMapCycle),
    )
  }
}

///|
test "Real Adobe UTF32 UseCMap sources retain four-byte origins and supplementary copy text" {
  let document = cid_layout_test_document(
    "BT /F1 10 Tf 20 100 Td <000030010001F600> Tj ET",
    cmap=cmap_real_test_source("UniJIS-UTF32-V"),
    cmap_parent=cmap_real_test_source("UniJIS-UTF32-H"),
    tounicode="2 beginbfchar <00003001> <3001> <0001F600> <D83DDE00> endbfchar",
  )
  let page = document.page(1).unwrap()
  assert_eq(page.text_content().text, "、😀")
  let provenance = document.text_provenance(1).unwrap()
  assert_eq(
    provenance.map(item => item.string_source.unwrap().bytes.length()),
    [4, 4],
  )
  assert_eq(provenance[0].cid, pdf_builtin_cmap_cid("UniJIS-UTF32-V", 0x3001))
  assert_eq(provenance.map(item => (item.source.start, item.source.end)), [
    (0, 1),
    (1, 3),
  ])
  assert_eq(
    page
    .select_text(
      provenance[1].source.item_index,
      0,
      provenance[1].source.item_index,
      2,
    )
    .unwrap().text,
    "😀",
  )
}

///|
test "Huge reader CMap ranges stay lazy before font reading and keep glyph provenance" {
  let document = cid_layout_test_document(
    "BT /F1 10 Tf 20 100 Td <0000004100000042> Tj ET",
    cmap="1 begincodespacerange <00000000> <7FFFFFFF> endcodespacerange 1 begincidrange <00000000> <7FFFFFFF> 1 endcidrange",
    tounicode="1 beginbfrange <00000000> <7FFFFFFF> <0000> endbfrange",
  )
  let page = document.page(1).unwrap()
  assert_eq(page.text_content().text, "AB")
  let provenance = document.text_provenance(1).unwrap()
  assert_eq(provenance.map(item => item.cid), [Some(66), Some(67)])
  assert_eq(
    provenance.map(item => item.string_source.unwrap().bytes.length()),
    [4, 4],
  )
  assert_true(
    document
    .text_recovery_diagnostics(1)
    .unwrap()
    .any(item => item.kind == CMapReaderFallback),
  )
}

///|
test "Deep UseCMap inheritance stops before dependency recursion and retains local mappings" {
  let document = cid_layout_test_document("BT /F1 10 Tf 20 100 Td <0041> Tj ET")
  let original = document.document.lookup_object_or_null(8)
  guard original is @syntax.PdfStreamObject(stream) else {
    fail("CMap stream expected")
  }
  for number in 11..<78 {
    let dictionary = stream.dictionary.add_dict_entry(
      pdf_name_key("/UseCMap"),
      @syntax.PdfIndirect(number + 1),
    )
    document.document.add_object_given_number(
      number,
      @syntax.pdf_stream(
        dictionary,
        @syntax.StreamGot(
          b"1 begincodespacerange <0000> <FFFF> endcodespacerange",
        ),
      ),
    )
  }
  document.document.add_object_given_number(
    8,
    @syntax.pdf_stream(
      stream.dictionary.add_dict_entry(
        pdf_name_key("/UseCMap"),
        @syntax.PdfIndirect(11),
      ),
      stream.data,
    ),
  )
  assert_eq(document.page(1).unwrap().text_content().text, "A")
  let diagnostics = document.text_recovery_diagnostics(1).unwrap()
  assert_true(diagnostics.any(item => item.kind == CMapReaderFallback))
  assert_true(diagnostics.any(item => item.kind == CMapSourceUnavailable))
  assert_true(!diagnostics.any(item => item.kind == CMapCycle))
}

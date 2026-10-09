///|
fn cmap_text_test_mixed_cmap() -> String {
  "/CMapType 1 def /WMode 0 def\n" +
  "5 begincodespacerange\n" +
  "<20> <7F>\n<0000> <00FF>\n<8000> <BFFF>\n" +
  "<C00000> <CFFFFF>\n<F0000000> <F0FFFFFF>\nendcodespacerange\n" +
  "5 begincidchar <41> 1 <20> 0 <8101> 2 <C00102> 1 <F0010203> 2 endcidchar\n"
}

///|
fn cmap_text_test_tounicode() -> String {
  "5 beginbfchar <41> <0041> <20> <0020> <8101> <03B2> " +
  "<C00102> <00660069> <F0010203> <65E5> endbfchar\n"
}

///|
fn cmap_text_test_page(contents : String) -> PdfPageModel raise {
  cid_layout_test_document(
    contents,
    cmap=cmap_text_test_mixed_cmap(),
    tounicode=cmap_text_test_tounicode(),
  )
  .page(1)
  .unwrap()
}

///|
fn cmap_text_test_high_page(contents : String) -> PdfPageModel raise {
  cid_layout_test_document(
    contents,
    cmap="/CMapType 1 def /WMode 0 def\n" +
      "1 begincodespacerange <F0000000> <FFFFFFFF> endcodespacerange\n" +
      "1 begincidchar <F0010203> 1 endcidchar",
    tounicode="1 beginbfchar <F0010203> <0041> endbfchar",
  )
  .page(1)
  .unwrap()
}

///|
test "viewer CMap recovery keeps unsigned four-byte ranges and lazy CID ranges" {
  let recovered = pdf_viewer_parse_cmap(
    @utf8.encode(
      "1 begincodespacerange <F0000000> <FFFFFFFF> endcodespacerange " +
      "1 begincidrange <F0000000> <FFFFFFFF> 7 endcidrange",
    )[:],
  )
  assert_eq(recovered.codespaces.length(), 1)
  assert_eq(recovered.codespaces[0].length, 4)
  assert_eq(recovered.codespaces[0].first.reinterpret_as_uint(), 0xF0000000U)
  assert_eq(recovered.codespaces[0].last.reinterpret_as_uint(), 0xFFFFFFFFU)
  assert_eq(recovered.cid_entries.length(), 1)
  assert_eq(
    pdf_viewer_cmap_lookup(
      recovered.cid_entries[:],
      0xF0000001U.reinterpret_as_int(),
    ),
    Some(8),
  )
}

///|
test "viewer CMap recovery restores text after pdflite drops high codespace" {
  let page = cmap_text_test_high_page("BT /F1 10 Tf 20 50 Td <F0010203> Tj ET")
  let text = page.text_content().items
  assert_eq(text.length(), 1)
  assert_eq([ for item in text => item.text ], ["A"])
  assert_eq(text[0].charcode.reinterpret_as_uint(), 0xF0010203U)
  assert_eq(text[0].advance_x, 5.0)
  assert_true(
    pdf_render_page_svg(page, 1.0, 0).contains(
      "data-pdf-font-outline=\"type1\"",
    ),
  )
}

///|
test "CMap codespaces select one through four bytes using unsigned bounds" {
  let parsed = @pdflite.pdf_parse_cmap_data(
    @utf8.encode(cmap_text_test_mixed_cmap()),
  )
  let codes = pdf_decode_cmap_codes(
    parsed, b"A\x81\x01\xC0\x01\x02\xF0\x01\x02\x03",
  )
  assert_eq([ for code in codes => code.bytes.length() ], [1, 2, 3, 4])
  assert_eq([ for code in codes => code.charcode.reinterpret_as_uint() ], [
    0x41U, 0x8101U, 0xC00102U, 0xF0010203U,
  ])
  assert_true(codes.iter().all(code => code.valid))
  let high = @pdflite.pdf_parse_cmap_data(
    b"1 begincodespacerange <8EA1A1A1> <8EA1FEFE> endcodespacerange",
  )
  let decoded = pdf_decode_cmap_codes(high, b"\x8E\xA1\xA1\xA1")
  assert_eq(decoded.length(), 1)
  assert_eq(decoded[0].charcode.reinterpret_as_uint(), 0x8EA1A1A1U)
  assert_eq(decoded[0].bytes.length(), 4)
}

///|
test "CMap decoding follows shortest matching codespace and preserves zeroes" {
  let overlap = @pdflite.pdf_parse_cmap_data(
    b"2 begincodespacerange <01> <7F> <0100> <01FF> endcodespacerange",
  )
  let short = pdf_decode_cmap_codes(overlap, b"\x01\x01")
  assert_eq([ for code in short => code.bytes.length() ], [1, 1])
  assert_eq([ for code in short => code.charcode ], [1, 1])
  let four = @pdflite.pdf_parse_cmap_data(
    b"2 begincodespacerange <01> <02> <00000003> <00000004> endcodespacerange",
  )
  let codes = pdf_decode_cmap_codes(four, b"\x01\x00\x00\x00\x03")
  assert_eq([ for code in codes => code.charcode ], [1, 3])
  assert_eq([ for code in codes => code.bytes.length() ], [1, 4])
}

///|
test "CMap inherited Identity codespaces are used only when local ranges are absent" {
  let inherited = @pdflite.pdf_parse_cmap_data(b"/Identity-H usecmap")
  let codes = pdf_decode_cmap_codes(inherited, b"\x00\x41\x00\x42")
  assert_eq([ for code in codes => code.charcode ], [65, 66])
  assert_eq([ for code in codes => code.bytes.length() ], [2, 2])
  let local_ranges = @pdflite.pdf_parse_cmap_data(
    b"/Identity-H usecmap 1 begincodespacerange <41> <42> endcodespacerange",
  )
  let codes = pdf_decode_cmap_codes(local_ranges, b"AB")
  assert_eq([ for code in codes => code.charcode ], [65, 66])
  assert_eq([ for code in codes => code.bytes.length() ], [1, 1])
}

///|
test "mixed-length CMap text draws CID outlines with mapped Unicode and advances" {
  let page = cmap_text_test_page(
    "BT /F1 10 Tf 20 50 Td <418101C00102F0010203> Tj ET",
  )
  let text = page.text_content().items
  assert_eq([ for item in text => item.text ], ["A", "\u03B2", "fi", "\u65E5"])
  assert_eq([ for item in text => item.advance_x ], [5.0, 3.0, 5.0, 3.0])
  let expected_x = [20.0, 25.0, 28.0, 33.0]
  for index, item in text {
    assert_eq(
      item.glyph_transform,
      Some([10.0, 0.0, 0.0, 10.0, expected_x[index], 50.0]),
    )
    guard item.type3_outline is Some(outline) else {
      fail("CID Type 1 outline missing")
    }
    assert_true(outline.contains("data-pdf-font-outline=\"type1\""))
  }
  assert_eq(text[3].charcode.reinterpret_as_uint(), 0xF0010203U)
  let selection = pdf_select_page(page, {
    min_x: 25.0,
    min_y: 40.0,
    max_x: 28.0,
    max_y: 60.0,
  })
  assert_true(selection.text.contains("\u03B2"))
}

///|
test "mixed-length CMap strings share TJ adjustments and following Tj position" {
  let page = cmap_text_test_page(
    "BT /F1 10 Tf 20 50 Td [<418101> 100 <C00102>] TJ <F0010203> Tj ET",
  )
  let text = page.text_content().items
  assert_eq(text.length(), 4)
  let expected_x = [20.0, 25.0, 27.0, 32.0]
  for index, item in text {
    assert_eq(
      item.glyph_transform,
      Some([10.0, 0.0, 0.0, 10.0, expected_x[index], 50.0]),
    )
  }
}

///|
test "CMap word spacing depends on the source length even for equal character codes" {
  let page = cmap_text_test_page(
    "BT /F1 10 Tf 7 Tw 1 Tc 50 Tz 20 50 Td <20> Tj <0020> Tj <41> Tj ET",
  )
  let text = page.text_content().items
  assert_eq(text.length(), 3)
  assert_eq([ for item in text => item.charcode ], [32, 32, 65])
  assert_eq([ for item in text => item.advance_x ], [6.0, 2.5, 3.0])
  assert_eq(text[1].glyph_transform, Some([5.0, 0.0, 0.0, 10.0, 26.0, 50.0]))
  assert_eq(text[2].glyph_transform, Some([5.0, 0.0, 0.0, 10.0, 28.5, 50.0]))
}

///|
test "CMap text quotes preserve original Tw while applying it only to source spaces" {
  let page = cmap_text_test_page(
    "BT /F1 10 Tf 12 TL 20 100 Td <41> Tj <8101> ' 7 1 <20> \" <002041> Tj ET",
  )
  let text = page.text_content().items
  assert_eq(text.length(), 5)
  assert_eq([ for item in text => item.advance_x ], [5.0, 3.0, 12.0, 5.0, 6.0])
  let positions = [
    (20.0, 100.0),
    (20.0, 88.0),
    (20.0, 76.0),
    (32.0, 76.0),
    (37.0, 76.0),
  ]
  for index, item in text {
    let (x, y) = positions[index]
    assert_eq(item.glyph_transform, Some([10.0, 0.0, 0.0, 10.0, x, y]))
  }
}

///|
test "CMap invalid and truncated codes consume one byte without losing valid text" {
  let page = cmap_text_test_page("BT /F1 10 Tf 20 50 Td <FF4181> Tj ET")
  let text = page.text_content().items
  assert_eq([ for item in text => item.charcode ], [0, 65, 0])
  assert_eq([ for item in text => item.text ], ["\uFFFD", "A", "\uFFFD"])
  assert_eq([ for item in text => item.advance_x ], [4.0, 5.0, 4.0])
  assert_eq(text[1].glyph_transform, Some([10.0, 0.0, 0.0, 10.0, 24.0, 50.0]))
  let parsed = @pdflite.pdf_parse_cmap_data(
    @utf8.encode(cmap_text_test_mixed_cmap()),
  )
  let codes = pdf_decode_cmap_codes(parsed, b"\xFF\x41\x81")
  assert_eq([ for code in codes => code.valid ], [false, true, false])
  assert_eq([ for code in codes => code.bytes.length() ], [1, 1, 1])
}

///|
test "mixed-length CMap text clipping preserves three and four byte CID mapping" {
  let page = cmap_text_test_page(
    "BT /F1 10 Tf 7 Tr 20 50 Td <C00102F0010203> Tj ET 0 0 150 150 re f",
  )
  let paths = text_clip_test_paths(page)
  assert_eq(paths.length(), 1)
  assert_eq(
    paths[0].clip_path,
    Some(
      "M 20 150 L 25 150 L 25 143 L 20 143 M 25 150 L 30 150 L 30 143 L 25 143",
    ),
  )
}

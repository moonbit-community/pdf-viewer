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
test "viewer recovers high-range ToUnicode mappings lazily" {
  let recovered = pdf_viewer_parse_cmap(
    @utf8.encode(
      "1 beginbfrange <80000000> <FFFFFFFF> <00000000> endbfrange " +
      "2 beginbfchar <F0010203> <D83DDE00> <F0010204> <00660069> endbfchar " +
      "1 beginbfrange <0041> <0043> [<0061> <0062> <0063>] endbfrange",
    )[:],
  )
  assert_eq(recovered.unicode_entries.length(), 6)
  assert_eq(
    pdf_viewer_unicode_lookup(
      recovered.unicode_entries[:],
      0xF0010203U.reinterpret_as_int(),
    ),
    Some(b"\xD8\x3D\xDE\x00"),
  )
  assert_eq(
    pdf_viewer_unicode_lookup(
      recovered.unicode_entries[:],
      0xF0010204U.reinterpret_as_int(),
    ),
    Some(b"\x00\x66\x00\x69"),
  )
  assert_eq(
    pdf_viewer_unicode_lookup(
      recovered.unicode_entries[:],
      0xFFFFFFFFU.reinterpret_as_int(),
    ),
    Some(b"\x7F\xFF\xFF\xFF"),
  )
  assert_eq(
    pdf_viewer_unicode_lookup(recovered.unicode_entries[:], 0x43),
    Some(b"\x00\x63"),
  )
}

///|
test "odd-byte ToUnicode destinations are decoded as UTF-16BE" {
  assert_eq(pdf_viewer_tounicode_text(b"A"), Some("A"))
  assert_eq(pdf_viewer_tounicode_text(b"\xF0"), Some("\u00F0"))
}

///|
test "recovered ToUnicode takes precedence over CID collection fallback" {
  let document = cid_layout_test_document(
    "BT /F1 10 Tf <F0010203> Tj ET",
    cmap="/CMapType 1 def /WMode 0 def\n" +
      "1 begincodespacerange <F0000000> <FFFFFFFF> endcodespacerange\n" +
      "1 begincidchar <F0010203> 843 endcidchar",
    tounicode="1 beginbfrange <F0010203> <F0010205> <D83DDE00> endbfrange",
  )
  let page = document.pages[0]
  let font_object = pdf_viewer_ttf_font_object(
    document.document,
    page.resources,
    "/F1",
  ).unwrap()
  let font = match pdf_read_font_for_viewer(document.document, font_object) {
    @pdflite.PdfFontCIDKeyed(font) => font
    _ => fail("expected the CID test font")
  }
  let font_with_collection_fallback = {
    ..font,
    composite: {
      ..font.composite,
      cid_system_info: {
        ..font.composite.cid_system_info,
        ordering: b"Japan1",
      },
    },
  }
  let font_without_reader_map = {
    ..font_with_collection_fallback,
    composite: {
      ..font_with_collection_fallback.composite,
      cid_fontdescriptor: {
        ..font_with_collection_fallback.composite.cid_fontdescriptor,
        tounicode: None,
      },
    },
  }
  let initial = @pdflite.pdf_content_initial_operator_state(
    0.0, 0.0, 200.0, 200.0,
  )
  let state = {
    ..initial,
    text_state: {
      ..initial.text_state,
      font: "/F1",
      font_size: 10.0,
      current_font: @pdflite.PdfFontCIDKeyed(font_without_reader_map),
    },
  }
  let (result, _) = pdf_apply_cid_text_op(
    document.document,
    state,
    font_without_reader_map,
    page.resources,
    @content.Op_Tj(b"\xF0\x01\x02\x03"),
  )
  guard result.entries[0].object is @pdflite.PdfContentGlyphObject(_, _, text) else {
    fail("expected a recovered CID glyph entry")
  }
  assert_eq(text, @utf8.decode(b"\xF0\x9F\x98\x80"))
}

///|
test "partial ToUnicode falls back to the Adobe CID collection map" {
  let document = cid_layout_test_document(
    "BT /F1 10 Tf <F0010203> Tj ET",
    cmap="/CMapType 1 def /WMode 0 def\n" +
      "1 begincodespacerange <F0000000> <FFFFFFFF> endcodespacerange\n" +
      "1 begincidchar <F0010203> 843 endcidchar",
    tounicode="1 beginbfchar <F0010204> <0042> endbfchar",
  )
  let page = document.pages[0]
  let font_object = pdf_viewer_ttf_font_object(
    document.document,
    page.resources,
    "/F1",
  ).unwrap()
  let font = match pdf_read_font_for_viewer(document.document, font_object) {
    @pdflite.PdfFontCIDKeyed(font) => font
    _ => fail("expected the CID test font")
  }
  let font_with_collection_fallback = {
    ..font,
    composite: {
      ..font.composite,
      cid_system_info: {
        ..font.composite.cid_system_info,
        ordering: b"Japan1",
      },
    },
  }
  let initial = @pdflite.pdf_content_initial_operator_state(
    0.0, 0.0, 200.0, 200.0,
  )
  let state = {
    ..initial,
    text_state: {
      ..initial.text_state,
      font: "/F1",
      font_size: 10.0,
      current_font: @pdflite.PdfFontCIDKeyed(font_with_collection_fallback),
    },
  }
  let (result, _) = pdf_apply_cid_text_op(
    document.document,
    state,
    font_with_collection_fallback,
    page.resources,
    @content.Op_Tj(b"\xF0\x01\x02\x03"),
  )
  guard result.entries[0].object is @pdflite.PdfContentGlyphObject(_, _, text) else {
    fail("expected a CID collection fallback entry")
  }
  assert_eq(text, "\u3042")
}

///|
test "named ToUnicode UseCMap recovers reader-dropped Adobe Unicode entries" {
  let document = cid_layout_test_document(
    "BT /F1 10 Tf <034B> Tj ET",
    cmap="/CMapType 1 def /WMode 0 def\n" +
      "1 begincodespacerange <0000> <FFFF> endcodespacerange\n" +
      "1 begincidchar <034B> 843 endcidchar",
    tounicode="/Adobe-Japan1-UCS2 usecmap",
  )
  let page = document.pages[0]
  let font_object = pdf_viewer_ttf_font_object(
    document.document,
    page.resources,
    "/F1",
  ).unwrap()
  let to_unicode_stream = document.document
    .lookup_direct(pdf_name_key("/ToUnicode"), font_object)
    .unwrap()
  let to_unicode_source = @utf8.decode_lossy(
    document.document.pdf_decode_stream(to_unicode_stream).stream_bytes()[:],
  ) catch {
    _ => fail("expected the ToUnicode stream to decode")
  }
  assert_true(to_unicode_source.contains("Adobe-Japan1-UCS2"))
  let unicode_recovery = pdf_viewer_tounicode_recovery_for_font(
    document.document,
    page.resources,
    "/F1",
  ).unwrap()
  assert_eq(unicode_recovery.usecmap, Some(pdf_name_key("/Adobe-Japan1-UCS2")))
  assert_eq(
    pdf_viewer_unicode_text_with_recovery(unicode_recovery, 843),
    Some("\u3042"),
  )
  let font = match pdf_read_font_for_viewer(document.document, font_object) {
    @pdflite.PdfFontCIDKeyed(font) => font
    _ => fail("expected the CID test font")
  }
  let font_without_reader_map = {
    ..font,
    composite: {
      ..font.composite,
      cid_fontdescriptor: {
        ..font.composite.cid_fontdescriptor,
        tounicode: None,
      },
    },
  }
  let initial = @pdflite.pdf_content_initial_operator_state(
    0.0, 0.0, 200.0, 200.0,
  )
  let state = {
    ..initial,
    text_state: {
      ..initial.text_state,
      font: "/F1",
      font_size: 10.0,
      current_font: @pdflite.PdfFontCIDKeyed(font_without_reader_map),
    },
  }
  let (result, _) = pdf_apply_cid_text_op(
    document.document,
    state,
    font_without_reader_map,
    page.resources,
    @content.Op_Tj(b"\x03\x4B"),
  )
  guard result.entries[0].object is @pdflite.PdfContentGlyphObject(_, _, text) else {
    fail("expected a recovered named ToUnicode glyph entry")
  }
  assert_eq(text, "\u3042")
}

///|
test "reader-loss recovery composes indirect UseCMap streams locally first" {
  let document = cid_layout_test_document(
    "BT /F1 10 Tf <F0010203> Tj ET",
    cmap="1 begincidchar <F0010203> 2 endcidchar",
    tounicode="1 beginbfchar <F0010203> <0042> endbfchar",
    cmap_parent="/CMapType 1 def /WMode 0 def\n" +
      "1 begincodespacerange <F0000000> <FFFFFFFF> endcodespacerange\n" +
      "1 begincidchar <F0010203> 1 endcidchar",
    tounicode_parent="1 beginbfchar <F0010203> <0041> endbfchar",
  )
  let page = document.pages[0]
  let font_object = pdf_viewer_ttf_font_object(
    document.document,
    page.resources,
    "/F1",
  ).unwrap()
  let font = match pdf_read_font_for_viewer(document.document, font_object) {
    @pdflite.PdfFontCIDKeyed(font) => font
    _ => fail("expected the CID test font")
  }
  let (object_number, parsed) = match font.encoding {
    @pdflite.PdfExternalCMap(number, parsed) => (number, parsed)
    _ => fail("expected an external CMap")
  }
  let font_without_reader_tables = {
    ..font,
    encoding: @pdflite.PdfExternalCMap(object_number, {
      ..parsed,
      map: [],
      cid_map: [],
      notdef_map: [],
      codespaces: [],
      usecmap: None,
      wmode: None,
    }),
    composite: {
      ..font.composite,
      cid_fontdescriptor: {
        ..font.composite.cid_fontdescriptor,
        tounicode: None,
      },
    },
  }
  let initial = @pdflite.pdf_content_initial_operator_state(
    0.0, 0.0, 200.0, 200.0,
  )
  let state = {
    ..initial,
    text_state: {
      ..initial.text_state,
      font: "/F1",
      font_size: 10.0,
      current_font: @pdflite.PdfFontCIDKeyed(font_without_reader_tables),
    },
  }
  let (result, glyphs) = pdf_apply_cid_text_op(
    document.document,
    state,
    font_without_reader_tables,
    page.resources,
    @content.Op_Tj(b"\xF0\x01\x02\x03"),
  )
  guard result.entries[0].object is @pdflite.PdfContentGlyphObject(_, _, text) else {
    fail("expected a recovered CID glyph entry")
  }
  assert_eq(text, "B")
  assert_eq(glyphs[0].advance_x, 3.0)
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

///|
test "CMap recovery reports malformed tokens and incomplete sections" {
  let recovery = pdf_viewer_parse_cmap(b"<GG> 1 begincidchar <41> 7")
  assert_eq(recovery.diagnostics.malformed_tokens, 1)
  assert_eq(recovery.diagnostics.incomplete_sections, ["cidchar"])
  assert_true(recovery.source_available)
}

///|
test "CMap recovery keeps reader fallback when source stream is unavailable" {
  let document = @pdflite.pdf_document_empty()
  let recovery = pdf_viewer_cmap_recovery_of_object(
    document,
    @syntax.PdfIndirect(99),
    Map([]),
  ).unwrap()
  assert_false(recovery.source_available)
  assert_true(recovery.diagnostics.source_unavailable)
  assert_eq(recovery.diagnostics.incomplete_sections, [])
}

///|
test "CMap recovery cuts indirect UseCMap cycles and records the reason" {
  let document = @pdflite.pdf_document_empty()
  let name_use_cmap = @core.pdf_name_of_bytes(@utf8.encode("/UseCMap"))
  let body_one = b"1 begincidchar <41> 1 endcidchar"
  let body_two = b"1 begincidchar <42> 2 endcidchar"
  let stream_one = @syntax.pdf_stream(
    @syntax.PdfDictionary([
      (
        @core.pdf_name_of_bytes(@utf8.encode("/Length")),
        @syntax.PdfInteger(body_one.length()),
      ),
      (name_use_cmap, @syntax.PdfIndirect(2)),
    ]),
    @syntax.StreamGot(body_one),
  )
  let stream_two = @syntax.pdf_stream(
    @syntax.PdfDictionary([
      (
        @core.pdf_name_of_bytes(@utf8.encode("/Length")),
        @syntax.PdfInteger(body_two.length()),
      ),
      (name_use_cmap, @syntax.PdfIndirect(1)),
    ]),
    @syntax.StreamGot(body_two),
  )
  document.add_object_given_number(1, stream_one)
  document.add_object_given_number(2, stream_two)
  let recovery = pdf_viewer_cmap_recovery_of_object(
    document,
    @syntax.PdfIndirect(1),
    Map([]),
  ).unwrap()
  assert_true(recovery.diagnostics.usecmap_cycle)
  assert_eq(pdf_viewer_cmap_lookup(recovery.cid_entries[:], 0x41), Some(1))
  assert_eq(pdf_viewer_cmap_lookup(recovery.cid_entries[:], 0x42), Some(2))
}

///|
test "CMap Unicode byte strings allow long mappings, whitespace and empty destinations" {
  let recovery = pdf_viewer_parse_cmap(
    b"2 beginbfchar <F0010203> <0061 0062 D83DDE00> <41> <> endbfchar 1 beginbfrange <F0010204> <F0010205> <006100620063> endbfrange",
  )
  assert_eq(recovery.diagnostics.malformed_tokens, 0)
  assert_eq(recovery.unicode_entries.length(), 3)
  assert_eq(
    pdf_viewer_unicode_lookup(
      recovery.unicode_entries[:],
      0xF0010203U.reinterpret_as_int(),
    ),
    Some(b"\x00\x61\x00\x62\xD8\x3D\xDE\x00"),
  )
  assert_eq(
    pdf_viewer_unicode_lookup(recovery.unicode_entries[:], 65),
    Some(b""),
  )
  assert_eq(
    pdf_viewer_unicode_lookup(
      recovery.unicode_entries[:],
      0xF0010205U.reinterpret_as_int(),
    ),
    Some(b"\x00\x61\x00\x62\x00\x64"),
  )
}

///|
test "CMap long destinations do not expand the allowed source code width" {
  let recovery = pdf_viewer_parse_cmap(
    b"1 begincodespacerange <0100000000> <01FFFFFFFF> endcodespacerange 1 beginbfchar <01FFFFFFFF> <0041> endbfchar 1 begincidrange <0100000000> <01FFFFFFFF> 7 endcidrange 1 begincidchar <> 8 endcidchar",
  )
  assert_true(recovery.codespaces.is_empty())
  assert_true(recovery.unicode_entries.is_empty())
  assert_true(recovery.cid_entries.is_empty())
}

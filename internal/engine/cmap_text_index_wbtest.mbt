///|
test "CID operation index preserves first reader mapping and recovery precedence" {
  let document = cid_layout_test_document(
    "BT /F1 10 Tf 20 50 Td <00410042> Tj ET",
  )
  let collected = pdf_collected_entries_of_page(
    document.document,
    document.pages[0],
  )
  guard collected[0].state.text_state.current_font
    is @pdflite.PdfFontCIDKeyed(original) else {
    fail("Expected a CID font")
  }
  let mappings : Array[(Int, Bytes)] = [
    (0, b"\x00\x40"),
    (65, b"\x00\x41"),
    (65, b"\x00\x42"),
    (66, b""),
    (67, b"\xD8\x00"),
    (67, b"\x00\x43"),
    (68, b"\x41"),
    (69, b"\xFF\xFD"),
    (70, b"\xD8\x3D\xDE\x00"),
    (-1, b"\x00\x5A"),
  ]
  let recovered = pdf_viewer_parse_cmap(
    b"4 beginbfchar <0041> <0058> <0042> <0059> <0043> <00660069> <0047> <03B2> endbfchar"[:],
  )
  let large = [..mappings, ..[ for code in 1000..<1256 => (code, b"\x00\x41") ]]
  for entries in [Some(mappings), Some(large), None] {
    let font = {
      ..original,
      composite: {
        ..original.composite,
        cid_fontdescriptor: {
          ..original.composite.cid_fontdescriptor,
          tounicode: entries,
        },
      },
    }
    let codes = [
      for index in 0..<64 => {
        let value = match index % 11 {
          0 => 0
          9 => -1
          10 => 0
          offset => 64 + offset
        }
        {
          charcode: value,
          bytes: match value {
            -1 => b"\xFF\xFF\xFF\xFF"[:]
            _ =>
              Bytes::makei(2, i => (if i == 0 { 0 } else { value }).to_byte())[:]
          },
          valid: index % 11 != 10,
        }
      }
    ]
    let glyphs = [
      for index, code in codes => {
        { ..collected[index % 2].text_glyph.unwrap(), charcode: code.charcode, }
      }
    ]
    let state = collected[0].state
    for recovery in [Some(recovered), None] {
      let expected = [
        for index, glyph in glyphs => {
          pdf_cmap_glyph_entry(state, font, codes[index], glyph, None, recovery)
        }
      ]
      assert_eq(
        pdf_cid_text_entries(state, font, codes[:], glyphs[:], None, recovery),
        expected,
      )
      // A full index still marks absent entries, whereas a capacity miss uses
      // the original lookup. Both must preserve invalid first duplicates.
      let bounded = pdf_cid_reader_unicode(font, codes[:], limit=3)
      assert_true(bounded.length() <= 3)
      for code in codes {
        assert_eq(
          pdf_cmap_unicode_of_code(
            font,
            code,
            None,
            recovery,
            reader_index=Some(bounded),
          ),
          pdf_cmap_unicode_of_code(font, code, None, recovery),
        )
      }
    }
    if entries is Some(_) {
      let index = pdf_cid_reader_unicode(font, codes[:])
      assert_eq(index.get(65), Some((true, Some("A"))))
      assert_eq(index.get(66), Some((true, Some(""))))
      assert_eq(index.get(67), Some((true, None)))
      assert_eq(index.get(68), Some((true, Some("A"))))
      assert_eq(index.get(71), Some((false, None)))
      assert_eq(index.get(-1), Some((true, Some("Z"))))
    }
  }
}

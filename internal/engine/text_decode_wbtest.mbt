///|
fn text_decode_test_legacy(
  state : @pdflite.PdfContentOperatorState,
  glyph : @pdflite.PdfContentTextGlyphPlacement,
  unicode : PdfViewerCMapRecovery?,
) -> @pdflite.PdfContentJsonEntry raise {
  let font = state.text_state.current_font
  let entry = state.content_text_glyph_entry(font, glyph)
  let text = match
    unicode.bind(map => {
      pdf_viewer_unicode_text_with_recovery(map, glyph.charcode)
    }) {
    Some(text) => Some(text)
    None => pdf_font_encoding_text(font, glyph.charcode)
  }
  match (entry.object, text) {
    (@pdflite.PdfContentGlyphObject(name, code, _), Some(text)) =>
      { ..entry, object: @pdflite.PdfContentGlyphObject(name, code, text), }
    _ => entry
  }
}

///|
test "Operation text decoder preserves all byte codes and Unicode recovery" {
  for
    document in [
      provenance_test_document("BT /F1 10 Tf (ABBA) Tj ET"),
      unicode_search_test_document(["", "😀", "ﬃ", "\uFFFD", "אב"]),
      truetype_test_document(truetype_test_fixture(), unicode="D800"),
      truetype_test_document(truetype_test_fixture(), unicode="41"),
    ] {
    let collected = pdf_collected_entries_of_page(
        document.document,
        document.pages[0],
      )[0]
    let state = collected.state
    let unicode = pdf_viewer_tounicode_recovery_for_font(
      document.document,
      collected.font_object,
    )
    let glyphs = [
      for index in 0..<512 => {
        { ..collected.text_glyph.unwrap(), charcode: index % 256, }
      }
    ]
    let actual = pdf_simple_text_entries(
      state,
      state.text_state.current_font,
      glyphs[:],
      unicode,
    )
    for index, glyph in glyphs {
      assert_eq(actual[index], text_decode_test_legacy(state, glyph, unicode))
    }
  }
}

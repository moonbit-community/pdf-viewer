///|
/// Decode each distinct simple-font code once per text operation. The final
/// viewer mapping takes precedence before constructing an entry: the generic
/// extractor otherwise rebuilds ToUnicode tables and produces discarded text.
/// Only immutable code/text values share this bounded, operation-local index;
/// every placement retains its own original bounding box.
fn pdf_simple_text_entries(
  state : @pdflite.PdfContentOperatorState,
  font : @pdflite.PdfFont,
  glyphs : ArrayView[@pdflite.PdfContentTextGlyphPlacement],
  unicode : PdfViewerCMapRecovery?,
) -> Array[@pdflite.PdfContentJsonEntry] raise @core.PdfError {
  let encoding = pdf_font_encoding_base(font)
  let objects : Map[Int, @pdflite.PdfContentObject] = Map([])
  let glyph_state = @pdflite.PdfContentStateGlyph(
    state.text_state.content_glyph_state(state.clipping_path),
  )
  [
    for glyph in glyphs => {
      let code = glyph.charcode
      let object = match objects.get(code) {
        Some(object) => object
        None => {
          // Preserve the dependency's byte validation and ASCII source-code
          // spelling, separately from the Unicode string used by selection.
          let bytes = font.content_bytes_of_charcode(code)
          let text = match
            unicode.bind(map => pdf_viewer_unicode_text_with_recovery(map, code)) {
            Some(text) => Some(text)
            None => pdf_font_encoding_text(encoding, code)
          }
          let object = match text {
            Some(text) =>
              @pdflite.PdfContentGlyphObject(
                code,
                @ascii.decode_lossy(bytes),
                text,
              )
            None => state.content_text_glyph_entry(font, glyph).object
          }
          // This entry point handles one-byte Standard/simple fonts. Avoid
          // retaining arbitrary CID codes if a future caller changes that.
          if code >= 0 && code <= 255 {
            objects[code] = object
          }
          object
        }
      }
      { object, state: glyph_state, bounding_box: glyph.bounding_box, }
    }
  ]
}

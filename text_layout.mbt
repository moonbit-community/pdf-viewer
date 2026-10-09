///|
/// Collect entries and glyph placements from one layout pass so the paint,
/// selection, text clips and following operators share the corrected advance.
fn pdf_apply_op_for_viewer(
  document : @pdflite.PdfDocument,
  state : @pdflite.PdfContentOperatorState,
  resources : @syntax.PdfObject,
  op : @content.PdfContentOp,
) -> (
  @pdflite.PdfContentOperatorResourceResult,
  Array[@pdflite.PdfContentTextGlyphPlacement],
) raise @core.PdfError {
  match op {
    @content.Op_Tj(_)
    | @content.Op_TJ(_)
    | @content.Op_quote(_)
    | @content.Op_double_quote(_, _, _) => {
      let original_font = state.text_state.current_font
      if original_font is @pdflite.PdfFontCIDKeyed(font) &&
        font.encoding is @pdflite.PdfExternalCMap(_, parsed) &&
        !original_font.content_is_vertical() {
        return pdf_apply_cmap_text_op(state, font, parsed, op)
      }
      let layout = state.text_state.content_apply_text_op(
        original_font,
        state.ctm,
        op,
      )
      let next_state = { ..state, text_state: layout.text_state, }
      let entries = [
        for glyph in layout.glyphs => {
          next_state.content_text_glyph_entry(original_font, glyph)
        }
      ]
      ({ state: next_state, entries, }, layout.glyphs)
    }
    _ => (document.content_apply_resource_op(state, resources, op), [])
  }
}

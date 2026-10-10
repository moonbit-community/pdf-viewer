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
  match pdf_apply_colour_op_for_viewer(document, state, resources, op) {
    Some(state) => return ({ state, entries: [], }, [])
    None => ()
  }
  match op {
    @content.Op_Tf(_, _) => {
      let result = document.content_apply_resource_op(state, resources, op) catch {
        @core.CIDFontDescriptorExpected
        | @core.FontWidthsExpected
        | @core.FontWidthExpected
        | @core.FontFirstCharExpected
        | @core.FontLastCharExpected as error => {
          let text_state = state.text_state.content_apply_text_state_op(op)
          guard pdf_viewer_ttf_font_object(document, resources, text_state.font)
            is Some(object) else {
            raise error
          }
          let current_font = pdf_read_font_for_viewer(document, object)
          {
            state: { ..state, text_state: { ..text_state, current_font, }, },
            entries: [],
          }
        }
        error => raise error
      }
      let next = result.state
      let current_font = match
        pdf_viewer_ttf_font_object(document, resources, next.text_state.font) {
        Some(object) =>
          pdf_font_with_recovered_tounicode(
            document,
            object,
            next.text_state.current_font,
          )
        None => next.text_state.current_font
      }
      (
        {
          ..result,
          state: { ..next, text_state: { ..next.text_state, current_font, }, },
        },
        [],
      )
    }
    @content.Op_Tj(_)
    | @content.Op_TJ(_)
    | @content.Op_quote(_)
    | @content.Op_double_quote(_, _, _) => {
      let original_font = state.text_state.current_font
      if original_font is @pdflite.PdfFontCIDKeyed(font) {
        return pdf_apply_cid_text_op(document, state, font, resources, op)
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

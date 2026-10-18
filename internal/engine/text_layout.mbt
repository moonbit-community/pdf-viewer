///|
/// Apply the same font recovery used by Tf to an ExtGState font binding.
fn pdf_apply_extgstate_font_for_viewer(
  document : @pdflite.PdfDocument,
  state : @pdflite.PdfContentOperatorState,
  extgstate : @syntax.PdfObject,
  resource_context? : PdfResourceBuildContext? = None,
) -> @pdflite.PdfContentOperatorState raise @core.PdfError {
  match document.lookup_direct(pdf_name_key("/Font"), extgstate) {
    Some(@syntax.PdfArray([@syntax.PdfIndirect(number) as object, size])) => {
      let font = pdf_read_font_for_viewer(document, object, resource_context~)
      let font_size = document.get_number(size) catch {
        _ => state.text_state.font_size
      }
      {
        ..state,
        text_state: {
          ..state.text_state,
          font: "__EXTGSTATE__" + number.to_string(),
          font_size,
          current_font: font,
        },
      }
    }
    _ => state
  }
}

///|
/// Collect entries and glyph placements from one layout pass so the paint,
/// selection, text clips and following operators share the corrected advance.
fn pdf_apply_op_for_viewer(
  document : @pdflite.PdfDocument,
  state : @pdflite.PdfContentOperatorState,
  resources : @syntax.PdfObject,
  op : @content.PdfContentOp,
  font_object : @syntax.PdfObject?,
  resource_context? : PdfResourceBuildContext? = None,
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
      let text_state = state.text_state.content_apply_text_state_op(op)
      // Always resolve the current resource binding: a recovered unmatched Q
      // can restore a parent's name cache inside a different Form dictionary.
      // The page context shares indirect fonts by object number instead.
      let current_font = match
        pdf_viewer_ttf_font_object(document, resources, text_state.font) {
        Some(object) =>
          pdf_read_font_for_viewer(document, object, resource_context~)
        None => state.text_state.current_font
      }
      let text_state = text_state.content_cache_font(
        text_state.font,
        current_font,
      )
      ({ state: { ..state, text_state, }, entries: [], }, [])
    }
    @content.Op_Tj(_)
    | @content.Op_TJ(_)
    | @content.Op_quote(_)
    | @content.Op_double_quote(_, _, _) => {
      let original_font = state.text_state.current_font
      if original_font is @pdflite.PdfFontCIDKeyed(font) {
        return pdf_apply_cid_text_op(
          document,
          state,
          font,
          font_object,
          op,
          resource_context~,
        )
      }
      let layout = state.text_state.content_apply_text_op(
        original_font,
        state.ctm,
        op,
      )
      let next_state = { ..state, text_state: layout.text_state, }
      let unicode = if original_font
        is (@pdflite.PdfFontStandard(_) | @pdflite.PdfFontSimple(_)) {
        pdf_viewer_tounicode_recovery_for_font(
          document,
          font_object,
          resource_context~,
        )
      } else {
        None
      }
      let entries = pdf_simple_text_entries(
        next_state,
        original_font,
        layout.glyphs[:],
        unicode,
      )
      ({ state: next_state, entries, }, layout.glyphs)
    }
    _ => (document.content_apply_resource_op(state, resources, op), [])
  }
}

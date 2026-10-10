///|
/// Apply the same font recovery used by Tf to an ExtGState font binding.
fn pdf_apply_extgstate_font_for_viewer(
  document : @pdflite.PdfDocument,
  state : @pdflite.PdfContentOperatorState,
  extgstate : @syntax.PdfObject,
) -> @pdflite.PdfContentOperatorState raise @core.PdfError {
  match document.lookup_direct(pdf_name_key("/Font"), extgstate) {
    Some(@syntax.PdfArray([@syntax.PdfIndirect(number) as object, size])) => {
      let font = pdf_read_font_for_viewer(document, object)
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
        return pdf_apply_cid_text_op(document, state, font, font_object, op)
      }
      let layout = state.text_state.content_apply_text_op(
        original_font,
        state.ctm,
        op,
      )
      let next_state = { ..state, text_state: layout.text_state, }
      let unicode = if original_font is @pdflite.PdfFontStandard(_) {
        pdf_viewer_tounicode_recovery_for_font(document, font_object)
      } else {
        None
      }
      let entries = [
        for glyph in layout.glyphs => {
          let entry = next_state.content_text_glyph_entry(original_font, glyph)
          let text = unicode.bind(map => {
            pdf_viewer_unicode_text_with_recovery(map, glyph.charcode)
          })
          match (entry.object, text) {
            (@pdflite.PdfContentGlyphObject(name, code, _), Some(text)) =>
              {
                ..entry,
                object: @pdflite.PdfContentGlyphObject(name, code, text),
              }
            _ => entry
          }
        }
      ]
      ({ state: next_state, entries, }, layout.glyphs)
    }
    _ => (document.content_apply_resource_op(state, resources, op), [])
  }
}

///|
/// pdflite's layout indexes /W by character code. For an external CMap,
/// provide a temporary width table indexed by the codes in this operator.
fn pdf_layout_font_for_viewer(
  original : @pdflite.PdfFont,
  op : @content.PdfContentOp,
) -> @pdflite.PdfFont {
  guard original is @pdflite.PdfFontCIDKeyed(font) &&
    font.encoding is @pdflite.PdfExternalCMap(_, _) &&
    !original.content_is_vertical() else {
    return original
  }
  let strings : Array[Bytes] = []
  match op {
    @content.Op_Tj(bytes)
    | @content.Op_quote(bytes)
    | @content.Op_double_quote(_, _, bytes) => strings.push(bytes)
    @content.Op_TJ(@syntax.PdfArray(elements)) =>
      for element in elements {
        if element is @syntax.PdfString(bytes) {
          strings.push(bytes)
        }
      }
    _ => return original
  }
  let widths : Map[Int, Double] = Map([])
  for bytes in strings {
    for charcode in original.content_charcodes_of_bytes(bytes) {
      if !widths.contains(charcode) {
        let cid = match pdf_viewer_cid_of_charcode(font, charcode) {
          Some(value) => value
          None => charcode
        }
        widths[charcode] = original.content_width_of_charcode(cid).0
      }
    }
  }
  @pdflite.PdfFontCIDKeyed({
    ..font,
    composite: {
      ..font.composite,
      cid_widths: [
        for (code, width) in widths => (code, width)
      ],
    },
  })
}

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
      let layout = state.text_state.content_apply_text_op(
        pdf_layout_font_for_viewer(original_font, op),
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

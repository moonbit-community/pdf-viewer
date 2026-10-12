///|
/// Preserve the text rendering matrix independently of the glyph selection
/// quad. A quad uses advance width and font metrics; it is not the glyph's
/// outline BBox and cannot be used to fit the outline.
fn pdf_glyph_transform(
  state : @pdflite.PdfContentOperatorState,
  glyph : @pdflite.PdfContentTextGlyphPlacement,
) -> @geometry.TransformMatrix {
  let text = state.text_state
  let parameters : @geometry.TransformMatrix = {
    a: text.font_size * text.horizontal_scaling,
    b: 0.0,
    c: 0.0,
    d: text.font_size,
    e: 0.0,
    f: text.rise,
  }
  let matrix = @geometry.transform_matrix_compose(
    state.ctm,
    @geometry.transform_matrix_compose(glyph.text_matrix, parameters),
  )
  if !pdf_font_is_vertical(text.current_font) {
    return matrix
  }
  @geometry.transform_matrix_compose(
    matrix,
    @geometry.transform_translate(-glyph.pvx, -glyph.pvy),
  )
}

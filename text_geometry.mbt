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
  if !text.current_font.content_is_vertical() {
    return matrix
  }
  // The viewer corrects pdflite's vertical-run advance direction. Retain that
  // displacement without deriving the glyph basis from its bounding quad.
  let metrics = text.current_font.content_extra_metrics()
  let raw_corner = matrix.apply(
    @geometry.point2(glyph.pvx, metrics.1 / 1000.0 - glyph.pvy),
  )
  let (vx, vy) = pdf_vertical_glyph_origin(text.current_font, glyph.charcode)
  let origin = matrix.apply(@geometry.point2(vx, vy))
  {
    ..matrix,
    e: origin.x + glyph.bounding_box.x0 - raw_corner.x,
    f: origin.y + glyph.bounding_box.y0 - raw_corner.y,
  }
}

///|
fn pdf_vertical_glyph_origin(
  font : @pdflite.PdfFont,
  charcode : Int,
) -> (Double, Double) {
  if !font.content_is_vertical() {
    return (0.0, 0.0)
  }
  match font {
    @pdflite.PdfFontCIDKeyed(font) => {
      let cid = pdf_viewer_ttf_cid_of_charcode(font, charcode)
      for (code, metric) in font.composite.cid_widths2 {
        if code == cid {
          return (-metric.vx / 1000.0, -metric.vy / 1000.0)
        }
      }
      let mut width = font.composite.cid_default_width
      for (code, value) in font.composite.cid_widths {
        if code == cid {
          width = value
          break
        }
      }
      let vy = match font.composite.cid_default_width2 {
        [value, ..] => value
        [] => 880.0
      }
      (-width / 2000.0, -vy / 1000.0)
    }
    _ => (0.0, 0.0)
  }
}

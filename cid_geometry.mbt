///|
/// /W and /DW describe horizontal glyph widths even for a vertical font.
fn pdf_cid_horizontal_width(
  font : @pdflite.PdfCIDKeyedFont,
  cid : Int,
) -> Double {
  for (code, width) in font.composite.cid_widths {
    if code == cid {
      break width
    }
  } nobreak {
    font.composite.cid_default_width
  }
}

///|
/// Return (w1y, vx, vy), retaining the signs stored in /W2 and /DW2.
fn pdf_cid_vertical_metrics(
  font : @pdflite.PdfCIDKeyedFont,
  cid : Int,
  horizontal_width : Double,
) -> (Double, Double, Double) {
  for (code, metric) in font.composite.cid_widths2 {
    if code == cid {
      return (metric.width, metric.vx, metric.vy)
    }
  }
  let (vy, w1y) = match font.composite.cid_default_width2 {
    [vy, w1y, ..] => (vy, w1y)
    _ => (880.0, -1000.0)
  }
  (w1y, horizontal_width * 0.5, vy)
}

///|
/// Use the PDF text matrix itself for progression. Display, selection and text
/// clipping therefore share geometry across Tj/TJ and graphics-state changes.
fn pdf_layout_cid_glyph(
  font : @pdflite.PdfCIDKeyedFont,
  cid : Int,
  code : PdfDecodedCMapCode,
  layout : @pdflite.PdfContentTextLayout,
  vertical : Bool,
) -> @pdflite.PdfContentTextGlyphPlacement {
  let original = @pdflite.PdfFontCIDKeyed(font)
  let horizontal_width = pdf_cid_horizontal_width(font, cid)
  let width = horizontal_width / 1000.0
  let (w1y, vx, vy) = if vertical {
    pdf_cid_vertical_metrics(font, cid, horizontal_width)
  } else {
    (0.0, 0.0, 0.0)
  }
  let pvx = vx / 1000.0
  let pvy = vy / 1000.0
  let word_spacing = if code.bytes.length() == 1 && code.bytes[0] == 0x20 {
    layout.word_spacing
  } else {
    0.0
  }
  let spacing = layout.character_spacing + word_spacing
  let (advance_x, advance_y) = if vertical {
    (0.0, w1y / 1000.0 * layout.font_size + spacing)
  } else {
    ((width * layout.font_size + spacing) * layout.horizontal_scaling, 0.0)
  }
  let parameters : @geometry.TransformMatrix = {
    a: layout.font_size * layout.horizontal_scaling,
    b: 0.0,
    c: 0.0,
    d: layout.font_size,
    e: 0.0,
    f: layout.rise,
  }
  let matrix = @geometry.transform_matrix_compose(
    layout.ctm,
    @geometry.transform_matrix_compose(layout.text_matrix, parameters),
  )
  let metrics = original.content_extra_metrics()
  let p0 = matrix.apply(@geometry.point2(-pvx, metrics.1 / 1000.0 - pvy))
  let p1 = matrix.apply(@geometry.point2(-pvx, metrics.0 / 1000.0 - pvy))
  let p2 = matrix.apply(@geometry.point2(width - pvx, metrics.0 / 1000.0 - pvy))
  let p3 = matrix.apply(@geometry.point2(width - pvx, metrics.1 / 1000.0 - pvy))
  {
    charcode: code.charcode,
    text_matrix: layout.text_matrix,
    width,
    pvx,
    pvy,
    advance_x,
    advance_y,
    bounding_box: {
      x0: p0.x,
      y0: p0.y,
      x1: p1.x,
      y1: p1.y,
      x2: p2.x,
      y2: p2.y,
      x3: p3.x,
      y3: p3.y,
    },
  }
}

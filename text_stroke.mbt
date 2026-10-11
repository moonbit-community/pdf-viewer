///|
/// The PDF graphics-state pen is independent of the text rendering matrix.
/// `svg_path`, when available, is in paint-time user space with y reversed;
/// `transform` maps it to the top-left page SVG coordinate system.
/// A browser fallback can use `fallback_scale` only when the independent
/// text transform is a similarity. `unresolved` describes unavailable geometry.
pub(all) struct PdfTextStroke {
  svg_path : String?
  transform : Array[Double]
  line_width : Double
  line_cap : Int
  line_join : Int
  dash_array : Array[Double]
  dash_phase : Double
  miter_limit : Double
  stroke_alpha : Double
  fallback_scale : Double?
  unresolved : String?
} derive(Eq, Debug, ToJson)

///|
fn pdf_text_stroke(
  document : @pdflite.PdfDocument,
  collected : PdfCollectedEntry,
  cff_fonts : Map[Int, PdfCffFont?],
  type1_fonts : Map[Int, PdfType1Font?],
  charcode : Int,
  stroke_alpha : Double,
  origin_x : Double,
  origin_y : Double,
  height : Double,
  font_fallbacks? : ArrayView[PdfFontFallback] = [],
) -> PdfTextStroke? {
  let state = collected.state
  if !pdf_text_mode_strokes(state.text_state.rendering_mode) {
    return None
  }
  // Type 3 charprocs carry their own paints; Tr does not restroke those paths.
  match state.text_state.current_font {
    @pdflite.PdfFontSimple(
      { fonttype: @pdflite.PdfSimpleFontType::PdfType3(_), .. }
    ) => return None
    _ => ()
  }
  let pen_matrix = match collected.text_glyph {
    Some(glyph) =>
      Some(
        pdf_glyph_transform(
          { ..state, ctm: @geometry.transform_identity_matrix, },
          glyph,
        ),
      )
    None => None
  }
  let path = pdf_text_stroke_path(
    document, collected, cff_fonts, type1_fonts, charcode, pen_matrix, font_fallbacks,
  )
  let fallback_scale = pdf_text_stroke_similarity_scale(pen_matrix)
  let m = state.ctm
  Some({
    svg_path: path,
    transform: [m.a, -m.b, -m.c, m.d, m.e - origin_x, origin_y + height - m.f],
    line_width: state.path_state.line_width,
    line_cap: state.path_state.line_cap,
    line_join: state.path_state.line_join,
    dash_array: state.path_state.dash_pattern.array,
    dash_phase: state.path_state.dash_pattern.phase,
    miter_limit: state.miter_limit,
    stroke_alpha,
    fallback_scale,
    unresolved: match (path, fallback_scale) {
      (None, None) => Some("affine-text-pen-requires-glyph-outline")
      _ => None
    },
  })
}

///|
fn pdf_text_stroke_similarity_scale(
  matrix : @geometry.TransformMatrix?,
) -> Double? {
  guard matrix is Some(m) else { return None }
  let x = m.a * m.a + m.b * m.b
  let y = m.c * m.c + m.d * m.d
  let dot = m.a * m.c + m.b * m.d
  if x <= 0.0 || (x - y).abs() > x * 0.00000001 || dot.abs() > x * 0.00000001 {
    None
  } else {
    Some(x.sqrt())
  }
}

///|
/// Resolve A1 geometry before applying the graphics CTM. Glyph decoding,
/// FontMatrix, vertical origins and charcode/CID/GID selection remain A1's.
fn pdf_text_stroke_path(
  document : @pdflite.PdfDocument,
  collected : PdfCollectedEntry,
  cff_fonts : Map[Int, PdfCffFont?],
  type1_fonts : Map[Int, PdfType1Font?],
  charcode : Int,
  pen_matrix : @geometry.TransformMatrix?,
  font_fallbacks : ArrayView[PdfFontFallback],
) -> String? {
  let font = collected.state.text_state.current_font
  match
    pdf_cff_path_of_pdf_glyph(
      document, font, cff_fonts, charcode, pen_matrix, 0.0, 0.0, 0.0,
    ) {
    Some(path) => return Some(path)
    None => ()
  }
  match
    pdf_type1_path_of_pdf_glyph(
      document, font, type1_fonts, charcode, pen_matrix, 0.0, 0.0, 0.0,
    ) {
    Some(path) => return Some(path)
    None => ()
  }
  let path = pdf_truetype_path_of_pdf_glyph(
    document,
    font,
    collected.font_object,
    charcode,
    pen_matrix,
    0.0,
    0.0,
    0.0,
  ) catch {
    _ => None
  }
  match path {
    Some(path) => Some(path)
    None if !pdf_standard14_uses_host_fallback(
        document,
        font,
        collected.font_object,
        collected.state.text_state.font,
        font_fallbacks,
      ) =>
      pdf_standard14_path_of_pdf_glyph(
        font, charcode, pen_matrix, 0.0, 0.0, 0.0,
      )
    None => None
  }
}

///|
fn pdf_svg_text_pen_attributes(
  stroke : PdfTextStroke,
  units : Double,
) -> String {
  let dash = if stroke.dash_array.is_empty() {
    ""
  } else {
    " stroke-dasharray=\"" +
    pdf_svg_dash_array(stroke.dash_array, units) +
    "\" stroke-dashoffset=\"" +
    (stroke.dash_phase * units).to_string() +
    "\""
  }
  " stroke-width=\"" +
  (stroke.line_width * units).to_string() +
  "\" stroke-linecap=\"" +
  pdf_svg_line_cap(stroke.line_cap) +
  "\" stroke-linejoin=\"" +
  pdf_svg_line_join(stroke.line_join) +
  "\" stroke-miterlimit=\"" +
  stroke.miter_limit.to_string() +
  "\" stroke-opacity=\"" +
  stroke.stroke_alpha.to_string() +
  "\"" +
  dash
}

///|
fn pdf_text_stroke_outline(
  stroke : PdfTextStroke?,
  mode : Int,
  fill_color : String,
  stroke_color : String,
  fill_alpha : Double,
) -> String? {
  guard stroke is Some(stroke) && stroke.svg_path is Some(path) else {
    return None
  }
  if path == "" {
    return Some("")
  }
  let fill = if pdf_text_mode_fills(mode) { fill_color } else { "none" }
  Some(
    "<path d=\"" +
    path +
    "\" transform=\"matrix(" +
    pdf_svg_matrix_values(stroke.transform) +
    ")\" fill=\"" +
    pdf_escape_xml(fill) +
    "\" fill-opacity=\"" +
    fill_alpha.to_string() +
    "\" stroke=\"" +
    pdf_escape_xml(stroke_color) +
    "\"" +
    pdf_svg_text_pen_attributes(stroke, 1.0) +
    "/>",
  )
}

///|
/// An unresolved host-font outline is visible in both the model and SVG.
/// A similarity text transform permits exact pen compensation, even when
/// the independent graphics CTM is sheared, reflected or nonuniform.
fn pdf_svg_fallback_text_pen(item : PdfTextItem, scale : Double) -> String {
  match item.stroke {
    Some(stroke) =>
      match stroke.fallback_scale {
        Some(size) if size > 0.0 =>
          pdf_svg_text_pen_attributes(stroke, 1.0 / size)
        _ => {
          // Keep missing-outline fallback text visible, but label its
          // area-equivalent pen approximation instead of claiming fidelity.
          let units = match (item.glyph_transform, stroke.transform) {
            (Some([a, b, c, d, _, _]), [aa, bb, cc, dd, _, _]) => {
              let area = (a * d - b * c).abs()
              if area > 0.0 {
                ((aa * dd - bb * cc).abs() / area).sqrt()
              } else {
                0.0
              }
            }
            _ => scale
          }
          pdf_svg_text_pen_attributes(stroke, units) +
          " data-pdf-text-stroke-unresolved=\"affine-text-pen-requires-glyph-outline\""
        }
      }
    None => {
      // Host-built models predate retained pens. Their default PDF pen is
      // one user-space unit; do not invent a font-size-relative width.
      let units = match item.glyph_transform {
        Some([a, b, c, d, _, _]) => {
          let area = (a * d - b * c).abs()
          if area > 0.0 {
            1.0 / area.sqrt()
          } else {
            0.0
          }
        }
        _ => scale
      }
      " stroke-width=\"" +
      units.to_string() +
      "\" data-pdf-text-stroke-unresolved=\"missing-pdf-pen-state\""
    }
  }
}

///|
#deprecated
pub extend PdfTextStroke with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfTextStroke with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfTextStroke with ToJson::{to_json}

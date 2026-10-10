///|
#deprecated
pub extend PdfPathStroke with Eq::{not_equal, equal}

///|
#deprecated
pub extend PdfPathStroke with @debug.Debug::{to_repr}

///|
#deprecated
pub extend PdfPathStroke with ToJson::{to_json}

///|
fn pdf_path_stroke(
  path : @shape.PdfPath,
  state : @pdflite.PdfContentOperatorState,
  origin_x : Double,
  origin_y : Double,
  height : Double,
) -> PdfPathStroke {
  let m = state.ctm
  {
    svg_path: pdf_svg_path_of_shape_direct(path, 0.0, 0.0, 0.0),
    transform: [m.a, -m.b, -m.c, m.d, m.e - origin_x, origin_y + height - m.f],
    line_width: state.path_state.line_width,
    dash_array: state.path_state.dash_pattern.array,
    dash_phase: state.path_state.dash_pattern.phase,
    miter_limit: state.miter_limit,
  }
}

///|
/// Keep the complete affine transform on the stroke. Flattening it into an
/// average width loses anisotropic pen shapes, caps, joins and dash lengths.
fn pdf_svg_affine_stroke(
  output : StringBuilder,
  path : PdfPathItem,
  stroke : PdfPathStroke,
  scale : Double,
  colour : String,
) -> Unit {
  let transform = pdf_svg_matrix_values(
    [
      for value in stroke.transform => value * scale
    ],
  )
  let dash = if stroke.dash_array.is_empty() {
    ""
  } else {
    " stroke-dasharray=\"" +
    pdf_svg_dash_array(stroke.dash_array, 1.0) +
    "\" stroke-dashoffset=\"" +
    stroke.dash_phase.to_string() +
    "\""
  }
  output.write_string(
    "<path d=\"" +
    stroke.svg_path +
    "\" transform=\"matrix(" +
    transform +
    ")\" fill=\"none\" stroke=\"" +
    colour +
    "\" stroke-opacity=\"" +
    path.stroke_alpha.to_string() +
    "\" stroke-width=\"" +
    stroke.line_width.to_string() +
    "\" stroke-linecap=\"" +
    pdf_svg_line_cap(path.line_cap) +
    "\" stroke-linejoin=\"" +
    pdf_svg_line_join(path.line_join) +
    "\" stroke-miterlimit=\"" +
    stroke.miter_limit.to_string() +
    "\"" +
    pdf_svg_blend_style(path.blend_mode) +
    dash +
    "/>",
  )
}

///|
/// Pattern resources live in page space. Cancel the stroke-local transform
/// before applying their existing page transform, so the pen does not distort
/// or translate the pattern a second time.
fn pdf_svg_stroke_pattern_transform(
  stroke : PdfPathStroke?,
  page_transform : String,
) -> String {
  guard stroke is Some(stroke) && stroke.transform.length() == 6 else {
    return page_transform
  }
  let m = stroke.transform
  let inverse = @geometry.transform_matrix_invert({
    a: m[0],
    b: m[1],
    c: m[2],
    d: m[3],
    e: m[4],
    f: m[5],
  }) catch {
    _ => return page_transform
  }
  "matrix(" +
  pdf_svg_matrix_values([
    inverse.a,
    inverse.b,
    inverse.c,
    inverse.d,
    inverse.e,
    inverse.f,
  ]) +
  ") " +
  page_transform
}

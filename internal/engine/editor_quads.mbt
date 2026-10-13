///|
fn pdf_edit_quad_point(value : Json) -> PdfPoint raise @core.PdfError {
  {
    x: pdf_edit_number(pdf_edit_entry(value, "x")),
    y: pdf_edit_number(pdf_edit_entry(value, "y")),
  }
}

///|
fn pdf_edit_highlight_quads(
  document : @pdflite.PdfDocument,
  original : @syntax.PdfObject,
  patch : Json,
  adding : Bool,
  bounds : PdfBounds,
  old_bounds : PdfBounds?,
) -> Array[PdfQuad] raise @core.PdfError {
  let supplied = pdf_edit_entry(patch, "quads")
  if supplied is Array(values) {
    if values.is_empty() || values.length() > 20000 {
      raise @core.SoftError("Invalid highlight quadrilaterals")
    }
    return values.map(value => {
      let quad : PdfQuad = {
        p0: pdf_edit_quad_point(pdf_edit_entry(value, "p0")),
        p1: pdf_edit_quad_point(pdf_edit_entry(value, "p1")),
        p2: pdf_edit_quad_point(pdf_edit_entry(value, "p2")),
        p3: pdf_edit_quad_point(pdf_edit_entry(value, "p3")),
      }
      for point in [quad.p0, quad.p1, quad.p2, quad.p3] {
        if point.x < bounds.min_x - 0.001 ||
          point.x > bounds.max_x + 0.001 ||
          point.y < bounds.min_y - 0.001 ||
          point.y > bounds.max_y + 0.001 {
          raise @core.SoftError("Highlight quadrilateral is outside its bounds")
        }
      }
      quad
    })
  }
  if supplied != Json::null() {
    raise @core.SoftError("Invalid highlight quadrilaterals")
  }
  let previous = if adding {
    []
  } else {
    pdf_annotation_quad_points(document, original)
  }
  if !previous.is_empty() &&
    old_bounds is Some(old) &&
    old.max_x > old.min_x &&
    old.max_y > old.min_y {
    fn map_point(point : PdfPoint) -> PdfPoint {
      {
        x: bounds.min_x +
        (point.x - old.min_x) *
        (bounds.max_x - bounds.min_x) /
        (old.max_x - old.min_x),
        y: bounds.min_y +
        (point.y - old.min_y) *
        (bounds.max_y - bounds.min_y) /
        (old.max_y - old.min_y),
      }
    }
    return previous.map(quad => {
      p0: map_point(quad.p0),
      p1: map_point(quad.p1),
      p2: map_point(quad.p2),
      p3: map_point(quad.p3),
    })
  }
  [
    {
      p0: { x: bounds.min_x, y: bounds.min_y, },
      p1: { x: bounds.min_x, y: bounds.max_y, },
      p2: { x: bounds.max_x, y: bounds.max_y, },
      p3: { x: bounds.max_x, y: bounds.min_y, },
    },
  ]
}

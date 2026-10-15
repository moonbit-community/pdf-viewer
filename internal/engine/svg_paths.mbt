///|
fn pdf_svg_path(
  output : StringBuilder,
  page : PdfPageModel,
  path : PdfPathItem,
  scale : Double,
) -> Unit {
  let fill = if path.filled {
    match path.shading_pattern {
      Some(_) => "none"
      None =>
        match path.pattern {
          Some(_) => "url(#pdf-pattern-" + path.index.to_string() + ")"
          None => path.fill_color
        }
    }
  } else {
    "none"
  }
  let stroke = if path.stroked {
    match path.stroke_pattern {
      Some(pattern) if pattern.shading is None =>
        "url(#pdf-stroke-pattern-" + path.index.to_string() + ")"
      _ => path.stroke_color
    }
  } else {
    "none"
  }
  let transformed = pdf_transform_svg_path(path.svg_path, page.height, scale)
  let dash = if path.dash_array.length() == 0 {
    ""
  } else {
    " stroke-dasharray=\"" +
    pdf_svg_dash_array(path.dash_array, 1.0) +
    "\" stroke-dashoffset=\"" +
    path.dash_phase.to_string() +
    "\""
  }
  pdf_svg_clip_defs(output, path.index, path.clip_path, scale, clips=path.clips)
  pdf_svg_pattern_defs(output, page, path, scale)
  pdf_svg_soft_mask_defs(output, path.index, page, path.soft_mask, scale)
  pdf_svg_soft_mask_open(output, path.index, path.soft_mask)
  pdf_svg_clip_open(output, path.index, path.clip_path)
  output.write_string(
    "<path d=\"" +
    transformed +
    "\" transform=\"scale(" +
    scale.to_string() +
    ")" +
    "\" data-pdf-bounds=\"" +
    path.bounds.min_x.to_string() +
    "," +
    path.bounds.min_y.to_string() +
    "," +
    path.bounds.max_x.to_string() +
    "," +
    path.bounds.max_y.to_string() +
    "\" fill=\"" +
    fill +
    "\" fill-rule=\"" +
    (if path.fill_even_odd { "evenodd" } else { "nonzero" }) +
    "\" stroke=\"" +
    (if path.stroke is Some(_) { "none" } else { stroke }) +
    "\" fill-opacity=\"" +
    path.fill_alpha.to_string() +
    "\" stroke-opacity=\"" +
    path.stroke_alpha.to_string() +
    "\" stroke-width=\"" +
    path.line_width.to_string() +
    "\" stroke-linecap=\"" +
    pdf_svg_line_cap(path.line_cap) +
    "\" stroke-linejoin=\"" +
    pdf_svg_line_join(path.line_join) +
    "\"" +
    pdf_svg_blend_style(path.blend_mode) +
    dash +
    "/>",
  )
  pdf_svg_clip_close(output, path.index, path.clip_path)
  match path.shading_pattern {
    Some(shading) =>
      pdf_svg_shading_pattern_path(output, page, path, shading, scale)
    None => ()
  }
  if path.stroked && path.stroke is Some(geometry) {
    pdf_svg_clip_open(output, path.index, path.clip_path)
    pdf_svg_affine_stroke(output, path, geometry, scale, stroke)
    pdf_svg_clip_close(output, path.index, path.clip_path)
  }
  pdf_svg_soft_mask_close(output, path.index, path.soft_mask)
}

///|
fn pdf_svg_line_cap(value : Int) -> String {
  match value {
    1 => "round"
    2 => "square"
    _ => "butt"
  }
}

///|
fn pdf_svg_line_join(value : Int) -> String {
  match value {
    1 => "round"
    2 => "bevel"
    _ => "miter"
  }
}

///|
fn pdf_svg_dash_array(values : ArrayView[Double], scale : Double) -> String {
  let output = StringBuilder()
  let mut first = true
  for value in values {
    if !first {
      output.write_char(' ')
    }
    first = false
    output.write_string((value * scale).to_string())
  }
  output.to_string()
}

///|
fn pdf_transform_svg_path(
  path : String,
  page_height : Double,
  scale : Double,
) -> String {
  // Path data is stored in SVG page space. The path element applies the
  // requested scale, so the data remains readable to host-side tooling.
  ignore(page_height)
  ignore(scale)
  path
}

///|
fn pdf_svg_path_of_shape(
  path : @shape.PdfPath,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
  target_bounds : PdfBounds,
) -> String {
  pdf_svg_path_of_shape_with_quad(path, origin_x, origin_y, page_height, {
    p0: { x: target_bounds.min_x, y: target_bounds.min_y, },
    p1: { x: target_bounds.min_x, y: target_bounds.max_y, },
    p2: { x: target_bounds.max_x, y: target_bounds.max_y, },
    p3: { x: target_bounds.max_x, y: target_bounds.min_y, },
  })
}

///|
/// Serialize path coordinates directly after the caller has applied the PDF
/// current transformation matrix. This is used for page paths because a
/// bounding box cannot represent rotation, shear, or a translated Form XObject.
fn pdf_svg_path_of_shape_direct(
  path : @shape.PdfPath,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
) -> String {
  match pdf_shape_bounds(path) {
    Some(bounds) =>
      pdf_svg_path_of_shape_with_quad(path, origin_x, origin_y, page_height, {
        p0: { x: bounds.min_x, y: bounds.min_y, },
        p1: { x: bounds.min_x, y: bounds.max_y, },
        p2: { x: bounds.max_x, y: bounds.max_y, },
        p3: { x: bounds.max_x, y: bounds.min_y, },
      })
    None => ""
  }
}

///|
/// Serialize a path using the four-corner affine mapping emitted by pdflite.
/// This keeps rotations and shears intact instead of stretching the path to
/// its axis-aligned bounding box.
fn pdf_svg_path_of_shape_with_quad(
  path : @shape.PdfPath,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
  target_quad : PdfQuad,
) -> String {
  let source_bounds = match pdf_shape_bounds(path) {
    Some(bounds) => bounds
    None => { min_x: 0.0, min_y: 0.0, max_x: 0.0, max_y: 0.0, }
  }
  let output = StringBuilder()
  for subpath in path.subpaths {
    if subpath.segments.length() == 0 {
      continue
    }
    match subpath.segments[0] {
      @shape.PdfPathSegment::PdfPathStraight(start, end) => {
        output.write_string(
          "M " +
          pdf_svg_point_from_quad(
            start, origin_x, origin_y, page_height, source_bounds, target_quad,
          ),
        )
        output.write_string(
          " L " +
          pdf_svg_point_from_quad(
            end, origin_x, origin_y, page_height, source_bounds, target_quad,
          ),
        )
      }
      @shape.PdfPathSegment::PdfPathBezier(start, c1, c2, end) => {
        output.write_string(
          "M " +
          pdf_svg_point_from_quad(
            start, origin_x, origin_y, page_height, source_bounds, target_quad,
          ),
        )
        output.write_string(
          " C " +
          pdf_svg_point_from_quad(
            c1, origin_x, origin_y, page_height, source_bounds, target_quad,
          ) +
          " " +
          pdf_svg_point_from_quad(
            c2, origin_x, origin_y, page_height, source_bounds, target_quad,
          ) +
          " " +
          pdf_svg_point_from_quad(
            end, origin_x, origin_y, page_height, source_bounds, target_quad,
          ),
        )
      }
    }
    for segment in subpath.segments[1:] {
      match segment {
        @shape.PdfPathSegment::PdfPathStraight(_, end) =>
          output.write_string(
            " L " +
            pdf_svg_point_from_quad(
              end, origin_x, origin_y, page_height, source_bounds, target_quad,
            ),
          )
        @shape.PdfPathSegment::PdfPathBezier(_, c1, c2, end) =>
          output.write_string(
            " C " +
            pdf_svg_point_from_quad(
              c1, origin_x, origin_y, page_height, source_bounds, target_quad,
            ) +
            " " +
            pdf_svg_point_from_quad(
              c2, origin_x, origin_y, page_height, source_bounds, target_quad,
            ) +
            " " +
            pdf_svg_point_from_quad(
              end, origin_x, origin_y, page_height, source_bounds, target_quad,
            ),
          )
      }
    }
    match subpath.closure {
      @shape.PdfPathClosure::PdfPathClosed => output.write_string(" Z")
      @shape.PdfPathClosure::PdfPathOpen => ()
    }
  }
  output.to_string()
}

///|
fn pdf_shape_bounds(path : @shape.PdfPath) -> PdfBounds? {
  let mut bounds : PdfBounds? = None
  for subpath in path.subpaths {
    for segment in subpath.segments {
      match segment {
        @shape.PdfPathSegment::PdfPathStraight(start, end) => {
          bounds = pdf_shape_bounds_add_point(bounds, start)
          bounds = pdf_shape_bounds_add_point(bounds, end)
        }
        @shape.PdfPathSegment::PdfPathBezier(start, c1, c2, end) => {
          bounds = pdf_shape_bounds_add_point(bounds, start)
          bounds = pdf_shape_bounds_add_point(bounds, c1)
          bounds = pdf_shape_bounds_add_point(bounds, c2)
          bounds = pdf_shape_bounds_add_point(bounds, end)
        }
      }
    }
  }
  bounds
}

///|
fn pdf_shape_bounds_add_point(
  bounds : PdfBounds?,
  point : @geometry.Point2,
) -> PdfBounds? {
  match bounds {
    Some(bounds) =>
      Some({
        min_x: bounds.min_x.min(point.x),
        min_y: bounds.min_y.min(point.y),
        max_x: bounds.max_x.max(point.x),
        max_y: bounds.max_y.max(point.y),
      })
    None =>
      Some({ min_x: point.x, min_y: point.y, max_x: point.x, max_y: point.y, })
  }
}

///|
fn pdf_svg_point_from_quad(
  point : @geometry.Point2,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
  source_bounds : PdfBounds,
  target_quad : PdfQuad,
) -> String {
  let x_ratio = if source_bounds.max_x > source_bounds.min_x {
    (point.x - source_bounds.min_x) /
    (source_bounds.max_x - source_bounds.min_x)
  } else {
    0.0
  }
  let y_ratio = if source_bounds.max_y > source_bounds.min_y {
    (point.y - source_bounds.min_y) /
    (source_bounds.max_y - source_bounds.min_y)
  } else {
    0.0
  }
  let x = target_quad.p0.x +
    x_ratio * (target_quad.p3.x - target_quad.p0.x) +
    y_ratio * (target_quad.p1.x - target_quad.p0.x)
  let y = target_quad.p0.y +
    x_ratio * (target_quad.p3.y - target_quad.p0.y) +
    y_ratio * (target_quad.p1.y - target_quad.p0.y)
  (x - origin_x).to_string() + " " + (origin_y + page_height - y).to_string()
}

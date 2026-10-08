///|
fn pdf_render_page_svg(
  page : PdfPageModel,
  scale : Double,
  rotation : Int,
) -> String {
  let safe_scale = if scale <= 0.0 { 1.0 } else { scale }
  let viewport = page.viewport(scale=safe_scale, rotation~)
  let width = viewport.width
  let height = viewport.height
  let output = StringBuilder()
  output.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 " +
    width.to_string() +
    " " +
    height.to_string() +
    "\" width=\"" +
    width.to_string() +
    "\" height=\"" +
    height.to_string() +
    "\">",
  )
  pdf_svg_fonts(output, page)
  output.write_string("<rect width=\"100%\" height=\"100%\" fill=\"white\"/>")
  output.write_string("<g transform=\"" + viewport.transform + "\">")
  let text_run : Array[PdfTextItem] = []
  for item in page.items {
    match item {
      PdfPageItem::Text(text) =>
        match text_run.last() {
          Some(previous) if pdf_svg_text_can_join(previous, text) =>
            text_run.push(text)
          _ => {
            pdf_svg_flush_text_run(output, page, text_run, safe_scale)
            text_run.clear()
            text_run.push(text)
          }
        }
      PdfPageItem::Path(path) => {
        pdf_svg_flush_text_run(output, page, text_run, safe_scale)
        text_run.clear()
        pdf_svg_path(output, page, path, safe_scale)
      }
      PdfPageItem::Image(image) => {
        pdf_svg_flush_text_run(output, page, text_run, safe_scale)
        text_run.clear()
        pdf_svg_image(output, page, image, safe_scale)
      }
      PdfPageItem::Shading(shading) => {
        pdf_svg_flush_text_run(output, page, text_run, safe_scale)
        text_run.clear()
        pdf_svg_placeholder(output, page, shading, safe_scale, "shading")
      }
    }
  }
  pdf_svg_flush_text_run(output, page, text_run, safe_scale)
  output.write_string("</g>")
  output.write_string("</svg>")
  output.to_string()
}

///|
fn pdf_svg_flush_text_run(
  output : StringBuilder,
  page : PdfPageModel,
  items : ArrayView[PdfTextItem],
  scale : Double,
) -> Unit {
  match items[0:] {
    [] => ()
    [_first, ..] => pdf_svg_text(output, page, items, scale)
  }
}

///|
fn pdf_svg_text_can_join(previous : PdfTextItem, current : PdfTextItem) -> Bool {
  let line_threshold = if previous.font_size > current.font_size {
    previous.font_size * 0.2
  } else {
    current.font_size * 0.2
  }
  let previous_angle = pdf_text_angle(previous)
  let current_angle = pdf_text_angle(current)
  (previous.bounds.max_y - current.bounds.max_y).abs() <= line_threshold &&
  previous.font == current.font &&
  (previous_angle - current_angle).abs() <= 0.01
}

///|
fn pdf_svg_text(
  output : StringBuilder,
  page : PdfPageModel,
  items : ArrayView[PdfTextItem],
  scale : Double,
) -> Unit {
  let first = items[0]
  let angle = pdf_text_angle(first)
  let rotated = angle.abs() > 0.001
  let value = StringBuilder()
  let positions = StringBuilder()
  let mut first_position = true
  for item in items {
    if !first_position {
      positions.write_char(' ')
    }
    first_position = false
    let position = if rotated {
      pdf_text_offset(first, item) * scale
    } else {
      (item.quad.p1.x - page.origin_x) * scale
    }
    positions.write_string(position.to_string())
    value.write_string(item.text)
  }
  let (x, y, transform) = if rotated {
    let anchor_x = (first.quad.p1.x - page.origin_x) * scale
    let anchor_y = (page.origin_y + page.height - first.quad.p1.y) * scale
    let degrees = -angle * 180.0 / 3.141592653589793
    (
      "0",
      0.0,
      " transform=\"translate(" +
      anchor_x.to_string() +
      " " +
      anchor_y.to_string() +
      ") rotate(" +
      degrees.to_string() +
      ")\"",
    )
  } else {
    (
      positions.to_string(),
      (page.origin_y + page.height - first.quad.p1.y) * scale,
      "",
    )
  }
  let family = pdf_svg_font_family_for_page(page, first.font)
  let weight = if first.font.contains("Bold") { "bold" } else { "normal" }
  let style = if first.font.contains("Italic") || first.font.contains("Oblique") {
    "italic"
  } else {
    "normal"
  }
  output.write_string(
    "<text x=\"" +
    x +
    "\" y=\"" +
    y.to_string() +
    "\"" +
    transform +
    " font-family=\"" +
    family +
    "\" font-size=\"" +
    (first.font_size * scale).to_string() +
    "\" font-weight=\"" +
    weight +
    "\" font-style=\"" +
    style +
    "\" dominant-baseline=\"hanging\">" +
    pdf_escape_xml(value.to_string()) +
    "</text>",
  )
}

///|
fn pdf_text_angle(item : PdfTextItem) -> Double {
  @math.atan2(item.quad.p2.y - item.quad.p1.y, item.quad.p2.x - item.quad.p1.x)
}

///|
fn pdf_text_offset(first : PdfTextItem, item : PdfTextItem) -> Double {
  let angle = pdf_text_angle(first)
  let dx = item.quad.p1.x - first.quad.p1.x
  let dy = item.quad.p1.y - first.quad.p1.y
  dx * @math.cos(angle) + dy * @math.sin(angle)
}

///|
fn pdf_svg_font_family(font : String) -> String {
  if font.contains("Courier") || font.contains("Mono") {
    "monospace"
  } else if font.contains("Times") || font.contains("Serif") {
    "serif"
  } else {
    "sans-serif"
  }
}

///|
fn pdf_svg_embedded_font_family(font : String) -> String {
  "pdf-font-" +
  font
  .replace(old="/", new="-")
  .replace(old="#", new="-")
  .replace(old="+", new="-")
}

///|
fn pdf_svg_font_family_for_page(page : PdfPageModel, font : String) -> String {
  for resource in page.fonts {
    if resource.name == font && resource.data_uri is Some(_) {
      return resource.family
    }
  }
  pdf_svg_font_family(font)
}

///|
fn pdf_svg_fonts(output : StringBuilder, page : PdfPageModel) -> Unit {
  let css = StringBuilder()
  for resource in page.fonts {
    match resource.data_uri {
      Some(data_uri) => {
        css.write_string("@font-face{font-family:'")
        css.write_string(resource.family)
        css.write_string("';src:url('")
        css.write_string(data_uri)
        css.write_string("') format('")
        css.write_string(resource.format)
        css.write_string("');}")
      }
      None => ()
    }
  }
  if css.to_string().length() > 0 {
    output.write_string("<defs><style>")
    output.write_string(css.to_string())
    output.write_string("</style></defs>")
  }
}

///|
fn pdf_svg_path(
  output : StringBuilder,
  page : PdfPageModel,
  path : PdfPathItem,
  scale : Double,
) -> Unit {
  let fill = if path.filled { path.fill_color } else { "none" }
  let stroke = if path.stroked { path.stroke_color } else { "none" }
  let transformed = pdf_transform_svg_path(path.svg_path, page.height, scale)
  let dash = if path.dash_array.length() == 0 {
    ""
  } else {
    " stroke-dasharray=\"" +
    pdf_svg_dash_array(path.dash_array, scale) +
    "\" stroke-dashoffset=\"" +
    (path.dash_phase * scale).to_string() +
    "\""
  }
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
    "\" stroke=\"" +
    stroke +
    "\" fill-opacity=\"" +
    path.fill_alpha.to_string() +
    "\" stroke-opacity=\"" +
    path.stroke_alpha.to_string() +
    "\" stroke-width=\"" +
    (path.line_width * scale).to_string() +
    "\" stroke-linecap=\"" +
    pdf_svg_line_cap(path.line_cap) +
    "\" stroke-linejoin=\"" +
    pdf_svg_line_join(path.line_join) +
    "\"" +
    dash +
    "/>",
  )
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
fn pdf_svg_image(
  output : StringBuilder,
  page : PdfPageModel,
  item : PdfVisualItem,
  scale : Double,
) -> Unit {
  match item.resource {
    Some(resource) =>
      match resource.data_uri {
        Some(data_uri) => {
          let x = (item.bounds.min_x - page.origin_x) * scale
          let y = (page.origin_y + page.height - item.bounds.max_y) * scale
          let width = (item.bounds.max_x - item.bounds.min_x) * scale
          let height = (item.bounds.max_y - item.bounds.min_y) * scale
          output.write_string(
            "<image data-pdf-name=\"" +
            pdf_escape_xml(item.name) +
            "\" x=\"" +
            x.to_string() +
            "\" y=\"" +
            y.to_string() +
            "\" width=\"" +
            width.to_string() +
            "\" height=\"" +
            height.to_string() +
            "\" preserveAspectRatio=\"none\" href=\"" +
            data_uri +
            "\"/>",
          )
        }
        None => pdf_svg_placeholder(output, page, item, scale, "image")
      }
    None => pdf_svg_placeholder(output, page, item, scale, "image")
  }
}

///|
fn pdf_svg_placeholder(
  output : StringBuilder,
  page : PdfPageModel,
  item : PdfVisualItem,
  scale : Double,
  kind : String,
) -> Unit {
  let x = (item.bounds.min_x - page.origin_x) * scale
  let y = (page.origin_y + page.height - item.bounds.max_y) * scale
  let width = (item.bounds.max_x - item.bounds.min_x) * scale
  let height = (item.bounds.max_y - item.bounds.min_y) * scale
  output.write_string(
    "<g data-pdf-kind=\"" +
    kind +
    "\" data-pdf-name=\"" +
    pdf_escape_xml(item.name) +
    "\"><rect x=\"" +
    x.to_string() +
    "\" y=\"" +
    y.to_string() +
    "\" width=\"" +
    width.to_string() +
    "\" height=\"" +
    height.to_string() +
    "\" fill=\"#eef1f5\" stroke=\"#9aa4b2\" stroke-dasharray=\"3 2\"/>" +
    "<title>" +
    pdf_escape_xml(kind + ": " + item.name) +
    "</title></g>",
  )
}

///|
fn pdf_escape_xml(text : String) -> String {
  text
  .replace(old="&", new="&amp;")
  .replace(old="<", new="&lt;")
  .replace(old=">", new="&gt;")
  .replace(old="\"", new="&quot;")
  .replace(old="'", new="&apos;")
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
  let source_bounds = pdf_shape_bounds(path)
  let scale_x = match source_bounds {
    Some(bounds) if bounds.max_x > bounds.min_x &&
      target_bounds.max_x > target_bounds.min_x =>
      (target_bounds.max_x - target_bounds.min_x) /
      (bounds.max_x - bounds.min_x)
    _ => 1.0
  }
  let scale_y = match source_bounds {
    Some(bounds) if bounds.max_y > bounds.min_y &&
      target_bounds.max_y > target_bounds.min_y =>
      (target_bounds.max_y - target_bounds.min_y) /
      (bounds.max_y - bounds.min_y)
    _ => 1.0
  }
  let source_min_x = match source_bounds {
    Some(bounds) => bounds.min_x
    None => 0.0
  }
  let source_min_y = match source_bounds {
    Some(bounds) => bounds.min_y
    None => 0.0
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
          pdf_svg_point(
            start, origin_x, origin_y, page_height, source_min_x, source_min_y, scale_x,
            scale_y, target_bounds,
          ),
        )
        output.write_string(
          " L " +
          pdf_svg_point(
            end, origin_x, origin_y, page_height, source_min_x, source_min_y, scale_x,
            scale_y, target_bounds,
          ),
        )
      }
      @shape.PdfPathSegment::PdfPathBezier(start, c1, c2, end) => {
        output.write_string(
          "M " +
          pdf_svg_point(
            start, origin_x, origin_y, page_height, source_min_x, source_min_y, scale_x,
            scale_y, target_bounds,
          ),
        )
        output.write_string(
          " C " +
          pdf_svg_point(
            c1, origin_x, origin_y, page_height, source_min_x, source_min_y, scale_x,
            scale_y, target_bounds,
          ) +
          " " +
          pdf_svg_point(
            c2, origin_x, origin_y, page_height, source_min_x, source_min_y, scale_x,
            scale_y, target_bounds,
          ) +
          " " +
          pdf_svg_point(
            end, origin_x, origin_y, page_height, source_min_x, source_min_y, scale_x,
            scale_y, target_bounds,
          ),
        )
      }
    }
    for segment in subpath.segments[1:] {
      match segment {
        @shape.PdfPathSegment::PdfPathStraight(_, end) =>
          output.write_string(
            " L " +
            pdf_svg_point(
              end, origin_x, origin_y, page_height, source_min_x, source_min_y, scale_x,
              scale_y, target_bounds,
            ),
          )
        @shape.PdfPathSegment::PdfPathBezier(_, c1, c2, end) =>
          output.write_string(
            " C " +
            pdf_svg_point(
              c1, origin_x, origin_y, page_height, source_min_x, source_min_y, scale_x,
              scale_y, target_bounds,
            ) +
            " " +
            pdf_svg_point(
              c2, origin_x, origin_y, page_height, source_min_x, source_min_y, scale_x,
              scale_y, target_bounds,
            ) +
            " " +
            pdf_svg_point(
              end, origin_x, origin_y, page_height, source_min_x, source_min_y, scale_x,
              scale_y, target_bounds,
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
fn pdf_svg_point(
  point : @geometry.Point2,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
  source_min_x : Double,
  source_min_y : Double,
  scale_x : Double,
  scale_y : Double,
  target_bounds : PdfBounds,
) -> String {
  let x = target_bounds.min_x + (point.x - source_min_x) * scale_x
  let y = target_bounds.min_y + (point.y - source_min_y) * scale_y
  (x - origin_x).to_string() + " " + (origin_y + page_height - y).to_string()
}

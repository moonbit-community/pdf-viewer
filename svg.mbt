///|
fn pdf_render_page_svg(
  page : PdfPageModel,
  scale : Double,
  rotation : Int,
) -> String raise @core.PdfError {
  let safe_scale = if scale <= 0.0 { 1.0 } else { scale }
  let normalized_rotation = pdf_normalize_rotation_strict(rotation)
  let viewport = page.viewport(scale=safe_scale, rotation=normalized_rotation)
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
  output.write_string(
    "<g transform=\"" +
    pdf_svg_relative_viewport_transform(
      page.width * safe_scale,
      page.height * safe_scale,
      viewport.rotation,
    ) +
    "\">",
  )
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
        pdf_svg_shading(output, page, shading, safe_scale)
      }
    }
  }
  pdf_svg_flush_text_run(output, page, text_run, safe_scale)
  pdf_svg_annotations(output, page, safe_scale)
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
  (previous_angle - current_angle).abs() <= 0.01 &&
  previous.clip_path == current.clip_path
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
  let clip_attribute = pdf_svg_clip_attribute(first.index, first.clip_path)
  pdf_svg_clip_defs(output, first.index, first.clip_path)
  output.write_string(
    "<text" +
    clip_attribute +
    " x=\"" +
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
    "\" fill-opacity=\"" +
    first.fill_alpha.to_string() +
    "\"" +
    pdf_svg_blend_style(first.blend_mode) +
    " dominant-baseline=\"hanging\">" +
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
  let fill = if path.filled {
    match path.pattern {
      Some(_) => "url(#pdf-pattern-" + path.index.to_string() + ")"
      None => path.fill_color
    }
  } else {
    "none"
  }
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
  let clip_attribute = pdf_svg_clip_attribute(path.index, path.clip_path)
  pdf_svg_clip_defs(output, path.index, path.clip_path)
  pdf_svg_pattern_defs(output, path)
  output.write_string(
    "<path" +
    clip_attribute +
    " d=\"" +
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
    pdf_svg_blend_style(path.blend_mode) +
    dash +
    "/>",
  )
}

///|
fn pdf_svg_pattern_defs(output : StringBuilder, path : PdfPathItem) -> Unit {
  match path.pattern {
    Some(pattern) => {
      let id = "pdf-pattern-" + path.index.to_string()
      output.write_string(
        "<defs><pattern id=\"" +
        id +
        "\" patternUnits=\"userSpaceOnUse\" patternContentUnits=\"userSpaceOnUse\" x=\"0\" y=\"0\" width=\"" +
        pattern.x_step.to_string() +
        "\" height=\"" +
        pattern.y_step.to_string() +
        "\">" +
        pattern.tile_svg +
        "</pattern></defs>",
      )
    }
    None => ()
  }
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
          let clip_attribute = pdf_svg_clip_attribute(
            item.index,
            item.clip_path,
          )
          pdf_svg_clip_defs(output, item.index, item.clip_path)
          output.write_string(
            "<image" +
            clip_attribute +
            " data-pdf-name=\"" +
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
            "\" opacity=\"" +
            item.fill_alpha.to_string() +
            "\"" +
            pdf_svg_blend_style(item.blend_mode) +
            "/>",
          )
        }
        None => pdf_svg_placeholder(output, page, item, scale, "image")
      }
    None => pdf_svg_placeholder(output, page, item, scale, "image")
  }
}

///|
fn pdf_svg_shading(
  output : StringBuilder,
  page : PdfPageModel,
  item : PdfVisualItem,
  scale : Double,
) -> Unit {
  match item.shading {
    Some(shading) if shading.stops.length() > 0 => {
      let gradient_id = "pdf-shading-" +
        item.index.to_string() +
        "-" +
        item.name.replace(old="/", new="-")
      let x = (item.bounds.min_x - page.origin_x) * scale
      let y = (page.origin_y + page.height - item.bounds.max_y) * scale
      let width = (item.bounds.max_x - item.bounds.min_x) * scale
      let height = (item.bounds.max_y - item.bounds.min_y) * scale
      let clip_attribute = pdf_svg_clip_attribute(item.index, item.clip_path)
      pdf_svg_clip_defs(output, item.index, item.clip_path)
      output.write_string("<defs>")
      if shading.kind == "axial" && shading.coords.length() >= 4 {
        output.write_string(
          "<linearGradient id=\"" +
          pdf_escape_xml(gradient_id) +
          "\" gradientUnits=\"userSpaceOnUse\" x1=\"" +
          pdf_svg_shading_x(page, shading.coords[0], scale).to_string() +
          "\" y1=\"" +
          pdf_svg_shading_y(page, shading.coords[1], scale).to_string() +
          "\" x2=\"" +
          pdf_svg_shading_x(page, shading.coords[2], scale).to_string() +
          "\" y2=\"" +
          pdf_svg_shading_y(page, shading.coords[3], scale).to_string() +
          "\" spreadMethod=\"pad\">",
        )
        pdf_svg_gradient_stops(output, shading.stops)
        output.write_string("</linearGradient>")
      } else if shading.kind == "radial" && shading.coords.length() >= 6 {
        output.write_string(
          "<radialGradient id=\"" +
          pdf_escape_xml(gradient_id) +
          "\" gradientUnits=\"userSpaceOnUse\" cx=\"" +
          pdf_svg_shading_x(page, shading.coords[3], scale).to_string() +
          "\" cy=\"" +
          pdf_svg_shading_y(page, shading.coords[4], scale).to_string() +
          "\" r=\"" +
          (shading.coords[5].abs() * scale).to_string() +
          "\" fx=\"" +
          pdf_svg_shading_x(page, shading.coords[0], scale).to_string() +
          "\" fy=\"" +
          pdf_svg_shading_y(page, shading.coords[1], scale).to_string() +
          "\" fr=\"" +
          (shading.coords[2].abs() * scale).to_string() +
          "\" spreadMethod=\"pad\">",
        )
        pdf_svg_gradient_stops(output, shading.stops)
        output.write_string("</radialGradient>")
      } else {
        output.write_string(
          "<linearGradient id=\"" +
          pdf_escape_xml(gradient_id) +
          "\" gradientUnits=\"objectBoundingBox\">",
        )
        pdf_svg_gradient_stops(output, shading.stops)
        output.write_string("</linearGradient>")
      }
      output.write_string(
        "</defs>" +
        "<rect" +
        clip_attribute +
        " data-pdf-kind=\"shading\" data-pdf-name=\"" +
        pdf_escape_xml(item.name) +
        "\" x=\"" +
        x.to_string() +
        "\" y=\"" +
        y.to_string() +
        "\" width=\"" +
        width.to_string() +
        "\" height=\"" +
        height.to_string() +
        "\" fill-opacity=\"" +
        item.fill_alpha.to_string() +
        "\"" +
        pdf_svg_blend_style(item.blend_mode) +
        " fill=\"url(#" +
        pdf_escape_xml(gradient_id) +
        ")\"/>",
      )
    }
    _ => pdf_svg_placeholder(output, page, item, scale, "shading")
  }
}

///|
fn pdf_svg_gradient_stops(
  output : StringBuilder,
  stops : ArrayView[PdfGradientStop],
) -> Unit {
  for stop in stops {
    output.write_string(
      "<stop offset=\"" +
      (stop.offset * 100.0).to_string() +
      "%\" stop-color=\"" +
      pdf_escape_xml(stop.color) +
      "\"/>",
    )
  }
}

///|
fn pdf_svg_blend_style(blend_mode : String) -> String {
  if blend_mode == "normal" || blend_mode == "" {
    ""
  } else {
    " style=\"mix-blend-mode:" + pdf_escape_xml(blend_mode) + ";\""
  }
}

///|
fn pdf_svg_shading_x(
  page : PdfPageModel,
  value : Double,
  scale : Double,
) -> Double {
  (value - page.origin_x) * scale
}

///|
fn pdf_svg_shading_y(
  page : PdfPageModel,
  value : Double,
  scale : Double,
) -> Double {
  (page.origin_y + page.height - value) * scale
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
  let clip_attribute = pdf_svg_clip_attribute(item.index, item.clip_path)
  pdf_svg_clip_defs(output, item.index, item.clip_path)
  output.write_string(
    "<g" +
    clip_attribute +
    " data-pdf-kind=\"" +
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
fn pdf_svg_annotations(
  output : StringBuilder,
  page : PdfPageModel,
  scale : Double,
) -> Unit {
  for annotation in page.annotations {
    pdf_svg_annotation(output, page, annotation, scale)
  }
}

///|
fn pdf_svg_annotation(
  output : StringBuilder,
  page : PdfPageModel,
  annotation : PdfAnnotationItem,
  scale : Double,
) -> Unit {
  let x = (annotation.bounds.min_x - page.origin_x) * scale
  let y = (page.origin_y + page.height - annotation.bounds.max_y) * scale
  let width = (annotation.bounds.max_x - annotation.bounds.min_x) * scale
  let height = (annotation.bounds.max_y - annotation.bounds.min_y) * scale
  let color = match annotation.color {
    Some(value) => value
    None =>
      match annotation.subtype {
        "highlight" => "#facc15"
        "underline" => "#2563eb"
        "strikeout" => "#dc2626"
        _ => "#2563eb"
      }
  }
  let stroke_width = if annotation.border_width * scale < 0.5 {
    0.5
  } else {
    annotation.border_width * scale
  }
  let dash = if annotation.border_dash.length() > 0 {
    " stroke-dasharray=\"" +
    pdf_svg_annotation_dash(annotation.border_dash, scale) +
    "\""
  } else if annotation.border_style == "dashed" {
    " stroke-dasharray=\"4 3\""
  } else {
    ""
  }
  let name = "data-pdf-annotation-index=\"" +
    annotation.index.to_string() +
    "\" data-pdf-annotation-type=\"" +
    pdf_escape_xml(annotation.subtype) +
    "\""
  match annotation.uri {
    Some(uri) =>
      output.write_string(
        "<a href=\"" +
        pdf_escape_xml(uri) +
        "\" target=\"_blank\" " +
        name +
        ">",
      )
    None => ()
  }
  match annotation.subtype {
    "highlight" =>
      output.write_string(
        "<rect " +
        name +
        " x=\"" +
        x.to_string() +
        "\" y=\"" +
        y.to_string() +
        "\" width=\"" +
        width.to_string() +
        "\" height=\"" +
        height.to_string() +
        "\" fill=\"" +
        color +
        "\" fill-opacity=\"0.35\" stroke=\"none\"/>",
      )
    "underline" =>
      output.write_string(
        "<line " +
        name +
        " x1=\"" +
        x.to_string() +
        "\" y1=\"" +
        (y + height).to_string() +
        "\" x2=\"" +
        (x + width).to_string() +
        "\" y2=\"" +
        (y + height).to_string() +
        "\" stroke=\"" +
        color +
        "\" stroke-width=\"" +
        stroke_width.to_string() +
        "\"/>",
      )
    "strikeout" =>
      output.write_string(
        "<line " +
        name +
        " x1=\"" +
        x.to_string() +
        "\" y1=\"" +
        (y + height / 2.0).to_string() +
        "\" x2=\"" +
        (x + width).to_string() +
        "\" y2=\"" +
        (y + height / 2.0).to_string() +
        "\" stroke=\"" +
        color +
        "\" stroke-width=\"" +
        stroke_width.to_string() +
        "\"/>",
      )
    "text" => {
      let radius = 6.0.max(width.min(height) / 3.0)
      output.write_string(
        "<g " +
        name +
        "><circle cx=\"" +
        (x + radius).to_string() +
        "\" cy=\"" +
        (y + radius).to_string() +
        "\" r=\"" +
        radius.to_string() +
        "\" fill=\"" +
        color +
        "\" fill-opacity=\"0.9\" stroke=\"white\" stroke-width=\"1\"/>" +
        pdf_svg_annotation_title(annotation) +
        "</g>",
      )
    }
    _ =>
      output.write_string(
        "<rect " +
        name +
        " x=\"" +
        x.to_string() +
        "\" y=\"" +
        y.to_string() +
        "\" width=\"" +
        width.to_string() +
        "\" height=\"" +
        height.to_string() +
        "\" fill=\"none\" stroke=\"" +
        color +
        "\" stroke-width=\"" +
        stroke_width.to_string() +
        "\"" +
        dash +
        "/>" +
        pdf_svg_annotation_title(annotation),
      )
  }
  match annotation.uri {
    Some(_) => output.write_string("</a>")
    None => ()
  }
}

///|
fn pdf_svg_annotation_title(annotation : PdfAnnotationItem) -> String {
  match annotation.contents {
    Some(contents) => "<title>" + pdf_escape_xml(contents) + "</title>"
    None => ""
  }
}

///|
fn pdf_svg_annotation_dash(values : ArrayView[Int], scale : Double) -> String {
  let output = StringBuilder()
  let mut first = true
  for value in values {
    if !first {
      output.write_char(' ')
    }
    first = false
    output.write_string((value.to_double() * scale).to_string())
  }
  output.to_string()
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
/// Serialize explicit PDF clipping paths in page-space SVG coordinates.
fn pdf_svg_clip_path_of_shapes(
  paths : ArrayView[@shape.PdfPath],
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
) -> String? {
  let output = StringBuilder()
  let mut found = false
  for path in paths {
    match pdf_shape_bounds(path) {
      Some(bounds) => {
        let value = pdf_svg_path_of_shape(
          path, origin_x, origin_y, page_height, bounds,
        )
        if value != "" {
          if found {
            output.write_string("||")
          }
          found = true
          output.write_string(value)
        }
      }
      None => ()
    }
  }
  if found {
    Some(output.to_string())
  } else {
    None
  }
}

///|
fn pdf_svg_clip_defs(
  output : StringBuilder,
  index : Int,
  clip_path : String?,
) -> Unit {
  match clip_path {
    Some(path) => {
      let parts : Array[String] = []
      for part in path.split("||") {
        parts.push(part.to_owned())
      }
      let base = "pdf-clip-" + index.to_string()
      output.write_string("<defs>")
      for part_index, part in parts {
        let id = pdf_svg_clip_id(base, parts.length(), part_index)
        output.write_string("<clipPath id=\"" + id + "\">")
        if part_index == 0 {
          output.write_string("<path d=\"" + part + "\"/>")
        } else {
          let previous = pdf_svg_clip_id(base, parts.length(), part_index - 1)
          output.write_string(
            "<g clip-path=\"url(#" +
            previous +
            ")\"><path d=\"" +
            part +
            "\"/></g>",
          )
        }
        output.write_string("</clipPath>")
      }
      output.write_string("</defs>")
    }
    None => ()
  }
}

///|
fn pdf_svg_clip_attribute(index : Int, clip_path : String?) -> String {
  match clip_path {
    Some(path) => {
      let mut count = 0
      for _ in path.split("||") {
        count += 1
      }
      let base = "pdf-clip-" + index.to_string()
      " clip-path=\"url(#" + pdf_svg_clip_id(base, count, count - 1) + ")\""
    }
    None => ""
  }
}

///|
fn pdf_svg_clip_id(base : String, count : Int, index : Int) -> String {
  if count == 1 {
    base
  } else {
    base + "-" + index.to_string()
  }
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

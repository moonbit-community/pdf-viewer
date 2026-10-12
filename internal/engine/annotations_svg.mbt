///|
fn pdf_svg_annotations(
  output : StringBuilder,
  page : PdfPageModel,
  scale : Double,
) -> Unit {
  for annotation in page.annotations {
    if annotation.visible {
      let x = (annotation.bounds.min_x - page.origin_x) * scale
      let y = (page.origin_y + page.height - annotation.bounds.max_y) * scale
      let compensation = if annotation.style.no_zoom {
        1.0 / scale
      } else {
        1.0
      }
      let rotation = if annotation.style.no_rotate { -page.rotation } else { 0 }
      output.write_string(
        "<g opacity=\"\{annotation.style.opacity}\"" +
        (if annotation.subtype == "highlight" && annotation.appearance is None {
          " style=\"mix-blend-mode:multiply\""
        } else {
          ""
        }) +
        " transform=\"translate(\{x} \{y}) rotate(\{rotation}) scale(\{compensation}) translate(\{-x} \{-y})\">",
      )
      pdf_svg_annotation(output, page, annotation, scale)
      output.write_string("</g>")
    }
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
        "highlight" => "#FFFF00"
        _ => "#000000"
      }
  }
  let stroke_width = if (
      annotation.subtype == "square" || annotation.subtype == "circle"
    ) &&
    annotation.border_width <= 0.0 {
    0.0
  } else if (
      annotation.subtype == "line" ||
      annotation.subtype == "polyline" ||
      annotation.subtype == "polygon" ||
      annotation.subtype == "ink"
    ) &&
    annotation.border_width <= 0.0 {
    scale
  } else if annotation.border_width * scale < 0.5 {
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
    "\"" +
    pdf_svg_annotation_field_attributes(annotation)
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
  match annotation.appearance {
    Some(appearance) => {
      pdf_svg_annotation_appearance(
        output, page, annotation, appearance, scale, name,
      )
      match annotation.uri {
        Some(_) => output.write_string("</a>")
        None => ()
      }
      return
    }
    _ => ()
  }
  if annotation.subtype == "widget" {
    pdf_svg_annotation_widget_fallback(output, page, annotation, scale, name)
    match annotation.uri {
      Some(_) => output.write_string("</a>")
      None => ()
    }
    return
  }
  match annotation.subtype {
    "highlight" =>
      if annotation.quad_points.length() > 0 {
        for quad in annotation.quad_points {
          pdf_svg_annotation_quad(
            output, page, annotation, quad, color, "1", "none", "", scale,
          )
        }
      } else {
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
          "\" fill-opacity=\"1\" stroke=\"none\"/>",
        )
      }
    "underline" | "strikeout" | "squiggly" =>
      if annotation.quad_points.length() > 0 {
        for quad in annotation.quad_points {
          let first = if annotation.subtype == "underline" {
            quad.p0
          } else if annotation.subtype == "strikeout" {
            {
              x: (quad.p0.x + quad.p3.x) / 2.0,
              y: (quad.p0.y + quad.p3.y) / 2.0,
            }
          } else {
            quad.p0
          }
          let second = if annotation.subtype == "underline" {
            quad.p1
          } else if annotation.subtype == "strikeout" {
            {
              x: (quad.p1.x + quad.p2.x) / 2.0,
              y: (quad.p1.y + quad.p2.y) / 2.0,
            }
          } else {
            quad.p1
          }
          if annotation.subtype == "squiggly" {
            pdf_svg_annotation_squiggly(
              output, page, annotation, first, second, color, stroke_width, scale,
            )
          } else {
            pdf_svg_annotation_line(
              output, page, annotation, first, second, color, stroke_width, dash,
              scale,
            )
          }
        }
      } else {
        pdf_svg_annotation_line(
          output,
          page,
          annotation,
          { x: annotation.bounds.min_x, y: annotation.bounds.min_y, },
          { x: annotation.bounds.max_x, y: annotation.bounds.min_y, },
          color,
          stroke_width,
          dash,
          scale,
        )
      }
    "line" =>
      match annotation.line_points {
        [first, second, ..] => {
          pdf_svg_annotation_line(
            output, page, annotation, first, second, color, stroke_width, dash, scale,
          )
          pdf_svg_annotation_line_endings(
            output, page, annotation, first, second, color, stroke_width, scale,
          )
        }
        _ =>
          pdf_svg_annotation_line(
            output,
            page,
            annotation,
            { x: annotation.bounds.min_x, y: annotation.bounds.min_y, },
            { x: annotation.bounds.max_x, y: annotation.bounds.max_y, },
            color,
            stroke_width,
            dash,
            scale,
          )
      }
    "polygon" | "polyline" =>
      if annotation.vertices.length() >= 2 {
        pdf_svg_annotation_polyline(
          output,
          page,
          annotation,
          annotation.vertices,
          color,
          stroke_width,
          dash,
          annotation.subtype == "polygon",
          scale,
        )
        if annotation.subtype == "polyline" {
          pdf_svg_annotation_line_endings(
            output,
            page,
            annotation,
            annotation.vertices[0],
            annotation.vertices[annotation.vertices.length() - 1],
            color,
            stroke_width,
            scale,
          )
        }
      } else {
        pdf_svg_annotation_rect(
          output, annotation, x, y, width, height, color, stroke_width, dash, name,
        )
      }
    "ink" =>
      for points in annotation.ink_paths {
        if points.length() >= 2 {
          pdf_svg_annotation_polyline(
            output, page, annotation, points, color, stroke_width, dash, false, scale,
          )
        }
      }
    "free-text" => {
      let annotation_contents = match annotation.contents {
        Some(value) => value
        None => ""
      }
      output.write_string(
        "<text " +
        name +
        " x=\"" +
        x.to_string() +
        "\" y=\"" +
        (y + height).to_string() +
        "\" fill=\"" +
        color +
        "\" font-size=\"" +
        (height * 0.75).max(6.0).to_string() +
        "\">" +
        pdf_escape_xml(annotation_contents) +
        "</text>",
      )
    }
    "square" =>
      pdf_svg_annotation_rect(
        output, annotation, x, y, width, height, color, stroke_width, dash, name,
      )
    "circle" =>
      output.write_string(
        "<ellipse " +
        name +
        " cx=\"" +
        (x + width / 2.0).to_string() +
        "\" cy=\"" +
        (y + height / 2.0).to_string() +
        "\" rx=\"" +
        (width / 2.0).to_string() +
        "\" ry=\"" +
        (height / 2.0).to_string() +
        "\" fill=\"" +
        annotation.style.interior_color.unwrap_or("none") +
        "\" stroke=\"" +
        color +
        "\" stroke-width=\"" +
        stroke_width.to_string() +
        "\"" +
        dash +
        "/>",
      )
    "caret" =>
      output.write_string(
        "<path " +
        name +
        " d=\"M \{x} \{y + height} L \{x + width / 2.0} \{y} L \{x + width} \{y + height} Z\" fill=\"\{color}\"/>",
      )
    "text" | "file-attachment" | "sound" => {
      let icon = if annotation.subtype == "file-attachment" &&
        annotation.style.icon == "Note" {
        "Paperclip"
      } else {
        annotation.style.icon
      }
      output.write_string(
        "<g " +
        name +
        " data-pdf-annotation-icon=\"" +
        pdf_escape_xml(icon) +
        "\" transform=\"translate(\{x} \{y}) scale(\{width / 40.0} \{height / 40.0})\">" +
        pdf_annotation_icon_svg(icon) +
        pdf_svg_annotation_title(annotation) +
        "</g>",
      )
    }
    _ =>
      pdf_svg_annotation_rect(
        output, annotation, x, y, width, height, color, stroke_width, dash, name,
      )
  }
  match annotation.uri {
    Some(_) => output.write_string("</a>")
    None => ()
  }
}

///|
fn pdf_svg_annotation_field_attributes(
  annotation : PdfAnnotationItem,
) -> String {
  let output = StringBuilder()
  match annotation.field_name {
    Some(value) =>
      output.write_string(
        " data-pdf-field-name=\"" + pdf_escape_xml(value) + "\"",
      )
    None => ()
  }
  match annotation.field_type {
    Some(value) =>
      output.write_string(
        " data-pdf-field-type=\"" + pdf_escape_xml(value) + "\"",
      )
    None => ()
  }
  match annotation.field_value {
    Some(value) => {
      let value = if annotation.field_type == Some("Tx") &&
        annotation.field_flags.unwrap_or(0).land(8192) != 0 {
        String::from_iter(value.iter().map(_ => '*'))
      } else {
        value
      }
      output.write_string(
        " data-pdf-field-value=\"" + pdf_escape_xml(value) + "\"",
      )
    }
    None => ()
  }
  match annotation.field_flags {
    Some(value) =>
      output.write_string(" data-pdf-field-flags=\"" + value.to_string() + "\"")
    None => ()
  }
  output.to_string()
}

///|
/// Render a read-only fallback for a widget with no `/AP`. pdf.js synthesizes
/// these appearances for common text, choice, checkbox, and radio fields; the
/// fallback keeps the stored value visible while retaining the widget's
/// rectangle for a later interactive host.
fn pdf_svg_annotation_widget_fallback(
  output : StringBuilder,
  page : PdfPageModel,
  annotation : PdfAnnotationItem,
  scale : Double,
  name : String,
) -> Unit {
  let x = (annotation.bounds.min_x - page.origin_x) * scale
  let y = (page.origin_y + page.height - annotation.bounds.max_y) * scale
  let width = (annotation.bounds.max_x - annotation.bounds.min_x) * scale
  let height = (annotation.bounds.max_y - annotation.bounds.min_y) * scale
  let border = if annotation.border_width * scale < 0.5 {
    0.5
  } else {
    annotation.border_width * scale
  }
  let stroke = match annotation.color {
    Some(value) => value
    None => "#4b5563"
  }
  let field_type = match annotation.field_type {
    Some(value) => value
    None => ""
  }
  let value = match annotation.field_value {
    Some(value) => value
    None => ""
  }
  let flags = annotation.field_flags.unwrap_or(0)
  let pushbutton = (flags & 65536) != 0
  let radio = field_type == "Btn" && (flags & 32768) != 0 && !pushbutton
  if !radio {
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
      "\" fill=\"white\" fill-opacity=\"0.02\" stroke=\"" +
      stroke +
      "\" stroke-width=\"" +
      border.to_string() +
      "\"/>\n",
    )
  }
  match field_type {
    "Tx" | "Ch" =>
      if value != "" {
        output.write_string(
          "<text " +
          name +
          " x=\"" +
          (x + 2.0 * scale).to_string() +
          "\" y=\"" +
          (y + (height * 0.18).max(2.0 * scale)).to_string() +
          "\" font-family=\"sans-serif\" font-size=\"" +
          (height * 0.68).max(6.0 * scale).to_string() +
          "\" fill=\"#111827\" dominant-baseline=\"hanging\">" +
          pdf_escape_xml(value) +
          "</text>",
        )
      }
    "Btn" => {
      let selected = annotation.button_checked == Some(true)
      if pushbutton {
        if value != "" {
          output.write_string(
            "<text " +
            name +
            " x=\"" +
            (x + width / 2.0).to_string() +
            "\" y=\"" +
            (y + height * 0.2).to_string() +
            "\" font-family=\"sans-serif\" font-size=\"" +
            (height * 0.55).max(6.0 * scale).to_string() +
            "\" text-anchor=\"middle\" fill=\"#111827\" dominant-baseline=\"hanging\">" +
            pdf_escape_xml(value) +
            "</text>",
          )
        }
      } else if radio {
        let radius = (width.min(height) / 2.0 - border).max(1.0)
        output.write_string(
          "<circle " +
          name +
          " cx=\"" +
          (x + width / 2.0).to_string() +
          "\" cy=\"" +
          (y + height / 2.0).to_string() +
          "\" r=\"" +
          radius.to_string() +
          "\" fill=\"none\" stroke=\"" +
          stroke +
          "\" stroke-width=\"" +
          border.to_string() +
          "\"/>",
        )
        if selected {
          output.write_string(
            "<circle data-pdf-button-checked=\"true\" cx=\"" +
            (x + width / 2.0).to_string() +
            "\" cy=\"" +
            (y + height / 2.0).to_string() +
            "\" r=\"" +
            (radius * 0.48).to_string() +
            "\" fill=\"" +
            stroke +
            "\"/>",
          )
        }
      } else if selected {
        output.write_string(
          "<path data-pdf-button-checked=\"true\" " +
          name +
          " d=\"M " +
          (x + width * 0.2).to_string() +
          " " +
          (y + height * 0.52).to_string() +
          " L " +
          (x + width * 0.44).to_string() +
          " " +
          (y + height * 0.76).to_string() +
          " L " +
          (x + width * 0.82).to_string() +
          " " +
          (y + height * 0.24).to_string() +
          "\" fill=\"none\" stroke=\"" +
          stroke +
          "\" stroke-width=\"" +
          (border * 1.5).to_string() +
          "\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>",
        )
      }
    }
    _ => ()
  }
  match annotation.field_tooltip {
    Some(value) =>
      output.write_string("<title>" + pdf_escape_xml(value) + "</title>")
    None => ()
  }
}

///|
/// Render a normal annotation appearance stream. The appearance content is
/// already serialized in its own SVG coordinate system; this affine transform
/// maps that system into the PDF annotation rectangle while preserving the
/// stream's `/Matrix` and the PDF-to-top-left SVG axis flip.
fn pdf_svg_annotation_appearance(
  output : StringBuilder,
  page : PdfPageModel,
  annotation : PdfAnnotationItem,
  appearance : PdfAnnotationAppearance,
  scale : Double,
  name : String,
) -> Unit {
  let source = appearance.bbox
  let transformed = pdf_annotation_appearance_bounds(source, appearance.matrix)
  let source_width = transformed.max_x - transformed.min_x
  let source_height = transformed.max_y - transformed.min_y
  let degenerate = source_width == 0.0 || source_height == 0.0
  let target_x = (annotation.bounds.min_x - page.origin_x) * scale
  let target_y = (
      page.origin_y +
      page.height -
      (if degenerate {
        annotation.bounds.min_y
      } else {
        annotation.bounds.max_y
      })
    ) *
    scale
  let target_width = (annotation.bounds.max_x - annotation.bounds.min_x) * scale
  let target_height = (annotation.bounds.max_y - annotation.bounds.min_y) *
    scale
  let x_ratio = if degenerate { scale } else { target_width / source_width }
  let y_ratio = if degenerate { scale } else { target_height / source_height }
  let (a, b, c, d, e, f) = match appearance.matrix {
    [a, b, c, d, e, f] => (a, b, c, d, e, f)
    _ => (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
  }
  // The appearance fragment uses x'=x-bbox.min_x and
  // y'=bbox.max_y-y. Conjugate the PDF matrix through that axis flip, then
  // move the transformed bounding box to the origin before fitting /Rect.
  let tx = a * source.min_x +
    c * source.max_y +
    e -
    (if degenerate { 0.0 } else { transformed.min_x })
  let ty = (if degenerate { 0.0 } else { transformed.max_y }) -
    (b * source.min_x + d * source.max_y + f)
  let matrix = "matrix(" +
    (x_ratio * a).to_string() +
    " " +
    (y_ratio * -b).to_string() +
    " " +
    (x_ratio * -c).to_string() +
    " " +
    (y_ratio * d).to_string() +
    " " +
    (target_x + x_ratio * tx).to_string() +
    " " +
    (target_y + y_ratio * ty).to_string() +
    ")"
  output.write_string(
    "<g " +
    name +
    " data-pdf-annotation-appearance=\"true\" transform=\"" +
    matrix +
    "\">" +
    appearance.svg +
    "</g>",
  )
}

///|
/// Compute the axis-aligned bounds of an appearance BBox after its PDF
/// `/Matrix`, as required by pdf.js' `getTransformMatrix` algorithm.
fn pdf_annotation_appearance_bounds(
  bbox : PdfBounds,
  matrix : Array[Double],
) -> PdfBounds {
  let (a, b, c, d, e, f) = match matrix {
    [a, b, c, d, e, f] => (a, b, c, d, e, f)
    _ => (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)
  }
  let x0 = a * bbox.min_x + c * bbox.min_y + e
  let y0 = b * bbox.min_x + d * bbox.min_y + f
  let x1 = a * bbox.min_x + c * bbox.max_y + e
  let y1 = b * bbox.min_x + d * bbox.max_y + f
  let x2 = a * bbox.max_x + c * bbox.max_y + e
  let y2 = b * bbox.max_x + d * bbox.max_y + f
  let x3 = a * bbox.max_x + c * bbox.min_y + e
  let y3 = b * bbox.max_x + d * bbox.min_y + f
  {
    min_x: x0.min(x1).min(x2).min(x3),
    min_y: y0.min(y1).min(y2).min(y3),
    max_x: x0.max(x1).max(x2).max(x3),
    max_y: y0.max(y1).max(y2).max(y3),
  }
}

///|
fn pdf_svg_annotation_point(
  page : PdfPageModel,
  point : PdfPoint,
  scale : Double,
) -> String {
  ((point.x - page.origin_x) * scale).to_string() +
  " " +
  ((page.origin_y + page.height - point.y) * scale).to_string()
}

///|
fn pdf_svg_annotation_xy(
  page : PdfPageModel,
  point : PdfPoint,
  scale : Double,
) -> (String, String) {
  (
    ((point.x - page.origin_x) * scale).to_string(),
    ((page.origin_y + page.height - point.y) * scale).to_string(),
  )
}

///|
fn pdf_svg_annotation_quad(
  output : StringBuilder,
  page : PdfPageModel,
  annotation : PdfAnnotationItem,
  quad : PdfQuad,
  color : String,
  opacity : String,
  stroke : String,
  dash : String,
  scale : Double,
) -> Unit {
  output.write_string(
    "<polygon data-pdf-annotation-index=\"" +
    annotation.index.to_string() +
    "\" points=\"" +
    pdf_svg_annotation_point(page, quad.p0, scale) +
    " " +
    pdf_svg_annotation_point(page, quad.p1, scale) +
    " " +
    pdf_svg_annotation_point(page, quad.p2, scale) +
    " " +
    pdf_svg_annotation_point(page, quad.p3, scale) +
    "\" fill=\"" +
    color +
    "\" fill-opacity=\"" +
    opacity +
    "\" stroke=\"" +
    stroke +
    "\"" +
    dash +
    "/>",
  )
}

///|
fn pdf_svg_annotation_line(
  output : StringBuilder,
  page : PdfPageModel,
  annotation : PdfAnnotationItem,
  first : PdfPoint,
  second : PdfPoint,
  color : String,
  width : Double,
  dash : String,
  scale : Double,
) -> Unit {
  let (first_x, first_y) = pdf_svg_annotation_xy(page, first, scale)
  let (second_x, second_y) = pdf_svg_annotation_xy(page, second, scale)
  output.write_string(
    "<line data-pdf-annotation-index=\"" +
    annotation.index.to_string() +
    "\" x1=\"" +
    first_x +
    "\" y1=\"" +
    first_y +
    "\" x2=\"" +
    second_x +
    "\" y2=\"" +
    second_y +
    "\" stroke=\"" +
    color +
    "\" stroke-width=\"" +
    width.to_string() +
    "\" stroke-linecap=\"round\"" +
    dash +
    "/>",
  )
}

///|
fn pdf_svg_annotation_polyline(
  output : StringBuilder,
  page : PdfPageModel,
  annotation : PdfAnnotationItem,
  points : ArrayView[PdfPoint],
  color : String,
  width : Double,
  dash : String,
  closed : Bool,
  scale : Double,
) -> Unit {
  let values = StringBuilder()
  for index, point in points {
    if index > 0 {
      values.write_char(' ')
    }
    values.write_string(pdf_svg_annotation_point(page, point, scale))
  }
  if closed && points.length() > 0 {
    values.write_char(' ')
    values.write_string(pdf_svg_annotation_point(page, points[0], scale))
  }
  output.write_string(
    "<polyline data-pdf-annotation-index=\"" +
    annotation.index.to_string() +
    "\" points=\"" +
    values.to_string() +
    "\" fill=\"" +
    (if closed {
      annotation.style.interior_color.unwrap_or("none")
    } else {
      "none"
    }) +
    "\" stroke=\"" +
    color +
    "\" stroke-width=\"" +
    width.to_string() +
    "\" stroke-linecap=\"round\" stroke-linejoin=\"round\"" +
    dash +
    "/>",
  )
}

///|
fn pdf_svg_annotation_rect(
  output : StringBuilder,
  annotation : PdfAnnotationItem,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
  color : String,
  stroke_width : Double,
  dash : String,
  name : String,
) -> Unit {
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
    annotation.style.interior_color.unwrap_or("none") +
    "\" stroke=\"" +
    color +
    "\" stroke-width=\"" +
    stroke_width.to_string() +
    "\"" +
    dash +
    "/>" +
    pdf_svg_annotation_title(annotation),
  )
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

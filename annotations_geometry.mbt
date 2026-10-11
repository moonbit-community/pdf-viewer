///|
fn pdf_svg_annotation_squiggly(
  output : StringBuilder,
  page : PdfPageModel,
  annotation : PdfAnnotationItem,
  first : PdfPoint,
  second : PdfPoint,
  color : String,
  width : Double,
  scale : Double,
) -> Unit {
  let x0 = (first.x - page.origin_x) * scale
  let y0 = (page.origin_y + page.height - first.y) * scale
  let x1 = (second.x - page.origin_x) * scale
  let y1 = (page.origin_y + page.height - second.y) * scale
  let length = ((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)).sqrt()
  if length <= 0.0 {
    return
  }
  let count = (length / (2.0 * scale).max(0.01))
    .ceil()
    .to_int()
    .max(2)
    .min(4096)
  let amplitude = scale.max(width)
  let path = StringBuilder()
  path.write_string("M \{x0} \{y0}")
  for i in 1..<=count {
    let t = i.to_double() / count.to_double()
    let offset = if i == count {
      0.0
    } else if i % 2 == 0 {
      -amplitude
    } else {
      amplitude
    }
    let x = x0 + t * (x1 - x0) - (y1 - y0) / length * offset
    let y = y0 + t * (y1 - y0) + (x1 - x0) / length * offset
    path.write_string(" L \{x} \{y}")
  }
  output.write_string(
    "<path data-pdf-annotation-index=\"\{annotation.index}\" data-pdf-markup=\"squiggly\" d=\"" +
    path.to_string() +
    "\" fill=\"none\" stroke=\"\{color}\" stroke-width=\"\{width}\"/>",
  )
}

///|
fn pdf_svg_annotation_line_endings(
  output : StringBuilder,
  page : PdfPageModel,
  annotation : PdfAnnotationItem,
  first : PdfPoint,
  second : PdfPoint,
  color : String,
  width : Double,
  scale : Double,
) -> Unit {
  let x0 = (first.x - page.origin_x) * scale
  let y0 = (page.origin_y + page.height - first.y) * scale
  let x1 = (second.x - page.origin_x) * scale
  let y1 = (page.origin_y + page.height - second.y) * scale
  let length = ((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0)).sqrt()
  if length <= 0.0 {
    return
  }
  let ux = (x1 - x0) / length
  let uy = (y1 - y0) / length
  let size = (width * 3.0).max(3.0 * scale)
  for i in 0..<annotation.style.line_endings.length().min(2) {
    let name = annotation.style.line_endings[i]
    let (x, y, dx, dy) = if i == 0 {
      (x0, y0, ux, uy)
    } else {
      (x1, y1, -ux, -uy)
    }
    let fill = annotation.style.interior_color.unwrap_or(color)
    output.write_string(
      "<g data-pdf-line-ending=\"" +
      pdf_escape_xml(name) +
      "\" transform=\"matrix(\{dx} \{dy} \{-dy} \{dx} \{x} \{y})\" stroke=\"\{color}\" stroke-width=\"\{width}\" fill=\"\{fill}\" stroke-linejoin=\"miter\">",
    )
    match name {
      "Square" =>
        output.write_string(
          "<rect x=\"\{-size}\" y=\"\{-size}\" width=\"\{size * 2.0}\" height=\"\{size * 2.0}\"/>",
        )
      "Circle" =>
        output.write_string("<circle cx=\"0\" cy=\"0\" r=\"\{size}\"/>")
      "Diamond" =>
        output.write_string(
          "<path d=\"M \{-size} 0 L 0 \{-size} L \{size} 0 L 0 \{size} Z\"/>",
        )
      "OpenArrow" | "ClosedArrow" | "ROpenArrow" | "RClosedArrow" => {
        let direction = if name.has_prefix("R") { -1.0 } else { 1.0 }
        let close = if name == "ClosedArrow" || name == "RClosedArrow" {
          " Z"
        } else {
          ""
        }
        let paint = if close == "" { "none" } else { fill }
        output.write_string(
          "<path fill=\"\{paint}\" d=\"M \{size * 2.0 * direction} \{-size} L 0 0 L \{size * 2.0 * direction} \{size}\{close}\"/>",
        )
      }
      "Butt" =>
        output.write_string(
          "<path fill=\"none\" d=\"M 0 \{-size} L 0 \{size}\"/>",
        )
      "Slash" =>
        output.write_string(
          "<path fill=\"none\" d=\"M \{-size * 0.5} \{-size} L \{size * 0.5} \{size}\"/>",
        )
      _ => ()
    }
    output.write_string("</g>")
  }
}

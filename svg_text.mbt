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
  let same_transform = match
    (previous.glyph_transform, current.glyph_transform) {
    (Some([a, b, c, d, e, f]), Some([aa, bb, cc, dd, ee, ff])) => {
      let determinant = a * d - b * c
      determinant != 0.0 &&
      (a - aa).abs() < 0.000001 &&
      (b - bb).abs() < 0.000001 &&
      (c - cc).abs() < 0.000001 &&
      (d - dd).abs() < 0.000001 &&
      ((-b * (ee - e) + a * (ff - f)) / determinant).abs() < 0.000001
    }
    (None, None) => true
    _ => false
  }
  let line_threshold = if previous.font_size > current.font_size {
    previous.font_size * 0.2
  } else {
    current.font_size * 0.2
  }
  let previous_angle = pdf_text_angle(previous)
  let current_angle = pdf_text_angle(current)
  (previous.bounds.max_y - current.bounds.max_y).abs() <= line_threshold &&
  previous.font == current.font &&
  previous.font_size == current.font_size &&
  previous.fill_alpha == current.fill_alpha &&
  previous.blend_mode == current.blend_mode &&
  same_transform &&
  previous.rendering_mode == current.rendering_mode &&
  previous.fill_color == current.fill_color &&
  previous.stroke_color == current.stroke_color &&
  (previous_angle - current_angle).abs() <= 0.01 &&
  previous.clip_path == current.clip_path &&
  previous.soft_mask == current.soft_mask
}

///|
/// Keep source text in the page model for extraction and selection, but omit
/// undefined Standard 14 codes when serializing SVG text nodes. PDF.js keeps
/// those source codes in textContent while its canvas renderer does not paint
/// arbitrary Unicode fallback glyphs for them.
fn pdf_svg_display_text(page : PdfPageModel, item : PdfTextItem) -> String {
  if item.type3_outline is Some(outline) && !outline.is_empty() {
    return item.text
  }
  for font in page.fonts {
    if font.name == item.font {
      let standard_font = match font.standard_font {
        Some(name) => pdf_standard_font_of_base_name("/" + name)
        None => None
      }
      return pdf_standard14_display_text(
        standard_font,
        item.charcode,
        item.text,
      )
    }
  }
  item.text
}

///|
/// XML labels retain copied text while omitting characters XML 1.0 cannot
/// serialize. The extraction/source model still contains those characters.
fn pdf_svg_xml_text(text : String) -> String {
  let output = StringBuilder()
  for char in text.iter() {
    let code = char.to_int()
    if code == 9 ||
      code == 10 ||
      code == 13 ||
      (
        code >= 32 &&
        code <= 0x10FFFF &&
        !(code >= 0xD800 && code <= 0xDFFF) &&
        code != 0xFFFE &&
        code != 0xFFFF
      ) {
      output.write_char(char)
    }
  }
  output.to_string()
}

///|
fn pdf_svg_text(
  output : StringBuilder,
  page : PdfPageModel,
  items : ArrayView[PdfTextItem],
  scale : Double,
) -> Unit {
  let has_outline = for item in items {
    if item.type3_outline is Some(_) {
      break true
    }
  } nobreak {
    false
  }
  if has_outline {
    let label = StringBuilder()
    for item in items {
      label.write_string(pdf_svg_xml_text(pdf_svg_display_text(page, item)))
    }
    output.write_string(
      "<g><title>" + pdf_escape_xml(label.to_string()) + "</title>",
    )
    for item in items {
      match item.type3_outline {
        Some(_) => pdf_svg_outline_text(output, page, item, scale)
        None => pdf_svg_text(output, page, [item], scale)
      }
    }
    output.write_string("</g>")
    return
  }
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
    value.write_string(pdf_svg_display_text(page, item))
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
  let (x, y, transform, font_size, baseline) = match first.glyph_transform {
    Some([a, b, c, d, e, f]) if a * d - b * c != 0.0 => {
      let positions : Array[String] = []
      for item in items {
        let position = match item.glyph_transform {
          Some([_, _, _, _, ee, ff]) =>
            (d * (ee - e) - c * (ff - f)) / (a * d - b * c)
          _ => 0.0
        }
        positions.push(position.to_string())
      }
      let values = [
        a * scale,
        -b * scale,
        -c * scale,
        d * scale,
        (e - page.origin_x) * scale,
        (page.origin_y + page.height - f) * scale,
      ]
      let matrix = values.map(v => v.to_string()).join(" ")
      (
        positions.join(" "),
        0.0,
        " transform=\"matrix(\{matrix})\"",
        1.0,
        "alphabetic",
      )
    }
    _ => (x, y, transform, first.font_size * scale, "hanging")
  }
  let family = pdf_svg_font_family_for_page(page, first.font)
  let weight = pdf_svg_font_weight_for_page(page, first.font)
  let style = pdf_svg_font_style_for_page(page, first.font)
  let fill = if pdf_text_mode_fills(first.rendering_mode) {
    first.fill_color
  } else {
    "none"
  }
  let stroke = if pdf_text_mode_strokes(first.rendering_mode) {
    first.stroke_color
  } else {
    "none"
  }
  let stroke_width = if stroke == "none" { 0.0 } else { font_size * 0.04 }
  pdf_svg_clip_defs(output, first.index, first.clip_path, scale)
  pdf_svg_soft_mask_defs(output, first.index, page, first.soft_mask, scale)
  pdf_svg_soft_mask_open(output, first.index, first.soft_mask)
  pdf_svg_clip_open(output, first.index, first.clip_path)
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
    font_size.to_string() +
    "\" font-weight=\"" +
    weight +
    "\" font-style=\"" +
    style +
    "\" fill=\"" +
    pdf_escape_xml(fill) +
    "\" stroke=\"" +
    pdf_escape_xml(stroke) +
    "\" stroke-width=\"" +
    stroke_width.to_string() +
    "\" fill-opacity=\"" +
    first.fill_alpha.to_string() +
    "\"" +
    pdf_svg_blend_style(first.blend_mode) +
    " dominant-baseline=\"" +
    baseline +
    "\">" +
    pdf_escape_xml(value.to_string()) +
    "</text>",
  )
  pdf_svg_clip_close(output, first.index, first.clip_path)
  pdf_svg_soft_mask_close(output, first.index, first.soft_mask)
}

///|
fn pdf_svg_outline_text(
  output : StringBuilder,
  page : PdfPageModel,
  item : PdfTextItem,
  scale : Double,
) -> Unit {
  match item.type3_outline {
    None => ()
    Some(outline) => {
      pdf_svg_clip_defs(output, item.index, item.clip_path, scale)
      pdf_svg_soft_mask_defs(output, item.index, page, item.soft_mask, scale)
      pdf_svg_soft_mask_open(output, item.index, item.soft_mask)
      pdf_svg_clip_open(output, item.index, item.clip_path)
      output.write_string(
        "<g transform=\"scale(" +
        scale.to_string() +
        ")\" data-pdf-text-outline=\"true\" data-pdf-text-index=\"" +
        item.index.to_string() +
        "\"" +
        pdf_svg_blend_style(item.blend_mode) +
        ">" +
        outline +
        "</g>",
      )
      pdf_svg_clip_close(output, item.index, item.clip_path)
      pdf_svg_soft_mask_close(output, item.index, item.soft_mask)
    }
  }
}

///|
/// PDF text rendering modes 0, 2, 4 and 6 paint glyph interiors.
fn pdf_text_mode_fills(mode : Int) -> Bool {
  mode == 0 || mode == 2 || mode == 4 || mode == 6
}

///|
/// PDF text rendering modes 1, 2, 5 and 6 paint glyph outlines.
fn pdf_text_mode_strokes(mode : Int) -> Bool {
  mode == 1 || mode == 2 || mode == 5 || mode == 6
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
  if font.contains("Courier") ||
    font.contains("Mono") ||
    font.contains("NimbusMono") ||
    font.contains("CMTT") {
    "monospace"
  } else if font.contains("Times") ||
    font.contains("Serif") ||
    font.contains("Roman") ||
    font.contains("NimbusRom") ||
    font.contains("NimbusRoman") ||
    font.contains("CMR") ||
    font.contains("CMSY") ||
    font.contains("CMMI") ||
    font.contains("CMEX") ||
    font.contains("LiberationSerif") {
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
    if resource.name == font {
      return resource.family
    }
  }
  pdf_svg_font_family(font)
}

///|
fn pdf_svg_font_weight_for_page(page : PdfPageModel, font : String) -> String {
  for resource in page.fonts {
    if resource.name == font {
      return resource.weight
    }
  }
  if font.contains("Bold") ||
    font.contains("Medi") ||
    font.contains("Demi") ||
    font.contains("Black") {
    "bold"
  } else {
    "normal"
  }
}

///|
fn pdf_svg_font_style_for_page(page : PdfPageModel, font : String) -> String {
  for resource in page.fonts {
    if resource.name == font {
      return resource.style
    }
  }
  if font.contains("Italic") ||
    font.contains("Oblique") ||
    font.contains("Slant") {
    "italic"
  } else {
    "normal"
  }
}

///|
fn pdf_svg_fonts(output : StringBuilder, page : PdfPageModel) -> Unit {
  let css = StringBuilder()
  for resource in page.fonts {
    match resource.data_uri {
      Some(data_uri) =>
        if resource.format != "cff" && resource.format != "type1" {
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

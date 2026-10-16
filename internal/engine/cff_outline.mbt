///|
fn pdf_cff_svg_point(
  matrix : @geometry.TransformMatrix,
  x : Double,
  y : Double,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
) -> String {
  let point = matrix.apply(@geometry.point2(x, y))
  (point.x - origin_x).to_string() +
  " " +
  (origin_y + page_height - point.y).to_string()
}

///|
fn pdf_cff_svg_path(
  commands : ArrayView[PdfCffPathCommand],
  matrix : @geometry.TransformMatrix,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
) -> String {
  let output = StringBuilder()
  for command in commands {
    match command {
      CffMove(x, y) => {
        output.write_string("M ")
        output.write_string(
          pdf_cff_svg_point(matrix, x, y, origin_x, origin_y, page_height),
        )
      }
      CffLine(x, y) => {
        output.write_string(" L ")
        output.write_string(
          pdf_cff_svg_point(matrix, x, y, origin_x, origin_y, page_height),
        )
      }
      CffCurve(x1, y1, x2, y2, x, y) => {
        output.write_string(" C ")
        output.write_string(
          pdf_cff_svg_point(matrix, x1, y1, origin_x, origin_y, page_height),
        )
        output.write_char(' ')
        output.write_string(
          pdf_cff_svg_point(matrix, x2, y2, origin_x, origin_y, page_height),
        )
        output.write_char(' ')
        output.write_string(
          pdf_cff_svg_point(matrix, x, y, origin_x, origin_y, page_height),
        )
      }
      CffClose => output.write_string(" Z")
    }
  }
  output.to_string()
}

///|
fn pdf_cff_glyph_geometry(
  font : PdfCffFont,
  glyph_id : Int,
) -> (Array[PdfCffPathCommand], @geometry.TransformMatrix)? {
  let commands = match font.outlines.get(glyph_id) {
    Some(Some(value)) => value
    Some(None) => return None
    None => {
      let code = match font.charstrings.get(glyph_id) {
        Some(value) => value
        None => return None
      }
      let state = Ref(pdf_cff_new_state(Ref(100000)))
      if !pdf_cff_run_charstring(font, glyph_id, code, state, [], 0) {
        font.outlines[glyph_id] = None
        return None
      }
      font.outlines[glyph_id] = Some(state.val.commands)
      state.val.commands
    }
  }
  if commands.is_empty() {
    return Some((commands, { a: 1.0, b: 0.0, c: 0.0, d: 1.0, e: 0.0, f: 0.0, }))
  }
  let font_matrix = if font.cid {
    match font.fd_select.get(glyph_id) {
      Some(fd) =>
        match font.fd_font_matrices.get(fd) {
          Some(matrix) => matrix
          None => return None
        }
      None => return None
    }
  } else {
    font.font_matrix
  }
  Some((commands, font_matrix))
}

///|
fn pdf_cff_outline_path(
  font : PdfCffFont,
  glyph_id : Int,
  glyph_matrix : @geometry.TransformMatrix,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
) -> String? {
  let (commands, font_matrix) = match pdf_cff_glyph_geometry(font, glyph_id) {
    Some(value) => value
    None => return None
  }
  if commands.is_empty() {
    return Some("")
  }
  let matrix = @geometry.transform_matrix_compose(glyph_matrix, font_matrix)
  for value in [matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f] {
    if value.is_inf() || value.is_nan() {
      return None
    }
  }
  let path = pdf_cff_svg_path(
    commands[:],
    matrix,
    origin_x,
    origin_y,
    page_height,
  )
  if path == "" {
    None
  } else {
    Some(path)
  }
}

///|
fn pdf_cff_paint_path(
  path : String,
  rendering_mode : Int,
  fill_color : String,
  stroke_color : String,
  fill_alpha : Double,
  stroke_alpha : Double,
) -> String {
  let fill = if pdf_text_mode_fills(rendering_mode) {
    fill_color
  } else {
    "none"
  }
  let stroke = if pdf_text_mode_strokes(rendering_mode) {
    stroke_color
  } else {
    "none"
  }
  let stroke_width = if stroke == "none" { 0.0 } else { 1.0 }
  "<path d=\"" +
  pdf_escape_xml(path) +
  "\" fill=\"" +
  pdf_escape_xml(fill) +
  "\" stroke=\"" +
  pdf_escape_xml(stroke) +
  "\" stroke-width=\"" +
  stroke_width.to_string() +
  "\" fill-opacity=\"" +
  fill_alpha.to_string() +
  "\" stroke-opacity=\"" +
  stroke_alpha.to_string() +
  "\" data-pdf-font-outline=\"cff\"/>"
}

///|
/// Resolve the page-space geometry independently of painting and clipping.
fn pdf_cff_geometry_of_pdf_glyph(
  document : @pdflite.PdfDocument,
  pdf_font : @pdflite.PdfFont,
  fonts : Map[Int, PdfCffFont?],
  charcode : Int,
) -> (Array[PdfCffPathCommand], @geometry.TransformMatrix)? {
  let number = match pdf_font.embedded_fontfile_number() {
    Some(value) => value
    None => return None
  }
  let font = match fonts.get(number) {
    Some(Some(value)) => value
    Some(None) => return None
    None => {
      let parsed = try {
        let bytes = pdf_decode_font_stream_with_recovery(
          document,
          @syntax.PdfIndirect(number),
        ).stream_bytes()
        pdf_cff_parse_font(bytes)
      } catch {
        _ => None
      }
      fonts[number] = parsed
      match parsed {
        Some(value) => value
        None => return None
      }
    }
  }
  let glyph_id = match
    pdf_cff_glyph_for_pdf_charcode(document, font, pdf_font, charcode) {
    Some(value) => value
    None => return None
  }
  pdf_cff_glyph_geometry(font, glyph_id)
}

///|
fn pdf_cff_path_of_pdf_glyph(
  document : @pdflite.PdfDocument,
  pdf_font : @pdflite.PdfFont,
  fonts : Map[Int, PdfCffFont?],
  charcode : Int,
  glyph_matrix : @geometry.TransformMatrix?,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
) -> String? {
  let glyph_matrix = match glyph_matrix {
    Some(value) => value
    None => return None
  }
  let (commands, font_matrix) = match
    pdf_cff_geometry_of_pdf_glyph(document, pdf_font, fonts, charcode) {
    Some(value) => value
    None => return None
  }
  if commands.is_empty() {
    return Some("")
  }
  let matrix = @geometry.transform_matrix_compose(glyph_matrix, font_matrix)
  guard [matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f].all(value => {
    !value.is_nan() && !value.is_inf()
  }) else {
    return None
  }
  let path = pdf_cff_svg_path(
    commands[:],
    matrix,
    origin_x,
    origin_y,
    page_height,
  )
  if path == "" {
    None
  } else {
    Some(path)
  }
}

///|
/// Render one embedded raw CFF glyph as an SVG path.
fn pdf_cff_outline_of_pdf_glyph(
  document : @pdflite.PdfDocument,
  pdf_font : @pdflite.PdfFont,
  fonts : Map[Int, PdfCffFont?],
  charcode : Int,
  glyph_matrix : @geometry.TransformMatrix?,
  rendering_mode : Int,
  fill_color : String,
  stroke_color : String,
  fill_alpha : Double,
  stroke_alpha : Double,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
) -> String? {
  match
    pdf_cff_path_of_pdf_glyph(
      document, pdf_font, fonts, charcode, glyph_matrix, origin_x, origin_y, page_height,
    ) {
    Some("") => Some("")
    Some(path) =>
      Some(
        pdf_cff_paint_path(
          path, rendering_mode, fill_color, stroke_color, fill_alpha, stroke_alpha,
        ),
      )
    None => None
  }
}

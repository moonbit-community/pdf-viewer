///|
/// Raw Type 1 font data used to construct outlines for embedded PDF fonts.
/// Single-FD CID-keyed programs are normalized into the same charstring model;
/// more complex FDArray/CMap cases remain on the normal text fallback path.
priv struct PdfType1Font {
  font_matrix : @geometry.TransformMatrix
  charstrings : Map[String, Bytes]
  subrs : Array[Bytes?]
  builtin_encoding : Map[Int, String]
  outlines : Map[String, Array[PdfCffPathCommand]?]
}

///|
fn pdf_type1_parse_font(data : Bytes) -> PdfType1Font? raise @core.PdfError {
  let source = data[:]
  if pdf_type1_is_cid_keyed_source(source) {
    match pdf_type1_parse_cid_font(data) {
      Some(font) => return Some(font)
      None => ()
    }
  }
  let (header, eexec) = match pdf_type1_pfb_parts(source) {
    Some((header, encrypted)) => (header, encrypted)
    None => {
      let marker = match pdf_type1_find(source, "eexec", 0) {
        Some(value) => value
        None => return None
      }
      let encrypted = match pdf_type1_eexec_bytes(source, marker + 5) {
        Some(value) => value
        None => return None
      }
      let header_data : Array[Int] = []
      for byte in source[:marker] {
        header_data.push(byte.to_int())
      }
      let header = @core.pdf_bytes_of_int_array(header_data)
      (header, encrypted)
    }
  }
  let (font_matrix, builtin_encoding) = pdf_type1_header_properties(header[:])
  let decoded = match pdf_type1_decrypt(eexec[:], 55665, 4) {
    Some(value) => value
    None => return None
  }
  pdf_type1_parse_program(decoded[:], font_matrix, builtin_encoding)
}

///|
fn pdf_type1_glyph_geometry(
  font : PdfType1Font,
  glyph_name : String,
) -> (Array[PdfCffPathCommand], @geometry.TransformMatrix)? {
  let commands = match font.outlines.get(glyph_name) {
    Some(Some(value)) => value
    Some(None) => return None
    None => {
      let state = Ref(pdf_cff_new_state(Ref(100000)))
      if !pdf_type1_run_glyph(font, glyph_name, state, [], 0) {
        font.outlines[glyph_name] = None
        return None
      }
      font.outlines[glyph_name] = Some(state.val.commands)
      state.val.commands
    }
  }
  Some((commands, font.font_matrix))
}

///|
fn pdf_type1_paint_path(
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
  "\" data-pdf-font-outline=\"type1\"/>"
}

///|
fn pdf_type1_geometry_of_pdf_glyph(
  document : @pdflite.PdfDocument,
  pdf_font : @pdflite.PdfFont,
  fonts : Map[Int, PdfType1Font?],
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
        pdf_type1_parse_font(bytes)
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
  let glyph_name = match
    pdf_type1_glyph_name(document, font, pdf_font, charcode) {
    Some(value) => value
    None => return None
  }
  pdf_type1_glyph_geometry(font, glyph_name)
}

///|
fn pdf_type1_path_of_pdf_glyph(
  document : @pdflite.PdfDocument,
  pdf_font : @pdflite.PdfFont,
  fonts : Map[Int, PdfType1Font?],
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
    pdf_type1_geometry_of_pdf_glyph(document, pdf_font, fonts, charcode) {
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
fn pdf_type1_outline_of_pdf_glyph(
  document : @pdflite.PdfDocument,
  pdf_font : @pdflite.PdfFont,
  fonts : Map[Int, PdfType1Font?],
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
    pdf_type1_path_of_pdf_glyph(
      document, pdf_font, fonts, charcode, glyph_matrix, origin_x, origin_y, page_height,
    ) {
    Some("") => Some("")
    Some(path) =>
      Some(
        pdf_type1_paint_path(
          path, rendering_mode, fill_color, stroke_color, fill_alpha, stroke_alpha,
        ),
      )
    None => None
  }
}

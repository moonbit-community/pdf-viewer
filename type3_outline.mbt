///|
fn pdf_type3_page_matrix(
  quad : PdfQuad,
  bbox : @geometry.PdfRectangle,
) -> @geometry.TransformMatrix {
  let width = bbox.max_x - bbox.min_x
  let height = bbox.max_y - bbox.min_y
  if width == 0.0 || height == 0.0 {
    @geometry.transform_identity_matrix
  } else {
    let x_vector = {
      x: (quad.p2.x - quad.p1.x) / width,
      y: (quad.p2.y - quad.p1.y) / width,
    }
    let y_vector = {
      x: (quad.p1.x - quad.p0.x) / height,
      y: (quad.p1.y - quad.p0.y) / height,
    }
    {
      a: x_vector.x,
      b: x_vector.y,
      c: y_vector.x,
      d: y_vector.y,
      e: quad.p0.x - x_vector.x * bbox.min_x - y_vector.x * bbox.min_y,
      f: quad.p0.y - x_vector.y * bbox.min_x - y_vector.y * bbox.min_y,
    }
  }
}

///|
fn pdf_type3_paint_type(
  document : @pdflite.PdfDocument,
  font : @syntax.PdfObject,
) -> Int {
  match document.lookup_direct(pdf_name_key("/PaintType"), font) {
    Some(@syntax.PdfInteger(value)) => value
    Some(@syntax.PdfReal(value)) => value.to_int()
    _ => 2
  }
}

///|
fn pdf_type3_outline_of_glyph(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  font_name : String,
  charcode : Int,
  quad : PdfQuad,
  rendering_mode : Int,
  fill_color : String,
  stroke_color : String,
  fill_alpha : Double,
  stroke_alpha : Double,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
) -> String? raise @core.PdfError {
  match document.lookup_direct(pdf_name_key("/Font"), resources) {
    None => None
    Some(fonts) =>
      match document.lookup_direct(pdf_name_key(font_name), fonts) {
        None => None
        Some(font_object) =>
          match pdf_read_font_for_viewer(document, font_object) {
            @pdflite.PdfFontSimple(simple) =>
              match simple.fonttype {
                @pdflite.PdfSimpleFontType::PdfType3(data) => {
                  let glyph_name = for (code, name) in simple.encoding.table() {
                    if code == charcode {
                      break Some(name)
                    }
                  } nobreak {
                    None
                  }
                  match glyph_name {
                    None => None
                    Some(glyph_name) => {
                      let charproc = for (name, object) in data.charprocs {
                        if name == glyph_name {
                          break Some(object)
                        }
                      } nobreak {
                        None
                      }
                      match charproc {
                        None => None
                        Some(charproc) => {
                          let ops = document.parse_content_ops_with_resources(
                            data.resources,
                            [charproc],
                          )
                          let initial = @pdflite.pdf_content_initial_operator_state(
                            data.fontbbox.min_x,
                            data.fontbbox.min_y,
                            data.fontbbox.max_x,
                            data.fontbbox.max_y,
                          )
                          let entries = pdf_collected_entries_of_ops(
                            document,
                            initial,
                            data.resources,
                            ops,
                            initial.clipping_path,
                            None,
                            [],
                            false,
                            false,
                          )
                          let mapping = pdf_type3_page_matrix(
                            quad,
                            data.fontbbox,
                          )
                          let paint_type = pdf_type3_paint_type(
                            document, font_object,
                          )
                          let output = StringBuilder()
                          for collected in entries {
                            match collected.entry.object {
                              @pdflite.PdfContentPathObject(drawn) => {
                                let path_state = match collected.entry.state {
                                  @pdflite.PdfContentStatePath(value) =>
                                    Some(value)
                                  _ => None
                                }
                                let combined = @geometry.transform_matrix_compose(
                                  mapping,
                                  collected.state.ctm,
                                )
                                let path = drawn.path.transform(combined)
                                let d = pdf_svg_path_of_shape_direct(
                                  path, origin_x, origin_y, page_height,
                                )
                                if d != "" {
                                  let path_fill = if drawn.filled &&
                                    pdf_text_mode_fills(rendering_mode) {
                                    if paint_type == 1 {
                                      pdf_colour_hex_for_paint_in_space(
                                        match path_state {
                                          Some(value) =>
                                            value.colourspace_non_stroke
                                          None => @pdflite.PdfDeviceGray
                                        },
                                        match path_state {
                                          Some(value) => value.colour_non_stroke
                                          None =>
                                            @pdflite.PdfContentColourFloats([
                                              0.0,
                                            ])
                                        },
                                        collected.fill_color_explicit,
                                        document=Some(document),
                                      )
                                    } else {
                                      fill_color
                                    }
                                  } else {
                                    "none"
                                  }
                                  let path_stroke = if drawn.stroked &&
                                    pdf_text_mode_strokes(rendering_mode) {
                                    if paint_type == 1 {
                                      pdf_colour_hex_for_paint_in_space(
                                        match path_state {
                                          Some(value) =>
                                            value.colourspace_stroke
                                          None => @pdflite.PdfDeviceGray
                                        },
                                        match path_state {
                                          Some(value) => value.colour_stroke
                                          None =>
                                            @pdflite.PdfContentColourFloats([
                                              0.0,
                                            ])
                                        },
                                        collected.stroke_color_explicit,
                                        document=Some(document),
                                      )
                                    } else {
                                      stroke_color
                                    }
                                  } else {
                                    "none"
                                  }
                                  let line_width = match path_state {
                                    Some(value) =>
                                      value.line_width *
                                      pdf_ctm_stroke_scale(combined)
                                    None => 1.0
                                  }
                                  let dash = match path_state {
                                    Some(value) if value.dash_pattern.array.length() >
                                      0 =>
                                      " stroke-dasharray=\"" +
                                      pdf_svg_dash_array(
                                        [
                                          for dash in value.dash_pattern.array => {
                                            dash *
                                            pdf_ctm_stroke_scale(combined)
                                          }
                                        ],
                                        1.0,
                                      ) +
                                      "\" stroke-dashoffset=\"" +
                                      (value.dash_pattern.phase *
                                      pdf_ctm_stroke_scale(combined)).to_string() +
                                      "\""
                                    _ => ""
                                  }
                                  output.write_string(
                                    "<path d=\"" +
                                    pdf_escape_xml(d) +
                                    "\" fill=\"" +
                                    path_fill +
                                    "\" stroke=\"" +
                                    path_stroke +
                                    "\" stroke-width=\"" +
                                    line_width.to_string() +
                                    "\" fill-opacity=\"" +
                                    fill_alpha.to_string() +
                                    "\" stroke-opacity=\"" +
                                    stroke_alpha.to_string() +
                                    "\"" +
                                    dash +
                                    " data-pdf-type3=\"true\"/>",
                                  )
                                }
                              }
                              _ => ()
                            }
                          }
                          let value = output.to_string()
                          if value == "" {
                            None
                          } else {
                            Some(value)
                          }
                        }
                      }
                    }
                  }
                }
                _ => None
              }
            _ => None
          }
      }
  }
}

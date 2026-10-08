///|
/// Resolve a PDF `/Pattern` resource and lower a simple coloured tiling
/// pattern to an SVG pattern cell. `pdflite` currently exposes tiling patterns
/// as a placeholder, but its content parser can still walk the pattern stream;
/// keeping this adapter here lets the viewer render the common path-only case
/// without changing pdflite's API.
fn pdf_pattern_resource_of(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : String,
) -> PdfPatternResource? {
  let patterns_name = pdf_image_name("/Pattern")
  let pattern_name = pdf_image_name(name)
  match document.lookup_direct(patterns_name, resources) {
    Some(patterns) =>
      match document.lookup_direct(pattern_name, patterns) {
        Some(pattern) =>
          pdf_pattern_resource_of_object(document, resources, name, pattern)
        None => None
      }
    None => None
  }
}

///|
fn pdf_pattern_resource_of_object(
  document : @pdflite.PdfDocument,
  page_resources : @syntax.PdfObject,
  name : String,
  pattern : @syntax.PdfObject,
) -> PdfPatternResource? {
  match document.lookup_direct(pdf_image_name("/PatternType"), pattern) {
    Some(@syntax.PdfInteger(1)) => {
      let bbox = match
        document.lookup_direct(pdf_image_name("/BBox"), pattern) {
        Some(value) =>
          try Some(document.parse_rectangle(value)) catch {
            _ => None
          } noraise {
            value => value
          }
        None => None
      }
      let bbox = match bbox {
        Some(value) => value
        None => return None
      }
      let x_step = pdf_pattern_number_or(
        document,
        pattern,
        "/XStep",
        bbox.max_x - bbox.min_x,
      )
      let y_step = pdf_pattern_number_or(
        document,
        pattern,
        "/YStep",
        bbox.max_y - bbox.min_y,
      )
      if x_step <= 0.0 || y_step <= 0.0 {
        return None
      }
      let pattern_resources = match
        document.lookup_direct(pdf_image_name("/Resources"), pattern) {
        Some(value) => value
        None => page_resources
      }
      let ops = document.parse_content_ops_with_resources(pattern_resources, [
        pattern,
      ]) catch {
        _ => return None
      }
      let rectangle : @geometry.PdfRectangle = {
        min_x: bbox.min_x,
        min_y: bbox.min_y,
        max_x: bbox.max_x,
        max_y: bbox.max_y,
      }
      let entries = @pdflite.pdf_content_entries_of_ops_recursive(
        document, rectangle, pattern_resources, ops,
      ) catch {
        _ => return None
      }
      let tile_svg = pdf_pattern_tile_svg(
        entries,
        bbox.min_x,
        bbox.min_y,
        bbox.max_y - bbox.min_y,
      )
      Some({
        name,
        bbox: {
          min_x: bbox.min_x,
          min_y: bbox.min_y,
          max_x: bbox.max_x,
          max_y: bbox.max_y,
        },
        x_step,
        y_step,
        tile_svg,
      })
    }
    _ => None
  }
}

///|
fn pdf_pattern_number_or(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  key : String,
  fallback : Double,
) -> Double {
  match document.lookup_direct(pdf_image_name(key), object) {
    Some(value) => document.get_number(value) catch { _ => fallback }
    None => fallback
  }
}

///|
fn pdf_pattern_tile_svg(
  entries : ArrayView[@pdflite.PdfContentJsonEntry],
  bbox_min_x : Double,
  bbox_min_y : Double,
  bbox_height : Double,
) -> String {
  let output = StringBuilder()
  for entry in entries {
    match entry.object {
      @pdflite.PdfContentPathObject(drawn) => {
        let bounds = pdf_bounds_of_quad(entry.bounding_box)
        let path = pdf_svg_path_of_shape(
          drawn.path,
          bbox_min_x,
          bbox_min_y,
          bbox_height,
          bounds,
        )
        if path != "" {
          let (fill, stroke, line_width, line_cap, line_join, dash) = match
            entry.state {
            @pdflite.PdfContentStatePath(state) =>
              (
                if drawn.filled {
                  pdf_colour_hex(state.colour_non_stroke)
                } else {
                  "none"
                },
                if drawn.stroked {
                  pdf_colour_hex(state.colour_stroke)
                } else {
                  "none"
                },
                state.line_width,
                state.line_cap,
                state.line_join,
                state.dash_pattern.array,
              )
            _ => ("none", "none", 1.0, 0, 0, [])
          }
          let dash_attribute = if dash.length() == 0 {
            ""
          } else {
            " stroke-dasharray=\"" + pdf_svg_dash_array(dash, 1.0) + "\""
          }
          output.write_string(
            "<path d=\"" +
            path +
            "\" fill=\"" +
            fill +
            "\" stroke=\"" +
            stroke +
            "\" stroke-width=\"" +
            line_width.to_string() +
            "\" stroke-linecap=\"" +
            pdf_svg_line_cap(line_cap) +
            "\" stroke-linejoin=\"" +
            pdf_svg_line_join(line_join) +
            "\"" +
            dash_attribute +
            "/>",
          )
        }
      }
      _ => ()
    }
  }
  output.to_string()
}

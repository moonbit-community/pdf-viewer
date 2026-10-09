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
      let matrix = pdf_pattern_matrix_or_identity(document, pattern)
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
        document,
        pattern_resources,
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
        matrix,
        tile_svg,
        shading: None,
      })
    }
    Some(@syntax.PdfInteger(2)) => {
      let shading_object = match
        document.lookup_direct(pdf_image_name("/Shading"), pattern) {
        Some(value) => value
        None => return None
      }
      let shading = try
        Some(pdf_shading_resource_of_object(document, name, shading_object))
      catch {
        _ => None
      } noraise {
        value => value
      }
      match shading {
        Some(value) => {
          let matrix = pdf_pattern_matrix_or_identity(document, pattern)
          Some({
            name,
            bbox: pdf_mesh_bounds_or_unit(value.mesh),
            x_step: pdf_mesh_extent_or_unit(value.mesh, true),
            y_step: pdf_mesh_extent_or_unit(value.mesh, false),
            // Keep the Pattern dictionary's matrix on the resource.  The
            // paint-site CTM is composed into it below before the path is
            // lowered as a clipped mesh.
            matrix,
            tile_svg: "",
            shading: Some(value),
          })
        }
        None => None
      }
    }
    _ => None
  }
}

///|
fn pdf_mesh_bounds_or_unit(mesh : ArrayView[PdfMeshTriangle]) -> PdfBounds {
  if mesh.length() == 0 {
    { min_x: 0.0, min_y: 0.0, max_x: 1.0, max_y: 1.0, }
  } else {
    let first = mesh[0].p0
    let mut min_x = first.x
    let mut min_y = first.y
    let mut max_x = first.x
    let mut max_y = first.y
    for triangle in mesh {
      for point in [triangle.p0, triangle.p1, triangle.p2] {
        min_x = min_x.min(point.x)
        min_y = min_y.min(point.y)
        max_x = max_x.max(point.x)
        max_y = max_y.max(point.y)
      }
    }
    { min_x, min_y, max_x, max_y, }
  }
}

///|
fn pdf_mesh_extent_or_unit(
  mesh : ArrayView[PdfMeshTriangle],
  horizontal : Bool,
) -> Double {
  let bounds = pdf_mesh_bounds_or_unit(mesh)
  let value = if horizontal {
    bounds.max_x - bounds.min_x
  } else {
    bounds.max_y - bounds.min_y
  }
  if value > 0.0 {
    value
  } else {
    1.0
  }
}

///|
fn pdf_pattern_matrix_or_identity(
  document : @pdflite.PdfDocument,
  pattern : @syntax.PdfObject,
) -> Array[Double] {
  try document.parse_matrix(pdf_image_name("/Matrix"), pattern) catch {
    _ => [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
  } noraise {
    matrix => [matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f]
  }
}

///|
/// Compose the pattern's own matrix with the CTM active at its paint site.
fn pdf_pattern_resource_with_ctm(
  pattern : PdfPatternResource,
  ctm : @geometry.TransformMatrix,
) -> PdfPatternResource {
  let pattern_matrix = if pattern.matrix.length() >= 6 {
    pattern.matrix
  } else {
    [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
  }
  // A PatternType 2 shading is already painted in page user space. Its
  // `/Matrix` is the pattern-to-user transform and must stay independent of
  // the CTM that was used to construct the path being clipped. This mirrors
  // pdf.js' `handleColorN` path: the pattern matrix is retained on the
  // shading IR, while the path geometry carries the paint-site CTM.
  match pattern.shading {
    Some(value) => {
      let shading = { ..value, matrix: pattern_matrix, }
      { ..pattern, matrix: pattern_matrix, shading: Some(shading), }
    }
    None => {
      let a = ctm.a * pattern_matrix[0] + ctm.c * pattern_matrix[1]
      let b = ctm.b * pattern_matrix[0] + ctm.d * pattern_matrix[1]
      let c = ctm.a * pattern_matrix[2] + ctm.c * pattern_matrix[3]
      let d = ctm.b * pattern_matrix[2] + ctm.d * pattern_matrix[3]
      let e = ctm.a * pattern_matrix[4] + ctm.c * pattern_matrix[5] + ctm.e
      let f = ctm.b * pattern_matrix[4] + ctm.d * pattern_matrix[5] + ctm.f
      { ..pattern, matrix: [a, b, c, d, e, f], shading: None, }
    }
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
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
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
      @pdflite.PdfContentImageObject(name) =>
        match pdf_image_resource_of_resources(document, resources, name) {
          Some(resource) =>
            match resource.data_uri {
              Some(data_uri) => {
                let quad = pdf_quad_of_box(entry.bounding_box)
                let transform = pdf_svg_pattern_image_transform(
                  quad, bbox_min_x, bbox_min_y, bbox_height,
                )
                output.write_string(
                  "<image data-pdf-name=\"" +
                  pdf_escape_xml(name) +
                  "\" x=\"0\" y=\"0\" width=\"1\" height=\"1\" transform=\"" +
                  transform +
                  "\" preserveAspectRatio=\"none\" href=\"" +
                  data_uri +
                  "\"/>",
                )
              }
              None => ()
            }
          None => ()
        }
      _ => ()
    }
  }
  output.to_string()
}

///|
/// Map a content-entry image quad into the pattern cell's top-left SVG
/// coordinate system. Pattern entries are already in pattern user space, so
/// only the pattern bbox origin and PDF y-axis need to be applied here.
fn pdf_svg_pattern_image_transform(
  quad : PdfQuad,
  bbox_min_x : Double,
  bbox_min_y : Double,
  bbox_height : Double,
) -> String {
  let top_left = {
    x: quad.p1.x - bbox_min_x,
    y: bbox_min_y + bbox_height - quad.p1.y,
  }
  let top_right = {
    x: quad.p2.x - bbox_min_x,
    y: bbox_min_y + bbox_height - quad.p2.y,
  }
  let bottom_left = {
    x: quad.p0.x - bbox_min_x,
    y: bbox_min_y + bbox_height - quad.p0.y,
  }
  "matrix(" +
  (top_right.x - top_left.x).to_string() +
  " " +
  (top_right.y - top_left.y).to_string() +
  " " +
  (bottom_left.x - top_left.x).to_string() +
  " " +
  (bottom_left.y - top_left.y).to_string() +
  " " +
  top_left.x.to_string() +
  " " +
  top_left.y.to_string() +
  ")"
}

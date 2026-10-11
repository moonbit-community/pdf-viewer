///|
priv struct PdfPatternInitialState {
  state : @pdflite.PdfContentOperatorState
  fill_explicit : Bool
  stroke_explicit : Bool
}

///|
fn pdf_pattern_resource_of_paint(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  space : @pdflite.PdfColourSpace,
  colour : @pdflite.PdfContentColourValues,
  ctm : @geometry.TransformMatrix,
  context? : PdfResourceBuildContext = pdf_resource_build_context(),
  initial_state? : PdfPatternInitialState? = None,
  retain_ink_samples? : Bool = false,
  convert_ink_to_device_cmyk? : Bool = true,
) -> PdfPatternResource? {
  guard space
    is (@pdflite.PdfPattern | @pdflite.PdfPatternWithBaseColourSpace(_)) &&
    colour is @pdflite.PdfContentColourNamed(name, values) else {
    return None
  }
  match
    pdf_pattern_resource_of(
      document,
      resources,
      name,
      Some(values),
      space,
      context~,
      initial_state~,
      retain_ink_samples~,
      convert_ink_to_device_cmyk~,
    ) {
    Some(resource) => Some(pdf_pattern_resource_with_ctm(resource, ctm))
    None => None
  }
}

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
  base_colour : Array[Double]?,
  base_colour_space : @pdflite.PdfColourSpace,
  context? : PdfResourceBuildContext = pdf_resource_build_context(),
  initial_state? : PdfPatternInitialState? = None,
  retain_ink_samples? : Bool = false,
  convert_ink_to_device_cmyk? : Bool = true,
) -> PdfPatternResource? {
  let patterns_name = pdf_image_name("/Pattern")
  let pattern_name = pdf_image_name(name)
  match document.lookup_direct(patterns_name, resources) {
    Some(patterns) =>
      match document.lookup_direct(pattern_name, patterns) {
        Some(pattern) =>
          pdf_pattern_resource_of_object(
            document,
            resources,
            name,
            pattern,
            base_colour,
            base_colour_space,
            context~,
            initial_state~,
            retain_ink_samples~,
            convert_ink_to_device_cmyk~,
          )
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
  base_colour : Array[Double]?,
  base_colour_space : @pdflite.PdfColourSpace,
  context? : PdfResourceBuildContext = pdf_resource_build_context(),
  initial_state? : PdfPatternInitialState? = None,
  retain_ink_samples? : Bool = false,
  convert_ink_to_device_cmyk? : Bool = true,
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
      if x_step == 0.0 ||
        y_step == 0.0 ||
        bbox.max_x <= bbox.min_x ||
        bbox.max_y <= bbox.min_y ||
        context.pattern_depth >= 16 ||
        context.pattern_count >= 256 {
        return None
      }
      let matrix = pdf_pattern_matrix_or_identity(document, pattern)
      let paint_type = pdf_pattern_number_or(
        document, pattern, "/PaintType", 1.0,
      )
      let uncolored_colour = if paint_type == 2.0 {
        Some(
          pdf_colour_hex_in_space(
            base_colour_space,
            @pdflite.PdfContentColourFloats(base_colour.unwrap_or([])),
            document=Some(document),
          ),
        )
      } else {
        None
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
      let initial = @pdflite.pdf_content_initial_operator_state(
        rectangle.min_x,
        rectangle.min_y,
        rectangle.max_x,
        rectangle.max_y,
      )
      let initial = match initial_state {
        Some(base) =>
          {
            ..base.state,
            ctm: initial.ctm,
            clipping_path: initial.clipping_path,
            partial_path: initial.partial_path,
            path: initial.path,
            text_state: { ..base.state.text_state, font_cache: [], },
            state_stack: [],
            alpha_constant_stroke: 1.0,
            alpha_constant_non_stroke: 1.0,
            alpha_source: false,
            blend_mode: @syntax.PdfNameObject(pdf_name_key("/Normal")),
            soft_mask: @syntax.PdfNull,
          }
        None => initial
      }
      let uncolored_source = pdf_colour_source(
        base_colour_space,
        @pdflite.PdfContentColourFloats(base_colour.unwrap_or([])),
        document=Some(document),
        resource_context=Some(context),
      )
      let initial = if paint_type == 2.0 {
        let base_space = match base_colour_space {
          @pdflite.PdfPatternWithBaseColourSpace(space) => space
          _ => base_colour_space
        }
        let values = @pdflite.PdfContentColourFloats(base_colour.unwrap_or([]))
        {
          ..initial,
          path_state: {
            ..initial.path_state,
            colourspace_non_stroke: base_space,
            colourspace_stroke: base_space,
            colour_non_stroke: values,
            colour_stroke: values,
          },
        }
      } else {
        initial
      }
      let entries = pdf_collected_entries_of_ops(
        document,
        initial,
        pattern_resources,
        ops,
        initial.clipping_path,
        None,
        [],
        paint_type == 2.0 || initial_state is Some({ fill_explicit: true, .. }),
        paint_type == 2.0 ||
        initial_state is Some({ stroke_explicit: true, .. }),
        resource_context=context,
      ) catch {
        _ => return None
      }
      context.pattern_depth += 1
      context.pattern_count += 1
      let scope : PdfAppearanceFontScope = {
        id: "pattern-" + context.pattern_count.to_string(),
        fonts: [],
        sources: [],
      }
      let lowered = Some(
        pdf_items_of_collected(
          document,
          entries[:],
          bbox.min_x,
          bbox.min_y,
          bbox.max_x - bbox.min_x,
          bbox.max_y - bbox.min_y,
          appearance_fonts=scope,
          resource_context=context,
          retain_ink_samples~,
          convert_ink_to_device_cmyk~,
        ),
      ) catch {
        _ => None
      }
      context.pattern_depth -= 1
      let items = match lowered {
        Some(value) => value
        None => return None
      }
      let items = match uncolored_colour {
        Some(color) =>
          items.map(item => {
            match item {
              Path(value) =>
                Path({
                  ..value,
                  fill_color: color,
                  stroke_color: color,
                  fill_source: uncolored_source,
                  stroke_source: uncolored_source,
                })
              Text(value) =>
                Text({
                  ..value,
                  fill_color: color,
                  stroke_color: color,
                  fill_source: uncolored_source,
                  stroke_source: uncolored_source,
                })
              _ => item
            }
          })
        None => items
      }
      let tile_page : PdfPageModel = {
        number: 1,
        blend_space: "DeviceRGB",
        blend_profile_id: None,
        blend_calibration: None,
        icc_profiles: [],
        origin_x: bbox.min_x,
        origin_y: bbox.min_y,
        width: bbox.max_x - bbox.min_x,
        height: bbox.max_y - bbox.min_y,
        user_unit: 1.0,
        rotation: 0,
        fonts: scope.fonts,
        items,
        annotations: [],
        text: "",
      }
      let output = StringBuilder()
      pdf_svg_fonts(output, tile_page)
      pdf_svg_render_items(output, tile_page, tile_page.items[:], 1.0, 0)
      let tile_svg = output.to_string()
      // Keep the image sampling compatibility stream for simple cells. Rich
      // cells use the complete page model, including text and group boundaries.
      let simple = tile_page.items.all(item => {
        match item {
          Path(value) =>
            value.group_path.is_empty() &&
            value.soft_mask is None &&
            value.clips.is_empty()
          Image(value) =>
            value.group_path.is_empty() &&
            value.soft_mask is None &&
            value.clips.is_empty()
          _ => false
        }
      })
      let tile_parts = if simple {
        let (_, parts) = pdf_pattern_tile_svg(
          document,
          entries,
          bbox.min_x,
          bbox.min_y,
          bbox.max_y - bbox.min_y,
          uncolored_colour,
        )
        parts
      } else {
        []
      }
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
        tile_page: Some(tile_page),
        tile_parts,
        shading: None,
      })
    }
    Some(@syntax.PdfInteger(2)) => {
      let shading_object = match
        document.lookup_direct(pdf_image_name("/Shading"), pattern) {
        Some(value) => value
        None => return None
      }
      let initial = match initial_state {
        Some(base) => base.state
        None => @pdflite.pdf_content_initial_operator_state(0.0, 0.0, 1.0, 1.0)
      }
      let initial = {
        ..initial,
        ctm: @geometry.transform_identity_matrix,
        alpha_constant_stroke: 1.0,
        alpha_constant_non_stroke: 1.0,
        alpha_source: false,
        blend_mode: @syntax.PdfNameObject(pdf_name_key("/Normal")),
        soft_mask: @syntax.PdfNull,
      }
      let shading_state = match
        document.lookup_direct(pdf_name_key("/ExtGState"), pattern) {
        Some(dictionary) =>
          pdf_shading_pattern_apply_state(document, initial, dictionary)
        None => initial
      }
      let shading = try
        Some(
          pdf_shading_resource_of_object(
            document,
            name,
            shading_object,
            resources=page_resources,
            resource_context=context,
            rendering_intent=shading_state.path_state.rendering_intent,
            black_generation=pdf_colour_device_function(
              Some(document),
              shading_state.black_generation,
            ),
            undercolour_removal=pdf_colour_device_function(
              Some(document),
              shading_state.undercolour_removal,
            ),
          ),
        )
      catch {
        _ => None
      } noraise {
        value => value
      }
      match shading {
        Some(value) => {
          let value = try {
            let state = pdf_shading_pattern_state(
              document, page_resources, pattern, shading_object, initial, shading_state,
              context,
            )
            { ..value, pattern_state: Some(state), }
          } catch {
            error => pdf_shading_error_resource(name, @debug.to_string(error))
          }
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
            tile_page: None,
            tile_parts: [],
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
      let m = pdf_pattern_compose_matrix(ctm, pattern_matrix)
      let pattern_state = value.pattern_state.map(state => {
        ..state,
        soft_mask: state.soft_mask.map(mask => {
          ..mask,
          matrix: pdf_pattern_compose_matrix(
            { a: m[0], b: m[1], c: m[2], d: m[3], e: m[4], f: m[5], },
            mask.matrix,
          ),
        }),
      })
      let shading = { ..value, matrix: m, pattern_state, }
      { ..pattern, matrix: m, shading: Some(shading), }
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
  entries : ArrayView[PdfCollectedEntry],
  bbox_min_x : Double,
  bbox_min_y : Double,
  bbox_height : Double,
  uncolored_colour : String?,
) -> (String, Array[PdfPatternTilePart]) {
  let parts : Array[PdfPatternTilePart] = []
  for collected in entries {
    let output = StringBuilder()
    let entry = collected.entry
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
                if drawn.filled && collected.fill_color_explicit {
                  pdf_colour_hex_in_space(
                    state.colourspace_non_stroke,
                    state.colour_non_stroke,
                    document=Some(document),
                  )
                } else if drawn.filled {
                  "#000000"
                } else {
                  "none"
                },
                if drawn.stroked && collected.stroke_color_explicit {
                  pdf_colour_hex_in_space(
                    state.colourspace_stroke,
                    state.colour_stroke,
                    document=Some(document),
                  )
                } else if drawn.stroked {
                  "#000000"
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
          let fill = if drawn.filled {
            uncolored_colour.unwrap_or(fill)
          } else {
            "none"
          }
          let stroke = if drawn.stroked {
            uncolored_colour.unwrap_or(stroke)
          } else {
            "none"
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
        match
          pdf_image_resource_of_resources(document, collected.resources, name) {
          Some(resource) =>
            match resource.data_uri {
              Some(_) => {
                let quad = pdf_quad_of_box(entry.bounding_box)
                parts.push(PdfPatternTilePart::Image(resource, quad))
              }
              None => ()
            }
          None => ()
        }
      _ => ()
    }
    let fragment = output.to_string()
    if fragment != "" {
      parts.push(PdfPatternTilePart::Svg(fragment))
    }
  }
  (
    pdf_pattern_parts_svg(
      parts[:],
      bbox_min_x,
      bbox_min_y,
      bbox_height,
      [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
      1.0,
    ),
    parts,
  )
}

///|
fn pdf_pattern_parts_svg(
  parts : ArrayView[PdfPatternTilePart],
  bbox_min_x : Double,
  bbox_min_y : Double,
  bbox_height : Double,
  matrix : Array[Double],
  scale : Double,
) -> String {
  let output = StringBuilder()
  for part in parts {
    match part {
      PdfPatternTilePart::Svg(fragment) => output.write_string(fragment)
      PdfPatternTilePart::Image(resource, quad) =>
        if resource.data_uri is Some(data_uri) {
          let transform = pdf_svg_pattern_image_transform(
            quad, bbox_min_x, bbox_min_y, bbox_height,
          )
          let sampled_quad = pdf_pattern_sample_quad(quad, matrix)
          output.write_string(
            "<image data-pdf-name=\"" +
            pdf_escape_xml(resource.name) +
            "\" x=\"0\" y=\"0\" width=\"1\" height=\"1\" transform=\"" +
            transform +
            "\" preserveAspectRatio=\"none\"" +
            pdf_svg_image_sampling(resource, sampled_quad, scale) +
            " href=\"" +
            data_uri +
            "\"/>",
          )
        }
    }
  }
  output.to_string()
}

///|
fn pdf_pattern_sample_quad(quad : PdfQuad, matrix : Array[Double]) -> PdfQuad {
  if matrix.length() < 6 {
    return quad
  }
  let transform = fn(point : PdfPoint) {
    {
      x: matrix[0] * point.x + matrix[2] * point.y + matrix[4],
      y: matrix[1] * point.x + matrix[3] * point.y + matrix[5],
    }
  }
  {
    p0: transform(quad.p0),
    p1: transform(quad.p1),
    p2: transform(quad.p2),
    p3: transform(quad.p3),
  }
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

///|
fn pdf_pattern_compose_matrix(
  ctm : @geometry.TransformMatrix,
  matrix : Array[Double],
) -> Array[Double] {
  [
    ctm.a * matrix[0] + ctm.c * matrix[1],
    ctm.b * matrix[0] + ctm.d * matrix[1],
    ctm.a * matrix[2] + ctm.c * matrix[3],
    ctm.b * matrix[2] + ctm.d * matrix[3],
    ctm.a * matrix[4] + ctm.c * matrix[5] + ctm.e,
    ctm.b * matrix[4] + ctm.d * matrix[5] + ctm.f,
  ]
}

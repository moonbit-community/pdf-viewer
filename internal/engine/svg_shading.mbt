///|
/// Lower a PatternType 2 shading as a clipped mesh.  A PDF shading pattern is
/// defined over the path that selected it; treating it as an endlessly
/// repeated SVG tile changes both the extent and the edge behavior.  Clipping
/// the mesh to the original path preserves that relationship and works in
/// browsers without a custom Canvas renderer.
fn pdf_svg_shading_pattern_path(
  output : StringBuilder,
  page : PdfPageModel,
  path : PdfPathItem,
  shading : PdfShadingResource,
  scale : Double,
) -> Unit {
  if shading.mesh.length() == 0 {
    return
  }
  let clip_id = "pdf-shading-path-" + path.index.to_string()
  let transformed = pdf_transform_svg_path(path.svg_path, page.height, scale)
  pdf_svg_clip_open(output, path.index, path.clip_path)
  output.write_string(
    "<defs><clipPath id=\"" +
    clip_id +
    "\" clipPathUnits=\"userSpaceOnUse\"><path d=\"" +
    transformed +
    "\" clip-rule=\"" +
    (if path.fill_even_odd { "evenodd" } else { "nonzero" }) +
    "\" transform=\"scale(" +
    scale.to_string() +
    ")\"/></clipPath></defs><g clip-path=\"url(#" +
    clip_id +
    ")\" opacity=\"" +
    path.fill_alpha.to_string() +
    "\"><g transform=\"" +
    pdf_svg_shading_transform(page, shading.matrix, scale) +
    "\">",
  )
  pdf_svg_mesh_triangles(output, shading.mesh)
  output.write_string("</g></g>")
  pdf_svg_clip_close(output, path.index, path.clip_path)
}

///|
fn pdf_svg_mesh_triangles(
  output : StringBuilder,
  triangles : ArrayView[PdfMeshTriangle],
) -> Unit {
  let steps = pdf_mesh_subdivision_steps(triangles.length())
  for triangle in triangles {
    pdf_svg_mesh_triangle(output, triangle, steps)
  }
}

///|
/// SVG has no consistently supported mesh-gradient element. Subdivide each
/// source triangle and sample its barycentric colour at each small triangle's
/// centroid. This follows the same linear interpolation as pdf.js' software
/// path and avoids the obvious one-colour facets of the old fallback.
fn pdf_svg_mesh_triangle(
  output : StringBuilder,
  triangle : PdfMeshTriangle,
  steps : Int,
) -> Unit {
  let denominator = steps.to_double()
  for row in 0..<steps {
    for column in 0..<(steps - row) {
      let u0 = column.to_double() / denominator
      let v0 = row.to_double() / denominator
      let u1 = (column + 1).to_double() / denominator
      let v1 = (row + 1).to_double() / denominator
      let a = pdf_mesh_triangle_point(triangle, u0, v0)
      let b = pdf_mesh_triangle_point(triangle, u1, v0)
      let c = pdf_mesh_triangle_point(triangle, u0, v1)
      pdf_svg_mesh_microtriangle(
        output,
        triangle,
        a,
        b,
        c,
        (u0 + u1 + u0) / 3.0,
        (v0 + v0 + v1) / 3.0,
      )
      if column < steps - row - 1 {
        let d = pdf_mesh_triangle_point(triangle, u1, v1)
        pdf_svg_mesh_microtriangle(
          output,
          triangle,
          b,
          d,
          c,
          (u1 + u1 + u0) / 3.0,
          (v0 + v1 + v1) / 3.0,
        )
      }
    }
  }
}

///|
/// Serialize one microtriangle. A very small same-colour stroke closes the
/// subpixel antialiasing seam between adjacent polygons without drawing the
/// heavy outlines used by the old large-triangle fallback.
fn pdf_svg_mesh_microtriangle(
  output : StringBuilder,
  source : PdfMeshTriangle,
  first : PdfPoint,
  second : PdfPoint,
  third : PdfPoint,
  u : Double,
  v : Double,
) -> Unit {
  let color = pdf_mesh_triangle_color_at(source, u, v)
  output.write_string(
    "<polygon points=\"" +
    first.x.to_string() +
    " " +
    first.y.to_string() +
    " " +
    second.x.to_string() +
    " " +
    second.y.to_string() +
    " " +
    third.x.to_string() +
    " " +
    third.y.to_string() +
    "\" fill=\"" +
    color +
    "\" stroke=\"" +
    color +
    "\" stroke-width=\"0.08\" stroke-linejoin=\"round\"/>",
  )
}

///|
fn pdf_svg_pattern_defs(
  output : StringBuilder,
  page : PdfPageModel,
  path : PdfPathItem,
  scale : Double,
) -> Unit {
  for
    (prefix, resource) in [
      ("pdf-pattern-", path.pattern),
      ("pdf-stroke-pattern-", path.stroke_pattern),
    ] {
    if resource is Some(pattern) && pattern.shading is None {
      let id = prefix + path.index.to_string()
      let tile_svg = if pattern.tile_parts.is_empty() {
        pattern.tile_svg
      } else {
        pdf_pattern_parts_svg(
          pattern.tile_parts[:],
          pattern.bbox.min_x,
          pattern.bbox.min_y,
          pattern.bbox.max_y - pattern.bbox.min_y,
          pattern.matrix,
          scale,
        )
      }
      output.write_string(
        "<defs><pattern id=\"" +
        id +
        "\" patternUnits=\"userSpaceOnUse\" patternContentUnits=\"userSpaceOnUse\" x=\"0\" y=\"0\" width=\"" +
        pattern.x_step.to_string() +
        "\" height=\"" +
        pattern.y_step.to_string() +
        "\" patternTransform=\"" +
        (if prefix == "pdf-stroke-pattern-" {
          pdf_svg_stroke_pattern_transform(
            path.stroke,
            pdf_svg_shading_transform(page, pattern.matrix, 1.0),
          )
        } else {
          pdf_svg_shading_transform(page, pattern.matrix, 1.0)
        }) +
        "\">" +
        tile_svg +
        "</pattern></defs>",
      )
    }
  }
}

///|
fn pdf_svg_shading(
  output : StringBuilder,
  page : PdfPageModel,
  item : PdfVisualItem,
  scale : Double,
) -> Unit {
  pdf_svg_soft_mask_defs(output, item.index, page, item.soft_mask, scale)
  pdf_svg_soft_mask_open(output, item.index, item.soft_mask)
  match item.shading {
    Some(shading) if shading.mesh.length() > 0 => {
      pdf_svg_clip_defs(
        output,
        item.index,
        item.clip_path,
        scale,
        clips=item.clips,
      )
      pdf_svg_clip_open(output, item.index, item.clip_path)
      output.write_string(
        "<g data-pdf-kind=\"mesh-shading\" data-pdf-name=\"" +
        pdf_escape_xml(item.name) +
        "\" opacity=\"" +
        item.fill_alpha.to_string() +
        "\" transform=\"" +
        pdf_svg_shading_transform(page, shading.matrix, scale) +
        "\">",
      )
      pdf_svg_mesh_triangles(output, shading.mesh)
      output.write_string("</g>")
      pdf_svg_clip_close(output, item.index, item.clip_path)
    }
    Some(shading) if shading.stops.length() > 0 => {
      let gradient_id = "pdf-shading-" +
        item.index.to_string() +
        "-" +
        item.name.replace(old="/", new="-")
      pdf_svg_clip_defs(
        output,
        item.index,
        item.clip_path,
        scale,
        clips=item.clips,
      )
      pdf_svg_clip_open(output, item.index, item.clip_path)
      output.write_string("<defs>")
      if shading.kind == "axial" && shading.coords.length() >= 4 {
        output.write_string(
          "<linearGradient id=\"" +
          pdf_escape_xml(gradient_id) +
          "\" gradientUnits=\"userSpaceOnUse\" gradientTransform=\"" +
          pdf_svg_shading_transform(page, shading.matrix, scale) +
          "\" x1=\"" +
          shading.coords[0].to_string() +
          "\" y1=\"" +
          shading.coords[1].to_string() +
          "\" x2=\"" +
          shading.coords[2].to_string() +
          "\" y2=\"" +
          shading.coords[3].to_string() +
          "\" spreadMethod=\"pad\">",
        )
        pdf_svg_gradient_stops(output, shading.stops)
        output.write_string("</linearGradient>")
      } else if shading.kind == "radial" && shading.coords.length() >= 6 {
        output.write_string(
          "<radialGradient id=\"" +
          pdf_escape_xml(gradient_id) +
          "\" gradientUnits=\"userSpaceOnUse\" gradientTransform=\"" +
          pdf_svg_shading_transform(page, shading.matrix, scale) +
          "\" cx=\"" +
          shading.coords[3].to_string() +
          "\" cy=\"" +
          shading.coords[4].to_string() +
          "\" r=\"" +
          shading.coords[5].abs().to_string() +
          "\" fx=\"" +
          shading.coords[0].to_string() +
          "\" fy=\"" +
          shading.coords[1].to_string() +
          "\" fr=\"" +
          shading.coords[2].abs().to_string() +
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
        " data-pdf-kind=\"shading\" data-pdf-name=\"" +
        pdf_escape_xml(item.name) +
        "\" x=\"0\" y=\"0\" width=\"" +
        (page.width * scale).to_string() +
        "\" height=\"" +
        (page.height * scale).to_string() +
        "\" fill-opacity=\"" +
        item.fill_alpha.to_string() +
        "\"" +
        pdf_svg_blend_style(item.blend_mode) +
        " fill=\"url(#" +
        pdf_escape_xml(gradient_id) +
        ")\"/>",
      )
      pdf_svg_clip_close(output, item.index, item.clip_path)
    }
    _ => pdf_svg_placeholder(output, page, item, scale, "shading")
  }
  pdf_svg_soft_mask_close(output, item.index, item.soft_mask)
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
fn pdf_svg_shading_transform(
  page : PdfPageModel,
  matrix : ArrayView[Double],
  scale : Double,
) -> String {
  let m = if matrix.length() >= 6 {
    matrix
  } else {
    [1.0, 0.0, 0.0, 1.0, 0.0, 0.0][:]
  }
  "matrix(" +
  (m[0] * scale).to_string() +
  " " +
  (-m[1] * scale).to_string() +
  " " +
  (m[2] * scale).to_string() +
  " " +
  (-m[3] * scale).to_string() +
  " " +
  ((m[4] - page.origin_x) * scale).to_string() +
  " " +
  ((page.origin_y + page.height - m[5]) * scale).to_string() +
  ")"
}

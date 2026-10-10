///|
/// Render an already decoded page, allowing hosts to reuse the page model for
/// zoom, rotation, text selection and repeated paint operations.
///
/// ```mbt check
/// test {
///   let page : @pdf-viewer.PdfPageModel = {
///     number: 1,
///     origin_x: 0.0,
///     origin_y: 0.0,
///     width: 200.0,
///     height: 300.0,
///     user_unit: 1.0,
///     rotation: 0,
///     fonts: [],
///     items: [],
///     annotations: [],
///     text: "",
///   }
///   assert_true(
///     page.render_svg(scale=2.0, rotation=90).contains("viewBox=\"0 0 600 400\""),
///   )
/// }
/// ```
pub fn PdfPageModel::render_svg(
  self : PdfPageModel,
  scale? : Double = 1.0,
  rotation? : Int = self.rotation,
) -> String raise @core.PdfError {
  pdf_render_page_svg(self, scale, rotation)
}

///|
fn pdf_render_page_svg(
  page : PdfPageModel,
  scale : Double,
  rotation : Int,
) -> String raise @core.PdfError {
  let safe_scale = if scale <= 0.0 { 1.0 } else { scale }
  let normalized_rotation = pdf_normalize_rotation_strict(rotation)
  let page = { ..page, rotation: normalized_rotation, }
  let viewport = page.viewport(scale=safe_scale, rotation=normalized_rotation)
  let paint_scale = safe_scale * pdf_safe_user_unit(page.user_unit)
  let width = viewport.width
  let height = viewport.height
  let output = StringBuilder()
  output.write_string(
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 " +
    width.to_string() +
    " " +
    height.to_string() +
    "\" width=\"" +
    width.to_string() +
    "\" height=\"" +
    height.to_string() +
    "\">",
  )
  pdf_svg_fonts(output, page)
  output.write_string("<rect width=\"100%\" height=\"100%\" fill=\"white\"/>")
  output.write_string(
    "<g transform=\"" +
    pdf_svg_relative_viewport_transform(
      page.width * paint_scale,
      page.height * paint_scale,
      viewport.rotation,
    ) +
    "\">",
  )
  pdf_svg_render_items(output, page, page.items[:], paint_scale, 0)
  pdf_svg_annotations(output, page, paint_scale)
  output.write_string("</g>")
  output.write_string("</svg>")
  output.to_string()
}

///|
/// Serialize a page-item slice in source paint order. Keeping this traversal
/// separate from the page wrapper lets a Form transparency group reuse the
/// exact same text-run, soft-mask, and image/path handling as the page root.
fn pdf_svg_render_items(
  output : StringBuilder,
  page : PdfPageModel,
  items : ArrayView[PdfPageItem],
  scale : Double,
  group_depth : Int,
) -> Unit {
  let text_run : Array[PdfTextItem] = []
  let mut item_index = 0
  while item_index < items.length() {
    let item = items[item_index]
    if group_depth >= 0 {
      match pdf_transparency_group_at_depth(item, group_depth) {
        Some(group) => {
          pdf_svg_flush_text_run(output, page, text_run, scale)
          text_run.clear()
          let first = item_index
          item_index += 1
          while item_index < items.length() {
            let same_group = match
              pdf_transparency_group_at_depth(items[item_index], group_depth) {
              Some(candidate) => candidate == group
              None => false
            }
            if same_group {
              item_index += 1
            } else {
              break
            }
          }
          pdf_svg_transparency_group(
            output,
            page,
            group,
            items[first:item_index],
            scale,
            group_depth,
          )
          continue
        }
        None => ()
      }
    }
    match pdf_soft_mask_of_page_item(item) {
      Some(mask) => {
        pdf_svg_flush_text_run(output, page, text_run, scale)
        text_run.clear()
        let first_index = pdf_page_item_index(item)
        let masked_items : Array[PdfPageItem] = []
        while item_index < items.length() {
          let candidate = items[item_index]
          let same_scope = match
            (
              pdf_transparency_group_at_depth(item, group_depth),
              pdf_transparency_group_at_depth(candidate, group_depth),
            ) {
            (Some(first_group), Some(candidate_group)) =>
              first_group == candidate_group
            (None, None) => true
            _ => false
          }
          let same_mask = same_scope &&
            (match pdf_soft_mask_of_page_item(candidate) {
              Some(value) => value == mask
              None => false
            })
          if same_mask {
            masked_items.push(pdf_page_item_without_soft_mask(candidate))
            item_index += 1
          } else {
            break
          }
        }
        pdf_svg_masked_item_run(
          output, page, first_index, mask, masked_items, scale, group_depth,
        )
      }
      None => {
        item_index += 1
        match item {
          PdfPageItem::Text(text) =>
            match text_run.last() {
              Some(previous) if pdf_svg_text_can_join(previous, text) =>
                text_run.push(text)
              _ => {
                pdf_svg_flush_text_run(output, page, text_run, scale)
                text_run.clear()
                text_run.push(text)
              }
            }
          PdfPageItem::Path(path) => {
            pdf_svg_flush_text_run(output, page, text_run, scale)
            text_run.clear()
            pdf_svg_path(output, page, path, scale)
          }
          PdfPageItem::Image(image) => {
            pdf_svg_flush_text_run(output, page, text_run, scale)
            text_run.clear()
            pdf_svg_image(output, page, image, scale)
          }
          PdfPageItem::Shading(shading) => {
            pdf_svg_flush_text_run(output, page, text_run, scale)
            text_run.clear()
            pdf_svg_shading(output, page, shading, scale)
          }
        }
      }
    }
  }
  pdf_svg_flush_text_run(output, page, text_run, scale)
}

///|
fn pdf_transparency_group_at_depth(
  item : PdfPageItem,
  depth : Int,
) -> PdfTransparencyGroup? {
  if depth < 0 {
    None
  } else {
    let groups = match item {
      PdfPageItem::Text(value) => value.group_path
      PdfPageItem::Path(value) => value.group_path
      PdfPageItem::Image(value) => value.group_path
      PdfPageItem::Shading(value) => value.group_path
    }
    groups.get(depth)
  }
}

///|
/// Preserve the Form boundary as an SVG compositor group. CSS can express
/// isolation, while the explicit data attributes keep non-isolated and
/// knockout semantics available to a future canvas/WebGL renderer.
fn pdf_svg_transparency_group(
  output : StringBuilder,
  page : PdfPageModel,
  group : PdfTransparencyGroup,
  items : ArrayView[PdfPageItem],
  scale : Double,
  group_depth : Int,
) -> Unit {
  let isolation = if group.isolated {
    " style=\"isolation:isolate\""
  } else {
    ""
  }
  output.write_string(
    "<g data-pdf-group-id=\"" +
    pdf_escape_xml(group.id) +
    "\" data-pdf-group-isolated=\"" +
    pdf_svg_bool(group.isolated) +
    "\" data-pdf-group-knockout=\"" +
    pdf_svg_bool(group.knockout) +
    "\"" +
    isolation +
    ">",
  )
  pdf_svg_render_items(output, page, items, scale, group_depth + 1)
  output.write_string("</g>")
}

///|
fn pdf_svg_bool(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
/// Render adjacent paint items that share one active soft mask as a single
/// source group. pdf.js composites the source group first and applies the mask
/// to the accumulated result; keeping the mask outside the child elements
/// avoids multiplying the same mask once per path or glyph.
fn pdf_svg_masked_item_run(
  output : StringBuilder,
  page : PdfPageModel,
  index : Int,
  mask : PdfSoftMaskResource,
  items : ArrayView[PdfPageItem],
  scale : Double,
  group_depth : Int,
) -> Unit {
  pdf_svg_soft_mask_defs(output, index, page, Some(mask), scale)
  pdf_svg_soft_mask_open(output, index, Some(mask))
  pdf_svg_render_items(output, page, items, scale, group_depth)
  pdf_svg_soft_mask_close(output, index, Some(mask))
}

///|
fn pdf_soft_mask_of_page_item(item : PdfPageItem) -> PdfSoftMaskResource? {
  match item {
    PdfPageItem::Text(value) => value.soft_mask
    PdfPageItem::Path(value) => value.soft_mask
    PdfPageItem::Image(value) => value.soft_mask
    PdfPageItem::Shading(value) => value.soft_mask
  }
}

///|
fn pdf_page_item_index(item : PdfPageItem) -> Int {
  match item {
    PdfPageItem::Text(value) => value.index
    PdfPageItem::Path(value) => value.index
    PdfPageItem::Image(value) => value.index
    PdfPageItem::Shading(value) => value.index
  }
}

///|
fn pdf_page_item_without_soft_mask(item : PdfPageItem) -> PdfPageItem {
  match item {
    PdfPageItem::Text(value) => PdfPageItem::Text({ ..value, soft_mask: None, })
    PdfPageItem::Path(value) => PdfPageItem::Path({ ..value, soft_mask: None, })
    PdfPageItem::Image(value) =>
      PdfPageItem::Image({ ..value, soft_mask: None, })
    PdfPageItem::Shading(value) =>
      PdfPageItem::Shading({ ..value, soft_mask: None, })
  }
}

///|
fn pdf_svg_path(
  output : StringBuilder,
  page : PdfPageModel,
  path : PdfPathItem,
  scale : Double,
) -> Unit {
  let fill = if path.filled {
    match path.shading_pattern {
      Some(_) => "none"
      None =>
        match path.pattern {
          Some(_) => "url(#pdf-pattern-" + path.index.to_string() + ")"
          None => path.fill_color
        }
    }
  } else {
    "none"
  }
  let stroke = if path.stroked {
    match path.stroke_pattern {
      Some(pattern) if pattern.shading is None =>
        "url(#pdf-stroke-pattern-" + path.index.to_string() + ")"
      _ => path.stroke_color
    }
  } else {
    "none"
  }
  let transformed = pdf_transform_svg_path(path.svg_path, page.height, scale)
  let dash = if path.dash_array.length() == 0 {
    ""
  } else {
    " stroke-dasharray=\"" +
    pdf_svg_dash_array(path.dash_array, scale) +
    "\" stroke-dashoffset=\"" +
    (path.dash_phase * scale).to_string() +
    "\""
  }
  pdf_svg_clip_defs(output, path.index, path.clip_path, scale)
  pdf_svg_pattern_defs(output, page, path, scale)
  pdf_svg_soft_mask_defs(output, path.index, page, path.soft_mask, scale)
  pdf_svg_soft_mask_open(output, path.index, path.soft_mask)
  pdf_svg_clip_open(output, path.index, path.clip_path)
  output.write_string(
    "<path d=\"" +
    transformed +
    "\" transform=\"scale(" +
    scale.to_string() +
    ")" +
    "\" data-pdf-bounds=\"" +
    path.bounds.min_x.to_string() +
    "," +
    path.bounds.min_y.to_string() +
    "," +
    path.bounds.max_x.to_string() +
    "," +
    path.bounds.max_y.to_string() +
    "\" fill=\"" +
    fill +
    "\" stroke=\"" +
    stroke +
    "\" fill-opacity=\"" +
    path.fill_alpha.to_string() +
    "\" stroke-opacity=\"" +
    path.stroke_alpha.to_string() +
    "\" stroke-width=\"" +
    (path.line_width * scale).to_string() +
    "\" stroke-linecap=\"" +
    pdf_svg_line_cap(path.line_cap) +
    "\" stroke-linejoin=\"" +
    pdf_svg_line_join(path.line_join) +
    "\"" +
    pdf_svg_blend_style(path.blend_mode) +
    dash +
    "/>",
  )
  pdf_svg_clip_close(output, path.index, path.clip_path)
  match path.shading_pattern {
    Some(shading) =>
      pdf_svg_shading_pattern_path(output, page, path, shading, scale)
    None => ()
  }
  pdf_svg_soft_mask_close(output, path.index, path.soft_mask)
}

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
  output.write_string(
    "<defs><clipPath id=\"" +
    clip_id +
    "\"><path d=\"" +
    transformed +
    "\"/></clipPath></defs><g clip-path=\"url(#" +
    clip_id +
    ")\" opacity=\"" +
    path.fill_alpha.to_string() +
    "\" transform=\"" +
    pdf_svg_shading_transform(page, shading.matrix, scale) +
    "\">",
  )
  pdf_svg_mesh_triangles(output, shading.mesh)
  output.write_string("</g>")
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
        pdf_svg_shading_transform(page, pattern.matrix, 1.0) +
        "\">" +
        tile_svg +
        "</pattern></defs>",
      )
    }
  }
}

///|
fn pdf_svg_line_cap(value : Int) -> String {
  match value {
    1 => "round"
    2 => "square"
    _ => "butt"
  }
}

///|
fn pdf_svg_line_join(value : Int) -> String {
  match value {
    1 => "round"
    2 => "bevel"
    _ => "miter"
  }
}

///|
fn pdf_svg_dash_array(values : ArrayView[Double], scale : Double) -> String {
  let output = StringBuilder()
  let mut first = true
  for value in values {
    if !first {
      output.write_char(' ')
    }
    first = false
    output.write_string((value * scale).to_string())
  }
  output.to_string()
}

///|
fn pdf_svg_image(
  output : StringBuilder,
  page : PdfPageModel,
  item : PdfVisualItem,
  scale : Double,
) -> Unit {
  pdf_svg_soft_mask_defs(output, item.index, page, item.soft_mask, scale)
  pdf_svg_soft_mask_open(output, item.index, item.soft_mask)
  match item.resource {
    Some(resource) =>
      match resource.mask_data_uri {
        Some(mask_data_uri) =>
          pdf_svg_masked_image(output, page, item, scale, mask_data_uri)
        None =>
          match (resource.data_uri, resource.alpha_mask_data_uri) {
            (Some(data_uri), Some(alpha_mask_data_uri)) => {
              let masked_data_uri = pdf_svg_alpha_mask_data_uri(
                item, data_uri, alpha_mask_data_uri,
              )
              pdf_svg_clip_defs(output, item.index, item.clip_path, scale)
              pdf_svg_clip_open(output, item.index, item.clip_path)
              output.write_string(
                "<image data-pdf-name=\"" +
                pdf_escape_xml(item.name) +
                "\" x=\"0\" y=\"0\" width=\"1\" height=\"1\" transform=\"" +
                pdf_svg_image_transform(page, item.quad, scale) +
                "\" preserveAspectRatio=\"none\" href=\"" +
                masked_data_uri +
                "\" opacity=\"" +
                item.fill_alpha.to_string() +
                "\"" +
                pdf_svg_image_sampling(resource, item.quad, scale) +
                pdf_svg_blend_style(item.blend_mode) +
                "/>",
              )
              pdf_svg_clip_close(output, item.index, item.clip_path)
            }
            (Some(data_uri), None) => {
              pdf_svg_clip_defs(output, item.index, item.clip_path, scale)
              pdf_svg_clip_open(output, item.index, item.clip_path)
              output.write_string(
                "<image data-pdf-name=\"" +
                pdf_escape_xml(item.name) +
                "\" x=\"0\" y=\"0\" width=\"1\" height=\"1\" transform=\"" +
                pdf_svg_image_transform(page, item.quad, scale) +
                "\" preserveAspectRatio=\"none\" href=\"" +
                data_uri +
                "\" opacity=\"" +
                item.fill_alpha.to_string() +
                "\"" +
                pdf_svg_image_sampling(resource, item.quad, scale) +
                pdf_svg_blend_style(item.blend_mode) +
                "/>",
              )
              pdf_svg_clip_close(output, item.index, item.clip_path)
            }
            _ => pdf_svg_placeholder(output, page, item, scale, "image")
          }
      }
    None => pdf_svg_placeholder(output, page, item, scale, "image")
  }
  pdf_svg_soft_mask_close(output, item.index, item.soft_mask)
}

///|
/// Paint an ImageMask as a coloured rectangle controlled by a luminance mask.
/// The mask and the rectangle share the source image quad, so rotations and
/// Form-XObject placement remain affine rather than falling back to a box.
fn pdf_svg_masked_image(
  output : StringBuilder,
  page : PdfPageModel,
  item : PdfVisualItem,
  scale : Double,
  mask_data_uri : String,
) -> Unit {
  let mask_data_uri = pdf_svg_colored_mask_data_uri(item, mask_data_uri)
  pdf_svg_clip_defs(output, item.index, item.clip_path, scale)
  pdf_svg_clip_open(output, item.index, item.clip_path)
  output.write_string(
    "<image data-pdf-name=\"" +
    pdf_escape_xml(item.name) +
    "\" x=\"0\" y=\"0\" width=\"1\" height=\"1\" transform=\"" +
    pdf_svg_image_transform(page, item.quad, scale) +
    "\" preserveAspectRatio=\"none\" href=\"" +
    mask_data_uri +
    "\" opacity=\"" +
    item.fill_alpha.to_string() +
    "\"" +
    (match item.resource {
      Some(resource) => pdf_svg_image_sampling(resource, item.quad, scale)
      None => ""
    }) +
    pdf_svg_blend_style(item.blend_mode) +
    "/>",
  )
  pdf_svg_clip_close(output, item.index, item.clip_path)
}

///|
/// Build a self-contained SVG image for an ImageMask. Chromium handles the
/// mask correctly while the image is in its own coordinate system, then the
/// outer viewer image applies the PDF quad transform. Applying the same
/// transform directly to an outer `<mask>` makes some browser versions treat
/// the mask as a solid rectangle.
fn pdf_svg_colored_mask_data_uri(
  item : PdfVisualItem,
  mask_data_uri : String,
) -> String {
  let (width, height) = match item.resource {
    Some(resource) =>
      (resource.width.unwrap_or(1).max(1), resource.height.unwrap_or(1).max(1))
    None => (1, 1)
  }
  let mask_id = "pdf-image-mask-inner-" + item.index.to_string()
  let inner = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 " +
    width.to_string() +
    " " +
    height.to_string() +
    "\" width=\"" +
    width.to_string() +
    "\" height=\"" +
    height.to_string() +
    "\"><defs><mask id=\"" +
    mask_id +
    "\" mask-type=\"luminance\" maskUnits=\"userSpaceOnUse\" maskContentUnits=\"userSpaceOnUse\" x=\"0\" y=\"0\" width=\"" +
    width.to_string() +
    "\" height=\"" +
    height.to_string() +
    "\"><image x=\"0\" y=\"0\" width=\"" +
    width.to_string() +
    "\" height=\"" +
    height.to_string() +
    "\" preserveAspectRatio=\"none\" image-rendering=\"crisp-edges\" href=\"" +
    mask_data_uri +
    "\"/></mask></defs><rect x=\"0\" y=\"0\" width=\"" +
    width.to_string() +
    "\" height=\"" +
    height.to_string() +
    "\" fill=\"" +
    pdf_escape_xml(item.fill_color) +
    "\" mask=\"url(#" +
    mask_id +
    ")\"/></svg>"
  "data:image/svg+xml;base64," + @base64.encode(@utf8.encode(inner))
}

///|
/// Combine a decoded image with an explicit `/Mask` or `/SMask` image. The
/// mask is evaluated in the image's local coordinate system before the whole
/// nested SVG receives the PDF quad transform, which keeps soft masks correct
/// for rotated and sheared image placements.
fn pdf_svg_alpha_mask_data_uri(
  item : PdfVisualItem,
  data_uri : String,
  alpha_mask_data_uri : String,
) -> String {
  let (width, height) = match item.resource {
    Some(resource) =>
      (
        resource.width
        .unwrap_or(1)
        .max(1)
        .max(resource.alpha_mask_width.unwrap_or(1)),
        resource.height
        .unwrap_or(1)
        .max(1)
        .max(resource.alpha_mask_height.unwrap_or(1)),
      )
    None => (1, 1)
  }
  let mask_id = "pdf-alpha-mask-inner-" + item.index.to_string()
  let inner = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 " +
    width.to_string() +
    " " +
    height.to_string() +
    "\" width=\"" +
    width.to_string() +
    "\" height=\"" +
    height.to_string() +
    "\"><defs><mask id=\"" +
    mask_id +
    "\" mask-type=\"luminance\" maskUnits=\"userSpaceOnUse\" maskContentUnits=\"userSpaceOnUse\" x=\"0\" y=\"0\" width=\"" +
    width.to_string() +
    "\" height=\"" +
    height.to_string() +
    "\"><image x=\"0\" y=\"0\" width=\"" +
    width.to_string() +
    "\" height=\"" +
    height.to_string() +
    "\" preserveAspectRatio=\"none\" image-rendering=\"crisp-edges\" href=\"" +
    alpha_mask_data_uri +
    "\"/></mask></defs><image x=\"0\" y=\"0\" width=\"" +
    width.to_string() +
    "\" height=\"" +
    height.to_string() +
    "\" preserveAspectRatio=\"none\" image-rendering=\"crisp-edges\" href=\"" +
    data_uri +
    "\" mask=\"url(#" +
    mask_id +
    ")\"/></svg>"
  "data:image/svg+xml;base64," + @base64.encode(@utf8.encode(inner))
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
      pdf_svg_clip_defs(output, item.index, item.clip_path, scale)
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
      pdf_svg_clip_defs(output, item.index, item.clip_path, scale)
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
fn pdf_svg_blend_style(blend_mode : String) -> String {
  if blend_mode == "normal" || blend_mode == "" {
    ""
  } else {
    " style=\"mix-blend-mode:" + pdf_escape_xml(blend_mode) + ";\""
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

///|
/// Convert the PDF unit-square quad for an image or shading into an SVG
/// affine transform. `pdflite` emits the unit square in PDF order (lower-left,
/// upper-left, upper-right, lower-right), while an SVG image's local origin
/// is its top-left corner. The page group's rotation is applied by the caller
/// after this page-space transform.
fn pdf_svg_visual_transform(
  page : PdfPageModel,
  quad : PdfQuad,
  scale : Double,
) -> String {
  let top_left = {
    x: (quad.p1.x - page.origin_x) * scale,
    y: (page.origin_y + page.height - quad.p1.y) * scale,
  }
  let top_right = {
    x: (quad.p2.x - page.origin_x) * scale,
    y: (page.origin_y + page.height - quad.p2.y) * scale,
  }
  let bottom_left = {
    x: (quad.p0.x - page.origin_x) * scale,
    y: (page.origin_y + page.height - quad.p0.y) * scale,
  }
  let a = top_right.x - top_left.x
  let b = top_right.y - top_left.y
  let c = bottom_left.x - top_left.x
  let d = bottom_left.y - top_left.y
  "matrix(" +
  a.to_string() +
  " " +
  b.to_string() +
  " " +
  c.to_string() +
  " " +
  d.to_string() +
  " " +
  top_left.x.to_string() +
  " " +
  top_left.y.to_string() +
  ")"
}

///|
fn pdf_svg_placeholder(
  output : StringBuilder,
  page : PdfPageModel,
  item : PdfVisualItem,
  scale : Double,
  kind : String,
) -> Unit {
  pdf_svg_clip_defs(output, item.index, item.clip_path, scale)
  pdf_svg_clip_open(output, item.index, item.clip_path)
  output.write_string(
    "<g data-pdf-placeholder=\"true\" data-pdf-kind=\"" +
    kind +
    "\" data-pdf-name=\"" +
    pdf_escape_xml(item.name) +
    "\"><rect x=\"0\" y=\"0\" width=\"1\" height=\"1\" transform=\"" +
    pdf_svg_visual_transform(page, item.quad, scale) +
    "\" fill=\"#eef1f5\" stroke=\"#9aa4b2\" stroke-dasharray=\"3 2\"/>" +
    "<title>" +
    pdf_escape_xml(kind + ": " + item.name) +
    "</title></g>",
  )
  pdf_svg_clip_close(output, item.index, item.clip_path)
}

///|
fn pdf_escape_xml(text : String) -> String {
  text
  .replace(old="&", new="&amp;")
  .replace(old="<", new="&lt;")
  .replace(old=">", new="&gt;")
  .replace(old="\"", new="&quot;")
  .replace(old="'", new="&apos;")
}

///|
fn pdf_transform_svg_path(
  path : String,
  page_height : Double,
  scale : Double,
) -> String {
  // Path data is stored in SVG page space. The path element applies the
  // requested scale, so the data remains readable to host-side tooling.
  ignore(page_height)
  ignore(scale)
  path
}

///|
/// Serialize explicit PDF clipping paths in page-space SVG coordinates.
fn pdf_svg_clip_path_of_shapes(
  paths : ArrayView[@shape.PdfPath],
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
) -> String? {
  let output = StringBuilder()
  let mut found = false
  for path in paths {
    match pdf_shape_bounds(path) {
      Some(bounds) => {
        let value = pdf_svg_path_of_shape(
          path, origin_x, origin_y, page_height, bounds,
        )
        if value != "" {
          if found {
            output.write_string("||")
          }
          found = true
          output.write_string(value)
        }
      }
      None => ()
    }
  }
  if found {
    Some(output.to_string())
  } else {
    None
  }
}

///|
fn pdf_svg_clip_defs(
  output : StringBuilder,
  index : Int,
  clip_path : String?,
  scale : Double,
) -> Unit {
  match clip_path {
    Some(path) => {
      let parts : Array[String] = []
      for part in path.split("||") {
        parts.push(part.to_owned())
      }
      let base = "pdf-clip-" + index.to_string()
      // Clips are stored in unscaled, page-relative SVG coordinates. Their
      // wrappers sit outside the individual paints' scaled transforms, so
      // apply the output scale here once, including every intersection part.
      let transform = if scale == 1.0 {
        ""
      } else {
        " transform=\"scale(" + scale.to_string() + ")\""
      }
      output.write_string("<defs>")
      for part_index, part in parts {
        let id = pdf_svg_clip_id(base, parts.length(), part_index)
        output.write_string(
          "<clipPath id=\"" +
          id +
          "\" clipPathUnits=\"userSpaceOnUse\"><path d=\"" +
          part +
          "\"" +
          transform +
          "/></clipPath>",
        )
      }
      output.write_string("</defs>")
    }
    None => ()
  }
}

///|
fn pdf_svg_clip_open(
  output : StringBuilder,
  index : Int,
  clip_path : String?,
) -> Unit {
  match clip_path {
    Some(path) => {
      let mut count = 0
      for _ in path.split("||") {
        count += 1
      }
      let base = "pdf-clip-" + index.to_string()
      for part_index in 0..<count {
        output.write_string(
          "<g clip-path=\"url(#" +
          pdf_svg_clip_id(base, count, part_index) +
          ")\">",
        )
      }
    }
    None => ()
  }
}

///|
fn pdf_svg_clip_close(
  output : StringBuilder,
  index : Int,
  clip_path : String?,
) -> Unit {
  match clip_path {
    Some(path) => {
      let mut count = 0
      for _ in path.split("||") {
        count += 1
      }
      ignore(index)
      for _ in 0..<count {
        output.write_string("</g>")
      }
    }
    None => ()
  }
}

///|
/// Define a page-space SVG mask for an ExtGState soft mask. The mask image is
/// placed with ordinary x/y/width/height attributes so browser coordinate
/// systems do not lose it when the painted item has a PDF affine transform.
fn pdf_svg_soft_mask_defs(
  output : StringBuilder,
  index : Int,
  page : PdfPageModel,
  soft_mask : PdfSoftMaskResource?,
  scale : Double,
) -> Unit {
  match soft_mask {
    Some(mask) => {
      let id = "pdf-soft-mask-" + index.to_string()
      let x = (mask.bounds.min_x - page.origin_x) * scale
      let y = (page.origin_y + page.height - mask.bounds.max_y) * scale
      let width = (mask.bounds.max_x - mask.bounds.min_x) * scale
      let height = (mask.bounds.max_y - mask.bounds.min_y) * scale
      output.write_string(
        "<defs><mask id=\"" +
        id +
        "\" mask-type=\"luminance\" maskUnits=\"userSpaceOnUse\" maskContentUnits=\"userSpaceOnUse\" x=\"0\" y=\"0\" width=\"" +
        (page.width * scale).to_string() +
        "\" height=\"" +
        (page.height * scale).to_string() +
        "\"><rect x=\"0\" y=\"0\" width=\"" +
        (page.width * scale).to_string() +
        "\" height=\"" +
        (page.height * scale).to_string() +
        "\" fill=\"" +
        pdf_escape_xml(mask.background) +
        "\"/><image x=\"" +
        x.to_string() +
        "\" y=\"" +
        y.to_string() +
        "\" width=\"" +
        width.to_string() +
        "\" height=\"" +
        height.to_string() +
        "\" preserveAspectRatio=\"none\" href=\"" +
        mask.data_uri +
        "\"/></mask></defs>",
      )
    }
    None => ()
  }
}

///|
fn pdf_svg_soft_mask_open(
  output : StringBuilder,
  index : Int,
  soft_mask : PdfSoftMaskResource?,
) -> Unit {
  match soft_mask {
    Some(_) =>
      output.write_string(
        "<g mask=\"url(#pdf-soft-mask-" + index.to_string() + ")\">",
      )
    None => ()
  }
}

///|
fn pdf_svg_soft_mask_close(
  output : StringBuilder,
  index : Int,
  soft_mask : PdfSoftMaskResource?,
) -> Unit {
  match soft_mask {
    Some(_) => {
      ignore(index)
      output.write_string("</g>")
    }
    None => ()
  }
}

///|
fn pdf_svg_clip_id(base : String, count : Int, index : Int) -> String {
  if count == 1 {
    base
  } else {
    base + "-" + index.to_string()
  }
}

///|
fn pdf_svg_path_of_shape(
  path : @shape.PdfPath,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
  target_bounds : PdfBounds,
) -> String {
  pdf_svg_path_of_shape_with_quad(path, origin_x, origin_y, page_height, {
    p0: { x: target_bounds.min_x, y: target_bounds.min_y, },
    p1: { x: target_bounds.min_x, y: target_bounds.max_y, },
    p2: { x: target_bounds.max_x, y: target_bounds.max_y, },
    p3: { x: target_bounds.max_x, y: target_bounds.min_y, },
  })
}

///|
/// Serialize path coordinates directly after the caller has applied the PDF
/// current transformation matrix. This is used for page paths because a
/// bounding box cannot represent rotation, shear, or a translated Form XObject.
fn pdf_svg_path_of_shape_direct(
  path : @shape.PdfPath,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
) -> String {
  match pdf_shape_bounds(path) {
    Some(bounds) =>
      pdf_svg_path_of_shape_with_quad(path, origin_x, origin_y, page_height, {
        p0: { x: bounds.min_x, y: bounds.min_y, },
        p1: { x: bounds.min_x, y: bounds.max_y, },
        p2: { x: bounds.max_x, y: bounds.max_y, },
        p3: { x: bounds.max_x, y: bounds.min_y, },
      })
    None => ""
  }
}

///|
/// Serialize a path using the four-corner affine mapping emitted by pdflite.
/// This keeps rotations and shears intact instead of stretching the path to
/// its axis-aligned bounding box.
fn pdf_svg_path_of_shape_with_quad(
  path : @shape.PdfPath,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
  target_quad : PdfQuad,
) -> String {
  let source_bounds = match pdf_shape_bounds(path) {
    Some(bounds) => bounds
    None => { min_x: 0.0, min_y: 0.0, max_x: 0.0, max_y: 0.0, }
  }
  let output = StringBuilder()
  for subpath in path.subpaths {
    if subpath.segments.length() == 0 {
      continue
    }
    match subpath.segments[0] {
      @shape.PdfPathSegment::PdfPathStraight(start, end) => {
        output.write_string(
          "M " +
          pdf_svg_point_from_quad(
            start, origin_x, origin_y, page_height, source_bounds, target_quad,
          ),
        )
        output.write_string(
          " L " +
          pdf_svg_point_from_quad(
            end, origin_x, origin_y, page_height, source_bounds, target_quad,
          ),
        )
      }
      @shape.PdfPathSegment::PdfPathBezier(start, c1, c2, end) => {
        output.write_string(
          "M " +
          pdf_svg_point_from_quad(
            start, origin_x, origin_y, page_height, source_bounds, target_quad,
          ),
        )
        output.write_string(
          " C " +
          pdf_svg_point_from_quad(
            c1, origin_x, origin_y, page_height, source_bounds, target_quad,
          ) +
          " " +
          pdf_svg_point_from_quad(
            c2, origin_x, origin_y, page_height, source_bounds, target_quad,
          ) +
          " " +
          pdf_svg_point_from_quad(
            end, origin_x, origin_y, page_height, source_bounds, target_quad,
          ),
        )
      }
    }
    for segment in subpath.segments[1:] {
      match segment {
        @shape.PdfPathSegment::PdfPathStraight(_, end) =>
          output.write_string(
            " L " +
            pdf_svg_point_from_quad(
              end, origin_x, origin_y, page_height, source_bounds, target_quad,
            ),
          )
        @shape.PdfPathSegment::PdfPathBezier(_, c1, c2, end) =>
          output.write_string(
            " C " +
            pdf_svg_point_from_quad(
              c1, origin_x, origin_y, page_height, source_bounds, target_quad,
            ) +
            " " +
            pdf_svg_point_from_quad(
              c2, origin_x, origin_y, page_height, source_bounds, target_quad,
            ) +
            " " +
            pdf_svg_point_from_quad(
              end, origin_x, origin_y, page_height, source_bounds, target_quad,
            ),
          )
      }
    }
    match subpath.closure {
      @shape.PdfPathClosure::PdfPathClosed => output.write_string(" Z")
      @shape.PdfPathClosure::PdfPathOpen => ()
    }
  }
  output.to_string()
}

///|
fn pdf_shape_bounds(path : @shape.PdfPath) -> PdfBounds? {
  let mut bounds : PdfBounds? = None
  for subpath in path.subpaths {
    for segment in subpath.segments {
      match segment {
        @shape.PdfPathSegment::PdfPathStraight(start, end) => {
          bounds = pdf_shape_bounds_add_point(bounds, start)
          bounds = pdf_shape_bounds_add_point(bounds, end)
        }
        @shape.PdfPathSegment::PdfPathBezier(start, c1, c2, end) => {
          bounds = pdf_shape_bounds_add_point(bounds, start)
          bounds = pdf_shape_bounds_add_point(bounds, c1)
          bounds = pdf_shape_bounds_add_point(bounds, c2)
          bounds = pdf_shape_bounds_add_point(bounds, end)
        }
      }
    }
  }
  bounds
}

///|
fn pdf_shape_bounds_add_point(
  bounds : PdfBounds?,
  point : @geometry.Point2,
) -> PdfBounds? {
  match bounds {
    Some(bounds) =>
      Some({
        min_x: bounds.min_x.min(point.x),
        min_y: bounds.min_y.min(point.y),
        max_x: bounds.max_x.max(point.x),
        max_y: bounds.max_y.max(point.y),
      })
    None =>
      Some({ min_x: point.x, min_y: point.y, max_x: point.x, max_y: point.y, })
  }
}

///|
fn pdf_svg_point_from_quad(
  point : @geometry.Point2,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
  source_bounds : PdfBounds,
  target_quad : PdfQuad,
) -> String {
  let x_ratio = if source_bounds.max_x > source_bounds.min_x {
    (point.x - source_bounds.min_x) /
    (source_bounds.max_x - source_bounds.min_x)
  } else {
    0.0
  }
  let y_ratio = if source_bounds.max_y > source_bounds.min_y {
    (point.y - source_bounds.min_y) /
    (source_bounds.max_y - source_bounds.min_y)
  } else {
    0.0
  }
  let x = target_quad.p0.x +
    x_ratio * (target_quad.p3.x - target_quad.p0.x) +
    y_ratio * (target_quad.p1.x - target_quad.p0.x)
  let y = target_quad.p0.y +
    x_ratio * (target_quad.p3.y - target_quad.p0.y) +
    y_ratio * (target_quad.p1.y - target_quad.p0.y)
  (x - origin_x).to_string() + " " + (origin_y + page_height - y).to_string()
}

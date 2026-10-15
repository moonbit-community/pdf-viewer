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
              pdf_svg_clip_defs(
                output,
                item.index,
                item.clip_path,
                scale,
                clips=item.clips,
              )
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
              pdf_svg_clip_defs(
                output,
                item.index,
                item.clip_path,
                scale,
                clips=item.clips,
              )
              pdf_svg_clip_open(output, item.index, item.clip_path)
              output.write_string(
                "<image data-pdf-name=\"" +
                pdf_escape_xml(item.name) +
                "\" x=\"0\" y=\"0\" width=\"1\" height=\"1\" transform=\"" +
                pdf_svg_image_transform(page, item.quad, scale) +
                "\" preserveAspectRatio=\"none\" href=\"" +
                pdf_image_embedded_uri(data_uri) +
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
  pdf_svg_clip_defs(output, item.index, item.clip_path, scale, clips=item.clips)
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
  let mask_data_uri = pdf_image_embedded_uri(mask_data_uri)
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
  let data_uri = pdf_image_embedded_uri(data_uri)
  let alpha_mask_data_uri = pdf_image_embedded_uri(alpha_mask_data_uri)
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
  pdf_svg_clip_defs(output, item.index, item.clip_path, scale, clips=item.clips)
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

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
  let style = (if group.isolated { "isolation:isolate" } else { "" }) +
    (if group.blend_mode == "normal" || group.blend_mode == "Normal" {
      ""
    } else {
      ";mix-blend-mode:" + pdf_escape_xml(group.blend_mode) + ";"
    })
  let isolation = if style == "" { "" } else { " style=\"" + style + "\"" }
  output.write_string(
    "<g data-pdf-group-id=\"" +
    pdf_escape_xml(group.id) +
    "\" data-pdf-group-isolated=\"" +
    pdf_svg_bool(group.isolated) +
    "\" data-pdf-group-knockout=\"" +
    pdf_svg_bool(group.knockout) +
    "\"" +
    isolation +
    " opacity=\"" +
    group.alpha.to_string() +
    "\">",
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
fn pdf_svg_blend_style(blend_mode : String) -> String {
  if blend_mode == "normal" || blend_mode == "" {
    ""
  } else {
    " style=\"mix-blend-mode:" + pdf_escape_xml(blend_mode) + ";\""
  }
}

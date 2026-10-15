///|
/// Render an already decoded page, allowing hosts to reuse the page model for
/// zoom, rotation, text selection and repeated paint operations.
///
/// ```mbt check
/// test {
///   let page : @pdf-viewer.PdfPageModel = {
///     number: 1,
///     blend_space: "DeviceRGB",
///     blend_profile_id: None,
///     blend_calibration: None,
///     icc_profiles: [],
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
  let diagnostics = page.graphics_diagnostics(renderer="svg")
  if !diagnostics.is_empty() {
    output.write_string(
      "<metadata id=\"pdf-renderer-diagnostics\">" +
      pdf_escape_xml(diagnostics.to_json().stringify()) +
      "</metadata>",
    )
  }
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
              Some(candidate) => candidate.id == group.id
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
fn pdf_escape_xml(text : String) -> String {
  text
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
  .replace_all(old="\"", new="&quot;")
  .replace_all(old="'", new="&apos;")
}

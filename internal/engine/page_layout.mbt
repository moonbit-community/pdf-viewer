///|
/// Resolve a page's viewport without interpreting its content, fonts or images.
/// Hosts can lay out unloaded pages using the same geometry as rendering.
/// Page numbers are one-based; the requested rotation is added to `/Rotate`.
pub fn PdfViewerDocument::page_viewport(
  self : PdfViewerDocument,
  number : Int,
  scale? : Double = 1.0,
  rotation? : Int = 0,
) -> PdfViewport? {
  guard number >= 1 && number <= self.pages.length() else { return None }
  let page = self.pages[number - 1]
  let box = pdf_page_view_box(self.document, page)
  let model : PdfPageModel = {
    number,
    origin_x: box.min_x,
    origin_y: box.min_y,
    width: box.max_x - box.min_x,
    height: box.max_y - box.min_y,
    user_unit: pdf_page_user_unit(self.document, page),
    rotation: @page.pdf_page_int_of_rotation(page.rotate),
    // Geometry-only placeholder: no colour resources are resolved here.
    blend_space: "DeviceRGB",
    blend_profile_id: None,
    blend_calibration: None,
    icc_profiles: [],
    fonts: [],
    items: [],
    annotations: [],
    text: "",
  }
  Some(model.viewport(scale~, rotation=model.rotation + rotation))
}

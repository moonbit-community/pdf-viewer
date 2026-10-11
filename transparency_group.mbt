///|
fn pdf_group_bounds(
  document : @pdflite.PdfDocument,
  form : @syntax.PdfObject,
  ctm : @geometry.TransformMatrix,
) -> PdfBounds? {
  try {
    let object = match document.lookup_direct(pdf_name_key("/BBox"), form) {
      Some(value) => value
      None => return None
    }
    let box = document.parse_rectangle(object)
    let matrix = @geometry.transform_matrix_compose(
      ctm,
      document.parse_matrix(pdf_name_key("/Matrix"), form),
    )
    let points = [
      matrix.apply({ x: box.min_x, y: box.min_y, }),
      matrix.apply({ x: box.max_x, y: box.min_y, }),
      matrix.apply({ x: box.max_x, y: box.max_y, }),
      matrix.apply({ x: box.min_x, y: box.max_y, }),
    ]
    let mut min_x = points[0].x
    let mut max_x = min_x
    let mut min_y = points[0].y
    let mut max_y = min_y
    for point in points {
      min_x = Double::min(min_x, point.x)
      min_y = Double::min(min_y, point.y)
      max_x = Double::max(max_x, point.x)
      max_y = Double::max(max_y, point.y)
    }
    Some({ min_x, min_y, max_x, max_y, })
  } catch {
    _ => None
  }
}

///|
fn pdf_page_blend_space(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
) -> String {
  match document.lookup_direct(pdf_name_key("/Group"), page.rest) {
    Some(group) =>
      match document.lookup_direct(pdf_name_key("/CS"), group) {
        Some(@syntax.PdfNameObject(name)) => pdf_colour_colorant_name(name)
        _ => "DeviceRGB"
      }
    None => "DeviceRGB"
  }
}

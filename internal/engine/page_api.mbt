///|
/// Convert a PDF user-space point to viewport coordinates, matching pdf.js'
/// `PageViewport.convertToViewportPoint`.
pub fn PdfViewport::convert_to_viewport_point(
  self : PdfViewport,
  point : PdfPoint,
) -> PdfPoint {
  {
    x: self.matrix[0] * point.x + self.matrix[2] * point.y + self.matrix[4],
    y: self.matrix[1] * point.x + self.matrix[3] * point.y + self.matrix[5],
  }
}

///|
/// Convert a viewport point back to PDF user-space coordinates, matching
/// pdf.js' `PageViewport.convertToPdfPoint`.
pub fn PdfViewport::convert_to_pdf_point(
  self : PdfViewport,
  point : PdfPoint,
) -> PdfPoint {
  let a = self.matrix[0]
  let b = self.matrix[1]
  let c = self.matrix[2]
  let d = self.matrix[3]
  let e = self.matrix[4]
  let f = self.matrix[5]
  let determinant = a * d - b * c
  {
    x: (d * (point.x - e) - c * (point.y - f)) / determinant,
    y: (-b * (point.x - e) + a * (point.y - f)) / determinant,
  }
}

///|
/// Compute a pdf.js-style viewport for a page.
pub fn PdfPageModel::viewport(
  self : PdfPageModel,
  scale? : Double = 1.0,
  rotation? : Int = 0,
) -> PdfViewport {
  let safe_scale = if scale <= 0.0 { 1.0 } else { scale }
  let user_unit = pdf_safe_user_unit(self.user_unit)
  let paint_scale = safe_scale * user_unit
  let normalized_rotation = pdf_normalize_rotation(rotation)
  let scaled_width = self.width * paint_scale
  let scaled_height = self.height * paint_scale
  let (rotate_a, rotate_b, rotate_c, rotate_d) = match normalized_rotation {
    90 => (0.0, 1.0, 1.0, 0.0)
    180 => (-1.0, 0.0, 0.0, 1.0)
    270 => (0.0, -1.0, -1.0, 0.0)
    _ => (1.0, 0.0, 0.0, -1.0)
  }
  let center_x = self.origin_x + self.width / 2.0
  let center_y = self.origin_y + self.height / 2.0
  let (width, height, offset_x, offset_y) = if rotate_a == 0.0 {
    (
      scaled_height,
      scaled_width,
      (center_y - self.origin_y).abs() * paint_scale,
      (center_x - self.origin_x).abs() * paint_scale,
    )
  } else {
    (
      scaled_width,
      scaled_height,
      (center_x - self.origin_x).abs() * paint_scale,
      (center_y - self.origin_y).abs() * paint_scale,
    )
  }
  let matrix = [
    rotate_a * paint_scale,
    rotate_b * paint_scale,
    rotate_c * paint_scale,
    rotate_d * paint_scale,
    offset_x -
    rotate_a * paint_scale * center_x -
    rotate_c * paint_scale * center_y,
    offset_y -
    rotate_b * paint_scale * center_x -
    rotate_d * paint_scale * center_y,
  ]
  // Keep this field identical to pdf.js' `PageViewport.transform`: it maps
  // PDF user-space coordinates directly into the top-left viewport. The SVG
  // serializer uses a separate relative transform because page items already
  // have their media-box origin removed.
  let transform = "matrix(" + pdf_svg_matrix_values(matrix) + ")"
  {
    width,
    height,
    scale: safe_scale,
    user_unit,
    rotation: normalized_rotation,
    matrix,
    transform,
  }
}

///|
fn pdf_svg_matrix_values(values : ArrayView[Double]) -> String {
  let output = StringBuilder()
  for index, value in values {
    if index > 0 {
      output.write_char(' ')
    }
    output.write_string(value.to_string())
  }
  output.to_string()
}

///|
fn pdf_svg_relative_viewport_transform(
  width : Double,
  height : Double,
  rotation : Int,
) -> String {
  match rotation {
    90 => "translate(" + height.to_string() + " 0) rotate(90)"
    180 =>
      "translate(" +
      width.to_string() +
      " " +
      height.to_string() +
      ") rotate(180)"
    270 => "translate(0 " + width.to_string() + ") rotate(-90)"
    _ => "translate(0 0)"
  }
}

///|
/// Return the page's positioned text items and their reading-order text.
pub fn PdfPageModel::text_content(self : PdfPageModel) -> PdfTextContent {
  let items = pdf_text_reading_order_of_page_items(self.items[:])
  { items, text: pdf_join_text_items(items[:]), }
}

///|
/// Return the page display list without reparsing the source document.
pub fn PdfPageModel::operator_list(self : PdfPageModel) -> Array[PdfPageItem] {
  self.items
}

///|
fn pdf_normalize_rotation(rotation : Int) -> Int {
  let mut value = rotation % 360
  if value < 0 {
    value += 360
  }
  match value {
    0 | 90 | 180 | 270 => value
    _ => 0
  }
}

///|
fn pdf_safe_user_unit(value : Double) -> Double {
  if value <= 0.0 || value.is_nan() || value.is_inf() {
    1.0
  } else {
    value
  }
}

///|
fn pdf_normalize_rotation_strict(rotation : Int) -> Int raise @core.PdfError {
  let mut value = rotation % 360
  if value < 0 {
    value += 360
  }
  match value {
    0 | 90 | 180 | 270 => value
    _ => raise @core.PageRotationExpected(rotation)
  }
}

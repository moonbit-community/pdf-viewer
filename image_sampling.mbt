///|
fn pdf_image_interpolate(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> Bool {
  document.lookup_direct_or_else(
    pdf_image_name("/Interpolate"),
    pdf_image_name("/I"),
    object,
  )
  is Some(@syntax.PdfBoolean(true))
}

///|
/// Match the pinned PDF.js up/downsampling decision using the affine scale
/// of a source pixel. Rotation preserves singular values; shear and unequal
/// axes do not. SVG output uses one CSS pixel per viewport unit.
fn pdf_image_smoothing_enabled(
  interpolate : Bool,
  quad : PdfQuad,
  width : Int,
  height : Int,
  scale : Double,
) -> Bool {
  if interpolate || width <= 0 || height <= 0 {
    return true
  }
  let a = (quad.p2.x - quad.p1.x) * scale / width.to_double()
  let b = (quad.p2.y - quad.p1.y) * scale / width.to_double()
  let c = (quad.p0.x - quad.p1.x) * scale / height.to_double()
  let d = (quad.p0.y - quad.p1.y) * scale / height.to_double()
  let aa = a * a + b * b
  let bb = a * c + b * d
  let cc = c * c + d * d
  let first = (aa + cc) / 2.0
  let second = (first * first - (aa * cc - bb * bb)).max(0.0).sqrt()
  let largest = Float::from_double((first + second).sqrt())
  largest <= Float::from_double(4.0 / 3.0)
}

///|
/// `crisp-edges` asks Chromium for nearest-neighbour sampling even at a
/// fractional zoom. `pixelated` may add a smoothing pass after integer zoom.
fn pdf_svg_image_sampling(
  resource : PdfImageResource,
  quad : PdfQuad,
  scale : Double,
) -> String {
  let width = resource.width
    .unwrap_or(1)
    .max(resource.alpha_mask_width.unwrap_or(1))
  let height = resource.height
    .unwrap_or(1)
    .max(resource.alpha_mask_height.unwrap_or(1))
  if pdf_image_smoothing_enabled(
      resource.interpolate,
      quad,
      width,
      height,
      scale,
    ) {
    " image-rendering=\"auto\""
  } else {
    " image-rendering=\"crisp-edges\""
  }
}

///|
/// PDF.js rounds both corners for axis-aligned image draws. Do this in the
/// final rotated viewport, then invert the page wrapper so all source quads,
/// clipping and selection remain in their original PDF coordinate system.
fn pdf_svg_image_transform(
  page : PdfPageModel,
  quad : PdfQuad,
  scale : Double,
) -> String {
  let viewport = page.viewport(
    scale=scale / pdf_safe_user_unit(page.user_unit),
    rotation=page.rotation,
  )
  let top_left = viewport.convert_to_viewport_point(quad.p1)
  let top_right = viewport.convert_to_viewport_point(quad.p2)
  let bottom_left = viewport.convert_to_viewport_point(quad.p0)
  let a = top_right.x - top_left.x
  let b = top_right.y - top_left.y
  let c = bottom_left.x - top_left.x
  let d = bottom_left.y - top_left.y
  if !((b == 0.0 && c == 0.0) || (a == 0.0 && d == 0.0)) {
    return pdf_svg_visual_transform(page, quad, scale)
  }
  let tx = (top_left.x + 0.5).floor()
  let ty = (top_left.y + 0.5).floor()
  let a = pdf_image_rounded_extent(top_left.x, a)
  let b = pdf_image_rounded_extent(top_left.y, b)
  let c = pdf_image_rounded_extent(top_left.x, c)
  let d = pdf_image_rounded_extent(top_left.y, d)
  let values = match pdf_normalize_rotation(page.rotation) {
    90 => [b, -a, d, -c, ty, page.height * scale - tx]
    180 => [-a, -b, -c, -d, page.width * scale - tx, page.height * scale - ty]
    270 => [-b, a, -d, c, page.width * scale - ty, tx]
    _ => [a, b, c, d, tx, ty]
  }
  "matrix(" + pdf_svg_matrix_values(values) + ")"
}

///|
fn pdf_image_rounded_extent(origin : Double, extent : Double) -> Double {
  if extent == 0.0 {
    return 0.0
  }
  let rounded = (origin + extent + 0.5).floor() - (origin + 0.5).floor()
  if rounded == 0.0 {
    if extent < 0.0 {
      -1.0
    } else {
      1.0
    }
  } else {
    rounded
  }
}

///|
/// Optional straight source samples retained only for subtractive compositing.
/// Normalized components are interleaved big-endian 16-bit; alpha is separate
/// row-major 8-bit. Both have already received Decode, resize, masks and Matte.
pub(all) struct PdfImageInkSamples {
  width : Int
  height : Int
  components : Int
  bits : Int
  row_bytes : Int
  data_base64 : String
  alpha_base64 : String
  source_colour : PdfSourceColour
  process_cmyk : Bool
} derive(Debug, Eq, ToJson)

///|
/// Bound all extra retained sample buffers together, before allocation.
fn pdf_image_ink_dimensions(
  width : Int,
  height : Int,
  components : Int,
) -> (Int, Int) {
  let (width, height) = pdf_image_draw_dimensions(width, height)
  let factor = (67108864.0 /
    (width.to_double() * height.to_double() * (components * 2 + 1).to_double()))
    .sqrt()
    .min(1.0)
  (
    (width.to_double() * factor).floor().to_int().max(1),
    (height.to_double() * factor).floor().to_int().max(1),
  )
}

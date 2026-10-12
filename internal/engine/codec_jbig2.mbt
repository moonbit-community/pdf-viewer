///|
/// Packed MSB-first one-bit PDF luminance; no Decode, colour keys or masks.
fn pdf_jbig2_samples(
  data : Bytes,
  globals : Bytes?,
  width : Int,
  height : Int,
) -> Bytes? {
  @jbig2.decode(data, globals, width, height)
}

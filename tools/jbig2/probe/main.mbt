///|
pub fn decode_image(
  data : Bytes,
  globals : Bytes,
  width : Int,
  height : Int,
) -> Bytes? {
  @jbig2.decode(data, Some(globals), width, height)
}

///|
#cfg(target="native")
#borrow(data, globals, output)
extern "C" fn native_decode(
  data : Bytes,
  data_size : Int,
  globals : Bytes,
  globals_size : Int,
  width : Int,
  height : Int,
  output : Bytes,
  output_size : Int,
) -> Int = "pdf_viewer_jbig2_native"

///|
#cfg(target="native")
fn host_decode(
  data : Bytes,
  globals : Bytes,
  width : Int,
  height : Int,
) -> Bytes? {
  let size = (width + 7) / 8 * height
  let output = Bytes::make(size, 0)
  if native_decode(
      data,
      data.length(),
      globals,
      globals.length(),
      width,
      height,
      output,
      size,
    ) ==
    1 {
    Some(output)
  } else {
    None
  }
}

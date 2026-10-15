///|
/// Only the browser Worker's compiled Canvas request enables this hook.
/// Other hosts and self-contained exports retain the ordinary PNG encoder.
#cfg(target="js")
extern "js" fn pdf_image_host_raster_enabled() -> Bool =
  #| () => globalThis.__moonbit_pdf_rasters?.enabled === true

///|
#cfg(target="js")
extern "js" fn pdf_image_host_raster(
  width : Int,
  height : Int,
  colour_type : Int,
  rows : Bytes,
  encode : () -> Bytes,
) -> Bytes =
  #| (w,h,c,rows,encode) => globalThis.__moonbit_pdf_rasters?.capture(w,h,c,rows,encode) || new Uint8Array(0)

///|
#cfg(target="js")
extern "js" fn pdf_image_host_raster_uri(
  mime : String,
  bytes : Bytes,
) -> String =
  #| (mime,bytes) => mime === 'image/png' ? (globalThis.__moonbit_pdf_rasters?.uri(bytes) || '') : ''

///|
#cfg(target="js")
extern "js" fn pdf_image_embedded_uri(uri : String) -> String =
  #| uri => globalThis.__moonbit_pdf_rasters?.embed(uri) || uri

///|
#cfg(not(target="js"))
fn pdf_image_host_raster_enabled() -> Bool {
  false
}

///|
#cfg(not(target="js"))
fn pdf_image_host_raster(
  _width : Int,
  _height : Int,
  _colour_type : Int,
  _rows : Bytes,
  _encode : () -> Bytes,
) -> Bytes {
  b""
}

///|
#cfg(not(target="js"))
fn pdf_image_host_raster_uri(_mime : String, _bytes : Bytes) -> String {
  ""
}

///|
#cfg(not(target="js"))
fn pdf_image_embedded_uri(uri : String) -> String {
  uri
}

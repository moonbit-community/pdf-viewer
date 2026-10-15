///|
/// The optional JS host only returns fully validated, bounded zlib streams.
/// Empty/failed/over-limit decodes retain the portable decoder's recovery.
#cfg(target="js")
extern "js" fn pdf_image_host_inflate(data : Bytes, limit : Int) -> Bytes =
  #| (data, limit) => globalThis.__moonbit_pdf_image_inflate?.(data, limit) || new Uint8Array(0)

///|
#cfg(target="js")
extern "js" fn pdf_image_host_deflate(data : Bytes) -> Bytes =
  #| data => globalThis.__moonbit_pdf_image_deflate?.(data) || new Uint8Array(0)

///|
#cfg(not(target="js"))
fn pdf_image_host_inflate(_data : Bytes, _limit : Int) -> Bytes {
  b""
}

///|
#cfg(not(target="js"))
fn pdf_image_host_deflate(_data : Bytes) -> Bytes {
  b""
}

///|
#cfg(target="js")
#external
priv type PdfNameKeyCache

///|
#cfg(target="js")
extern "js" fn pdf_name_key_cache_new() -> PdfNameKeyCache =
  #| () => new Map()

///|
#cfg(target="js")
let pdf_name_keys : PdfNameKeyCache = pdf_name_key_cache_new()

///|
/// Cache immutable key bytes only. The original encoder handles misses so
/// Unicode and invalid-surrogate behavior stays identical on every backend.
#cfg(target="js")
extern "js" fn pdf_name_key_bytes(
  cache : PdfNameKeyCache,
  text : String,
  encode : (String) -> Bytes,
) -> Bytes =
  #| (cache, text, encode) => {
  #|   if (text.length > 96) return encode(text);
  #|   const found = cache.get(text);
  #|   if (found !== undefined) return found;
  #|   const bytes = encode(text);
  #|   if (cache.size < 256) cache.set(text, bytes);
  #|   return bytes;
  #| }

///|
#cfg(target="js")
fn pdf_name_key_encode(text : String) -> Bytes {
  @utf8.encode(text)
}

///|
#cfg(target="js")
fn pdf_name_key(text : String) -> @core.PdfName {
  @core.pdf_name_of_bytes(
    pdf_name_key_bytes(pdf_name_keys, text, pdf_name_key_encode),
  )
}

///|
#cfg(not(target="js"))
fn pdf_name_key(text : String) -> @core.PdfName {
  @core.pdf_name_of_bytes(@utf8.encode(text))
}

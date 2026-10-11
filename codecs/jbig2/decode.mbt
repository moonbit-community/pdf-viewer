///|
/// Whether this host has installed the bounded JBIG2 decoder.
/// Availability does not imply that arbitrary input can be decoded.
pub fn available() -> Bool {
  host_available()
}

///|
#cfg(target="js")
extern "js" fn host_available() -> Bool =
  #| () => typeof globalThis.__pdf_viewer_jbig2_decode === "function"

///|
#cfg(not(any(target="js", target="native")))
fn host_available() -> Bool {
  false
}

///|
/// Standalone JBIG2 host adapter. Output is tight, row-aligned, MSB-first
/// one-bit luminance (0 black, 1 white). Decode, colour keys, ImageMask and
/// alpha are applied by the image pipeline, never by this codec.
/// The JS host must await codecs/jbig2/decoder.mjs::installJbig2Decoder first.
pub fn decode(
  data : Bytes,
  globals : Bytes?,
  width : Int,
  height : Int,
) -> Bytes? {
  if width <= 0 ||
    height <= 0 ||
    width > 32768 ||
    height > 32768 ||
    width > 67108864 / height ||
    data.length() == 0 ||
    data.length() > 16777216 {
    return None
  }
  let globals = globals.unwrap_or(b"")
  if globals.length() > 16777216 - data.length() {
    return None
  }
  let output = host_decode(data, globals, width, height)
  match output {
    Some(bytes) if bytes.length() == (width + 7) / 8 * height => Some(bytes)
    _ => None
  }
}

///|
#cfg(target="js")
extern "js" fn host_decode(
  data : Bytes,
  globals : Bytes,
  width : Int,
  height : Int,
) -> Bytes? =
  #| (data, globals, width, height) => {
  #|   const decode = globalThis.__pdf_viewer_jbig2_decode;
  #|   if (typeof decode !== "function") return undefined;
  #|   try { return decode(data, globals, width, height) ?? undefined; } catch { return undefined; }
  #| }

///|
/// No MoonBit-Wasm host is currently linked. Returning None is
/// intentional; successful cross-target typechecking is not decoder support.
#cfg(not(any(target="js", target="native")))
fn host_decode(
  _data : Bytes,
  _globals : Bytes,
  _width : Int,
  _height : Int,
) -> Bytes? {
  None
}

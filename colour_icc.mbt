///|
/// An ICC transform is compiled by a mature host engine, never approximated
/// by profile metadata. Values are straight, normalized PDF samples; output
/// is straight sRGB. A failed/absent engine is represented by None.
priv struct PdfIccTransform {
  convert : (ArrayView[Double]) -> (Double, Double, Double)
}

///|
let pdf_icc_cache : Array[(Bytes, Int, Int, PdfIccTransform?)] = []

///|
fn pdf_icc_transform(
  bytes : Bytes,
  components : Int,
  intent? : Int = 1,
) -> PdfIccTransform? {
  let intent = if intent >= 0 && intent <= 3 { intent } else { 1 }
  if !pdf_icc_profile_valid(bytes, components) || !pdf_icc_engine_available() {
    return None
  }
  for (profile, count, cached_intent, transform) in pdf_icc_cache {
    if count == components && cached_intent == intent && profile == bytes {
      return transform
    }
  }
  let transform = pdf_icc_engine_transform(bytes, components, intent)
  // The host explicitly caps active CMM transforms and allocations. Eviction
  // releases CMM resources, while retained closures can safely reopen lazily.
  if pdf_icc_cache.length() >= 8 {
    ignore(pdf_icc_cache.remove(0))
  }
  pdf_icc_cache.push((bytes, components, intent, transform))
  transform
}

///|
fn pdf_icc_profile_valid(bytes : Bytes, components : Int) -> Bool {
  if !(components is (1 | 3 | 4)) ||
    bytes.length() < 132 ||
    bytes.length() > 16777216 {
    return false
  }
  if bytes[36:40] != b"acsp" {
    return false
  }
  let signature = if components == 1 {
    b"GRAY"
  } else if components == 3 {
    b"RGB "
  } else {
    b"CMYK"
  }
  if bytes[16:20] != signature[:] {
    return false
  }
  let size = pdf_icc_u32(bytes, 0)
  if size < 132 || size > bytes.length() {
    return false
  }
  let count = pdf_icc_u32(bytes, 128)
  if count < 0 || count > (size - 132) / 12 {
    return false
  }
  for i in 0..<count {
    let offset = pdf_icc_u32(bytes, 132 + i * 12 + 4)
    let length = pdf_icc_u32(bytes, 132 + i * 12 + 8)
    if offset < 0 || length < 0 || offset > size || length > size - offset {
      return false
    }
  }
  true
}

///|
fn pdf_icc_u32(bytes : Bytes, offset : Int) -> Int {
  (bytes[offset].to_int() << 24) |
  (bytes[offset + 1].to_int() << 16) |
  (bytes[offset + 2].to_int() << 8) |
  bytes[offset + 3].to_int()
}

///|
fn pdf_icc_ranges(
  count : Int,
  range : Array[Double],
) -> Array[(Double, Double)] {
  [
    for i in 0..<count => {
      let low = range.get(i * 2).unwrap_or(0.0)
      let high = range.get(i * 2 + 1).unwrap_or(1.0)
      if low.is_nan() ||
        high.is_nan() ||
        low.is_inf() ||
        high.is_inf() ||
        low > high {
        (0.0, 1.0)
      } else {
        (low, high)
      }
    }
  ]
}

///|
fn pdf_icc_clip(
  values : ArrayView[Double],
  ranges : Array[(Double, Double)],
) -> Array[Double] {
  [
    for i in 0..<ranges.length() => {
      let (low, high) = ranges[i]
      let value = values.get(i).unwrap_or(0.0)
      if value.is_nan() {
        0.0.max(low).min(high)
      } else {
        value.max(low).min(high)
      }
    }
  ]
}

///|
#cfg(target="native")
#external
type PdfIccHandle

///|
#cfg(target="native")
extern "C" fn pdf_icc_engine_available() -> Bool = "pdf_icc_available"

///|
#cfg(target="native")
#borrow(bytes)
extern "C" fn pdf_icc_native_open(
  bytes : Bytes,
  length : Int,
  components : Int,
  intent : Int,
) -> PdfIccHandle = "pdf_icc_open"

///|
#cfg(target="native")
#borrow(handle)
extern "C" fn pdf_icc_native_valid(handle : PdfIccHandle) -> Bool = "pdf_icc_valid"

///|
#cfg(target="native")
#borrow(handle, bytes, output)
extern "C" fn pdf_icc_native_convert(
  handle : PdfIccHandle,
  bytes : Bytes,
  length : Int,
  a : Double,
  b : Double,
  c : Double,
  d : Double,
  output : FixedArray[Double],
) -> Bool = "pdf_icc_convert"

///|
#cfg(target="native")
fn pdf_icc_engine_transform(
  bytes : Bytes,
  components : Int,
  intent : Int,
) -> PdfIccTransform? {
  let handle = pdf_icc_native_open(bytes, bytes.length(), components, intent)
  if !pdf_icc_native_valid(handle) {
    return None
  }
  let output : FixedArray[Double] = [0.0, 0.0, 0.0]
  Some({
    convert: values => {
      let converted = pdf_icc_native_convert(
        handle,
        bytes,
        bytes.length(),
        values.get(0).unwrap_or(0.0),
        values.get(1).unwrap_or(0.0),
        values.get(2).unwrap_or(0.0),
        values.get(3).unwrap_or(0.0),
        output,
      )
      if converted {
        (output[0], output[1], output[2])
      } else {
        (0.0 / 0.0, 0.0 / 0.0, 0.0 / 0.0)
      }
    },
  })
}

///|
#cfg(target="js")
#external
type PdfIccHandle

///|
#cfg(target="js")
extern "js" fn pdf_icc_engine_available() -> Bool =
  #| () => !!globalThis.__moonbit_pdf_icc

///|
#cfg(target="js")
extern "js" fn pdf_icc_js_open(
  bytes : Bytes,
  components : Int,
  intent : Int,
) -> PdfIccHandle =
  #| (bytes, components, intent) => globalThis.__moonbit_pdf_icc.open(bytes, components, intent)

///|
#cfg(target="js")
extern "js" fn pdf_icc_js_valid(handle : PdfIccHandle) -> Bool =
  #| handle => handle !== null

///|
#cfg(target="js")
extern "js" fn pdf_icc_js_convert(
  handle : PdfIccHandle,
  a : Double,
  b : Double,
  c : Double,
  d : Double,
  output : FixedArray[Double],
) -> Bool =
  #| (handle, a, b, c, d, output) => handle.convert(a, b, c, d, output)

///|
#cfg(target="js")
fn pdf_icc_engine_transform(
  bytes : Bytes,
  components : Int,
  intent : Int,
) -> PdfIccTransform? {
  let handle = pdf_icc_js_open(bytes, components, intent)
  if !pdf_icc_js_valid(handle) {
    return None
  }
  let output : FixedArray[Double] = [0.0, 0.0, 0.0]
  Some({
    convert: values => {
      let converted = pdf_icc_js_convert(
        handle,
        values.get(0).unwrap_or(0.0),
        values.get(1).unwrap_or(0.0),
        values.get(2).unwrap_or(0.0),
        values.get(3).unwrap_or(0.0),
        output,
      )
      if converted {
        (output[0], output[1], output[2])
      } else {
        (0.0 / 0.0, 0.0 / 0.0, 0.0 / 0.0)
      }
    },
  })
}

///|
#cfg(target="wasm")
fn pdf_icc_engine_available() -> Bool {
  false
}

///|
#cfg(target="wasm-gc")
fn pdf_icc_engine_available() -> Bool {
  false
}

///|
#cfg(target="wasm")
fn pdf_icc_engine_transform(
  _bytes : Bytes,
  _components : Int,
  _intent : Int,
) -> PdfIccTransform? {
  None
}

///|
#cfg(target="wasm-gc")
fn pdf_icc_engine_transform(
  _bytes : Bytes,
  _components : Int,
  _intent : Int,
) -> PdfIccTransform? {
  None
}

///|
fn pdf_icc_intent(name : String) -> Int {
  match name {
    "/Perceptual" | "Perceptual" => 0
    "/Saturation" | "Saturation" => 2
    "/AbsoluteColorimetric" | "AbsoluteColorimetric" => 3
    _ => 1
  }
}

///|
/// Explicitly release active CMM allocations at document close. Retained
/// PdfColourTransform values remain safe and reopen lazily if used again.
pub fn clear_icc_transforms() -> Unit {
  pdf_icc_cache.clear()
  pdf_icc_clear_active()
}

///|
/// Hosts must report alternate-only as fallback capability, not ICC support.
pub fn icc_capability() -> String {
  if pdf_icc_engine_available() {
    "icc-engine"
  } else {
    "alternate-only"
  }
}

///|
#cfg(target="native")
extern "C" fn pdf_icc_clear_active() -> Unit = "pdf_icc_clear_active"

///|
#cfg(target="native")
extern "C" fn pdf_icc_active_count() -> Int = "pdf_icc_active_count"

///|
#cfg(target="native")
extern "C" fn pdf_icc_allocated_bytes() -> Int = "pdf_icc_allocated_bytes"

///|
#cfg(target="js")
extern "js" fn pdf_icc_clear_active() -> Unit =
  #| () => globalThis.__moonbit_pdf_icc?.clearActiveTransforms()

///|
#cfg(target="wasm")
fn pdf_icc_clear_active() -> Unit {
  ()
}

///|
#cfg(target="wasm-gc")
fn pdf_icc_clear_active() -> Unit {
  ()
}

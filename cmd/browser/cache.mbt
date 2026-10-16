///|
priv struct BrowserCachedPage {
  page : @pdf.PdfPageModel
  canvas_program : @engine.PdfCanvasProgram?
  bytes : Int
  used : Int
  accessibility : Json?
  accessibility_bytes : Int
}

///|
let page_cache_bytes : Ref[Int] = Ref(0)

///|
let page_cache_clock : Ref[Int] = Ref(0)

///|
let page_cache_hits : Ref[Int] = Ref(0)

///|
let page_cache_misses : Ref[Int] = Ref(0)

///|
let page_cache_evictions : Ref[Int] = Ref(0)

///|
let accessibility_cache_hits : Ref[Int] = Ref(0)

///|
let accessibility_cache_misses : Ref[Int] = Ref(0)

///|
fn browser_clear_pages() -> Unit {
  page_cache.clear()
  page_cache_bytes.val = 0
  page_cache_clock.val = 0
  page_cache_hits.val = 0
  page_cache_misses.val = 0
  page_cache_evictions.val = 0
  accessibility_cache_hits.val = 0
  accessibility_cache_misses.val = 0
}

///|
fn browser_cached_page(number : Int) -> @pdf.PdfPageModel? {
  page_cache_clock.val += 1
  if page_cache.get(number) is Some({ canvas_program: Some(_), .. }) {
    page_cache_misses.val += 1
    return None
  }
  match page_cache.get(number) {
    Some(entry) => {
      page_cache_hits.val += 1
      page_cache[number] = { ..entry, used: page_cache_clock.val, }
      Some(entry.page)
    }
    None => {
      page_cache_misses.val += 1
      None
    }
  }
}

///|
fn browser_cache_page(
  number : Int,
  page : @pdf.PdfPageModel,
  canvas_program? : @engine.PdfCanvasProgram? = None,
) -> Unit {
  // Serialized UTF-16 bytes plus per-item overhead are a conservative cache
  // estimate, not a measurement of the JS heap or the parsed PDF object store.
  let bytes = browser_json_size(ToJson::to_json(page)) * 2 +
    page.items.length() * 256 +
    page.fonts.length() * 128 +
    canvas_program.map(program => program.estimated_bytes()).unwrap_or(0)
  let budget = 32 * 1024 * 1024
  if bytes > budget {
    return
  }
  if page_cache.get(number) is Some(old) {
    page_cache_bytes.val -= old.bytes
    page_cache.remove(number)
  }
  while page_cache.length() >= 8 || page_cache_bytes.val + bytes > budget {
    let mut oldest : Int? = None
    let mut used = 0x7fffffff
    for key, entry in page_cache {
      if entry.used <= used {
        oldest = Some(key)
        used = entry.used
      }
    }
    guard oldest is Some(key) else { break }
    let entry = page_cache[key]
    page_cache_bytes.val -= entry.bytes
    page_cache.remove(key)
    page_cache_evictions.val += 1
  }
  page_cache[number] = {
    page,
    canvas_program,
    bytes,
    used: page_cache_clock.val,
    accessibility: None,
    accessibility_bytes: 0,
  }
  page_cache_bytes.val += bytes
}

///|
fn browser_page_accessibility(
  number : Int,
  page : @pdf.PdfPageModel,
  program? : @engine.PdfCanvasProgram? = None,
) -> Json {
  if page_cache.get(number) is Some({ accessibility: Some(value), .. }) {
    accessibility_cache_hits.val += 1
    return value
  }
  accessibility_cache_misses.val += 1
  guard current_document.val is Some(document) else { return Json::null() }
  let value = try {
    match program {
      Some(program) => program.accessibility_page_json(document, number, page)
      None => document.accessibility_page_json(number, page_model=Some(page))
    }
  } catch {
    _ => return Json::null()
  }
  guard value is Some(value) else { return Json::null() }
  // Semantic nodes share the page's eviction and invalidation lifetime. Charge
  // serialized data plus node overhead rather than keeping an unbounded map.
  let bytes = browser_json_size(value) * 2 + page.items.length() * 128
  if page_cache_bytes.val + bytes <= 32 * 1024 * 1024 &&
    page_cache.get(number) is Some(entry) {
    page_cache[number] = {
      ..entry,
      bytes: entry.bytes + bytes,
      accessibility: Some(value),
      accessibility_bytes: bytes,
    }
    page_cache_bytes.val += bytes
  }
  value
}

///|
fn browser_clear_page_accessibility() -> Unit {
  for number, entry in page_cache {
    if entry.accessibility is Some(_) {
      page_cache[number] = {
        ..entry,
        bytes: entry.bytes - entry.accessibility_bytes,
        accessibility: None,
        accessibility_bytes: 0,
      }
      page_cache_bytes.val -= entry.accessibility_bytes
    }
  }
}

///|
/// Cache accounting excludes the parsed document and temporary decoding work.
pub fn cache_info() -> String {
  let result : Json = {
    "ok": true,
    "pages": page_cache.length(),
    "estimated_bytes": page_cache_bytes.val,
    "budget_bytes": 32 * 1024 * 1024,
    "max_pages": 8,
    "hits": page_cache_hits.val,
    "misses": page_cache_misses.val,
    "evictions": page_cache_evictions.val,
    "compiled_resources": current_document.val
    .map(document => @engine.canvas_resource_cache_info(document))
    .unwrap_or(Json::null()),
    "accessibility_hits": accessibility_cache_hits.val,
    "accessibility_misses": accessibility_cache_misses.val,
  }
  result.stringify()
}

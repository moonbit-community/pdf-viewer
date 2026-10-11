///|
priv struct BrowserCachedPage {
  page : @pdf.PdfPageModel
  bytes : Int
  used : Int
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
fn browser_clear_pages() -> Unit {
  page_cache.clear()
  page_cache_bytes.val = 0
  page_cache_clock.val = 0
  page_cache_hits.val = 0
  page_cache_misses.val = 0
  page_cache_evictions.val = 0
}

///|
fn browser_cached_page(number : Int) -> @pdf.PdfPageModel? {
  page_cache_clock.val += 1
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
fn browser_cache_page(number : Int, page : @pdf.PdfPageModel) -> Unit {
  // Serialized UTF-16 bytes plus per-item overhead are a conservative cache
  // estimate, not a measurement of the JS heap or the parsed PDF object store.
  let bytes = ToJson::to_json(page).stringify().length() * 2 +
    page.items.length() * 256 +
    page.fonts.length() * 128
  let budget = 32 * 1024 * 1024
  if bytes > budget {
    return
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
  page_cache[number] = { page, bytes, used: page_cache_clock.val, }
  page_cache_bytes.val += bytes
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
  }
  result.stringify()
}

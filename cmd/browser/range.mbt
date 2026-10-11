///|
let current_range : Ref[@pdf.PdfRangeReader?] = Ref(None)

///|
pub fn range_open(header : Bytes, tail : Bytes, length : Int) -> String {
  try {
    let reader = @pdf.open_range_reader(header, tail, length)
    current_range.val = Some(reader)
    current_document.val = None
    browser_clear_pages()
    ({ "ok": true } : Json).stringify()
  } catch {
    error => browser_error_with_code("range-fallback", @debug.to_string(error))
  }
}

///|
pub fn range_section(offset : Int, bytes : Bytes) -> String {
  try {
    guard current_range.val is Some(reader) else {
      return browser_error("No range document")
    }
    reader.install_section(offset, bytes)
    ({ "ok": true } : Json).stringify()
  } catch {
    error => browser_error_with_code("range-fallback", @debug.to_string(error))
  }
}

///|
pub fn range_next_section() -> String {
  guard current_range.val is Some(reader) else {
    return browser_error("No range document")
  }
  let offset : Json = match reader.next_section() {
    Some(offset) => offset.to_json()
    None => Json::null()
  }
  ({ "ok": true, "offset": offset } : Json).stringify()
}

///|
pub fn range_missing(mode : String, number : Int) -> String {
  try {
    guard current_range.val is Some(reader) else {
      return browser_error("No range document")
    }
    ({ "ok": true, "objects": reader.missing(mode, number).to_json() } : Json).stringify()
  } catch {
    error => browser_error_with_code("range-fallback", @debug.to_string(error))
  }
}

///|
pub fn range_object_request(number : Int) -> String {
  guard current_range.val is Some(reader) &&
    reader.object_request(number) is Some((number, start, end)) else {
    return browser_error("Missing range object")
  }
  (
    {
      "ok": true,
      "number": number,
      "start": start,
      "end": end,
      "loaded": reader.object_loaded(number),
    } : Json).stringify()
}

///|
pub fn range_object(number : Int, bytes : Bytes) -> String {
  try {
    guard current_range.val is Some(reader) else {
      return browser_error("No range document")
    }
    reader.install_object(number, bytes)
    ({ "ok": true } : Json).stringify()
  } catch {
    error => browser_error_with_code("range-fallback", @debug.to_string(error))
  }
}

///|
pub fn range_document() -> String {
  try {
    guard current_range.val is Some(reader) else {
      return browser_error("No range document")
    }
    let view = reader.document_view()
    let view = match current_document.val {
      Some(old) => view.with_font_fallbacks(old.font_fallbacks())
      None => view
    }
    if current_document.val is None {
      browser_install_document(view)
    } else {
      // Hydration only adds objects from the same validated source. Completed
      // page models are independent snapshots and remain valid in the bounded
      // page cache, including when their encoded streams have been evicted.
      current_document.val = Some(view)
      ({ "ok": true, "pages": view.page_count() } : Json).stringify()
    }
  } catch {
    error => browser_error_with_code("range-fallback", @debug.to_string(error))
  }
}

///|
pub fn range_cache_info() -> String {
  match current_range.val {
    Some(reader) => reader.cache_info().stringify()
    None => "null"
  }
}

///|
pub fn search_page(
  number : Int,
  query : String,
  case_sensitive : Bool,
  whole_word : Bool,
  diacritic_sensitive : Bool,
) -> String {
  try {
    guard current_document.val is Some(document) else {
      return browser_error("No document open")
    }
    let results = document.search(
      query,
      page=Some(number),
      options=@pdf.pdf_search_options(
        case_sensitive~,
        whole_word~,
        diacritic_sensitive~,
      ),
    )
    ({ "ok": true, "results": results.to_json() } : Json).stringify()
  } catch {
    error => browser_error(@debug.to_string(error))
  }
}

///|
pub fn range_object_dependencies(bytes : Bytes) -> String {
  try {
    guard current_range.val is Some(reader) else {
      return browser_error("No range document")
    }
    (
      { "ok": true, "objects": reader.object_dependencies(bytes).to_json() } :
      Json).stringify()
  } catch {
    error => browser_error_with_code("range-fallback", @debug.to_string(error))
  }
}

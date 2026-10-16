///|
let current_document : Ref[@pdf.PdfViewerDocument?] = Ref(None)

///|
let page_cache : Map[Int, BrowserCachedPage] = Map([])

///|
/// JS Bytes are Uint8Array. Read the document once and cache page models so
/// toolbar changes do not repeatedly decode the PDF or its embedded fonts.
pub fn open_pdf(bytes : Bytes) -> String {
  current_range.val = None
  try {
    let document = @pdf.open_document(bytes)
    browser_install_document(document)
  } catch {
    @core.SoftError(message) if message == "PDF password authentication failed" =>
      browser_error_with_code(
        "password-required", "This PDF requires a password",
      )
    error => browser_error_with_code("document-error", @debug.to_string(error))
  }
}

///|
/// Retry an encrypted document with a user or owner password. Password bytes stay in
/// the browser bridge and are never included in the document status JSON.
pub fn open_pdf_with_password(bytes : Bytes, password : Bytes) -> String {
  current_range.val = None
  try {
    let document = @pdf.open_document_with_passwords(
      bytes,
      user_password=Some(password),
      owner_password=Some(password),
    )
    browser_install_document(document)
  } catch {
    @core.SoftError(message) if message == "PDF password authentication failed" =>
      browser_error_with_code(
        "password-invalid", "The PDF password is incorrect",
      )
    error => browser_error_with_code("document-error", @debug.to_string(error))
  }
}

///|
/// Apply host font-family replacements to the open document. The input is a
/// JSON array of `{ pdf_name, family, weight?, style? }` objects. Only CSS
/// family metadata crosses this bridge; the host remains responsible for
/// resolving an installed or otherwise licensed font.
pub fn set_font_fallbacks(fallbacks_json : String) -> String {
  guard current_document.val is Some(document) else {
    return browser_error_with_code("document-closed", "No document open")
  }
  let fallbacks = match browser_parse_font_fallbacks(fallbacks_json) {
    Some(value) => value
    None =>
      return browser_error(
        "Font fallbacks must be a JSON array with pdf_name and family strings",
      )
  }
  current_document.val = Some(document.with_font_fallbacks(fallbacks))
  browser_clear_pages()
  let result : Json = { "ok": true, "count": fallbacks.length() }
  result.stringify()
}

///|
fn browser_parse_font_fallbacks(
  source : String,
) -> Array[@pdf.PdfFontFallback]? {
  let value = @json.parse(source) catch { _ => return None }
  guard value is Json::Array(entries) else { return None }
  let output : Array[@pdf.PdfFontFallback] = []
  for entry in entries {
    guard entry is Json::Object(fields) else { return None }
    let pdf_name = match fields.get("pdf_name") {
      Some(Json::String(value)) if !value.is_empty() => value
      _ => return None
    }
    let family = match fields.get("family") {
      Some(Json::String(value)) if !value.is_empty() => value
      _ => return None
    }
    let weight = match fields.get("weight") {
      Some(Json::String(value)) => Some(value)
      Some(Json::Null) | None => None
      _ => return None
    }
    let style = match fields.get("style") {
      Some(Json::String(value)) => Some(value)
      Some(Json::Null) | None => None
      _ => return None
    }
    output.push({ pdf_name, family, weight, style, })
  }
  Some(output)
}

///|
fn browser_install_document(document : @pdf.PdfViewerDocument) -> String {
  editor_original.val = None
  current_document.val = Some(document)
  browser_clear_pages()
  let labels = document.page_labels() catch { _ => [] }
  let info : Json = {
    "ok": true,
    "pages": document.page_count(),
    "labels": labels,
  }
  info.stringify()
}

///|
fn browser_error(message : String) -> String {
  let result : Json = { "ok": false, "error": message }
  result.stringify()
}

///|
fn browser_error_with_code(code : String, message : String) -> String {
  let result : Json = { "ok": false, "code": code, "error": message }
  result.stringify()
}

///|
pub fn close_pdf() -> Unit {
  editor_original.val = None
  current_range.val = None
  current_document.val = None
  browser_clear_pages()
}

///|
/// Return document-level navigation and metadata without exposing the
/// pdflite implementation types to JavaScript.
pub fn document_info() -> String {
  guard current_document.val is Some(document) else {
    return browser_error_with_code("document-closed", "No document open")
  }
  let labels = document.page_labels() catch { _ => [] }
  let outline = document.outline_navigation_json() catch { _ => [] }
  let info = document.info_json() catch { _ => {} }
  let attachments = document.attachment_manifest_json() catch { _ => [] }
  let metadata = document.metadata_bytes() catch { _ => None }
  let result : Json = {
    "ok": true,
    "labels": labels,
    "outline": outline,
    "info": info,
    "attachments": attachments,
    "layers": (document.optional_content_layers_json() catch { _ => None }).unwrap_or(
      Json::null(),
    ),
    "metadata": {
      "available": metadata is Some(_),
      "size": match metadata {
        Some(bytes) => bytes.length()
        None => 0
      },
    },
  }
  result.stringify()
}

///|
/// Download one attachment as base64 so the browser can create a local Blob.
pub fn download_attachment(index : Int) -> String {
  try {
    guard current_document.val is Some(document) else {
      return browser_error_with_code("document-closed", "No document open")
    }
    guard document.attachment_bytes(index) is Some(bytes) else {
      return browser_error("Attachment does not contain downloadable bytes")
    }
    let result : Json = { "ok": true, "data": @base64.encode(bytes) }
    result.stringify()
  } catch {
    error => browser_error(@debug.to_string(error))
  }
}

///|
/// Download the embedded XMP packet as base64.
pub fn download_metadata() -> String {
  try {
    guard current_document.val is Some(document) else {
      return browser_error_with_code("document-closed", "No document open")
    }
    guard document.metadata_bytes() is Some(bytes) else {
      return browser_error("Document has no XMP metadata")
    }
    let result : Json = { "ok": true, "data": @base64.encode(bytes) }
    result.stringify()
  } catch {
    error => browser_error(@debug.to_string(error))
  }
}

///|
fn browser_page(number : Int) -> @pdf.PdfPageModel? raise {
  if browser_cached_page(number) is Some(page) {
    return Some(page)
  }
  guard current_document.val is Some(document) else { return None }
  let page = document.page(number).map(page => browser_page_fonts(number, page))
  if page is Some(page) {
    browser_cache_page(number, page)
  }
  page
}

///|
fn browser_canvas_page(
  number : Int,
) -> (@pdf.PdfPageModel, @engine.PdfCanvasProgram?)? raise {
  page_cache_clock.val += 1
  if page_cache.get(number) is Some(entry) {
    page_cache_hits.val += 1
    page_cache[number] = { ..entry, used: page_cache_clock.val, }
    return Some((entry.page, entry.canvas_program))
  }
  page_cache_misses.val += 1
  guard current_document.val is Some(document) else { return None }
  guard @engine.prepare_canvas_page(document, number) is Some((page, program)) else {
    return None
  }
  let page = browser_page_fonts(number, page)
  browser_cache_page(number, page, canvas_program=Some(program))
  Some((page, Some(program)))
}

///|
fn browser_text_page(number : Int) -> @pdf.PdfPageModel? raise {
  if page_cache.get(number) is Some(entry) {
    page_cache_clock.val += 1
    page_cache_hits.val += 1
    page_cache[number] = { ..entry, used: page_cache_clock.val, }
    return Some(entry.page)
  }
  browser_page(number)
}

///|
fn browser_page_fonts(
  number : Int,
  page : @pdf.PdfPageModel,
) -> @pdf.PdfPageModel {
  // Display and print SVGs share the document CSS font namespace.
  let fonts = page.fonts.map(font => {
    if font.data_uri is Some(_) &&
      font.format != "cff" &&
      font.format != "type1" {
      { ..font, family: "pdf-page-\{number}-" + font.family, }
    } else {
      font
    }
  })
  { ..page, fonts, }
}

///|
/// Canvas readers can omit the legacy SVG document without changing the
/// Canvas, selection, annotation, editing or accessibility payloads.
pub fn render_page(
  number : Int,
  scale : Double,
  rotation : Int,
  omit_svg? : Bool = false,
  compiled_canvas? : Bool = false,
  text_runs? : Bool = false,
) -> String {
  browser_render_page(
    number,
    scale,
    rotation,
    false,
    omit_svg,
    compiled_canvas~,
    text_runs~,
  )
}

///|
fn browser_render_page(
  number : Int,
  scale : Double,
  rotation : Int,
  printing : Bool,
  omit_svg : Bool,
  compiled_canvas? : Bool = false,
  text_runs? : Bool = false,
) -> String {
  if scale <= 0.0 || scale.is_nan() || scale.is_inf() {
    return browser_error_with_code(
      "invalid-scale", "Scale must be finite and positive",
    )
  }
  if rotation % 90 != 0 {
    return browser_error_with_code(
      "invalid-rotation", "Rotation must be a multiple of 90",
    )
  }
  try {
    let prepared = if printing {
      current_document.val
      .bind(document => document.page(number, optional_content_intent=Print))
      .map(page => (browser_page_fonts(number, page), None))
    } else if omit_svg && compiled_canvas {
      browser_canvas_page(number)
    } else {
      browser_page(number).map(page => (page, None))
    }
    guard prepared is Some((page, program)) else {
      return browser_error_with_code(
        "page-missing", "No document or page does not exist",
      )
    }
    let page = if printing { page.with_print_annotations() } else { page }
    let rotation = page.rotation + rotation
    let svg = if omit_svg { "" } else { page.render_svg(rotation~, scale~) }
    let result : Json = {
      "ok": true,
      "page": number,
      "svg": svg,
      "canvas": match program {
        Some(program) => program.canvas_plan(page, scale, rotation, text_runs~)
        None => page.canvas_plan(scale~, rotation~)
      },
      "layer": match program {
        Some(program) => program.text_layer(page, scale, rotation)
        None => page.text_layer(scale~, rotation~)
      },
      "editor": if printing {
        Json::array([])
      } else {
        current_document.val
        .bind(document => document.editor_page_json(number))
        .unwrap_or(Json::array([]))
      },
      "annotations": if printing {
        Json::array([])
      } else {
        match current_document.val {
          Some(document) =>
            document.annotation_layer_json(number).unwrap_or(Json::array([]))
          None => Json::array([])
        }
      },
      "accessibility": if printing {
        Json::null()
      } else {
        browser_page_accessibility(number, page, program~)
      },
      "intent": if printing {
        "print"
      } else {
        "display"
      },
    }
    result.stringify()
  } catch {
    error => browser_error_with_code("render-error", @debug.to_string(error))
  }
}

///|
pub fn select_text(
  number : Int,
  start_item : Int,
  start_offset : Int,
  end_item : Int,
  end_offset : Int,
) -> String {
  try {
    guard browser_text_page(number) is Some(page) else {
      return browser_error_with_code(
        "page-missing", "No document or page does not exist",
      )
    }
    guard page.select_text(start_item, start_offset, end_item, end_offset)
      is Some(selection) else {
      return browser_error_with_code("invalid-range", "Invalid text range")
    }
    let result : Json = { "ok": true, "selection": selection }
    result.stringify()
  } catch {
    error => browser_error(@debug.to_string(error))
  }
}

///|
/// Search the currently open document and return geometry-rich matches for
/// the browser search toolbar. Result offsets remain UTF-16 source offsets;
/// the browser uses page and item indices to scroll and highlight each match.
pub fn search_pdf(
  query : String,
  case_sensitive : Bool,
  whole_word : Bool,
  diacritic_sensitive : Bool,
) -> String {
  try {
    guard current_document.val is Some(document) else {
      return browser_error_with_code("document-closed", "No document open")
    }
    let results = document.search(
      query,
      options=@pdf.pdf_search_options(
        case_sensitive~,
        whole_word~,
        diacritic_sensitive~,
      ),
    )
    let result : Json = {
      "ok": true,
      "results": Json::array([ for value in results => ToJson::to_json(value) ]),
    }
    result.stringify()
  } catch {
    error => browser_error(@debug.to_string(error))
  }
}

///|
pub fn process_cmyk_to_rgb(
  cyan : Double,
  magenta : Double,
  yellow : Double,
  black : Double,
) -> Array[Double] {
  @pdf.process_cmyk_to_rgb(cyan, magenta, yellow, black)
}

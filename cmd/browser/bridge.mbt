///|
let current_document : Ref[@pdf.PdfViewerDocument?] = Ref(None)

///|
let page_cache : Map[Int, @pdf.PdfPageModel] = Map([])

///|
/// JS Bytes are Uint8Array. Read the document once and cache page models so
/// toolbar changes do not repeatedly decode the PDF or its embedded fonts.
pub fn open_pdf(bytes : Bytes) -> String {
  try {
    let document = @pdf.open_document(bytes)
    current_document.val = Some(document)
    page_cache.clear()
    let labels = document.page_labels() catch { _ => [] }
    let info : Json = { "ok": true, "pages": document.page_count(), "labels": labels, }
    info.stringify()
  } catch {
    error => browser_error(@debug.to_string(error))
  }
}

///|
fn browser_error(message : String) -> String {
  let result : Json = { "ok": false, "error": message, }
  result.stringify()
}

///|
pub fn close_pdf() -> Unit {
  current_document.val = None
  page_cache.clear()
}

///|
fn browser_page(number : Int) -> @pdf.PdfPageModel? raise {
  if page_cache.get(number) is Some(page) { return Some(page) }
  guard current_document.val is Some(document) else { return None }
  let page = document.page(number).map(page => {
    // SVG @font-face rules share the document CSS namespace. Identical PDF
    // resource names on separate pages must not replace each other's fonts.
    let fonts = page.fonts.map(font => {
      if font.data_uri is Some(_) && font.format != "cff" && font.format != "type1" {
        { ..font, family: "pdf-page-\{number}-" + font.family, }
      } else { font }
    })
    { ..page, fonts, }
  })
  if page is Some(page) { page_cache[number] = page }
  page
}

///|
pub fn render_page(number : Int, scale : Double, rotation : Int) -> String {
  if scale <= 0.0 || scale.is_nan() || scale.is_inf() {
    return browser_error("Scale must be finite and positive")
  }
  if rotation % 90 != 0 { return browser_error("Rotation must be a multiple of 90") }
  try {
    guard browser_page(number) is Some(page) else {
      return browser_error("No document or page does not exist")
    }
    let rotation = page.rotation + rotation
    let svg = page.render_svg(rotation~, scale~)
    let result : Json = {
      "ok": true, "page": number, "svg": svg,
      "layer": page.text_layer(scale~, rotation~),
    }
    result.stringify()
  } catch {
    error => browser_error(@debug.to_string(error))
  }
}

///|
pub fn select_text(
  number : Int, start_item : Int, start_offset : Int, end_item : Int, end_offset : Int,
) -> String {
  try {
    guard browser_page(number) is Some(page) else {
      return browser_error("No document or page does not exist")
    }
    guard page.select_text(start_item, start_offset, end_item, end_offset) is Some(selection) else {
      return browser_error("Invalid text range")
    }
    let result : Json = { "ok": true, "selection": selection, }
    result.stringify()
  } catch {
    error => browser_error(@debug.to_string(error))
  }
}

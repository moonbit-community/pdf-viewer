///|
/// Page geometry only: do not decode off-screen content to reserve its space.
pub fn page_layouts() -> String {
  guard current_document.val is Some(document) else {
    return browser_error_with_code("document-closed", "No document open")
  }
  let layouts : Array[Json] = []
  for number in 1..<=document.page_count() {
    guard document.page_viewport(number) is Some(viewport) else { continue }
    layouts.push({
      "page": number,
      "width": viewport.width,
      "height": viewport.height,
      "rotation": viewport.rotation,
    })
  }
  let result : Json = { "ok": true, "layouts": layouts }
  result.stringify()
}

///|
/// Select text on an unloaded page. A negative item opens that end of the
/// range to the first/last logical glyph; an empty page returns null.
pub fn select_page_text(
  number : Int,
  start_item : Int,
  start_offset : Int,
  end_item : Int,
  end_offset : Int,
) -> String {
  try {
    guard browser_page(number) is Some(page) else {
      return browser_error_with_code("page-missing", "Page does not exist")
    }
    let items = page.text_layer().items
    if items.is_empty() {
      let result : Json = { "ok": true, "selection": Json::null() }
      return result.stringify()
    }
    let first = items[0]
    let last = items[items.length() - 1]
    let start_item = if start_item < 0 { first.item_index } else { start_item }
    let start_offset = if start_item == first.item_index && start_offset < 0 {
      0
    } else {
      start_offset
    }
    let end_item = if end_item < 0 { last.item_index } else { end_item }
    let end_offset = if end_item == last.item_index && end_offset < 0 {
      last.text.length()
    } else {
      end_offset
    }
    if start_item == end_item && start_offset == end_offset {
      for item in items {
        if item.item_index == start_item &&
          start_offset >= 0 &&
          start_offset <= item.text.length() {
          let result : Json = { "ok": true, "selection": Json::null() }
          return result.stringify()
        }
      }
    }
    guard page.select_text(start_item, start_offset, end_item, end_offset)
      is Some(selection) else {
      return browser_error_with_code("invalid-range", "Invalid text range")
    }
    let result : Json = {
      "ok": true,
      "selection": selection,
      "start": { "page": number, "item": start_item, "offset": start_offset },
      "end": { "page": number, "item": end_item, "offset": end_offset },
    }
    result.stringify()
  } catch {
    error => browser_error(@debug.to_string(error))
  }
}

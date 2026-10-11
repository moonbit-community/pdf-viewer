///|
pub fn optional_content_info() -> String {
  guard current_document.val is Some(document) else {
    return browser_error_with_code("document-closed", "No document open")
  }
  (
    {
      "ok": true,
      "layers": document.optional_content_layers_json().unwrap_or(Json::null()),
    } : Json).stringify() catch {
    error => browser_error_with_code("layer-error", @debug.to_string(error))
  }
}

///|
fn browser_install_layer_state(
  document : @pdf.PdfViewerDocument,
) -> String raise @core.PdfError {
  let result = (
    {
      "ok": true,
      "layers": document.optional_content_layers_json().unwrap_or(Json::null()),
    } : Json).stringify()
  current_document.val = Some(document)
  if editor_original.val is Some(original) &&
    document.optional_content_state() is Some(selected) {
    editor_original.val = Some(original.with_optional_content_state(selected))
  }
  browser_clear_pages()
  result
}

///|
pub fn set_optional_content_visibility(number : Int, visible : Bool) -> String {
  guard current_document.val is Some(document) else {
    return browser_error_with_code("document-closed", "No document open")
  }
  browser_install_layer_state(
    document.with_optional_content_visibility(number, visible),
  ) catch {
    error => browser_error_with_code("layer-error", @debug.to_string(error))
  }
}

///|
/// `-1` selects the document's default configuration and resets user toggles.
pub fn set_optional_content_config(index : Int) -> String {
  guard current_document.val is Some(document) else {
    return browser_error_with_code("document-closed", "No document open")
  }
  browser_install_layer_state(
    document.with_optional_content_config(
      if index == -1 {
        None
      } else {
        Some(index)
      },
    ),
  ) catch {
    error => browser_error_with_code("layer-error", @debug.to_string(error))
  }
}

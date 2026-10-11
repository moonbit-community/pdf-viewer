///|
let editor_original : Ref[@pdf.PdfViewerDocument?] = Ref(None)

///|
pub fn prepare_editor(bytes : Bytes) -> String {
  let fallbacks = current_document.val
    .map(document => document.font_fallbacks())
    .unwrap_or([])
  let result = open_pdf(bytes)
  if current_document.val is Some(document) && !fallbacks.is_empty() {
    current_document.val = Some(document.with_font_fallbacks(fallbacks))
  }
  result
}

///|
pub fn editor_info() -> String {
  guard current_document.val is Some(document) else {
    return browser_error_with_code("document-closed", "No document open")
  }
  let encrypted = document.document.saved_encryption is Some(_) ||
    document.document.is_encrypted()
  (
    {
      "ok": true,
      "editable": !encrypted,
      "reason": if encrypted {
        "暂不支持保存加密 PDF 的编辑"
      } else {
        ""
      },
    } : Json).stringify()
}

///|
/// Apply an entire undo/redo snapshot against the same baseline.
pub fn apply_edits(changes : String) -> String {
  guard current_document.val is Some(document) else {
    return browser_error_with_code("document-closed", "No document open")
  }
  try {
    let original = editor_original.val.unwrap_or(document)
    let changes = @json.parse(changes)
    let edited = original.with_editor_changes(changes)
    editor_original.val = Some(original)
    current_document.val = Some(edited)
    browser_clear_pages()
    ({ "ok": true } : Json).stringify()
  } catch {
    error => browser_error_with_code("edit-error", @debug.to_string(error))
  }
}

///|
pub fn save_pdf() -> String {
  guard current_document.val is Some(document) else {
    return browser_error_with_code("document-closed", "No document open")
  }
  ({ "ok": true, "data": @base64.encode(document.save_bytes()) } : Json).stringify() catch {
    error => browser_error_with_code("save-error", @debug.to_string(error))
  }
}

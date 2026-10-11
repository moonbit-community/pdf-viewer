///|
let editor_original : Ref[@pdf.PdfViewerDocument?] = Ref(None)

///|
pub fn prepare_editor(bytes : Bytes) -> String {
  let fallbacks = current_document.val
    .map(document => document.font_fallbacks())
    .unwrap_or([])
  let selected = current_document.val.bind(document => {
    document.optional_content_state()
  })
  let result = open_pdf(bytes)
  if current_document.val is Some(document) && !fallbacks.is_empty() {
    current_document.val = Some(document.with_font_fallbacks(fallbacks))
  }
  if current_document.val is Some(document) && selected is Some(selected) {
    current_document.val = Some(document.with_optional_content_state(selected))
  }
  result
}

///|
pub fn editor_info() -> String {
  guard current_document.val is Some(document) else {
    return browser_error_with_code("document-closed", "No document open")
  }
  let permissions = document.editor_permissions()
  (
    {
      "ok": true,
      "editable": permissions.annotations || permissions.forms,
      "annotations": permissions.annotations,
      "forms": permissions.forms,
      "encrypted": permissions.encrypted,
      "reason": if !permissions.annotations && !permissions.forms {
        "此 PDF 的权限禁止批注编辑和表单填写"
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
  (
    {
      "ok": true,
      "data": @base64.encode(
        document.save_bytes(aes_iv_provider=(_, _, _) => editor_random_iv()),
      ),
    } : Json).stringify() catch {
    error => browser_error_with_code("save-error", @debug.to_string(error))
  }
}

///|
extern "js" fn editor_random_iv() -> Bytes =
  #| () => globalThis.crypto.getRandomValues(new Uint8Array(16))

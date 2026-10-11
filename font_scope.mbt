///|
/// Register resources from the active font binding, rather than resolving a
/// name again after entering another Form resource dictionary.
priv struct PdfPageFontScope {
  fonts : Array[PdfFontResource]
  sources : Array[(String, @syntax.PdfObject?)]
  fallbacks : Array[PdfFontFallback]
}

///|
fn pdf_page_font_name(
  document : @pdflite.PdfDocument,
  font : @pdflite.PdfFont,
  object : @syntax.PdfObject?,
  name : String,
  scope : PdfPageFontScope,
) -> String {
  for index, source in scope.sources {
    if source == (name, object) {
      return scope.fonts[index].name
    }
  }
  let registered_name = if scope.fonts.any(font => font.name == name) {
    name + "@font" + scope.fonts.length().to_string()
  } else {
    name
  }
  let base_name = match object {
    Some(object) =>
      match
        pdf_direct_for_viewer(document, object)
        .bind(object => object.lookup_immediate(pdf_name_key("/BaseFont")))
        .bind(value => pdf_direct_for_viewer(document, value)) {
        Some(@syntax.PdfNameObject(base)) => pdf_annotation_name_text(base)
        _ => name
      }
    None => name
  }
  let bytes = pdf_viewer_ttf_embedded_bytes(document, font) catch { _ => None }
  let fallback = pdf_font_fallback_for(scope.fallbacks[:], name, base_name)
  scope.sources.push((name, object))
  scope.fonts.push(
    pdf_font_resource_from_bytes(
      registered_name,
      base_name,
      bytes,
      registered_name,
      fallback~,
    ),
  )
  registered_name
}

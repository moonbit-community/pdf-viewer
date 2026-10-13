///|
/// Resolve legacy RoleMap and PDF 2 namespace-scoped roles with the same
/// bounded cycle protection. Unknown namespaces retain their original tag.
fn pdf_accessibility_role(
  document : @pdflite.PdfDocument,
  dictionary : @syntax.PdfObject,
  legacy : @syntax.PdfObject,
) -> (String, String?) {
  let mut tag = match document.lookup_direct(pdf_name_key("/S"), dictionary) {
    Some(@syntax.PdfNameObject(name)) => pdf_accessibility_name(name)
    _ => "NonStruct"
  }
  let mut role_namespace = document
    .lookup_direct(pdf_name_key("/NS"), dictionary)
    .unwrap_or(@syntax.PdfNull)
  let visited : Map[String, Bool] = Map([])
  for _ in 0..<16 {
    let uri = pdf_annotation_layer_string(document, role_namespace, "/NS").unwrap_or(
      "",
    )
    let key = uri + ":" + tag
    if visited.contains(key) {
      break
    }
    visited[key] = true
    let mapping = if role_namespace == @syntax.PdfNull {
      legacy
    } else {
      document
      .lookup_direct(pdf_name_key("/RoleMapNS"), role_namespace)
      .unwrap_or(@syntax.PdfNull)
    }
    match document.lookup_direct(pdf_name_key("/" + tag), mapping) {
      Some(@syntax.PdfNameObject(name)) => tag = pdf_accessibility_name(name)
      Some(@syntax.PdfArray([@syntax.PdfNameObject(name), target])) => {
        tag = pdf_accessibility_name(name)
        role_namespace = document.direct(target)
      }
      _ => break
    }
  }
  (tag, pdf_annotation_layer_string(document, role_namespace, "/NS"))
}

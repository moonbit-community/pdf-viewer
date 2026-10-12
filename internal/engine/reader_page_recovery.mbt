///|
/// A skipped page-tree branch. Resource paths refer to the original traversal,
/// and object_number identifies the requested PDF node when available.
pub(all) struct PdfReaderDiagnostic {
  resource : String
  object_number : Int?
  message : String
} derive(Eq, Debug, ToJson)

///|
pub fn PdfViewerDocument::reader_diagnostics(
  self : PdfViewerDocument,
) -> Array[PdfReaderDiagnostic] {
  self.reader_observations.copy()
}

///|
fn pdf_page_tree_recovery_node(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  path : String,
  parents : ArrayView[Int],
  depth : Int,
  budget : Ref[Int],
  changes : Map[Int, @syntax.PdfObject],
  diagnostics : Array[PdfReaderDiagnostic],
) -> (@syntax.PdfObject, Int)? raise @core.PdfError {
  let number = pdf_text_object_number(object)
  fn skipped(message : String) -> (@syntax.PdfObject, Int)? {
    diagnostics.push({ resource: path, object_number: number, message, })
    None
  }
  budget.val -= 1
  if depth > 256 || budget.val < 0 {
    return skipped("Page tree traversal limit")
  }
  if number is Some(number) && parents.contains(number) {
    return skipped("Page tree cycle")
  }
  guard pdf_direct_for_viewer(document, object)
    is Some(@syntax.PdfDictionary(_) as direct) else {
    return skipped("Page tree node unavailable")
  }
  for
    key in [
      "/Type", "/Resources", "/MediaBox", "/CropBox", "/Rotate", "/Contents", "/Kids",
    ] {
    if direct.lookup_immediate(pdf_name_key(key)) is Some(value) {
      guard pdf_direct_for_viewer(document, value) is Some(value) else {
        return skipped("Reference unavailable at " + key)
      }
      if (key == "/Contents" || key == "/MediaBox" || key == "/CropBox") &&
        value is @syntax.PdfArray(values) {
        for index, value in values {
          if pdf_direct_for_viewer(document, value) is None {
            return skipped(
              "Reference unavailable at " + key + "[" + index.to_string() + "]",
            )
          }
        }
      }
    }
  }
  let kind = direct
    .lookup_immediate(pdf_name_key("/Type"))
    .bind(value => pdf_direct_for_viewer(document, value))
  let kids = direct
    .lookup_immediate(pdf_name_key("/Kids"))
    .bind(value => pdf_direct_for_viewer(document, value))
  let branch = kind == Some(@syntax.PdfNameObject(pdf_name_key("/Pages"))) ||
    (kind is None && kids is Some(@syntax.PdfArray(_)))
  if !branch {
    return Some((object, 1))
  }
  guard kids is Some(@syntax.PdfArray(kids)) else {
    return skipped("Page tree Kids unavailable")
  }
  let ancestors : Array[Int] = [ for number in parents => number ]
  if number is Some(number) {
    ancestors.push(number)
  }
  let kept : Array[@syntax.PdfObject] = []
  let mut pages = 0
  for index, kid in kids {
    if pdf_page_tree_recovery_node(
        document,
        kid,
        path + "/Kids[" + index.to_string() + "]",
        ancestors[:],
        depth + 1,
        budget,
        changes,
        diagnostics,
      )
      is Some((kid, count)) {
      kept.push(kid)
      pages += count
    }
  }
  if pages == 0 {
    return None
  }
  let normalized = direct
    .add_dict_entry(pdf_name_key("/Kids"), @syntax.PdfArray(kept))
    .add_dict_entry(pdf_name_key("/Count"), @syntax.PdfInteger(pages))
  match number {
    Some(number) => {
      changes[number] = normalized
      Some((object, pages))
    }
    None => Some((normalized, pages))
  }
}

///|
/// Retain good pages from a damaged tree, then let the dependency materialize
/// inherited attributes. Only page-tree dictionaries change in a separate
/// object store; font/content bytes retain their original backing and identity.
fn pdf_page_tree_recovery_document(
  document : @pdflite.PdfDocument,
) -> (@pdflite.PdfDocument, Array[PdfReaderDiagnostic]) raise @core.PdfError {
  let catalog = pdf_direct_for_viewer(
    document,
    @syntax.PdfIndirect(document.root()),
  ).unwrap_or(@syntax.PdfNull)
  guard catalog.lookup_immediate(pdf_name_key("/Pages")) is Some(pages) else {
    raise @core.PageTreeExpected
  }
  let changes : Map[Int, @syntax.PdfObject] = Map([])
  let diagnostics : Array[PdfReaderDiagnostic] = []
  guard pdf_page_tree_recovery_node(
      document,
      pages,
      "/Root/Pages",
      [],
      0,
      Ref(131072),
      changes,
      diagnostics,
    )
    is Some((pages, _)) else {
    raise @core.PageTreeExpected
  }
  let shadow = document.copy()
  for (number, object) in changes {
    shadow.add_object_given_number(number, object)
  }
  shadow.add_object_given_number(
    document.root(),
    catalog.add_dict_entry(pdf_name_key("/Pages"), pages),
  )
  pdf_validate_page_tree_for_viewer(shadow)
  (shadow, diagnostics)
}

///|
fn pdf_page_tree_for_viewer(
  document : @pdflite.PdfDocument,
) -> (@pdflite.PdfDocument, Array[@page.PdfPage], Array[PdfReaderDiagnostic]) raise @core.PdfError {
  try {
    pdf_validate_page_tree_for_viewer(document)
    (document, document.pages_of_pagetree(), [])
  } catch {
    original => {
      let (shadow, diagnostics) = pdf_page_tree_recovery_document(document) catch {
        _ => raise original
      }
      (shadow, shadow.pages_of_pagetree(), diagnostics)
    }
  }
}

///|
/// Follow reference aliases without calling the reader's unbounded direct().
/// Normal parent/child object graphs are not reference-alias cycles.
fn pdf_direct_for_viewer(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> @syntax.PdfObject? {
  let seen : Map[Int, Bool] = Map([])
  let mut current = object
  for _ in 0..<64 {
    match current {
      @syntax.PdfIndirect(number) => {
        if seen.contains(number) {
          return None
        }
        seen[number] = true
        current = document.lookup_object_or_null(number)
      }
      _ => return Some(current)
    }
  }
  None
}

///|
/// The high-level reader probes the page tree before returning. Its recursion
/// limit exceeds the JavaScript stack on cyclic input, so use its strict xref
/// reader first when a catalog is available. Reconstruction still belongs to
/// pdflite; our bounded page-tree validation runs before materialization.
fn pdf_reader_strict_document_for_viewer(
  bytes : Bytes,
) -> @pdflite.PdfDocument? {
  let document = @pdflite.pdf_read_classic_document_from_bytes(bytes) catch {
    _ => return None
  }
  let catalog = pdf_direct_for_viewer(
    document,
    @syntax.PdfIndirect(document.root()),
  )
  if catalog.bind(catalog => catalog.lookup_immediate(pdf_name_key("/Pages")))
    is Some(_) {
    Some(document)
  } else {
    None
  }
}

///|
/// Validate only the reader's page-tree traversal boundary. Page records and
/// inherited resources/boxes/rotation are still materialized by pdflite.
/// A located PDF error replaces VM stack overflow on cyclic or very deep trees.
fn pdf_validate_page_tree_for_viewer(
  document : @pdflite.PdfDocument,
) -> Unit raise @core.PdfError {
  let root = @syntax.PdfIndirect(document.root())
  let catalog = pdf_direct_for_viewer(document, root).unwrap_or(@syntax.PdfNull)
  let pages = catalog.lookup_immediate(pdf_name_key("/Pages"))
  guard pages is Some(pages) else {
    raise @core.SoftError(
      "Page tree unavailable at /Root/Pages (object " +
      document.root().to_string() +
      ")",
    )
  }
  let pending : Array[(@syntax.PdfObject, String, Array[Int], Int)] = [
    (pages, "/Root/Pages", [], 0),
  ]
  let mut visits = 0
  while pending.pop() is Some((object, path, parents, depth)) {
    visits += 1
    let number = pdf_text_object_number(object)
    let location = path +
      number.map(number => " (object " + number.to_string() + ")").unwrap_or("")
    if depth > 256 || visits > 131072 {
      raise @core.SoftError("Page tree limit at " + location)
    }
    if number is Some(number) && parents.contains(number) {
      raise @core.SoftError("Page tree cycle at " + location)
    }
    let direct = pdf_direct_for_viewer(document, object).unwrap_or(
      @syntax.PdfNull,
    )
    guard direct is @syntax.PdfDictionary(_) else {
      raise @core.SoftError("Page tree node unavailable at " + location)
    }
    let next_parents = parents.copy()
    if number is Some(number) {
      next_parents.push(number)
    }
    for
      key in [
        "/Type", "/Resources", "/MediaBox", "/CropBox", "/Rotate", "/Contents", "/Kids",
      ] {
      if direct.lookup_immediate(pdf_name_key(key)) is Some(value) {
        guard pdf_direct_for_viewer(document, value) is Some(value) else {
          raise @core.SoftError("Reference cycle at " + location + key)
        }
        if (key == "/Contents" || key == "/MediaBox" || key == "/CropBox") &&
          value is @syntax.PdfArray(values) {
          for index, value in values {
            if pdf_direct_for_viewer(document, value) is None {
              raise @core.SoftError(
                "Reference cycle at " +
                location +
                key +
                "[" +
                index.to_string() +
                "]",
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
    if kind == Some(@syntax.PdfNameObject(pdf_name_key("/Pages"))) ||
      (kind is None && kids is Some(@syntax.PdfArray(_))) {
      guard kids is Some(@syntax.PdfArray(kids)) else {
        raise @core.SoftError(
          "Page tree Kids unavailable at " + location + "/Kids",
        )
      }
      for index in 0..<kids.length() {
        pending.push(
          (
            kids[index],
            path + "/Kids[" + index.to_string() + "]",
            next_parents,
            depth + 1,
          ),
        )
      }
    }
  }
}

///|
/// Collapse the library's code-point permutation to PDF glyph/source items.
/// A glyph with a multi-scalar ToUnicode mapping is kept intact. A permutation
/// that would split it, or erase a formatting-only source item, is unavailable.
fn pdf_text_bidi_permutation(
  items : ArrayView[PdfTextItem],
  direction : @bidi.Direction,
) -> Array[Int]? {
  let text = StringBuilder()
  let owners : Array[Int] = []
  for index, item in items {
    text.write_string(item.text)
    for _ in item.text.iter() {
      owners.push(index)
    }
  }
  let paragraph = @bidi.process(text.to_string(), direction~)
  let positions = @bidi.reorder(paragraph)
  let permutation : Array[Int] = []
  let seen : Array[Bool] = Array::make(items.length(), false)
  let mut previous : Int? = None
  for position in positions {
    let owner = owners[position]
    if previous == Some(owner) {
      continue
    }
    if seen[owner] {
      return None
    }
    seen[owner] = true
    permutation.push(owner)
    previous = Some(owner)
  }
  if permutation.length() == items.length() {
    Some(permutation)
  } else {
    None
  }
}

///|
fn pdf_text_bidi_matches_visual(
  logical : ArrayView[PdfTextItem],
  visual : ArrayView[PdfTextItem],
  direction : @bidi.Direction,
) -> Bool {
  match pdf_text_bidi_permutation(logical, direction) {
    Some(permutation) => {
      for position, item in permutation {
        if logical[item].index != visual[position].index {
          return false
        }
      }
      true
    }
    None => false
  }
}

///|
/// Recover logical order from positioned PDF glyphs without applying a
/// logical-to-visual string replacement to the copy/search text. Prefer
/// content order when its UAX #9 projection agrees with the painted geometry.
/// A visual-order candidate is accepted only if its forward projection agrees.
fn pdf_text_bidi_order(visual : ArrayView[PdfTextItem]) -> Array[PdfTextItem] {
  let source = visual.to_owned()
  source.sort_by((first, second) => first.index.compare(second.index))
  let source_text = StringBuilder()
  for item in source {
    source_text.write_string(item.text)
  }
  if !@bidi.requires_bidi(source_text.to_string()) {
    return visual.to_owned()
  }
  let direction = @bidi.detect_direction(source_text.to_string())
  if pdf_text_bidi_matches_visual(source[:], visual, direction) {
    return source
  }
  match pdf_text_bidi_permutation(visual, direction) {
    Some(permutation) => {
      let logical = [ for index in permutation => visual[index] ]
      if pdf_text_bidi_matches_visual(logical[:], visual, direction) {
        return logical
      }
    }
    None => ()
  }
  // Positioned text can be ambiguous (for example, broken ToUnicode mappings
  // or explicit embeddings without source controls). Keep the original PDF
  // sequence instead of reversing every Latin and numeric run.
  source
}

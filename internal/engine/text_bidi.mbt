///|
/// Collapse the library's code-point permutation to PDF glyph/source items.
/// A glyph with a multi-scalar ToUnicode mapping is kept intact. Formatting
/// glyphs remain in logical source text, but do not assert a painted position.
fn pdf_text_bidi_permutation(
  items : ArrayView[PdfTextItem],
  direction : @bidi.Direction,
) -> Array[Int]? {
  let text = StringBuilder()
  let owners : Array[Int] = []
  for index, item in items {
    text.write_string(item.text)
    for _ in item.text {
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
    if pdf_text_control_only(items[owner].text) {
      continue
    }
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
  if permutation.length() ==
    items.filter(item => !pdf_text_control_only(item.text)).length() {
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
      let visible = visual.filter(item => !pdf_text_control_only(item.text))
      if permutation.length() != visible.length() {
        return false
      }
      for position, item in permutation {
        if logical[item].index != visible[position].index {
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
  let controls = source.any(item => pdf_text_control_only(item.text))
  if !controls && !@bidi.requires_bidi(source_text.to_string()) {
    return visual.to_owned()
  }
  let direction = @bidi.detect_direction(source_text.to_string())
  if pdf_text_bidi_matches_visual(source[:], visual, direction) {
    return source
  }
  // Invisible embedding/isolate positions cannot establish an inverse order.
  if controls {
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

///|
fn pdf_text_control_only(text : String) -> Bool {
  guard !text.is_empty() else { return false }
  for char in text {
    if !pdf_text_control_char(char) {
      break false
    }
  } nobreak {
    true
  }
}

///|
fn pdf_text_has_control(text : String) -> Bool {
  for char in text {
    if pdf_text_control_char(char) {
      break true
    }
  } nobreak {
    false
  }
}

///|
fn pdf_text_control_char(char : Char) -> Bool {
  let code = char.to_int()
  let kind = @bidi.bidi_class(char)
  code < 32 ||
  code == 127 ||
  code == 0x061C ||
  code == 0x200E ||
  code == 0x200F ||
  code == 0x2028 ||
  code == 0x2029 ||
  kind.is_x9_removed() ||
  kind.is_isolate_initiator() ||
  kind == @bidi.PDI
}

///|
/// Find original UTF-16 intervals using the viewer's Unicode normalization
/// policy. Pairs are half-open (start, end) ranges in the original string.
pub fn PdfSearchOptions::find_matches(
  self : PdfSearchOptions,
  text : String,
  query : String,
) -> Array[(Int, Int)] {
  let needle = pdf_search_normalized(query, self).text
  if needle.is_empty() {
    return []
  }
  let source = pdf_search_normalized(text, self)
  let output : Array[(Int, Int)] = []
  let mut cursor = 0
  while cursor + needle.length() <= source.text.length() {
    guard source.text.get_view(start=cursor) is Some(tail) &&
      tail.find(needle[:]) is Some(offset) else {
      break
    }
    let first = cursor + offset
    let last = first + needle.length()
    let (start, end) = pdf_search_source_range(source, first, last)
    let complete = !self.diacritic_sensitive ||
      !source.text.get_char(last).map(pdf_search_mark).unwrap_or(false)
    if complete &&
      (!self.whole_word || pdf_search_boundary_word(text, start, end)) {
      output.push((start, end))
    }
    cursor = last
  }
  output
}

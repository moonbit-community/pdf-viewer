///|
/// One glyph item's half-open range in text_content().text, measured in
/// UTF-16 code units. Inferred separators occupy gaps between these ranges.
/// item_index and charcode retain the original display-list identity; this
/// is not a byte offset into a PDF stream or a CID/GID mapping.
pub(all) struct PdfTextSourceRange {
  item_index : Int
  start : Int
  end : Int
  font : String
  charcode : Int
} derive(Eq, Debug, ToJson)

///|
fn pdf_text_source_ranges(
  items : ArrayView[PdfTextItem],
  separators? : ArrayView[String]? = None,
) -> Array[PdfTextSourceRange] {
  let output : Array[PdfTextSourceRange] = []
  let mut offset = 0
  for index, item in items {
    let separator = match separators {
      Some(values) if values.length() == items.length() => values[index]
      _ => pdf_text_separator_at(items, index)
    }
    offset += separator.length()
    output.push({
      item_index: item.index,
      start: offset,
      end: offset + item.text.length(),
      font: item.font,
      charcode: item.charcode,
    })
    offset += item.text.length()
  }
  output
}

///|
/// Map logical copy/search offsets to the original glyph items. One glyph
/// can represent multiple Unicode scalars or a ligature; its entire source
/// range and selection quad remain associated with that glyph.
pub fn PdfPageModel::text_sources(
  self : PdfPageModel,
) -> Array[PdfTextSourceRange] {
  pdf_text_source_ranges(self.text_content().items[:])
}

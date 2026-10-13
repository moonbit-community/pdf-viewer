///|
/// XFA searches use the same MoonBit normalization and source intervals.
pub fn search_text(
  text : String,
  query : String,
  case_sensitive : Bool,
  whole_word : Bool,
  diacritic_sensitive : Bool,
) -> String {
  let options = @pdf.pdf_search_options(
    case_sensitive~,
    whole_word~,
    diacritic_sensitive~,
  )
  (
    {
      "ok": true,
      "matches": options
      .find_matches(text, query)
      .map(range => ({ "index": range.0, "length": range.1 - range.0 } : Json)),
    } : Json).stringify()
}

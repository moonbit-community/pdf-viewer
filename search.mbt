///|
/// Options for the viewer's read-only text search.
pub(all) struct PdfSearchOptions {
  case_sensitive : Bool
  whole_word : Bool
  diacritic_sensitive : Bool
} derive(Eq, Debug, ToJson)

///|
/// Build text-search options. Matching offsets use UTF-16 code units, the same
/// coordinate system used by `PdfTextLayerItem` and browser `Range` objects.
pub fn pdf_search_options(
  case_sensitive? : Bool = false,
  whole_word? : Bool = false,
  diacritic_sensitive? : Bool = false,
) -> PdfSearchOptions {
  { case_sensitive, whole_word, diacritic_sensitive, }
}

///|
/// One occurrence returned by `PdfViewerDocument::search`.
pub(all) struct PdfSearchResult {
  page : Int
  index : Int
  length : Int
  text : String
  bounds : PdfBounds
  item_indices : Array[Int]
} derive(Eq, Debug, ToJson)

///|
/// A normalized search string and the source UTF-16 interval represented by
/// each normalized code unit. Folding can expand one source character (for
/// example, `ß` to `ss`), so the viewer must not use normalized offsets as
/// offsets into the original page text.
priv struct PdfSearchNormalized {
  text : String
  source_starts : Array[Int]
  source_ends : Array[Int]
}

///|
fn pdf_search_item_starts(items : ArrayView[PdfTextItem]) -> Array[Int] {
  [
    for source in pdf_text_source_ranges(items) => source.start
  ]
}

///|
fn pdf_search_result_items(
  items : ArrayView[PdfTextItem],
  starts : ArrayView[Int],
  match_start : Int,
  match_end : Int,
) -> (Array[Int], PdfBounds?) {
  let indices : Array[Int] = []
  let mut bounds : PdfBounds? = None
  for index, item in items {
    let item_start = starts[index]
    let item_end = item_start + item.text.length()
    if item_start < match_end && item_end > match_start {
      indices.push(item.index)
      bounds = match bounds {
        Some(current) => Some(pdf_bounds_union(current, item.bounds))
        None => Some(item.bounds)
      }
    }
  }
  (indices, bounds)
}

///|
/// Search pages in page order and text in logical reading order.
///
/// The result is intentionally geometry-rich so a host can highlight matches
/// without reparsing the PDF. Empty queries return no results. This API searches
/// the current page models, so optional-content state selected on the document
/// is respected automatically.
pub fn PdfViewerDocument::search(
  self : PdfViewerDocument,
  query : String,
  options? : PdfSearchOptions = pdf_search_options(),
  page? : Int? = None,
) -> Array[PdfSearchResult] raise @core.PdfError {
  if query.length() == 0 {
    return []
  }
  let normalized_query = pdf_search_normalized(query, options).text
  if normalized_query.length() == 0 {
    return []
  }
  let output : Array[PdfSearchResult] = []
  let first = page.unwrap_or(1)
  let last = page.unwrap_or(self.page_count())
  if page is Some(_) && (first < 1 || first > self.page_count()) {
    raise @core.SoftError("Search page does not exist")
  }
  for page_number in first..<=last {
    let page = self.page(page_number).unwrap()
    let content = page.text_content()
    let source = content.text
    let normalized_source = pdf_search_normalized(source, options)
    let starts = pdf_search_item_starts(content.items[:])
    let mut cursor = 0
    while cursor + normalized_query.length() <= normalized_source.text.length() {
      let candidate_end = cursor + normalized_query.length()
      match normalized_source.text.get_view(start=cursor, end=candidate_end) {
        Some(candidate) if candidate.to_owned() == normalized_query => {
          let (source_start, source_end) = pdf_search_source_range(
            normalized_source, cursor, candidate_end,
          )
          let complete_diacritics = !options.diacritic_sensitive ||
            !normalized_source.text
            .get_char(candidate_end)
            .map(pdf_search_mark)
            .unwrap_or(false)
          if complete_diacritics &&
            (
              !options.whole_word ||
              pdf_search_boundary_word(source, source_start, source_end)
            ) {
            let (indices, bounds) = pdf_search_result_items(
              content.items[:],
              starts[:],
              source_start,
              source_end,
            )
            match bounds {
              Some(bounds) => {
                let text = source.get_view(start=source_start, end=source_end)
                match text {
                  Some(text) =>
                    output.push({
                      page: page_number,
                      index: source_start,
                      length: source_end - source_start,
                      text: text.to_owned(),
                      bounds,
                      item_indices: indices,
                    })
                  None => ()
                }
              }
              None => ()
            }
          }
          cursor = candidate_end.max(cursor + 1)
        }
        _ => cursor += 1
      }
    }
  }
  output
}

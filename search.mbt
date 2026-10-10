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
fn pdf_search_fold_diacritics(text : String) -> String {
  // Keep this deliberately small and deterministic. PDF text is often Latin
  // metadata or body text; the table covers the common precomposed accents
  // without pretending to implement a full Unicode normalization database.
  let replacements : Array[(String, String)] = [
    ("à", "a"),
    ("á", "a"),
    ("â", "a"),
    ("ã", "a"),
    ("ä", "a"),
    ("å", "a"),
    ("æ", "ae"),
    ("ç", "c"),
    ("è", "e"),
    ("é", "e"),
    ("ê", "e"),
    ("ë", "e"),
    ("ì", "i"),
    ("í", "i"),
    ("î", "i"),
    ("ï", "i"),
    ("ñ", "n"),
    ("ò", "o"),
    ("ó", "o"),
    ("ô", "o"),
    ("õ", "o"),
    ("ö", "o"),
    ("œ", "oe"),
    ("ù", "u"),
    ("ú", "u"),
    ("û", "u"),
    ("ü", "u"),
    ("ý", "y"),
    ("ÿ", "y"),
    ("ß", "ss"),
  ]
  let mut output = text
  for (source, target) in replacements {
    while output.contains(source) {
      output = output.replace(old=source, new=target)
    }
    let upper = source.to_upper()
    while output.contains(upper) {
      output = output.replace(old=upper, new=target)
    }
  }
  output
}

///|
fn pdf_search_normalized(
  text : String,
  options : PdfSearchOptions,
) -> PdfSearchNormalized {
  let output = StringBuilder()
  let source_starts : Array[Int] = []
  let source_ends : Array[Int] = []
  let mut source_offset = 0
  for char in text.iter() {
    let source = char.to_string()
    let lowered = if options.case_sensitive {
      source
    } else {
      source.to_lower()
    }
    let normalized = if options.diacritic_sensitive {
      lowered
    } else {
      pdf_search_fold_diacritics(lowered)
    }
    output.write_string(normalized)
    let source_end = source_offset + char.utf16_len()
    for _ in 0..<normalized.length() {
      source_starts.push(source_offset)
      source_ends.push(source_end)
    }
    source_offset = source_end
  }
  { text: output.to_string(), source_starts, source_ends, }
}

///|
fn pdf_search_word_character(text : String) -> Bool {
  match text.get_view(start=0, end=text.length()) {
    Some(view) => {
      let bytes = @utf8.encode(view.to_owned())
      match bytes.get(0) {
        Some(byte) => {
          let value = byte.to_int()
          (value >= 48 && value <= 57) ||
          (value >= 65 && value <= 90) ||
          (value >= 97 && value <= 122) ||
          value >= 128 ||
          byte == b'_'
        }
        None => false
      }
    }
    None => false
  }
}

///|
fn pdf_search_boundary_word(text : String, index : Int, end : Int) -> Bool {
  let before = if index == 0 {
    false
  } else {
    match text.get_view(start=index - 1, end=index) {
      Some(value) => pdf_search_word_character(value.to_owned())
      None => true
    }
  }
  let after = if end >= text.length() {
    false
  } else {
    match text.get_view(start=end, end=end + 1) {
      Some(value) => pdf_search_word_character(value.to_owned())
      None => true
    }
  }
  !before && !after
}

///|
fn pdf_search_item_starts(items : ArrayView[PdfTextItem]) -> Array[Int] {
  let starts : Array[Int] = []
  let mut cursor = 0
  let mut previous : PdfTextItem? = None
  for item in items {
    match previous {
      Some(last) => cursor += pdf_text_separator(last, item).length()
      None => ()
    }
    starts.push(cursor)
    cursor += item.text.length()
    previous = Some(item)
  }
  starts
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
/// Search all page text in source/paint order.
///
/// The result is intentionally geometry-rich so a host can highlight matches
/// without reparsing the PDF. Empty queries return no results. This API searches
/// the current page models, so optional-content state selected on the document
/// is respected automatically.
pub fn PdfViewerDocument::search(
  self : PdfViewerDocument,
  query : String,
  options? : PdfSearchOptions = pdf_search_options(),
) -> Array[PdfSearchResult] raise @core.PdfError {
  if query.length() == 0 {
    return []
  }
  let normalized_query = pdf_search_normalized(query, options).text
  if normalized_query.length() == 0 {
    return []
  }
  let output : Array[PdfSearchResult] = []
  for page_number in 1..<=self.page_count() {
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
          let source_start = normalized_source.source_starts[cursor]
          let source_end = normalized_source.source_ends[candidate_end - 1]
          if !options.whole_word ||
            pdf_search_boundary_word(source, source_start, source_end) {
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

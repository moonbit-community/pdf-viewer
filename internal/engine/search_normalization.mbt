///|
/// One decomposed Unicode scalar together with its original UTF-16 interval.
/// Canonical ordering may permute marks; their source intervals travel with
/// them instead of being inferred from the normalized string's offsets.
priv struct PdfSearchScalar {
  char : Char
  start : Int
  mut end : Int
}

///|
fn pdf_search_mark(char : Char) -> Bool {
  match @ucd.general_category(char) {
    Mn | Me => true
    _ => false
  }
}

///|
fn pdf_search_fold_scalar(char : Char, options : PdfSearchOptions) -> String {
  let source = if options.case_sensitive {
    char.to_string()
  } else {
    @ucd.to_lowercase(char)
  }
  // These letters have no Unicode compatibility decomposition. Retain the
  // viewer's Latin search policy separately from the normalization algorithm.
  if !options.case_sensitive && source == "ß" {
    return "ss"
  }
  if !options.case_sensitive && source == "ς" {
    return "σ"
  }
  if !options.diacritic_sensitive {
    match source {
      "æ" => return "ae"
      "Æ" => return "AE"
      "œ" => return "oe"
      "Œ" => return "OE"
      _ => ()
    }
  }
  source
}

///|
fn pdf_search_normalized(
  text : String,
  options : PdfSearchOptions,
) -> PdfSearchNormalized {
  let scalars : Array[PdfSearchScalar] = []
  let mut source_offset = 0
  for char in text {
    let source_end = source_offset + char.utf16_len()
    // Compatibility forms such as mathematical script capitals may have no
    // lowercase mapping until decomposed to their ordinary letter.
    let folded = StringBuilder()
    for scalar in @normalization.nfkd(char.to_string()) {
      folded.write_string(pdf_search_fold_scalar(scalar, options))
    }
    let decomposed = @normalization.nfkd(folded.to_string())
    for scalar in decomposed {
      if !options.diacritic_sensitive && pdf_search_mark(scalar) {
        // A separately encoded accent belongs to the preceding source scalar.
        // Include it in the returned original range even when search ignores it.
        if pdf_search_mark(char) {
          match scalars.last() {
            Some(previous) => previous.end = source_end
            None => ()
          }
        }
        continue
      }
      scalars.push({ char: scalar, start: source_offset, end: source_end, })
    }
    source_offset = source_end
  }
  let decomposed = String::from_array([ for scalar in scalars => scalar.char ])
  let normalized = @normalization.nfkd(decomposed)
  let origins : Map[Char, Array[PdfSearchScalar]] = Map([])
  for scalar in scalars {
    match origins.get(scalar.char) {
      Some(queue) => queue.push(scalar)
      None => origins[scalar.char] = [scalar]
    }
  }
  let consumed : Map[Char, Int] = Map([])
  let source_starts : Array[Int] = []
  let source_ends : Array[Int] = []
  for char in normalized {
    let index = consumed.get(char).unwrap_or(0)
    let scalar = origins.get(char).unwrap()[index]
    consumed[char] = index + 1
    for _ in 0..<char.utf16_len() {
      source_starts.push(scalar.start)
      source_ends.push(scalar.end)
    }
  }
  { text: normalized, source_starts, source_ends, }
}

///|
fn pdf_search_source_range(
  normalized : PdfSearchNormalized,
  start : Int,
  end : Int,
) -> (Int, Int) {
  let mut source_start = normalized.source_starts[start]
  let mut source_end = normalized.source_ends[start]
  for index in (start + 1)..<end {
    source_start = source_start.min(normalized.source_starts[index])
    source_end = source_end.max(normalized.source_ends[index])
  }
  (source_start, source_end)
}

///|
fn pdf_search_word_character(char : Char) -> Bool {
  match @ucd.general_category(char).group() {
    L | M | N => true
    _ => @ucd.general_category(char) == @ucd.Pc
  }
}

///|
fn pdf_search_boundary_word(text : String, index : Int, end : Int) -> Bool {
  let before = if index == 0 {
    None
  } else {
    match text.get_char(index - 1) {
      Some(char) => Some(char)
      None if index >= 2 => text.get_char(index - 2)
      None => None
    }
  }
  let after = text.get_char(end)
  !before.map(pdf_search_word_character).unwrap_or(false) &&
  !after.map(pdf_search_word_character).unwrap_or(false)
}

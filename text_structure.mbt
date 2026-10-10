///|
/// A logical run with one font, writing direction and baseline. Its UTF-16
/// interval can include inferred spaces; sources own only actual glyph text.
pub(all) struct PdfTextRun {
  start : Int
  end : Int
  font : String
  vertical : Bool
  bounds : PdfBounds
  sources : Array[PdfTextSourceRange]
} derive(Eq, Debug, ToJson)

///|
/// A geometrically inferred paragraph, not a tagged-PDF semantic assertion.
/// Runs and paragraph intervals use text_content().text's UTF-16 coordinates.
/// Separators between paragraphs have no invented glyph/byte owner.
pub(all) struct PdfTextParagraph {
  start : Int
  end : Int
  bounds : PdfBounds
  runs : Array[PdfTextRun]
} derive(Eq, Debug, ToJson)

///|
pub(all) struct PdfTextStructure {
  text : String
  paragraphs : Array[PdfTextParagraph]
} derive(Eq, Debug, ToJson)

///|
fn pdf_text_writing_axis(item : PdfTextItem) -> (Double, Double) {
  let (x, y) = if item.vertical {
    (item.quad.p1.x - item.quad.p0.x, item.quad.p1.y - item.quad.p0.y)
  } else {
    (item.quad.p2.x - item.quad.p1.x, item.quad.p2.y - item.quad.p1.y)
  }
  let length = (x * x + y * y).sqrt()
  if length > 0.000001 {
    (x / length, y / length)
  } else {
    match item.glyph_transform {
      Some([a, b, _, _, _, _]) if a * a + b * b > 0.000000000001 => {
        let length = (a * a + b * b).sqrt()
        (a / length, b / length)
      }
      _ => (1.0, 0.0)
    }
  }
}

///|
fn pdf_text_same_orientation(first : PdfTextItem, second : PdfTextItem) -> Bool {
  if first.vertical != second.vertical {
    return false
  }
  let (ax, ay) = pdf_text_writing_axis(first)
  let (bx, by) = pdf_text_writing_axis(second)
  ax * bx + ay * by > 0.98
}

///|
fn pdf_text_run_continues(
  previous : PdfTextItem,
  current : PdfTextItem,
) -> Bool {
  if previous.font != current.font ||
    !pdf_text_same_orientation(previous, current) ||
    pdf_text_separator(previous, current) == "\n" {
    return false
  }
  let size = previous.font_size.abs().max(current.font_size.abs()).max(0.001)
  if (previous.font_size - current.font_size).abs() > size * 0.01 {
    return false
  }
  if (pdf_text_direction_score(previous.text) > 0) !=
    (pdf_text_direction_score(current.text) > 0) {
    return false
  }
  let (ux, uy) = pdf_text_writing_axis(previous)
  let distance = ((current.quad.p1.x - previous.quad.p1.x) * ux +
  (current.quad.p1.y - previous.quad.p1.y) * uy).abs()
  let dx = previous.quad.p2.x - previous.quad.p1.x
  let dy = previous.quad.p2.y - previous.quad.p1.y
  let extent = if previous.vertical {
    (previous.advance_x * previous.advance_x +
    previous.advance_y * previous.advance_y).sqrt()
  } else {
    (dx * dx + dy * dy).sqrt()
  }
  distance <= extent + size * 2.0
}

///|
fn pdf_text_paragraph_break(
  previous : PdfTextItem,
  current : PdfTextItem,
) -> Bool {
  if !pdf_text_same_orientation(previous, current) {
    return true
  }
  if pdf_text_separator(previous, current) != "\n" {
    return false
  }
  let size = previous.font_size.abs().max(current.font_size.abs()).max(0.001)
  let (ux, uy) = pdf_text_writing_axis(previous)
  let cross = ((current.quad.p1.x - previous.quad.p1.x) * -uy +
  (current.quad.p1.y - previous.quad.p1.y) * ux).abs()
  cross > size * 1.8 ||
  (previous.font_size - current.font_size).abs() > size * 0.2
}

///|
/// Build run/paragraph views using the same ordered glyphs as copy, selection,
/// search and text_sources(). No run/paragraph sorting or renumbering occurs.
pub fn PdfPageModel::text_structure(self : PdfPageModel) -> PdfTextStructure {
  let content = self.text_content()
  let sources = pdf_text_source_ranges(content.items[:])
  let paragraphs : Array[PdfTextParagraph] = []
  let mut runs : Array[PdfTextRun] = []
  let mut paragraph_bounds : PdfBounds? = None
  let mut previous : PdfTextItem? = None
  for index, item in content.items {
    let source = sources[index]
    if previous is Some(last) &&
      pdf_text_paragraph_break(last, item) &&
      !runs.is_empty() {
      paragraphs.push({
        start: runs[0].start,
        end: runs[runs.length() - 1].end,
        bounds: paragraph_bounds.unwrap(),
        runs,
      })
      runs = []
      paragraph_bounds = None
    }
    if previous is Some(last) &&
      pdf_text_run_continues(last, item) &&
      !runs.is_empty() {
      let at = runs.length() - 1
      let run = runs[at]
      run.sources.push(source)
      runs[at] = {
        ..run,
        end: source.end,
        bounds: pdf_bounds_union(run.bounds, item.bounds),
      }
    } else {
      runs.push({
        start: source.start,
        end: source.end,
        font: source.font,
        vertical: item.vertical,
        bounds: item.bounds,
        sources: [source],
      })
    }
    paragraph_bounds = Some(
      match paragraph_bounds {
        Some(bounds) => pdf_bounds_union(bounds, item.bounds)
        None => item.bounds
      },
    )
    previous = Some(item)
  }
  if !runs.is_empty() {
    paragraphs.push({
      start: runs[0].start,
      end: runs[runs.length() - 1].end,
      bounds: paragraph_bounds.unwrap(),
      runs,
    })
  }
  { text: content.text, paragraphs, }
}

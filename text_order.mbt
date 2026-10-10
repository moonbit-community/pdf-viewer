///|
/// A logical line assembled from positioned glyph items. The source display
/// list remains paint ordered; this index is only used by text-facing APIs.
priv struct PdfTextLine {
  items : Array[PdfTextItem]
  key : Double
  vertical : Bool
  first_index : Int
}

///|
fn pdf_text_direction_score(text : String) -> Int {
  let mut score = 0
  for char in text.iter() {
    match @bidi.bidi_class(char) {
      R | AL => score += 1
      L => score -= 1
      _ => ()
    }
  }
  score
}

///|
fn pdf_text_line_key(item : PdfTextItem) -> Double {
  if item.vertical {
    item.bounds.max_x
  } else {
    item.bounds.max_y
  }
}

///|
fn pdf_text_line_threshold(item : PdfTextItem) -> Double {
  item.font_size.abs().max(0.001) * 0.8
}

///|
fn pdf_text_line_for_item(
  lines : ArrayView[PdfTextLine],
  item : PdfTextItem,
) -> Int? {
  let key = pdf_text_line_key(item)
  for index, line in lines {
    if line.vertical == item.vertical {
      let threshold = pdf_text_line_threshold(item).max(
        match line.items.last() {
          Some(previous) => pdf_text_line_threshold(previous)
          None => 0.001
        },
      )
      if (line.key - key).abs() <= threshold {
        return Some(index)
      }
    }
  }
  None
}

///|
fn pdf_text_compare_number(a : Double, b : Double) -> Int {
  if a < b {
    -1
  } else if a > b {
    1
  } else {
    0
  }
}

///|
/// Group positioned glyphs into lines inside one reading block. Horizontal
/// lines use bidi permutations checked against geometry and source identity;
/// vertical writing retains its content order.
fn pdf_text_order_in_block(
  items : ArrayView[PdfTextItem],
) -> Array[PdfTextItem] {
  let lines : Array[PdfTextLine] = []
  for item in items {
    guard !item.text.is_empty() else { continue }
    let line_index = pdf_text_line_for_item(lines[:], item)
    match line_index {
      Some(index) => lines[index].items.push(item)
      None =>
        lines.push({
          items: [item],
          key: pdf_text_line_key(item),
          vertical: item.vertical,
          first_index: item.index,
        })
    }
  }
  lines.sort_by((first, second) => {
    if first.vertical != second.vertical {
      return first.first_index - second.first_index
    }
    let key_order = if first.vertical {
      // Keep vertical columns in the content order until their writing
      // direction can be inferred from the full column, as PDF files often
      // mix rotated annotations with vertical glyph runs.
      0
    } else {
      pdf_text_compare_number(second.key, first.key)
    }
    if key_order != 0 {
      key_order
    } else {
      first.first_index - second.first_index
    }
  })
  let output : Array[PdfTextItem] = []
  for line in lines {
    if line.vertical {
      for item in line.items {
        output.push(item)
      }
      continue
    }
    line.items.sort_by((first, second) => {
      let first_key = if line.vertical {
        first.bounds.max_y
      } else {
        first.bounds.min_x
      }
      let second_key = if line.vertical {
        second.bounds.max_y
      } else {
        second.bounds.min_x
      }
      let order = pdf_text_compare_number(first_key, second_key)
      if order != 0 {
        order
      } else {
        first.index - second.index
      }
    })
    for item in pdf_text_bidi_order(line.items[:]) {
      output.push(item)
    }
  }
  output
}

///|
/// Collect text items from a paint-ordered page without changing the display
/// list itself.
fn pdf_text_reading_order_of_page_items(
  items : ArrayView[PdfPageItem],
) -> Array[PdfTextItem] {
  let text_items : Array[PdfTextItem] = []
  for item in items {
    match item {
      PdfPageItem::Text(text) => text_items.push(text)
      _ => ()
    }
  }
  pdf_text_reading_order(text_items[:])
}

///|
/// Join positioned text using the same line and word boundaries as the text
/// layer. This keeps copy, search and selection source text consistent.
fn pdf_join_text_items(items : ArrayView[PdfTextItem]) -> String {
  let output = StringBuilder()
  let mut previous : PdfTextItem? = None
  for item in items {
    match previous {
      Some(last) => output.write_string(pdf_text_separator(last, item))
      None => ()
    }
    output.write_string(item.text)
    previous = Some(item)
  }
  output.to_string()
}

///|
/// Infer a separator from the two glyph quads. Projection onto the writing
/// axis handles rotated and vertical text without relying on page rotation.
fn pdf_text_separator(previous : PdfTextItem, current : PdfTextItem) -> String {
  if previous.vertical != current.vertical {
    return "\n"
  }
  let (dx, dy, extent, cross_extent) = if previous.vertical {
    let x = previous.quad.p0.x - previous.quad.p1.x
    let y = previous.quad.p0.y - previous.quad.p1.y
    let cross_x = previous.quad.p2.x - previous.quad.p1.x
    let cross_y = previous.quad.p2.y - previous.quad.p1.y
    (
      x,
      y,
      (x * x + y * y).sqrt(),
      (cross_x * cross_x + cross_y * cross_y).sqrt(),
    )
  } else {
    let x = previous.quad.p2.x - previous.quad.p1.x
    let y = previous.quad.p2.y - previous.quad.p1.y
    let cross_x = previous.quad.p0.x - previous.quad.p1.x
    let cross_y = previous.quad.p0.y - previous.quad.p1.y
    (
      x,
      y,
      (x * x + y * y).sqrt(),
      (cross_x * cross_x + cross_y * cross_y).sqrt(),
    )
  }
  if extent < 0.000001 {
    return "\n"
  }
  let unit_x = dx / extent
  let unit_y = dy / extent
  let delta_x = current.quad.p1.x - previous.quad.p1.x
  let delta_y = current.quad.p1.y - previous.quad.p1.y
  let cross = (delta_x * -unit_y + delta_y * unit_x).abs()
  let line_threshold = cross_extent.max(
    previous.font_size.abs().max(current.font_size.abs()) * 0.8,
  )
  if cross > line_threshold {
    return "\n"
  }
  let along = delta_x * unit_x + delta_y * unit_y
  let gap = if along < 0.0 &&
    pdf_text_direction_score(previous.text + current.text) > 0 {
    let current_dx = current.quad.p2.x - current.quad.p1.x
    let current_dy = current.quad.p2.y - current.quad.p1.y
    -along - (current_dx * current_dx + current_dy * current_dy).sqrt()
  } else {
    along - extent
  }
  let word_threshold = previous.font_size.abs().max(current.font_size.abs()) *
    0.25
  let previous_rtl = pdf_text_direction_score(previous.text) > 0
  let current_rtl = pdf_text_direction_score(current.text) > 0
  if previous_rtl != current_rtl {
    // At a bidi run boundary, the next logical glyph need not be the closest
    // painted glyph. Its displacement can span the rest of an intervening
    // number/Latin run, which must not become an artificial space.
    return ""
  }
  if gap > word_threshold.max(0.001) &&
    !previous.text.has_suffix(" ") &&
    !current.text.has_prefix(" ") {
    " "
  } else {
    ""
  }
}

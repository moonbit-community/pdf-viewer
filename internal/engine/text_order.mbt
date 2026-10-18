///|
/// A logical line assembled from positioned glyph items. The source display
/// list remains paint ordered; this index is only used by text-facing APIs.
priv struct PdfTextLine {
  items : Array[PdfTextItem]
  key : Double
  vertical : Bool
  first_index : Int
  axis : (Double, Double)
}

///|
fn pdf_text_direction_score(text : String) -> Int {
  let mut score = 0
  for char in text {
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
  let (ux, uy) = pdf_text_writing_axis(item)
  let point = pdf_text_baseline(item)
  point.x * -uy + point.y * ux
}

///|
fn pdf_text_line_threshold(item : PdfTextItem) -> Double {
  let (ux, uy) = pdf_text_writing_axis(item)
  let (dx, dy) = if item.vertical {
    (item.quad.p2.x - item.quad.p1.x, item.quad.p2.y - item.quad.p1.y)
  } else {
    (item.quad.p0.x - item.quad.p1.x, item.quad.p0.y - item.quad.p1.y)
  }
  (dx * -uy + dy * ux).abs().max(item.font_size.abs()).max(0.001) * 0.8
}

///|
fn pdf_text_line_for_item(
  lines : ArrayView[PdfTextLine],
  item : PdfTextItem,
) -> Int? {
  let (ux, uy) = pdf_text_writing_axis(item)
  let point = pdf_text_baseline(item)
  for index, line in lines {
    if line.vertical == item.vertical &&
      line.axis.0 * ux + line.axis.1 * uy > 0.999 {
      let threshold = pdf_text_line_threshold(item).max(
        match line.items.last() {
          Some(previous) => pdf_text_line_threshold(previous)
          None => 0.001
        },
      )
      let key = point.x * -line.axis.1 + point.y * line.axis.0
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
          axis: pdf_text_writing_axis(item),
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
      let first_point = pdf_text_baseline(first)
      let second_point = pdf_text_baseline(second)
      let first_key = first_point.x * line.axis.0 + first_point.y * line.axis.1
      let second_key = second_point.x * line.axis.0 +
        second_point.y * line.axis.1
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
fn pdf_join_text_items(
  items : ArrayView[PdfTextItem],
  separators? : ArrayView[String]? = None,
) -> String {
  let output = StringBuilder()
  for index, item in items {
    output.write_string(
      match separators {
        Some(values) if values.length() == items.length() => values[index]
        _ => pdf_text_separator_at(items, index)
      },
    )
    output.write_string(item.text)
  }
  output.to_string()
}

///|
/// Compare entire neighboring direction runs at a bidi boundary. Painted
/// glyphs filling the interval prevent an invented space across that run.
fn pdf_text_separator_at(items : ArrayView[PdfTextItem], index : Int) -> String {
  if index <= 0 || index >= items.length() {
    return ""
  }
  let current = items[index]
  if pdf_text_control_only(current.text) {
    return ""
  }
  let mut before = index - 1
  let mut crossed_control = false
  while before >= 0 && pdf_text_control_only(items[before].text) {
    crossed_control = true
    let text = items[before].text
    if text.contains("\n") ||
      text.contains("\r") ||
      text.contains("\u2028") ||
      text.contains("\u2029") {
      return ""
    }
    before -= 1
  }
  if before < 0 {
    return ""
  }
  let previous = items[before]
  let ordinary = pdf_text_separator(previous, current)
  let rtl = pdf_text_direction_score(previous.text) > 0
  let (ux, uy) = pdf_text_writing_axis(previous)
  let interval = fn(item : PdfTextItem) -> (Double, Double) {
    let values = [
      for point in [item.quad.p0, item.quad.p1, item.quad.p2, item.quad.p3] => {
        point.x * ux + point.y * uy
      }
    ]
    (
      values[0].min(values[1]).min(values[2]).min(values[3]),
      values[0].max(values[1]).max(values[2]).max(values[3]),
    )
  }
  if ordinary == " " &&
    (
      crossed_control ||
      pdf_text_has_control(previous.text) ||
      pdf_text_has_control(current.text)
    ) {
    let a = interval(previous)
    let b = interval(current)
    let (start, end) = if a.1 <= b.0 { (a.1, b.0) } else { (b.1, a.0) }
    for at, item in items {
      if at == before ||
        at == index ||
        pdf_text_control_only(item.text) ||
        item.text.trim().is_empty() ||
        pdf_text_separator(previous, item) == "\n" {
        continue
      }
      let span = interval(item)
      if span.0 < end && span.1 > start {
        return ""
      }
    }
  }
  if ordinary == "\n" ||
    rtl == (pdf_text_direction_score(current.text) > 0) ||
    previous.text.has_suffix(" ") ||
    current.text.has_prefix(" ") {
    return ordinary
  }
  let mut a = interval(previous)
  let mut b = interval(current)
  let mut first = before
  while first > 0 {
    let item = items[first - 1]
    if pdf_text_control_only(item.text) {
      first -= 1
      continue
    }
    if (pdf_text_direction_score(item.text) > 0) != rtl ||
      pdf_text_separator(item, previous) == "\n" {
      break
    }
    let span = interval(item)
    a = (a.0.min(span.0), a.1.max(span.1))
    first -= 1
  }
  let mut last = index
  while last + 1 < items.length() {
    let item = items[last + 1]
    if pdf_text_control_only(item.text) {
      last += 1
      continue
    }
    if (pdf_text_direction_score(item.text) > 0) == rtl ||
      pdf_text_separator(current, item) == "\n" {
      break
    }
    let span = interval(item)
    b = (b.0.min(span.0), b.1.max(span.1))
    last += 1
  }
  let (start, end) = if a.1 <= b.0 {
    (a.1, b.0)
  } else if b.1 <= a.0 {
    (b.1, a.0)
  } else {
    return ""
  }
  let threshold = previous.font_size.abs().max(current.font_size.abs()) * 0.25
  if end - start <= threshold.max(0.001) {
    return ""
  }
  for at, item in items {
    if (at >= first && at <= last) ||
      pdf_text_control_only(item.text) ||
      item.text.trim().is_empty() ||
      pdf_text_separator(previous, item) == "\n" {
      continue
    }
    let span = interval(item)
    if span.0 < end && span.1 > start {
      return ""
    }
  }
  " "
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

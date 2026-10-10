///|
/// Find gutters in horizontal PDF text. Rotated/vertical runs retain the
/// existing line ordering, since page-axis projection would split those glyphs.
fn pdf_text_is_horizontal(item : PdfTextItem) -> Bool {
  let dx = item.quad.p2.x - item.quad.p1.x
  let dy = item.quad.p2.y - item.quad.p1.y
  !item.vertical && dx.abs() > 0.000001 && dy.abs() < dx.abs() * 0.01
}

///|
fn pdf_text_typical_height(items : ArrayView[PdfTextItem]) -> Double {
  let heights = [
    for item in items if !item.text.trim().is_empty() => {
      (item.bounds.max_y - item.bounds.min_y).abs()
    }
  ]
  heights.sort_by(pdf_text_compare_number)
  match heights.get(heights.length() / 2) {
    Some(height) => height.max(0.001)
    None => 0.001
  }
}

///|
/// A horizontal projection gap is useful for separating headings/footers from
/// a column body. A vertical projection gap must persist across the whole
/// region; spaces inside a text run do not count as painted blockers.
fn pdf_text_projection_gap(
  items : ArrayView[PdfTextItem],
  vertical : Bool,
  threshold : Double,
) -> Double? {
  let intervals = [
    for item in items if !item.text.trim().is_empty() => {
      if vertical {
        (item.bounds.min_x, item.bounds.max_x)
      } else {
        (item.bounds.min_y, item.bounds.max_y)
      }
    }
  ]
  intervals.sort_by((first, second) => {
    pdf_text_compare_number(first.0, second.0)
  })
  guard intervals[0:] is [first, ..] else { return None }
  let mut edge = first.1
  let mut largest = threshold
  let mut cut : Double? = None
  for interval in intervals[1:] {
    let gap = interval.0 - edge
    if gap > largest {
      largest = gap
      cut = Some((edge + interval.0) / 2.0)
    }
    edge = edge.max(interval.1)
  }
  cut
}

///|
fn pdf_text_has_multiple_lines(
  items : ArrayView[PdfTextItem],
  height : Double,
) -> Bool {
  let mut first : Double? = None
  for item in items {
    if item.text.trim().is_empty() {
      continue
    }
    match first {
      Some(key) if (item.bounds.max_y - key).abs() > height * 0.8 => return true
      Some(_) => ()
      None => first = Some(item.bounds.max_y)
    }
  }
  false
}

///|
fn pdf_text_reading_blocks(
  items : ArrayView[PdfTextItem],
  depth : Int,
) -> Array[Array[PdfTextItem]] {
  if depth >= 16 || items.length() < 4 {
    return [items.to_owned()]
  }
  let height = pdf_text_typical_height(items)
  match pdf_text_projection_gap(items, true, height * 1.5) {
    Some(cut) => {
      let left : Array[PdfTextItem] = []
      let right : Array[PdfTextItem] = []
      for item in items {
        if (item.bounds.min_x + item.bounds.max_x) / 2.0 < cut {
          left.push(item)
        } else {
          right.push(item)
        }
      }
      if pdf_text_has_multiple_lines(left[:], height) &&
        pdf_text_has_multiple_lines(right[:], height) {
        let rtl = items.fold(init=0, (score, item) => {
            score + pdf_text_direction_score(item.text)
          }) >
          0
        let (first, second) = if rtl { (right, left) } else { (left, right) }
        let blocks = pdf_text_reading_blocks(first[:], depth + 1)
        blocks.append(pdf_text_reading_blocks(second[:], depth + 1))
        return blocks
      }
    }
    None => ()
  }
  match pdf_text_projection_gap(items, false, height * 0.6) {
    Some(cut) => {
      let top : Array[PdfTextItem] = []
      let bottom : Array[PdfTextItem] = []
      for item in items {
        if (item.bounds.min_y + item.bounds.max_y) / 2.0 > cut {
          top.push(item)
        } else {
          bottom.push(item)
        }
      }
      if !top.is_empty() && !bottom.is_empty() {
        let blocks = pdf_text_reading_blocks(top[:], depth + 1)
        blocks.append(pdf_text_reading_blocks(bottom[:], depth + 1))
        return blocks
      }
    }
    None => ()
  }
  [items.to_owned()]
}

///|
/// Reading order is a view of source items, never a rewrite of the paint list.
/// Separate persistent column gutters before grouping lines, so adjacent
/// columns are not merged into one long row.
fn pdf_text_reading_order(items : ArrayView[PdfTextItem]) -> Array[PdfTextItem] {
  if items.is_empty() || !items.iter().all(pdf_text_is_horizontal) {
    return pdf_text_order_in_block(items)
  }
  let output : Array[PdfTextItem] = []
  for block in pdf_text_reading_blocks(items, 0) {
    output.append(pdf_text_order_in_block(block[:]))
  }
  output
}

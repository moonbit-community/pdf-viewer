///|
/// Geometry is immutable during reading-order inference. Sort its projections
/// once, then partition those ordered views along each accepted gutter.
priv struct PdfTextBlockEntry {
  item : PdfTextItem
  blank : Bool
  height : Double
  line_key : Double
  direction : Int
}

///|
priv struct PdfTextBlockIndex {
  items : Array[PdfTextBlockEntry]
  x : Array[PdfTextBlockEntry]
  y : Array[PdfTextBlockEntry]
  heights : Array[PdfTextBlockEntry]
}

///|
fn pdf_text_block_finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn pdf_text_reading_blocks(
  items : ArrayView[PdfTextItem],
  depth : Int,
) -> Array[Array[PdfTextItem]] {
  if depth >= 16 || items.length() < 4 {
    return [items.to_owned()]
  }
  let entries : Array[PdfTextBlockEntry] = []
  for item in items {
    let b = item.bounds
    let height = (b.max_y - b.min_y).abs()
    let key = pdf_text_line_key(item)
    // Nonfinite geometry does not define a total sort order. Keep the legacy
    // per-region sorting behavior for those public, manually created models.
    if b.min_x > b.max_x ||
      b.min_y > b.max_y ||
      !pdf_text_block_finite(b.min_x) ||
      !pdf_text_block_finite(b.min_y) ||
      !pdf_text_block_finite(b.max_x) ||
      !pdf_text_block_finite(b.max_y) ||
      !pdf_text_block_finite(b.min_x + b.max_x) ||
      !pdf_text_block_finite(b.min_y + b.max_y) ||
      !pdf_text_block_finite(height) ||
      !pdf_text_block_finite(key) {
      return pdf_text_reading_blocks_legacy(items, depth)
    }
    entries.push({
      item,
      blank: item.text.trim().is_empty(),
      height,
      line_key: key,
      direction: pdf_text_direction_score(item.text),
    })
  }
  let x = entries.filter(entry => !entry.blank)
  let y = x.copy()
  let heights = x.copy()
  x.sort_by((a, b) => {
    pdf_text_compare_number(a.item.bounds.min_x, b.item.bounds.min_x)
  })
  y.sort_by((a, b) => {
    pdf_text_compare_number(a.item.bounds.min_y, b.item.bounds.min_y)
  })
  heights.sort_by((a, b) => pdf_text_compare_number(a.height, b.height))
  pdf_text_indexed_blocks({ items: entries, x, y, heights, }, depth)
}

///|
fn pdf_text_block_gap(
  entries : ArrayView[PdfTextBlockEntry],
  vertical : Bool,
  threshold : Double,
) -> Double? {
  guard entries[0:] is [first, ..] else { return None }
  let mut edge = if vertical {
    first.item.bounds.max_x
  } else {
    first.item.bounds.max_y
  }
  let mut largest = threshold
  let mut cut : Double? = None
  for entry in entries[1:] {
    let b = entry.item.bounds
    let start = if vertical { b.min_x } else { b.min_y }
    let end = if vertical { b.max_x } else { b.max_y }
    let gap = start - edge
    if gap > largest {
      largest = gap
      cut = Some((edge + start) / 2.0)
    }
    edge = edge.max(end)
  }
  cut
}

///|
fn pdf_text_block_partition(
  entries : ArrayView[PdfTextBlockEntry],
  first : (PdfTextBlockEntry) -> Bool,
) -> (Array[PdfTextBlockEntry], Array[PdfTextBlockEntry]) {
  let a : Array[PdfTextBlockEntry] = []
  let b : Array[PdfTextBlockEntry] = []
  for entry in entries {
    if first(entry) {
      a.push(entry)
    } else {
      b.push(entry)
    }
  }
  (a, b)
}

///|
fn pdf_text_block_children(
  index : PdfTextBlockIndex,
  a : Array[PdfTextBlockEntry],
  b : Array[PdfTextBlockEntry],
  first : (PdfTextBlockEntry) -> Bool,
) -> (PdfTextBlockIndex, PdfTextBlockIndex) {
  let (ax, bx) = pdf_text_block_partition(index.x[:], first)
  let (ay, by) = pdf_text_block_partition(index.y[:], first)
  let (ah, bh) = pdf_text_block_partition(index.heights[:], first)
  (
    { items: a, x: ax, y: ay, heights: ah, },
    { items: b, x: bx, y: by, heights: bh, },
  )
}

///|
fn pdf_text_block_multiple_lines(
  entries : ArrayView[PdfTextBlockEntry],
  height : Double,
) -> Bool {
  let mut first : Double? = None
  for entry in entries {
    if entry.blank {
      continue
    }
    match first {
      Some(key) if (entry.item.bounds.max_y - key).abs() > height * 0.8 =>
        return true
      Some(_) => ()
      None => first = Some(entry.item.bounds.max_y)
    }
  }
  false
}

///|
fn pdf_text_block_cells(
  entries : ArrayView[PdfTextBlockEntry],
  height : Double,
) -> Array[(Double, Int)] {
  let rows : Array[(Double, Int)] = []
  for entry in entries {
    if entry.blank {
      continue
    }
    let key = entry.line_key
    match rows.search_by(row => (row.0 - key).abs() < height * 0.25) {
      Some(at) => rows[at] = (rows[at].0, rows[at].1 + entry.item.text.length())
      None => rows.push((key, entry.item.text.length()))
    }
  }
  rows.sort_by((a, b) => pdf_text_compare_number(b.0, a.0))
  rows
}

///|
fn pdf_text_block_table(
  left : ArrayView[PdfTextBlockEntry],
  right : ArrayView[PdfTextBlockEntry],
  height : Double,
) -> Bool {
  let a = pdf_text_block_cells(left, height)
  let b = pdf_text_block_cells(right, height)
  guard a.length() >= 3 && a.length() == b.length() else { return false }
  for i in 0..<a.length() {
    if (a[i].0 - b[i].0).abs() > height * 0.25 || a[i].1 > 24 || b[i].1 > 24 {
      return false
    }
  }
  true
}

///|
fn pdf_text_indexed_blocks(
  index : PdfTextBlockIndex,
  depth : Int,
) -> Array[Array[PdfTextItem]] {
  let original = fn() { [ for entry in index.items => entry.item ] }
  if depth >= 16 || index.items.length() < 4 {
    return [original()]
  }
  let height = index.heights
    .get(index.heights.length() / 2)
    .map(entry => entry.height.max(0.001))
    .unwrap_or(0.001)
  match pdf_text_block_gap(index.x[:], true, height * 1.5) {
    Some(cut) => {
      let first = fn(entry : PdfTextBlockEntry) {
        (entry.item.bounds.min_x + entry.item.bounds.max_x) / 2.0 < cut
      }
      let (left, right) = pdf_text_block_partition(index.items[:], first)
      if pdf_text_block_table(left[:], right[:], height) {
        return [original()]
      }
      if pdf_text_block_multiple_lines(left[:], height) &&
        pdf_text_block_multiple_lines(right[:], height) {
        let rtl = index.items.fold(init=0, (score, entry) => {
            score + entry.direction
          }) >
          0
        let (left, right) = pdf_text_block_children(index, left, right, first)
        let (first, second) = if rtl { (right, left) } else { (left, right) }
        let blocks = pdf_text_indexed_blocks(first, depth + 1)
        blocks.append(pdf_text_indexed_blocks(second, depth + 1))
        return blocks
      }
    }
    None => ()
  }
  match pdf_text_block_gap(index.y[:], false, height * 0.6) {
    Some(cut) => {
      let first = fn(entry : PdfTextBlockEntry) {
        (entry.item.bounds.min_y + entry.item.bounds.max_y) / 2.0 > cut
      }
      let (top, bottom) = pdf_text_block_partition(index.items[:], first)
      if !top.is_empty() && !bottom.is_empty() {
        let (top, bottom) = pdf_text_block_children(index, top, bottom, first)
        let blocks = pdf_text_indexed_blocks(top, depth + 1)
        blocks.append(pdf_text_indexed_blocks(bottom, depth + 1))
        return blocks
      }
    }
    None => ()
  }
  [original()]
}

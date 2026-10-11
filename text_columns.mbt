///|
/// Find gutters in horizontal PDF text. Rotated/vertical runs retain the
/// existing line ordering, since page-axis projection would split those glyphs.
fn pdf_text_is_horizontal(item : PdfTextItem) -> Bool {
  let dx = item.quad.p2.x - item.quad.p1.x
  let dy = item.quad.p2.y - item.quad.p1.y
  !item.vertical && dx > 0.000001 && dy.abs() < dx * 0.01
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
  // Synchronized rows of short cells are a compact table, not prose columns.
  // Long aligned prose lines remain eligible for persistent-gutter splitting.
  if pdf_text_compact_table(items, height) {
    return [items.to_owned()]
  }
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
  if items.any(item => pdf_text_control_only(item.text)) {
    let visible = items.filter(item => !pdf_text_control_only(item.text))
    if visible.is_empty() {
      let source = items.to_owned()
      source.sort_by((a, b) => a.index.compare(b.index))
      return source
    }
    let originals : Map[Int, PdfTextItem] = Map([])
    let geometry = [
      for item in items => {
        originals[item.index] = item
        if !pdf_text_control_only(item.text) {
          item
        } else {
          let following = visible.filter(other => other.index > item.index)
          following.sort_by((a, b) => a.index.compare(b.index))
          let preceding = visible.filter(other => other.index < item.index)
          preceding.sort_by((a, b) => b.index.compare(a.index))
          let closing = item.text
            .iter()
            .all(char => {
              @bidi.bidi_class(char) is (@bidi.PDI | @bidi.PDF) ||
              char == '\n' ||
              char == '\r'
            })
          let (preferred, alternate) = if closing {
            (preceding.get(0), following.get(0))
          } else {
            (following.get(0), preceding.get(0))
          }
          let anchor = preferred.unwrap_or(alternate.unwrap_or(visible[0]))
          {
            ..item,
            bounds: anchor.bounds,
            quad: anchor.quad,
            glyph_transform: anchor.glyph_transform,
            font_size: anchor.font_size,
            vertical: anchor.vertical,
          }
        }
      }
    ]
    return [
      for item in pdf_text_reading_order_geometry(geometry[:]) => {
        originals[item.index]
      }
    ]
  }
  pdf_text_reading_order_geometry(items)
}

///|
fn pdf_text_reading_order_geometry(
  items : ArrayView[PdfTextItem],
) -> Array[PdfTextItem] {
  if items.is_empty() {
    return []
  }
  if !items.iter().all(pdf_text_is_horizontal) {
    return pdf_text_oriented_reading_order(items)
  }
  let output : Array[PdfTextItem] = []
  for block in pdf_text_reading_blocks(items, 0) {
    output.append(pdf_text_order_in_block(block[:]))
  }
  output
}

///|
fn pdf_text_compact_table(
  items : ArrayView[PdfTextItem],
  height : Double,
) -> Bool {
  let cut = pdf_text_projection_gap(items, true, height * 1.5)
  guard cut is Some(cut) else { return false }
  let left = items.filter(item => {
    (item.bounds.min_x + item.bounds.max_x) / 2.0 < cut
  })
  let right = items.filter(item => {
    (item.bounds.min_x + item.bounds.max_x) / 2.0 >= cut
  })
  let cells = fn(values : ArrayView[PdfTextItem]) -> Array[(Double, Int)] {
    let rows : Array[(Double, Int)] = []
    for item in values {
      if item.text.trim().is_empty() {
        continue
      }
      let key = pdf_text_line_key(item)
      match rows.search_by(row => (row.0 - key).abs() < height * 0.25) {
        Some(at) => rows[at] = (rows[at].0, rows[at].1 + item.text.length())
        None => rows.push((key, item.text.length()))
      }
    }
    rows.sort_by((a, b) => pdf_text_compare_number(b.0, a.0))
    rows
  }
  let a = cells(left[:])
  let b = cells(right[:])
  guard a.length() >= 3 && a.length() == b.length() else { return false }
  for index in 0..<a.length() {
    if (a[index].0 - b[index].0).abs() > height * 0.25 ||
      a[index].1 > 24 ||
      b[index].1 > 24 {
      return false
    }
  }
  true
}

///|
/// Use a coordinate view to order rotated/skewed blocks. Only source indices
/// from that view escape; returned glyphs retain their original PDF quads.
fn pdf_text_project_for_reading(
  item : PdfTextItem,
  axis : (Double, Double),
) -> PdfTextItem {
  let point = fn(point : PdfPoint) -> PdfPoint {
    {
      x: point.x * axis.0 + point.y * axis.1,
      y: point.x * -axis.1 + point.y * axis.0,
    }
  }
  let quad : PdfQuad = {
    p0: point(item.quad.p0),
    p1: point(item.quad.p1),
    p2: point(item.quad.p2),
    p3: point(item.quad.p3),
  }
  let bounds : PdfBounds = {
    min_x: quad.p0.x.min(quad.p1.x).min(quad.p2.x).min(quad.p3.x),
    min_y: quad.p0.y.min(quad.p1.y).min(quad.p2.y).min(quad.p3.y),
    max_x: quad.p0.x.max(quad.p1.x).max(quad.p2.x).max(quad.p3.x),
    max_y: quad.p0.y.max(quad.p1.y).max(quad.p2.y).max(quad.p3.y),
  }
  let glyph_transform = item.glyph_transform.map(matrix => {
    match matrix {
      [a, b, c, d, e, f] =>
        [
          a * axis.0 + b * axis.1,
          a * -axis.1 + b * axis.0,
          c * axis.0 + d * axis.1,
          c * -axis.1 + d * axis.0,
          e * axis.0 + f * axis.1,
          e * -axis.1 + f * axis.0,
        ]
      _ => matrix
    }
  })
  { ..item, quad, bounds, glyph_transform, }
}

///|
fn pdf_text_oriented_reading_order(
  items : ArrayView[PdfTextItem],
) -> Array[PdfTextItem] {
  let groups : Array[Array[PdfTextItem]] = []
  let originals : Map[Int, PdfTextItem] = Map([])
  for item in items {
    originals[item.index] = item
    match groups.search_by(group => pdf_text_same_orientation(group[0], item)) {
      Some(at) => groups[at].push(item)
      None => groups.push([item])
    }
  }
  let output : Array[PdfTextItem] = []
  for group in groups {
    if group[0].vertical {
      output.append(pdf_text_order_in_block(group[:]))
      continue
    }
    let axis = pdf_text_writing_axis(group[0])
    let projected = [
      for item in group => pdf_text_project_for_reading(item, axis)
    ]
    for block in pdf_text_reading_blocks(projected[:], 0) {
      for item in pdf_text_order_in_block(block[:]) {
        output.push(originals[item.index])
      }
    }
  }
  output
}

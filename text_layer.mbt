///|
/// One DOM text span. The affine matrix maps a unit square with a top-left
/// origin onto the glyph's selection quad in viewport coordinates.
/// Offsets into `text` use UTF-16 code units, as in the browser DOM.
pub(all) struct PdfTextLayerItem {
  item_index : Int
  text : String
  separator : String
  matrix : Array[Double]
  font_family : String
  font_weight : String
  font_style : String
  vertical : Bool
} derive(Eq, Debug, ToJson)

///|
pub(all) struct PdfTextLayer {
  page : Int
  viewport : PdfViewport
  items : Array[PdfTextLayerItem]
} derive(Eq, Debug, ToJson)

///|
/// Produce geometry for native cursor selection over any paint backend.
/// The layer retains paint/source indices and does not draw visible glyphs.
///
/// ```mbt check
/// test {
///   let page : @pdf-viewer.PdfPageModel = {
///     number: 1,
///     origin_x: 0.0,
///     origin_y: 0.0,
///     width: 200.0,
///     height: 300.0,
///     rotation: 0,
///     fonts: [],
///     items: [],
///     annotations: [],
///     text: "",
///   }
///   let layer = page.text_layer(scale=2.0, rotation=90)
///   assert_eq(layer.viewport.width, 600.0)
///   assert_true(layer.items.is_empty())
/// }
/// ```
pub fn PdfPageModel::text_layer(
  self : PdfPageModel,
  scale? : Double = 1.0,
  rotation? : Int = self.rotation,
) -> PdfTextLayer {
  let viewport = self.viewport(scale~, rotation~)
  let output : Array[PdfTextLayerItem] = []
  let mut previous : PdfTextItem? = None
  for item in self.items {
    guard item is Text(text) && !text.text.is_empty() else { continue }
    let quad = text.quad
    let top_left = viewport.convert_to_viewport_point(quad.p1)
    let top_right = viewport.convert_to_viewport_point(quad.p2)
    let bottom_left = viewport.convert_to_viewport_point(quad.p0)
    output.push({
      item_index: text.index,
      text: text.text,
      separator: match previous {
        Some(last) => pdf_text_layer_separator(last, text)
        None => ""
      },
      matrix: [
        top_right.x - top_left.x,
        top_right.y - top_left.y,
        bottom_left.x - top_left.x,
        bottom_left.y - top_left.y,
        top_left.x,
        top_left.y,
      ],
      font_family: pdf_svg_font_family_for_page(self, text.font),
      font_weight: pdf_svg_font_weight_for_page(self, text.font),
      font_style: pdf_svg_font_style_for_page(self, text.font),
      vertical: text.vertical,
    })
    previous = Some(text)
  }
  { page: self.number, viewport, items: output, }
}

///|
/// Determine separators in the writing direction, independently of page
/// rotation. This preserves vertical columns and rotated text; general reading
/// order, bidi and paragraph reconstruction require a separate logical index.
fn pdf_text_layer_separator(
  previous : PdfTextItem,
  current : PdfTextItem,
) -> String {
  if previous.vertical != current.vertical {
    return "\n"
  }
  let first = previous.quad
  let next = current.quad
  let (dx, dy) = if previous.vertical {
    (first.p0.x - first.p1.x, first.p0.y - first.p1.y)
  } else {
    (first.p2.x - first.p1.x, first.p2.y - first.p1.y)
  }
  let length = (dx * dx + dy * dy).sqrt()
  if length < 0.000001 {
    return ""
  }
  let unit_x = dx / length
  let unit_y = dy / length
  let delta_x = next.p1.x - first.p1.x
  let delta_y = next.p1.y - first.p1.y
  let cross = (delta_x * unit_y - delta_y * unit_x).abs()
  let height_x = first.p0.x - first.p1.x
  let height_y = first.p0.y - first.p1.y
  let height = (height_x * height_x + height_y * height_y).sqrt()
  let threshold = if previous.vertical {
    let width_x = first.p2.x - first.p1.x
    let width_y = first.p2.y - first.p1.y
    (width_x * width_x + width_y * width_y).sqrt() * 0.5
  } else {
    height * 0.5
  }
  if cross > threshold.max(0.000001) {
    return "\n"
  }
  let gap = delta_x * unit_x + delta_y * unit_y - length
  if !previous.vertical &&
    gap > height * 0.25 &&
    !previous.text.has_suffix(" ") &&
    !current.text.has_prefix(" ") {
    " "
  } else {
    ""
  }
}

///|
/// A cursor selection mapped back onto page items. A partial ligature retains
/// the full source glyph's quad. Raw PDF byte offsets are not represented here.
pub(all) struct PdfTextRangeSelection {
  page : Int
  text : String
  item_indices : Array[Int]
  quads : Array[PdfQuad]
  start_item : Int
  start_offset : Int
  end_item : Int
  end_offset : Int
} derive(Eq, Debug, ToJson)

///|
/// Select a half-open DOM text range using stable display-list indices and
/// UTF-16 offsets. Reversed endpoints are normalized. Unknown indices,
/// out-of-bounds offsets and offsets inside surrogate pairs return None.
///
/// ```mbt check
/// test {
///   let page : @pdf-viewer.PdfPageModel = {
///     number: 1,
///     origin_x: 0.0,
///     origin_y: 0.0,
///     width: 200.0,
///     height: 300.0,
///     rotation: 0,
///     fonts: [],
///     items: [],
///     annotations: [],
///     text: "",
///   }
///   assert_eq(page.select_text(0, 0, 0, 1), None)
/// }
/// ```
pub fn PdfPageModel::select_text(
  self : PdfPageModel,
  start_item : Int,
  start_offset : Int,
  end_item : Int,
  end_offset : Int,
) -> PdfTextRangeSelection? {
  let items = self.text_content().items
  let first = items.search_by(item => item.index == start_item)
  let last = items.search_by(item => item.index == end_item)
  guard first is Some(first) && last is Some(last) else { return None }
  let (first, first_offset, last, last_offset) = if first > last ||
    (first == last && start_offset > end_offset) {
    (last, end_offset, first, start_offset)
  } else {
    (first, start_offset, last, end_offset)
  }
  if first_offset < 0 ||
    first_offset > items[first].text.length() ||
    last_offset < 0 ||
    last_offset > items[last].text.length() {
    return None
  }
  let output = StringBuilder()
  let indices : Array[Int] = []
  let quads : Array[PdfQuad] = []
  for position in first..<=last {
    let item = items[position]
    let begin = if position == first { first_offset } else { 0 }
    let end = if position == last { last_offset } else { item.text.length() }
    guard item.text.get_view(start=begin, end~) is Some(slice) else {
      return None
    }
    if position > first {
      output.write_string(pdf_text_layer_separator(items[position - 1], item))
    }
    output.write_string(slice.to_owned())
    if !slice.is_empty() {
      indices.push(item.index)
      quads.push(item.quad)
    }
  }
  Some({
    page: self.number,
    text: output.to_string(),
    item_indices: indices,
    quads,
    start_item: items[first].index,
    start_offset: first_offset,
    end_item: items[last].index,
    end_offset: last_offset,
  })
}

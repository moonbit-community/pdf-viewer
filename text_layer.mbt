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
///     blend_space: "DeviceRGB",
///     blend_profile_id: None,
///     blend_calibration: None,
///     icc_profiles: [],
///     origin_x: 0.0,
///     origin_y: 0.0,
///     width: 200.0,
///     height: 300.0,
///     user_unit: 1.0,
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
  let text_items = pdf_text_reading_order_of_page_items(self.items[:])
  for index, text in text_items {
    guard !text.text.is_empty() else { continue }
    let quad = text.quad
    let top_left = viewport.convert_to_viewport_point(quad.p1)
    let top_right = viewport.convert_to_viewport_point(quad.p2)
    let bottom_left = viewport.convert_to_viewport_point(quad.p0)
    output.push({
      item_index: text.index,
      text: text.text,
      separator: pdf_text_separator_at(text_items[:], index),
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
  }
  { page: self.number, viewport, items: output, }
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
///     blend_space: "DeviceRGB",
///     blend_profile_id: None,
///     blend_calibration: None,
///     icc_profiles: [],
///     origin_x: 0.0,
///     origin_y: 0.0,
///     width: 200.0,
///     height: 300.0,
///     user_unit: 1.0,
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
      output.write_string(pdf_text_separator_at(items[:], position))
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

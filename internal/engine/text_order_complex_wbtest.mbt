///|
test "bidi preserves logical source order around a left to right digit run" {
  let viewer = unicode_search_test_document(["א", "1", "2", "ב"], positions=[
    (30.0, 100.0),
    (18.0, 100.0),
    (24.0, 100.0),
    (12.0, 100.0),
  ])
  let page = viewer.page(1).unwrap()
  assert_eq(page.text_content().text, "א12ב")
  assert_eq([ for item in page.text_content().items => item.index ], [
    0, 1, 2, 3,
  ])
  assert_eq([ for item in page.text_layer().items => item.item_index ], [
    0, 1, 2, 3,
  ])
  assert_eq(viewer.search("12")[0].item_indices, [1, 2])
  assert_eq(page.select_text(0, 0, 3, 1).unwrap().text, "א12ב")
}

///|
test "bidi recovers visual PDF order without reversing the digit run" {
  let viewer = unicode_search_test_document(["ב", "1", "2", "א"], positions=[
    (12.0, 100.0),
    (18.0, 100.0),
    (24.0, 100.0),
    (30.0, 100.0),
  ])
  let page = viewer.page(1).unwrap()
  assert_eq(page.text_content().text, "א12ב")
  assert_eq([ for item in page.text_content().items => item.index ], [
    3, 1, 2, 0,
  ])
  assert_eq(viewer.search("א12ב")[0].item_indices, [3, 1, 2, 0])
  assert_eq(page.select_text(3, 0, 0, 1).unwrap().text, "א12ב")
}

///|
test "bidi keeps multi scalar glyph mappings and supplementary characters intact" {
  let viewer = unicode_search_test_document(["אב", "😀", "ﬁ", "גד"], positions=[
    (30.0, 100.0),
    (24.0, 100.0),
    (18.0, 100.0),
    (12.0, 100.0),
  ])
  let page = viewer.page(1).unwrap()
  let items = page.text_content().items
  assert_eq(items.length(), 4)
  assert_eq([ for item in items => item.text ], ["אב", "😀", "ﬁ", "גד"])
  assert_eq(viewer.search("fi")[0].item_indices, [2])
  let glyph = [ for item in items if item.text == "😀" => item ][0]
  assert_eq(page.select_text(glyph.index, 0, glyph.index, 1), None)
  assert_eq(
    page.select_text(glyph.index, 0, glyph.index, 2).unwrap().text,
    "😀",
  )
}

///|
test "persistent column gutters are read by column below a full width heading" {
  let viewer = unicode_search_test_document(
    ["Heading", "Right2", "Left1", "Right1", "Left2"],
    positions=[
      (20.0, 170.0),
      (120.0, 126.0),
      (20.0, 140.0),
      (120.0, 140.0),
      (20.0, 126.0),
    ],
    widths=[16000, 3000, 3000, 3000, 3000],
  )
  let page = viewer.page(1).unwrap()
  assert_eq(page.text_content().text, "Heading\nLeft1\nLeft2\nRight1\nRight2")
  assert_eq([ for item in page.text_content().items => item.index ], [
    0, 2, 4, 3, 1,
  ])
  assert_eq([ for item in page.text_layer().items => item.item_index ], [
    0, 2, 4, 3, 1,
  ])
  assert_eq(viewer.search("Left1\nLeft2")[0].item_indices, [2, 4])
  assert_eq(page.select_text(2, 0, 4, 5).unwrap().text, "Left1\nLeft2")
  // The paint list stays in the original source order.
  assert_eq([ for item in page.items if item is Text(text) => text.index ], [
    0, 1, 2, 3, 4,
  ])
}

///|
test "column detection does not split a single line at ordinary word gaps" {
  let page = unicode_search_test_document(
      ["First", "Second"],
      positions=[(20.0, 100.0), (80.0, 100.0)],
      widths=[3000, 3000],
    )
    .page(1)
    .unwrap()
  assert_eq(page.text_content().text, "First Second")
}

///|
test "right to left multi line columns start at the right gutter" {
  let page = unicode_search_test_document(
      ["אב", "גד", "הו", "זח"],
      positions=[(20.0, 140.0), (20.0, 126.0), (120.0, 140.0), (120.0, 126.0)],
      widths=[2000, 2000, 2000, 2000],
    )
    .page(1)
    .unwrap()
  assert_eq(page.text_content().text, "הו\nזח\nאב\nגד")
  assert_eq([ for item in page.text_content().items => item.index ], [
    2, 3, 0, 1,
  ])
}

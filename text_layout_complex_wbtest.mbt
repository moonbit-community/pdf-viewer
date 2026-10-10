///|
fn layout_test_transform(
  document : PdfViewerDocument,
  matrix : String,
) -> Unit raise {
  let content = @utf8.decode(
    document.document.pdf_decode_stream(@syntax.PdfIndirect(4)).stream_bytes(),
  )
  font_scope_test_content(document, "q " + matrix + " cm " + content + " Q")
}

///|
test "rotated and skewed lines use their own baseline without rewriting source quads" {
  for matrix in ["0 1 -1 0 200 0", "-1 0 0 -1 200 200", "1 0.5 0.3 1 0 0"] {
    let document = unicode_search_test_document(
      ["Bottom", "Top2", "Top1"],
      positions=[(20.0, 60.0), (50.0, 100.0), (20.0, 100.0)],
      widths=[3000, 2400, 3000],
    )
    layout_test_transform(document, matrix)
    let page = document.page(1).unwrap()
    assert_eq(page.text, "Top1Top2\nBottom")
    assert_eq([ for item in page.text_content().items => item.index ], [2, 1, 0])
    let paint : Map[Int, PdfTextItem] = Map([])
    for item in page.items {
      if item is Text(item) {
        paint[item.index] = item
      }
    }
    for item in page.text_content().items {
      assert_eq(item, paint[item.index])
    }
    assert_eq(document.search("Top1Top2")[0].item_indices, [2, 1])
    assert_eq(page.select_text(2, 0, 0, 6).unwrap().text, page.text)
    assert_eq(
      [
        for item in page.text_layer(rotation=90).items => item.item_index
      ],
      [2, 1, 0],
    )
    assert_true(
      document
      .text_lexical_sources(1)
      .unwrap()
      .all(source => source.failure is None),
    )
  }
}

///|
test "rotation preserves column reading order and UTF16 source joins" {
  let document = unicode_search_test_document(
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
  layout_test_transform(document, "0 1 -1 0 200 0")
  let page = document.page(1).unwrap()
  assert_eq(page.text, "Heading\nLeft1\nLeft2\nRight1\nRight2")
  assert_eq([ for source in page.text_sources() => source.item_index ], [
    0, 2, 4, 3, 1,
  ])
  assert_eq(document.search("Left1\nLeft2")[0].item_indices, [2, 4])
}

///|
test "aligned short table cells read by row instead of column" {
  let document = unicode_search_test_document(
    ["A3", "B1", "A1", "B3", "B2", "A2"],
    positions=[
      (20.0, 80.0),
      (120.0, 120.0),
      (20.0, 120.0),
      (120.0, 80.0),
      (120.0, 100.0),
      (20.0, 100.0),
    ],
    widths=[1200, 1200, 1200, 1200, 1200, 1200],
  )
  let page = document.page(1).unwrap()
  assert_eq(page.text, "A1 B1\nA2 B2\nA3 B3")
  assert_eq([ for source in page.text_sources() => source.item_index ], [
    2, 1, 5, 4, 0, 3,
  ])
  assert_eq(page.select_text(2, 0, 3, 2).unwrap().text, page.text)
  assert_eq(document.search("A2 B2")[0].item_indices, [5, 4])
}

///|
test "aligned prose retains column reading order" {
  let document = unicode_search_test_document(
    [
      "Right prose line three has many words", "Left prose line one has many words",
      "Right prose line one has many words", "Left prose line two has many words",
      "Right prose line two has many words", "Left prose line three has many words",
    ],
    positions=[
      (120.0, 80.0),
      (20.0, 120.0),
      (120.0, 120.0),
      (20.0, 100.0),
      (120.0, 100.0),
      (20.0, 80.0),
    ],
    widths=[6000, 6000, 6000, 6000, 6000, 6000],
  )
  assert_eq(
    [
      for item in document.page(1).unwrap().text_content().items => item.index
    ],
    [1, 3, 5, 2, 4, 0],
  )
}

///|
test "explicit bidi override controls are source glyphs without painted coordinates" {
  let document = unicode_search_test_document(
    ["X", "\u202E", "A", "B", "\u202C", "Y"],
    positions=[
      (10.0, 100.0),
      (900.0, 900.0),
      (22.0, 100.0),
      (16.0, 100.0),
      (-900.0, -900.0),
      (28.0, 100.0),
    ],
    widths=[600, 0, 600, 600, 0, 600],
  )
  let page = document.page(1).unwrap()
  assert_eq(page.text, "X\u202EAB\u202CY")
  assert_eq([ for source in page.text_sources() => source.item_index ], [
    0, 1, 2, 3, 4, 5,
  ])
  assert_eq(page.select_text(0, 0, 5, 1).unwrap().text, page.text)
  assert_eq(document.search("AB")[0].item_indices, [2, 3])
  assert_eq(page.text_structure().paragraphs.length(), 1)
}

///|
test "nested isolate controls preserve logical text and supplementary ownership" {
  let document = unicode_search_test_document(
    ["X", "\u2067", "א", "😀", "ב", "\u2069", "Y"],
    positions=[
      (10.0, 100.0),
      (800.0, 800.0),
      (28.0, 100.0),
      (22.0, 100.0),
      (16.0, 100.0),
      (-800.0, -800.0),
      (34.0, 100.0),
    ],
    widths=[600, 0, 600, 600, 600, 0, 600],
  )
  let page = document.page(1).unwrap()
  assert_eq(page.text, "X\u2067א😀ב\u2069Y")
  assert_eq(page.select_text(3, 0, 3, 1), None)
  assert_eq(page.select_text(3, 0, 3, 2).unwrap().text, "😀")
  assert_eq(document.text_provenance(1).unwrap().length(), 7)
}

///|
test "directional boundary spacing measures a whole number run" {
  let document = unicode_search_test_document(["א", "1", "2", "ב"], positions=[
    (50.0, 100.0),
    (18.0, 100.0),
    (24.0, 100.0),
    (12.0, 100.0),
  ])
  let page = document.page(1).unwrap()
  assert_eq(page.text, "א 12ב")
  assert_eq(document.search("12")[0].index, 2)
  assert_eq(page.select_text(0, 0, 3, 1).unwrap().text, page.text)
  assert_eq([ for item in page.text_layer().items => item.separator ], [
    "", " ", "", "",
  ])
  assert_eq(
    [
      for source in page.text_sources() => (source.start, source.end)
    ],
    [(0, 1), (2, 3), (3, 4), (4, 5)],
  )
}

///|
test "explicit newline source does not gain geometry-inferred duplicate newlines" {
  let document = unicode_search_test_document(
    ["A", "\n", "B"],
    positions=[(20.0, 120.0), (800.0, 800.0), (20.0, 80.0)],
    widths=[600, 0, 600],
  )
  assert_eq(document.page(1).unwrap().text, "A\nB")
  assert_eq(
    [
      for source in document.page(1).unwrap().text_sources() => {
        (source.start, source.end)
      }
    ],
    [(0, 1), (1, 2), (2, 3)],
  )
}

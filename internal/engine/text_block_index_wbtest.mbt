///|
fn text_block_test_item(
  base : PdfTextItem,
  index : Int,
  text : String,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> PdfTextItem {
  {
    ..base,
    index,
    text,
    font_size: height,
    bounds: { min_x: x, min_y: y, max_x: x + width, max_y: y + height, },
    quad: {
      p0: { x, y, },
      p1: { x, y: y + height, },
      p2: { x: x + width, y: y + height, },
      p3: { x: x + width, y, },
    },
  }
}

///|
test "ordered block indexes preserve recursive gutters tables blanks and RTL source identity" {
  let base = unicode_search_test_document(["X"]).page(1).unwrap().text_content().items[0]
  let random = Ref(7919)
  fn next(limit : Int) -> Int {
    random.val = (random.val * 1664525 + 1013904223) & 0x7fffffff
    random.val % limit
  }
  for scenario in 0..<120 {
    let items : Array[PdfTextItem] = []
    let columns = 1 + next(4)
    let rows = 2 + next(18)
    for row in 0..<rows {
      for column in 0..<columns {
        let count = 1 + next(12)
        for character in 0..<count {
          let text = match next(10) {
            0 => " "
            1 => "אב"
            2 => "中"
            3 => "😀"
            4 => "\u2067"
            _ => "word"
          }
          let x = column.to_double() * 180.0 + character.to_double() * 9.0
          let y = 1000.0 -
            row.to_double() * (12.0 + (scenario % 3).to_double() * 6.0)
          let height = 7.0 + next(7).to_double()
          items.push(
            text_block_test_item(base, items.length(), text, x, y, 6.0, height),
          )
        }
      }
    }
    if scenario % 3 == 0 {
      items.push(
        text_block_test_item(
          base,
          items.length(),
          "Heading",
          0.0,
          1030.0,
          columns.to_double() * 180.0,
          20.0,
        ),
      )
    }
    if scenario % 5 == 0 {
      items.push(
        text_block_test_item(
          base,
          items.length(),
          "Footer",
          0.0,
          100.0,
          40.0,
          8.0,
        ),
      )
    }
    for i = items.length() - 1; i > 0; i = i - 1 {
      let j = next(i + 1)
      let previous = items[i]
      items[i] = items[j]
      items[j] = previous
    }
    let fast = pdf_text_reading_blocks(items[:], 0)
    let control = pdf_text_reading_blocks_legacy(items[:], 0)
    assert_eq(fast, control)
    let fast_text : Array[PdfTextItem] = []
    let control_text : Array[PdfTextItem] = []
    for block in fast {
      fast_text.append(pdf_text_order_in_block(block[:]))
    }
    for block in control {
      control_text.append(pdf_text_order_in_block(block[:]))
    }
    assert_eq(fast_text, control_text)
    assert_eq(
      pdf_join_text_items(fast_text[:]),
      pdf_join_text_items(control_text[:]),
    )
  }
}

///|
test "ordered block indexes retain blank degenerate and nonfinite fallback behavior" {
  let base = unicode_search_test_document(["X"]).page(1).unwrap().text_content().items[0]
  for text in ["", " ", "\n", "אב", "a"] {
    let items = [
      for i in 0..<24 => {
        text_block_test_item(
          base,
          i,
          text,
          (i % 4).to_double() * 20.0,
          (i / 4).to_double() * 20.0,
          0.0,
          0.0,
        )
      }
    ]
    for depth in [0, 15, 16] {
      assert_eq(
        pdf_text_reading_blocks(items[:], depth),
        pdf_text_reading_blocks_legacy(items[:], depth),
      )
    }
  }
  let items = [
    for i in 0..<8 => {
      text_block_test_item(
        base,
        i,
        "x",
        i.to_double() * 20.0,
        i.to_double() * 20.0,
        6.0,
        10.0,
      )
    }
  ]
  for value in [1000.0, 1.0 / 0.0, -1.0 / 0.0, 0.0 / 0.0, 1.7e308] {
    let input = items.copy()
    input[0] = { ..input[0], bounds: { ..input[0].bounds, min_x: value, }, }
    let ids = fn(blocks : Array[Array[PdfTextItem]]) {
      [
        for block in blocks => [ for item in block => item.index ]
      ]
    }
    assert_eq(
      ids(pdf_text_reading_blocks(input[:], 0)),
      ids(pdf_text_reading_blocks_legacy(input[:], 0)),
    )
  }
}

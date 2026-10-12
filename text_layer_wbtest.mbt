///|
test "text layer corners follow the public viewport for every quarter rotation" {
  let page = annotation_test_page(
    [],
    contents="BT /F1 10 Tf 20 80 Td (AB) Tj ET",
    resources="<< /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >>",
  )
  for rotation in [0, 90, 180, 270, -90, 450] {
    for scale in [0.5, 1.0, 2.0] {
      let layer = page.text_layer(scale~, rotation~)
      assert_eq(layer.items.length(), 2)
      for index, item in layer.items {
        let source = page.text_content().items[index]
        assert_eq(item.item_index, source.index)
        assert_eq(item.quad, source.quad)
        let left = layer.viewport.convert_to_viewport_point(source.quad.p1)
        let right = layer.viewport.convert_to_viewport_point(source.quad.p2)
        let bottom = layer.viewport.convert_to_viewport_point(source.quad.p0)
        let matrix = item.matrix
        assert_eq((matrix[4], matrix[5]), (left.x, left.y))
        assert_eq(
          (matrix[4] + matrix[0], matrix[5] + matrix[1]),
          (right.x, right.y),
        )
        assert_eq(
          (matrix[4] + matrix[2], matrix[5] + matrix[3]),
          (bottom.x, bottom.y),
        )
      }
    }
  }
  assert_true(page.render_svg(scale=2.0, rotation=90).contains("<svg "))
}

///|
test "cursor ranges preserve sparse source indices partial glyphs and reverse endpoints" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream(
      "", "BT /F1 10 Tf 20 80 Td (A) Tj ET 0 0 1 1 re f BT /F1 10 Tf 26.67 80 Td (B) Tj ET",
    ),
    "<< /Type /Font /Subtype /TrueType /BaseFont /RangeProbe /FirstChar 65 /LastChar 66 /Widths [667 667] /FontDescriptor << /FontBBox [0 -200 1000 800] /Ascent 800 /Descent -200 >> /ToUnicode 6 0 R >>",
    annotation_test_stream(
      "", "2 beginbfchar <41> <00660069> <42> <D83DDE00> endbfchar",
    ),
  ])
  let page = document.page(1).unwrap()
  let text = page.text_content().items
  assert_eq([ for item in text => item.text ], ["fi", "😀"])
  assert_true(text[1].index > text[0].index + 1)
  let selection = page.select_text(text[0].index, 1, text[1].index, 2).unwrap()
  assert_eq(selection.text, "i😀")
  assert_eq(selection.item_indices, [text[0].index, text[1].index])
  assert_eq(selection.quads, [text[0].quad, text[1].quad])
  assert_eq(
    page.select_text(text[1].index, 2, text[0].index, 1),
    Some(selection),
  )
  assert_eq(page.select_text(text[0].index, 0, text[1].index, 1), None)
  assert_eq(page.select_text(text[0].index, -1, text[1].index, 2), None)
  assert_eq(page.select_text(text[0].index, 3, text[1].index, 2), None)
  assert_eq(page.select_text(999, 0, text[1].index, 2), None)
  let empty = page.select_text(text[0].index, 1, text[0].index, 1).unwrap()
  assert_eq(empty.text, "")
  assert_true(empty.item_indices.is_empty())
  for rotation in [0, 90, 180, 270] {
    let layer = page.text_layer(rotation~, scale=2.0)
    assert_eq(
      layer.select_text(text[0].index, 1, text[1].index, 2),
      Some(selection),
    )
    assert_eq(
      layer.select_text(text[1].index, 2, text[0].index, 1),
      Some(selection),
    )
    assert_eq(layer.select_text(text[0].index, 0, text[1].index, 1), None)
    assert_eq(layer.select_text(text[0].index, -1, text[1].index, 2), None)
    assert_eq(layer.select_text(999, 0, text[1].index, 2), None)
    assert_eq(
      layer.select_text(text[0].index, 1, text[0].index, 1),
      Some(empty),
    )
  }
}

///|
test "cursor text separators preserve rotated baselines and vertical columns" {
  let page = annotation_test_page(
    [],
    contents="BT /F1 10 Tf 0 1 -1 0 80 20 Tm (AB) Tj 0 -20 Td (CD) Tj ET",
    resources="<< /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >>",
  )
  assert_eq([ for item in page.text_layer().items => item.separator ], [
    "", "", "\n", "",
  ])
  let text = page.text_content().items
  assert_eq(
    page.select_text(text[0].index, 0, text[3].index, 1).unwrap().text,
    "AB\nCD",
  )
  let vertical = cid_vertical_test_document(
      "BT /F1 10 Tf 20 100 Td <00410042> Tj 30 0 Td <0043> Tj ET",
    )
    .page(1)
    .unwrap()
  assert_eq([ for item in vertical.text_layer().items => item.separator ], [
    "", "", "\n",
  ])
  assert_true(vertical.text_layer().items.iter().all(item => item.vertical))
  for source in [page, vertical] {
    let items = source.text_content().items
    let layer = source.text_layer(scale=1.5, rotation=270)
    for first in 0..<items.length() {
      for last in first..<items.length() {
        assert_eq(
          layer.select_text(
            items[first].index,
            0,
            items[last].index,
            items[last].text.length(),
          ),
          source.select_text(
            items[first].index,
            0,
            items[last].index,
            items[last].text.length(),
          ),
        )
      }
    }
  }
}

///|
test "DOM geometry remains affine under CTM shear and nonzero page origins" {
  let original = annotation_test_page(
    [],
    contents="2 0.5 0.3 3 5 7 cm BT /F1 10 Tf 20 30 Td (A) Tj ET",
    resources="<< /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >>",
  )
  let page = { ..original, origin_x: 20.0, origin_y: 30.0, }
  let layer = page.text_layer(scale=1.5, rotation=270)
  let item = layer.items[0]
  let source = page.text_content().items[0]
  let point = layer.viewport.convert_to_viewport_point(source.quad.p3)
  assert_true(
    (item.matrix[4] + item.matrix[0] + item.matrix[2] - point.x).abs() <
    0.000001,
  )
  assert_true(
    (item.matrix[5] + item.matrix[1] + item.matrix[3] - point.y).abs() <
    0.000001,
  )
}

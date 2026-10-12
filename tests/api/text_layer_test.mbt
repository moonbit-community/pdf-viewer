///|
test "public DOM text geometry and cursor selection share the decoded page" {
  let document = pdf_viewer_fixture()
  let page = document.page(1).unwrap()
  let layer = page.text_layer(scale=1.5, rotation=90)
  assert_eq(layer.page, 1)
  assert_eq(layer.items.length(), 10)
  assert_eq(layer.viewport.rotation, 90)
  let first = layer.items[0]
  let last = layer.items[9]
  let selected = page
    .select_text(first.item_index, 0, last.item_index, 1)
    .unwrap()
  assert_eq(selected.text, "Hello\nWorld")
  assert_eq(selected.item_indices.length(), 10)
  assert_eq(selected.quads.length(), 10)
  let svg = page.render_svg(scale=1.5, rotation=90)
  assert_eq(document.render_svg_with_rotation(1, 90, scale=1.5), Some(svg))
}

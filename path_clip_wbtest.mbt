///|
test "even-odd path fill and clip retain separate winding rules" {
  let page = annotation_test_page(
    [],
    contents="10 10 80 80 re 30 30 40 40 re f* 110 10 80 80 re 130 30 40 40 re W* n 0 0 200 200 re f",
  )
  let fill = stroke_test_path(page)
  let clip = stroke_test_path(page, index=1)
  assert_true(fill.fill_even_odd)
  assert_true(!clip.fill_even_odd)
  assert_true(clip.clips[0].even_odd)
  let svg = pdf_render_page_svg(page, 2.0, 0)
  assert_true(svg.contains("fill-rule=\"evenodd\""))
  assert_true(svg.contains("clip-rule=\"evenodd\" transform=\"scale(2)\""))
}

///|
test "W S paints using the old clip before installing the new clip" {
  let page = annotation_test_page(
    [],
    contents="20 w 40 40 80 80 re W S 0 0 200 200 re f",
  )
  let stroke = stroke_test_path(page)
  let fill = stroke_test_path(page, index=1)
  assert_eq(stroke.clips.length(), 0)
  assert_eq(fill.clips.length(), 1)
  assert_true(fill.clips[0].svg_path.contains("M 40 160"))
}

///|
test "empty clipping paths suppress subsequent paints and survive q Q" {
  let page = annotation_test_page(
    [],
    contents="10 10 m W n q 0 0 200 200 re f Q 0 0 20 20 re f",
  )
  for index in 0..<2 {
    let path = stroke_test_path(page, index~)
    assert_eq(path.clips[0].svg_path, "")
  }
  let svg = pdf_render_page_svg(page, 1.0, 0)
  assert_true(svg.contains("<path d=\"\"/>"))
}

///|
test "nested Form clip intersects transformed bbox and restores caller scope" {
  let page = annotation_test_page(
    [],
    contents="10 10 100 100 re W n q 2 0 0 2 20 30 cm /F Do Q 0 0 200 200 re f",
    resources="<< /XObject << /F 5 0 R >> >>",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 30 30] /Matrix [1 0.25 0.5 1 5 7] /Resources << >>",
        "0 0 30 30 re 8 8 14 14 re W* n 0 0 40 40 re f",
      ),
    ],
  )
  let form = stroke_test_path(page)
  let caller = stroke_test_path(page, index=1)
  assert_eq(form.clips.length(), 3)
  assert_true(form.clips[0].even_odd)
  assert_eq(caller.clips.length(), 1)
  assert_true(!caller.clips[0].even_odd)
  assert_true(form.clips[1].svg_path.contains("M 30 156"))
}

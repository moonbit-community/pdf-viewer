///|
test "annotation fallback retains line endings interior colour opacity and source index" {
  let page = annotation_test_page([
    "<< /Subtype /Line /Rect [10 10 100 60] /L [15 20 95 50] /LE [/OpenArrow /Diamond] /C [1 0 0] /IC [0 1 0] /CA 0.5 /BS << /W 2 /S /D /D [2 3] >> >>",
    "<< /Subtype /Square /Rect [10 70 50 100] /C [0 0 1] /IC [1 0.5 0] >>", "<< /Subtype /Circle /Rect [60 70 100 100] /IC [0.5] >>",
  ])
  assert_eq(page.annotations[0].style.line_endings, ["OpenArrow", "Diamond"])
  assert_eq(page.annotations[0].style.opacity, 0.5)
  assert_eq(page.annotations[0].style.interior_color, Some("#00FF00"))
  let svg = page.render_svg()
  assert_true(svg.contains("data-pdf-line-ending=\"OpenArrow\""))
  assert_true(svg.contains("data-pdf-line-ending=\"Diamond\""))
  assert_true(svg.contains("stroke-dasharray=\"2 3\""))
  assert_true(svg.contains("fill=\"#FF8000\""))
  assert_true(svg.contains("fill=\"#808080\""))
  assert_true(svg.contains("opacity=\"0.5\""))
}

///|
test "annotation squiggly produces a wave rather than a dashed underline" {
  let page = annotation_test_page([
    "<< /Subtype /Squiggly /Rect [10 10 90 30] /QuadPoints [10 30 90 30 10 10 90 10] /C [1 0 0] >>",
  ])
  let svg = page.render_svg()
  assert_true(svg.contains("data-pdf-markup=\"squiggly\""))
  assert_true(!svg.contains("stroke-dasharray"))
}

///|
test "annotation uses licensed named icons caret and generated stamp" {
  let page = annotation_test_page([
    "<< /Subtype /Text /Rect [10 10 30 30] /Name /Comment /Contents (Review) >>",
    "<< /Subtype /FileAttachment /Rect [40 10 60 30] /Name /Paperclip >>", "<< /Subtype /Caret /Rect [70 10 90 30] /C [1 0 0] >>",
    "<< /Subtype /Stamp /Rect [10 40 100 70] /Name /Approved >>",
  ])
  assert_eq(page.annotations.length(), 4)
  let svg = page.render_svg()
  assert_true(svg.contains("data-pdf-annotation-icon=\"Comment\""))
  assert_true(svg.contains("data-pdf-annotation-icon=\"Paperclip\""))
  assert_true(svg.contains("data-pdf-annotation-type=\"caret\""))
  assert_true(page.annotations[3].appearance is Some(_))
  assert_true(svg.contains("Approved"))
}

///|
test "annotation NoZoom NoRotate keep screen anchor and are ignored in print copies" {
  let page = annotation_test_page([
    "<< /Subtype /Square /Rect [10 20 30 40] /F 28 /IC [1 0 0] >>",
  ])
  let svg = pdf_render_page_svg(page, 2.0, 90)
  assert_true(
    svg.contains("translate(20 320) rotate(-90) scale(0.5) translate(-20 -320)"),
  )
  let printed = page.with_print_annotations()
  assert_true(
    !printed.annotations[0].style.no_zoom &&
    !printed.annotations[0].style.no_rotate,
  )
  assert_eq(printed.annotations[0].flags, 28)
  assert_true(
    page.annotations[0].style.no_zoom && page.annotations[0].style.no_rotate,
  )
  let plan = page.canvas_plan(scale=2.0, rotation=90).stringify()
  assert_true(plan.contains("\"no_zoom\":true"))
  assert_true(plan.contains("\"anchor\":[10,160]"))
}

///|
test "supplied annotation AP retains its own opacity without applying CA twice" {
  let document = field_layout_document(
    "<< /Subtype /Square /Rect [0 0 40 20] /CA 0.5 /AP << /N 6 0 R >> >>",
    extra=[
      annotation_test_stream(
        "/BBox [0 0 40 20] /Resources << /ExtGState << /G << /ca 0.5 >> >> >>", "/G gs 1 0 0 rg 0 0 40 20 re f",
      ),
    ],
  )
  let annotation = document.page(1).unwrap().annotations[0]
  assert_eq(annotation.style.opacity, 1.0)
  assert_true(annotation.appearance is Some(_))
  assert_true(document.render_svg(1).unwrap().contains("fill-opacity=\"0.5\""))
}

///|
test "pattern build budget never silently changes the last paint to black" {
  let contents = "/Pattern cs /P scn " +
    [ for _ in 0..<257 => "0 0 1 1 re f" ].join(" ")
  let page = annotation_test_page(
    [],
    contents~,
    resources="<< /Pattern << /P 5 0 R >> >>",
    extra=[
      annotation_test_stream(
        "/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 1 1] /XStep 1 /YStep 1 /Resources << >>",
        "1 0 0 rg 0 0 1 1 re f",
      ),
    ],
  )
  assert_eq(page.items.length(), 257)
  let diagnostics = page.graphics_diagnostics()
  assert_eq(diagnostics.length(), 1)
  assert_eq(diagnostics[0].code, "PDF_PATTERN_RESOURCE")
  assert_eq(diagnostics[0].item, 256)
  assert_true(page.canvas_plan().stringify().contains("PDF_PATTERN_RESOURCE"))
}

///|
test "missing stroke and fill pattern resources fail explicitly" {
  let page = annotation_test_page(
    [],
    contents="/Pattern cs /Missing scn 0 0 10 10 re f /Pattern CS /Missing SCN 20 0 10 10 re S",
  )
  let diagnostics = page.graphics_diagnostics()
  assert_eq(diagnostics.length(), 2)
  assert_true(diagnostics.all(value => value.code == "PDF_PATTERN_RESOURCE"))
}

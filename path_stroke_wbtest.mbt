///|
fn stroke_test_path(page : PdfPageModel, index? : Int = 0) -> PdfPathItem raise {
  let paths = page.items.filter_map(item => {
    match item {
      Path(path) => Some(path)
      _ => None
    }
  })
  guard paths.get(index) is Some(path) else { fail("missing path") }
  path
}

///|
test "affine strokes retain user-space pen metrics and complete CTM" {
  let page = annotation_test_page(
    [],
    contents="3 0.5 1 2 20 30 cm 4 w [6 3] 2 d 1 J 2 j 8 M 0 0 m 20 0 l 20 15 l S",
  )
  let path = stroke_test_path(page)
  guard path.stroke is Some(stroke) else { fail("missing affine stroke") }
  assert_eq(stroke.svg_path, "M 0 0 L 20 0 L 20 -15")
  assert_eq(stroke.transform, [3.0, -0.5, -1.0, 2.0, 20.0, 170.0])
  assert_eq(stroke.line_width, 4.0)
  assert_eq(stroke.dash_array, [6.0, 3.0])
  assert_eq(stroke.dash_phase, 2.0)
  assert_eq(stroke.miter_limit, 8.0)
  assert_eq(path.line_cap, 1)
  assert_eq(path.line_join, 2)
  // Compatibility geometry stays in page space for fills and clipping.
  assert_eq(path.svg_path, "M 20 170 L 80 160 L 95 130")
  for scale in [0.5, 1.0, 2.0] {
    let output = StringBuilder()
    pdf_svg_affine_stroke(output, path, stroke, scale, "#000000")
    let svg = output.to_string()
    assert_true(svg.contains("stroke-width=\"4\""))
    assert_true(svg.contains("stroke-dasharray=\"6 3\""))
    assert_true(svg.contains("stroke-dashoffset=\"2\""))
    assert_true(svg.contains("stroke-linecap=\"round\""))
    assert_true(svg.contains("stroke-linejoin=\"bevel\""))
    assert_true(svg.contains("stroke-miterlimit=\"8\""))
    assert_true(
      svg.contains(
        "transform=\"matrix(" +
        pdf_svg_matrix_values(stroke.transform.map(v => v * scale)) +
        ")\"",
      ),
    )
  }
}

///|
test "stroke transform includes page origin reflection and viewport rotation" {
  let viewer = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [-20 -10 180 190] /Contents 4 0 R >>",
    annotation_test_stream("", "-2 0 0 3 60 15 cm 2 w 0 0 m 10 10 l S"),
  ])
  guard viewer.page(1) is Some(page) else { fail("missing page") }
  let path = stroke_test_path(page)
  guard path.stroke is Some(stroke) else { fail("missing affine stroke") }
  assert_eq(stroke.transform, [-2.0, 0.0, 0.0, 3.0, 80.0, 175.0])
  for rotation in [0, 90, 180, 270] {
    let svg = pdf_render_page_svg(page, 2.0, rotation)
    assert_true(svg.contains("transform=\"matrix(-4 0 0 6 160 350)\""))
    assert_true(svg.contains("stroke-width=\"2\""))
  }
}

///|
test "page-space clips stay outside the affine stroke and scale once" {
  let page = annotation_test_page(
    [],
    contents="10 20 80 60 re W n 3 0.5 1 2 20 30 cm 4 w 0 0 m 40 20 l S",
  )
  let path = stroke_test_path(page)
  guard path.stroke is Some(_) && path.clip_path is Some(clip) else {
    fail("missing stroke or clip")
  }
  assert_true(clip.contains("M 10 180"))
  assert_true(clip.contains("L 90 120"))
  let svg = pdf_render_page_svg(page, 2.0, 0)
  assert_true(svg.contains("transform=\"scale(2)\""))
  assert_true(svg.contains("transform=\"matrix(6 -1 -2 4 40 340)\""))
  assert_true(svg.contains("clip-path=\"url(#pdf-clip-0"))
}

///|
test "default and graphics-state miter limits reach SVG strokes" {
  for (operator, expected) in [("", 10.0), ("/G gs", 2.0)] {
    let page = annotation_test_page(
      [],
      contents=operator + " 2 w 10 10 m 20 70 l 30 10 l S",
      resources="<< /ExtGState << /G << /ML 2 >> >> >>",
    )
    let path = stroke_test_path(page)
    guard path.stroke is Some(stroke) else { fail("missing stroke") }
    assert_eq(stroke.miter_limit, expected)
    assert_true(
      pdf_render_page_svg(page, 1.0, 0).contains(
        "stroke-miterlimit=\"" + expected.to_string() + "\"",
      ),
    )
  }
}

///|
test "stroke patterns cancel only the stroke-local coordinate transform" {
  let page = annotation_test_page(
    [],
    contents="2 0 0 3 10 20 cm /Pattern CS /P SCN 4 w 0 0 m 40 20 l S",
    resources="<< /Pattern << /P 5 0 R >> >>",
    extra=[
      annotation_test_stream(
        "/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 4 4] /XStep 4 /YStep 4 /Resources << >>",
        "1 0 0 rg 0 0 2 4 re f",
      ),
    ],
  )
  let path = stroke_test_path(page)
  guard path.stroke is Some(stroke) && path.stroke_pattern is Some(pattern) else {
    fail("missing patterned stroke")
  }
  let page_transform = pdf_svg_shading_transform(page, pattern.matrix, 1.0)
  let compensated = pdf_svg_stroke_pattern_transform(
    Some(stroke),
    page_transform,
  )
  assert_true(
    compensated.has_prefix("matrix(0.5 0 0 0.3333333333333333 -5 -60) "),
  )
  assert_true(compensated.has_suffix(page_transform))
  let svg = pdf_render_page_svg(page, 2.0, 0)
  assert_true(svg.contains("patternTransform=\"" + compensated + "\""))
  assert_true(svg.contains("stroke=\"url(#pdf-stroke-pattern-0)\""))
}

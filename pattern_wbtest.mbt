///|
fn pattern_test_page(
  paint_type : Int,
  base_space : String,
  base_components : String,
  pattern_contents : String,
) -> PdfPageModel raise {
  let page_contents = "/Cs cs " +
    base_components +
    " /P1 scn 20 20 100 100 re f"
  let viewer = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] " +
    "/Resources << /Pattern << /P1 5 0 R >> " +
    "/ColorSpace << /Cs [/Pattern " +
    base_space +
    "] >> >> " +
    "/Contents 4 0 R >>",
    annotation_test_stream("", page_contents),
    annotation_test_stream(
      "/Type /Pattern /PatternType 1 /PaintType " +
      paint_type.to_string() +
      " /TilingType 1 /BBox [0 0 10 10] /XStep 10 /YStep 10 " +
      "/Resources << >>",
      pattern_contents,
    ),
  ])
  viewer.page(1).unwrap()
}

///|
test "uncolored tiling patterns inherit gray rgb and cmyk base colours" {
  for
    (space, components, expected) in [
      ("/DeviceGray", "0.5", "#808080"),
      ("/DeviceRGB", "0.2 0.5 0.8", "#3380CC"),
      ("/DeviceCMYK", "0.1 0.2 0.3 1", "#201C15"),
    ] {
    let page = pattern_test_page(
      2, space, components, "0 0 5 10 re f 2 2 m 8 8 l S",
    )
    let svg = page.render_svg(scale=1.0, rotation=0)
    assert_true(svg.contains("fill=\"url(#pdf-pattern-"))
    assert_true(svg.contains("fill=\"" + expected + "\""))
    assert_true(svg.contains("stroke=\"" + expected + "\""))
  }
}

///|
test "colored tiling pattern retains its cell colour" {
  let page = pattern_test_page(
    1, "/DeviceRGB", "0.2 0.5 0.8", "0.9 0.1 0.2 rg 0 0 10 10 re f",
  )
  let svg = page.render_svg(scale=1.0, rotation=0)
  assert_true(svg.contains("fill=\"#E61A33\""))
  assert_true(!svg.contains("fill=\"#3380CC\""))
}

///|
test "tiling pattern output scale is applied once" {
  let page = pattern_test_page(
    1, "/DeviceRGB", "0.2 0.5 0.8", "0.2 0.4 0.8 rg 0 0 10 10 re f",
  )
  let svg = page.render_svg(scale=2.0, rotation=0)
  assert_true(svg.contains("patternTransform=\"matrix(1 0 0 -1 0 200)\""))
}

///|
test "uncolored tiling patterns use the calibrated base colour for fill and stroke" {
  let page = pattern_test_page(
    2, "[/CalGray << /WhitePoint [1 1 1] /Gamma 2 >>]", "0.49019607843137253", "0 0 5 10 re f 2 2 m 8 8 l S",
  )
  let svg = page.render_svg()
  assert_true(svg.contains("fill=\"#8F8F8F\""))
  assert_true(svg.contains("stroke=\"#8F8F8F\""))
}

///|
test "colored pattern cells resolve their own ColorSpace resources" {
  let viewer = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R " +
    "/Resources << /Pattern << /P1 5 0 R >> /ColorSpace << /Colour /DeviceRGB >> >> >>",
    annotation_test_stream("", "/Pattern cs /P1 scn 0 0 100 100 re f"),
    annotation_test_stream(
      "/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 " +
      "/BBox [0 0 10 10] /XStep 10 /YStep 10 " +
      "/Resources << /ColorSpace << /Colour [/CalGray << /WhitePoint [1 1 1] /Gamma 2 >>] >> >>",
      "/Colour cs 0.49019607843137253 sc 0 0 10 10 re f",
    ),
  ])
  let svg = viewer.page(1).unwrap().render_svg()
  assert_true(svg.contains("fill=\"#8F8F8F\""))
}

///|
test "stroking SCN selects its own pattern independently of scn" {
  let viewer = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R " +
    "/Resources << /Pattern << /P1 5 0 R >> /ColorSpace << /Cs [/Pattern /DeviceRGB] >> >> >>",
    annotation_test_stream("", "/Cs CS 0.2 0.5 0.8 /P1 SCN 0 0 m 100 100 l S"),
    annotation_test_stream(
      "/Type /Pattern /PatternType 1 /PaintType 2 /TilingType 1 " +
      "/BBox [0 0 10 10] /XStep 10 /YStep 10 /Resources << >>",
      "0 0 10 10 re f",
    ),
  ])
  let svg = viewer.page(1).unwrap().render_svg()
  assert_true(svg.contains("stroke=\"url(#pdf-stroke-pattern-"))
  assert_true(svg.contains("fill=\"#3380CC\""))
}

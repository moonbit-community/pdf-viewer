///|
fn sampling_quad(a : Double, b : Double, c : Double, d : Double) -> PdfQuad {
  {
    p0: { x: c, y: d, },
    p1: { x: 0.0, y: 0.0, },
    p2: { x: a, y: b, },
    p3: { x: a + c, y: b + d, },
  }
}

///|
test "image sampling decisions account for affine shear rotation and Float32 boundary" {
  assert_true(
    pdf_image_smoothing_enabled(
      false,
      sampling_quad(1.0, 0.0, 0.0, 1.0),
      1,
      1,
      1.0,
    ),
  )
  assert_true(
    !pdf_image_smoothing_enabled(
      false,
      sampling_quad(2.0, 0.0, 0.0, 0.5),
      1,
      1,
      1.0,
    ),
  )
  assert_true(
    !pdf_image_smoothing_enabled(
      false,
      sampling_quad(0.0, 2.0, -0.5, 0.0),
      1,
      1,
      1.0,
    ),
  )
  // Each basis is short enough in isolation, but shear magnifies one axis.
  assert_true(
    !pdf_image_smoothing_enabled(
      false,
      sampling_quad(1.0, 0.0, 1.0, 1.0),
      1,
      1,
      1.0,
    ),
  )
  assert_true(
    pdf_image_smoothing_enabled(
      false,
      sampling_quad(2.0, 0.0, 0.0, 2.0),
      2,
      2,
      1.0,
    ),
  )
  assert_true(
    pdf_image_smoothing_enabled(
      true,
      sampling_quad(100.0, 0.0, 0.0, 100.0),
      1,
      1,
      1.0,
    ),
  )
  assert_true(
    pdf_image_smoothing_enabled(
      false,
      sampling_quad(1.0, 0.0, 0.0, 1.0),
      1,
      1,
      4.0 / 3.0 + 1.0e-9,
    ),
  )
  assert_true(
    !pdf_image_smoothing_enabled(
      false,
      sampling_quad(1.0, 0.0, 0.0, 1.0),
      1,
      1,
      4.0 / 3.0 + 1.0e-6,
    ),
  )
}

///|
test "Interpolate and inline I survive the reader and SVG sampling path" {
  for enabled in [false, true] {
    let page = annotation_test_page(
      [],
      resources="<< /XObject << /Im1 5 0 R >> >>",
      contents="q 100 0 0 100 0 0 cm /Im1 Do Q",
      extra=[
        annotation_test_stream(
          "/Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 " +
          "/ColorSpace /DeviceRGB /Filter /ASCIIHexDecode /Interpolate \{enabled}",
          "FF0000>",
        ),
      ],
    )
    guard page.items is [Image({ resource: Some(resource), .. }), ..] else {
      fail("missing decoded image")
    }
    assert_eq(resource.interpolate, enabled)
    let expected = if enabled { "auto" } else { "crisp-edges" }
    for rotation in [0, 90, 180, 270] {
      assert_true(
        page.render_svg(rotation~).contains("image-rendering=\"\{expected}\""),
      )
    }
    assert_true(
      page.render_svg(scale=0.01).contains("image-rendering=\"auto\""),
    )
  }
  let inline = annotation_test_page(
    [],
    contents="q 100 0 0 100 0 0 cm BI /W 1 /H 1 /BPC 8 /CS /RGB /F /AHx /I true ID FF0000> EI Q",
  )
  guard inline.items is [Image({ resource: Some(resource), .. }), ..] else {
    fail("missing inline image")
  }
  assert_true(resource.interpolate)
  assert_true(inline.render_svg().contains("image-rendering=\"auto\""))
}

///|
test "image placement rounds both edges and retains a minimum pixel width" {
  let page : PdfPageModel = {
    number: 1,
    blend_space: "DeviceRGB",
    blend_profile_id: None,
    blend_calibration: None,
    icc_profiles: [],
    origin_x: 0.0,
    origin_y: 0.0,
    width: 10.25,
    height: 20.75,
    user_unit: 1.0,
    rotation: 0,
    fonts: [],
    items: [],
    annotations: [],
    text: "",
  }
  let quad : PdfQuad = {
    p0: { x: 4.321, y: 0.1, },
    p1: { x: 4.321, y: 10.532, },
    p2: { x: 14.753, y: 10.532, },
    p3: { x: 14.753, y: 0.1, },
  }
  assert_eq(pdf_svg_image_transform(page, quad, 1.0), "matrix(11 0 0 11 4 10)")
  assert_eq(pdf_image_rounded_extent(4.321, 10.432), 11.0)
  assert_eq(pdf_image_rounded_extent(4.321, 0.01), 1.0)
  assert_eq(pdf_image_rounded_extent(4.321, -0.01), -1.0)
  let rotated = { ..page, rotation: 90, }
  assert_eq(
    pdf_svg_image_transform(rotated, quad, 1.0),
    "matrix(11 0 0 11 4 9.75)",
  )
  let sheared = { ..quad, p2: { x: 14.753, y: 10.632, }, }
  assert_eq(
    pdf_svg_image_transform(page, sheared, 1.0),
    pdf_svg_visual_transform(page, sheared, 1.0),
  )
}

///|
test "pattern image sampling includes paint matrix zoom and source Interpolate" {
  for interpolate in [false, true] {
    let viewer = annotation_test_document([
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R " +
      "/Resources << /Pattern << /P1 5 0 R >> >> >>",
      annotation_test_stream("", "/Pattern cs /P1 scn 0 0 100 100 re f"),
      annotation_test_stream(
        "/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 2 1] " +
        "/XStep 2 /YStep 1 /Matrix [3 0 0 1 0 0] /Resources << /XObject << /Im1 6 0 R >> >>",
        "1 0 0 rg 0 0 2 1 re f q 2 0 0 1 0 0 cm /Im1 Do Q 0 0 1 rg 0 0 1 1 re f",
      ),
      annotation_test_stream(
        "/Type /XObject /Subtype /Image /Width 2 /Height 1 /BitsPerComponent 8 " +
        "/ColorSpace /DeviceRGB /Interpolate \{interpolate} /Filter /ASCIIHexDecode",
        "FF000000FF00>",
      ),
    ])
    let page = viewer.page(1).unwrap()
    guard page.items is [Path({ pattern: Some(pattern), .. }), ..] else {
      fail("missing pattern paint")
    }
    assert_true(pattern.tile_parts is [Svg(_), Image(_, _), Svg(_)])
    let expected = if interpolate { "auto" } else { "crisp-edges" }
    assert_true(page.render_svg().contains("image-rendering=\"\{expected}\""))
    assert_true(page.render_svg(scale=0.1).contains("image-rendering=\"auto\""))
    assert_true(
      page
      .render_svg(scale=2.0, rotation=90)
      .contains("image-rendering=\"\{expected}\""),
    )
  }
}

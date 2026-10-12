///|
fn image_pattern_test_page(
  contents : String,
  pattern_dictionary? : String = "/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 10 10] /XStep 10 /YStep 10 /Resources << >>",
  pattern_contents? : String = "1 0 0 rg 0 0 5 10 re f 0 0 1 rg 5 0 5 10 re f",
  image_dictionary? : String = "/ImageMask true /BitsPerComponent 1",
  image_contents? : String = "00>",
  resources? : String = "<< /Pattern << /P 5 0 R >> /XObject << /Im 6 0 R >> /ColorSpace << /PCS [/Pattern /DeviceRGB] >> >>",
) -> PdfPageModel raise {
  let viewer = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 20 20] /Resources \{resources} /Contents 4 0 R >>",
    annotation_test_stream("", contents),
    annotation_test_stream(pattern_dictionary, pattern_contents),
    annotation_test_stream(
      "/Type /XObject /Subtype /Image /Width 1 /Height 1 /Filter /ASCIIHexDecode " +
      image_dictionary,
      image_contents,
    ),
  ])
  guard viewer.page(1) is Some(page) else {
    fail("missing stencil pattern page")
  }
  page
}

///|
test "pattern compatibility images reuse their collected index and default colour policy" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 20 20] /Contents 4 0 R /Resources << /XObject << /Im 5 0 R >> >> >>",
    annotation_test_stream("", "/Im Do"),
    annotation_test_stream(
      "/Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /Filter /ASCIIHexDecode",
      "FF0000>",
    ),
  ])
  let entries = pdf_collected_entries_of_page(
    document.document,
    document.pages[0],
  )
  guard document.page(1).unwrap().items is [Image(image)] &&
    image.resource is Some(resource) else {
    fail("missing converted image")
  }
  let borrowed = PdfPageItem::Image({
    ..image,
    resource: Some({
      ..resource,
      data_uri: Some("data:image/png;base64,borrowed"),
    }),
  })
  let parts = (
    entries : ArrayView[PdfCollectedEntry],
    items : ArrayView[PdfPageItem],
  ) => {
    pdf_pattern_tile_svg(
      document.document,
      entries,
      0.0,
      0.0,
      20.0,
      None,
      decoded_items=items,
    ).0
  }
  assert_true(parts(entries[:], [borrowed]).contains("base64,borrowed"))
  let original = parts(entries[:], [])
  assert_eq(
    parts(entries[:], [Image({ ..image, index: 1, resource: image.resource, })]),
    original,
  )
  let altered = entries.map(entry => {
    ..entry,
    state: {
      ..entry.state,
      path_state: {
        ..entry.state.path_state,
        rendering_intent: "/AbsoluteColorimetric",
      },
    },
  })
  assert_eq(parts(altered[:], [borrowed]), original)
  let failed = PdfPageItem::Image({
    ..image,
    resource: Some({ ..resource, error: Some("retry"), }),
  })
  assert_eq(parts(entries[:], [failed]), original)
}

///|
test "stencil image captures coloured pattern before image CTM changes" {
  let page = image_pattern_test_page(
    "/Pattern cs /P scn q 20 0 0 20 0 0 cm /Im Do Q",
  )
  guard page.items is [Image(image)] else { fail("missing stencil image") }
  guard image.pattern is Some(pattern) else { fail("missing stencil pattern") }
  assert_eq(pattern.matrix, [1.0, 0.0, 0.0, 1.0, 0.0, 0.0])
  assert_eq((pattern.x_step, pattern.y_step), (10.0, 10.0))
  guard pattern.tile_page is Some(tile) else { fail("missing pattern cell") }
  assert_eq(tile.items.length(), 2)
  assert_eq(page.graphics_diagnostics(), [])
  assert_true(
    page
    .graphics_diagnostics(renderer="svg")
    .any(d => d.code == "PDF_SVG_IMAGE_PATTERN"),
  )
  let plan = page.canvas_plan().stringify()
  assert_true(plan.contains("\"tile_plan\""))
  assert_true(plan.contains("\"#FF0000\""))
  assert_true(plan.contains("\"#0000FF\""))
}

///|
test "inline stencil retains uncoloured pattern base paint" {
  let page = image_pattern_test_page(
    "/PCS cs 0 1 0 /P scn q 20 0 0 20 0 0 cm BI /W 1 /H 1 /IM true /BPC 1 /F /AHx ID 00> EI Q",
    pattern_dictionary="/Type /Pattern /PatternType 1 /PaintType 2 /TilingType 1 /BBox [0 0 10 10] /XStep 10 /YStep 10 /Resources << >>",
    pattern_contents="0 0 5 10 re f",
  )
  guard page.items is [Image({ pattern: Some(pattern), .. })] else {
    fail("inline stencil pattern lost")
  }
  guard pattern.tile_page is Some({ items: [Path(path)], .. }) else {
    fail("missing uncoloured cell")
  }
  assert_eq(path.fill_color, "#00FF00")
  assert_eq(page.graphics_diagnostics(), [])
}

///|
test "ordinary colour image ignores current pattern and missing stencil pattern is explicit" {
  let page = image_pattern_test_page(
    "/Pattern cs /P scn q 20 0 0 20 0 0 cm /Im Do Q",
    image_dictionary="/ColorSpace /DeviceRGB /BitsPerComponent 8",
    image_contents="FF0000>",
  )
  guard page.items is [Image({ pattern: None, resource: Some(resource), .. })] else {
    fail("ordinary image captured unrelated pattern")
  }
  assert_eq(colour_image_scanlines(resource), [0, 255, 0, 0])
  assert_eq(page.graphics_diagnostics(), [])
  let missing = image_pattern_test_page(
    "/Pattern cs /Missing scn q 20 0 0 20 0 0 cm /Im Do Q",
  )
  assert_true(
    missing
    .graphics_diagnostics()
    .any(d => d.code == "PDF_IMAGE_PATTERN_RESOURCE"),
  )
}

///|
test "stencil shading pattern reaches the nested Canvas pattern plan" {
  let page = image_pattern_test_page(
    "/Pattern cs /P scn q 20 0 0 20 0 0 cm /Im Do Q",
    pattern_dictionary="/Type /Pattern /PatternType 2 /Shading << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 20 0] /Extend [true true] /Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> >>",
    pattern_contents="",
  )
  guard page.items
    is [Image({ pattern: Some({ shading: Some(shading), .. }), .. })] else {
    fail("missing shading stencil paint")
  }
  assert_eq(shading.kind, "axial")
  assert_eq(page.graphics_diagnostics(), [])
  assert_true(page.canvas_plan().stringify().contains("\"kind\":\"axial\""))
}

///|
test "stencil and path patterns share stream-base matrix when selected after cm" {
  let page = image_pattern_test_page(
    "q 20 0 0 20 0 0 cm /Pattern cs /P scn /Im Do 0 0 1 1 re f Q",
  )
  guard page.items
    is [
      Image({ pattern: Some(image_pattern), .. }),
      Path({ pattern: Some(path_pattern), .. }),
    ] else {
    fail("missing paired stencil/path pattern")
  }
  assert_eq(image_pattern.matrix, path_pattern.matrix)
  assert_eq(image_pattern.matrix, [1.0, 0.0, 0.0, 1.0, 0.0, 0.0])
  assert_eq(image_pattern.bbox, path_pattern.bbox)
  assert_eq(
    (image_pattern.x_step, image_pattern.y_step),
    (path_pattern.x_step, path_pattern.y_step),
  )
}

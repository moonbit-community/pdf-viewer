///|
fn colour_test_hex(
  space : @pdflite.PdfColourSpace,
  values : Array[Double],
) -> String {
  pdf_colour_hex_in_space(space, @pdflite.PdfContentColourFloats(values))
}

///|
test "device colours use their declared space and PDF.js SWOP samples" {
  assert_eq(colour_test_hex(@pdflite.PdfDeviceGray, [0.5]), "#808080")
  assert_eq(colour_test_hex(@pdflite.PdfDeviceRGB, [0.2, 0.5, 0.8]), "#3380CC")
  // Expected colours are from test/unit/colorspace_spec.js, DeviceCmykCS.
  for
    (samples, expected) in [
      ([27, 125, 250, 128], "#875112"),
      ([131, 139, 140, 45], "#726661"),
      ([111, 25, 198, 78], "#70904B"),
      ([21, 147, 255, 69], "#BC621B"),
    ] {
    assert_eq(
      colour_test_hex(
        @pdflite.PdfDeviceCMYK,
        [
          for sample in samples => sample.to_double() / 255.0
        ],
      ),
      expected,
    )
  }
  assert_eq(
    colour_test_hex(@pdflite.PdfDeviceCMYK, [0.1, 0.2, 0.3, 1.0]),
    "#201C15",
  )
  assert_eq(
    colour_test_hex(@pdflite.PdfDeviceCMYK, [0.0, 0.0, 0.0, 1.0]),
    "#2C2E35",
  )
  assert_eq(
    colour_test_hex(@pdflite.PdfDeviceCMYK, [1.0, 0.0, 0.0, 0.0]),
    "#00B9F2",
  )
  assert_eq(
    colour_test_hex(@pdflite.PdfDeviceCMYK, [0.0, 1.0, 0.0, 0.0]),
    "#FB3199",
  )
  assert_eq(
    colour_test_hex(@pdflite.PdfDeviceCMYK, [0.0, 0.0, 1.0, 0.0]),
    "#FFEB3D",
  )
}

///|
test "CalGray gamma matches the PDF.js calibrated tone curve" {
  let space = @pdflite.PdfCalGray(
    { x: 1.0, y: 1.0, z: 1.0, },
    { x: 0.0, y: 0.0, z: 0.0, },
    2.0,
  )
  for
    (sample, expected) in [
      (27, "#191919"),
      (125, "#8F8F8F"),
      (250, "#FBFBFB"),
      (131, "#959595"),
    ] {
    assert_eq(colour_test_hex(space, [sample.to_double() / 255.0]), expected)
  }
  assert_eq(colour_test_hex(space, [0.0]), "#000000")
  assert_eq(colour_test_hex(space, [1.0]), "#FFFFFF")
}

///|
test "CalRGB output and primary matrix columns match PDF.js" {
  let white : @pdflite.PdfTristimulusPoint = { x: 1.0, y: 1.0, z: 1.0, }
  let black : @pdflite.PdfTristimulusPoint = { x: 0.0, y: 0.0, z: 0.0, }
  let space = @pdflite.PdfCalRGB(white, black, [1.0, 1.0, 1.0], [
    1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0,
  ])
  assert_eq(colour_test_hex(space, [0.1, 0.2, 0.3]), "#009397")
  for
    (samples, expected) in [
      ([27, 125, 250], "#00EEFF"),
      ([131, 139, 140], "#B9C4C3"),
      ([111, 25, 198], "#EB00F3"),
      ([21, 147, 255], "#00FFFF"),
    ] {
    assert_eq(
      colour_test_hex(
        space,
        [
          for sample in samples => sample.to_double() / 255.0
        ],
      ),
      expected,
    )
  }
  let columns = @pdflite.PdfCalRGB(white, black, [1.0, 1.0, 1.0], [
    0.1, 0.2, 0.3, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
  ])
  assert_eq(colour_test_hex(columns, [1.0, 0.0, 0.0]), "#009397")
  let invalid_gamma = @pdflite.PdfCalRGB(white, black, [-1.0, 2.0, 2.0], [])
  assert_eq(colour_test_hex(invalid_gamma, [0.1, 0.2, 0.3]), "#009397")
}

///|
test "Lab components retain their PDF ranges and PDF.js output curve" {
  let white : @pdflite.PdfTristimulusPoint = { x: 1.0, y: 1.0, z: 1.0, }
  let black : @pdflite.PdfTristimulusPoint = { x: 0.0, y: 0.0, z: 0.0, }
  let lab = @pdflite.PdfLab(white, black, [-100.0, 100.0, -100.0, 100.0])
  assert_eq(colour_test_hex(lab, [55.0, 25.0, 35.0]), "#BC643D")
  let restricted = @pdflite.PdfLab(white, black, [20.0, 30.0, 30.0, 40.0])
  assert_eq(colour_test_hex(restricted, [55.0, 25.0, 35.0]), "#BC643D")
  assert_eq(
    colour_test_hex(restricted, [55.0, 100.0, -100.0]),
    colour_test_hex(lab, [55.0, 30.0, 30.0]),
  )
  let malformed = @pdflite.PdfLab(white, black, [30.0, 20.0, 30.0, 40.0])
  assert_eq(colour_test_hex(malformed, [55.0, 25.0, 35.0]), "#BC643D")
  let d50 = @pdflite.PdfLab({ x: 0.9642, y: 1.0, z: 0.8249, }, black, [])
  assert_eq(colour_test_hex(d50, [0.0, 0.0, 0.0]), "#000000")
  assert_eq(colour_test_hex(d50, [100.0, 0.0, 0.0]), "#FFFFFF")
}

///|
test "Indexed and Pattern base spaces retain calibrated sample semantics" {
  let gray = @pdflite.PdfCalGray(
    { x: 1.0, y: 1.0, z: 1.0, },
    { x: 0.0, y: 0.0, z: 0.0, },
    2.0,
  )
  let indexed = @pdflite.PdfIndexed(gray, [(0, [27]), (1, [125])])
  assert_eq(colour_test_hex(indexed, [0.0]), "#191919")
  assert_eq(colour_test_hex(indexed, [1.0]), "#8F8F8F")
  assert_eq(colour_test_hex(indexed, [255.0]), "#8F8F8F")
  assert_eq(
    colour_test_hex(@pdflite.PdfPatternWithBaseColourSpace(gray), [
      125.0 / 255.0,
    ]),
    "#8F8F8F",
  )
  let rgb = @pdflite.PdfIndexed(@pdflite.PdfDeviceRGB, [
    (0, [23, 155, 35]),
    (1, [147, 69, 93]),
  ])
  assert_eq(colour_test_hex(rgb, [0.0]), "#179B23")
  assert_eq(colour_test_hex(rgb, [1.0]), "#93455D")
}

///|
test "ICCBased unsupported profile explicitly uses its alternate space" {
  let icc = @pdflite.PdfICCBased(
    4,
    @pdflite.PdfDeviceCMYK,
    [],
    None,
    @syntax.PdfNull,
  )
  assert_eq(colour_test_hex(icc, [0.1, 0.2, 0.3, 1.0]), "#201C15")
  let rgb = @pdflite.PdfICCBased(
    3,
    @pdflite.PdfDeviceRGB,
    [],
    None,
    @syntax.PdfNull,
  )
  assert_eq(colour_test_hex(rgb, [0.2, 0.5, 0.8]), "#3380CC")
}

///|
test "calibrated colours reach path text and shading through the page reader" {
  let page = annotation_test_page(
    [],
    resources="<< /ColorSpace << /Gray [/CalGray << /WhitePoint [1 1 1] /Gamma 2 >>] >> " +
      "/Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> " +
      "/Shading << /S1 << /ShadingType 2 /ColorSpace /Gray /Coords [0 0 100 0] " +
      "/Extend [true true] /Function << /FunctionType 2 /Domain [0 1] " +
      "/C0 [0] /C1 [1] /N 1 >> >> >> >>",
    contents="/Gray cs 0.49019607843137253 sc 0 0 20 20 re f " +
      "BT /F1 12 Tf 10 30 Td (A) Tj ET /S1 sh",
  )
  guard page.items is [Path(path), Text(text), Shading(shading), ..] else {
    fail("missing colour paint items")
  }
  assert_eq(path.fill_color, "#8F8F8F")
  assert_eq(text.fill_color, "#8F8F8F")
  guard shading.shading is Some(resource) else { fail("missing gradient") }
  assert_eq(resource.stops[0].color, "#000000")
  assert_eq(resource.stops[resource.stops.length() - 1].color, "#FFFFFF")
  assert_eq(resource.stops[resource.stops.length() / 2].color, "#929292")
}

///|
test "Separation and DeviceN evaluate tint functions before the alternate" {
  let page = annotation_test_page(
    [],
    resources="<< /ColorSpace << /Spot [/Separation /SpotGreen /DeviceRGB " +
      "<< /FunctionType 2 /Domain [0 1] /C0 [1 1 1] /C1 [0 1 0] /N 1 >>] " +
      "/Multi [/DeviceN [/Spot1 /Spot2] /DeviceRGB " +
      "<< /FunctionType 2 /Domain [0 1 0 1] /C0 [1 1 1] /C1 [0 1 0] /N 1 >>] >> >>",
    contents="/Spot cs 0.5 scn 0 0 10 10 re f",
  )
  guard page.items is [Path(path), ..] else { fail("missing spot path") }
  assert_eq(path.fill_color, "#80FF80")
  // A multi-input calculator exercises the DeviceN path independently.
  let viewer = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R " +
    "/Resources << /ColorSpace << /Multi [/DeviceN [/Spot1 /Spot2] /DeviceRGB 5 0 R] >> >> >>",
    annotation_test_stream("", "/Multi cs 0.2 0.8 scn 0 0 10 10 re f"),
    annotation_test_stream(
      "/FunctionType 4 /Domain [0 1 0 1] /Range [0 1 0 1 0 1]", "{ 0.5 }",
    ),
  ])
  guard viewer.page(1).unwrap().items is [Path(path), ..] else {
    fail("missing DeviceN path")
  }
  assert_eq(path.fill_color, "#33CC80")
}

///|
test "colour spaces restore across q Q and reset to PDF defaults on cs" {
  let page = annotation_test_page(
    [],
    resources="<< /ColorSpace << /Gray [/CalGray << /WhitePoint [1 1 1] /Gamma 2 >>] " +
      "/Spot [/Separation /SpotGreen /DeviceRGB " +
      "<< /FunctionType 2 /Domain [0 1] /C0 [1 1 1] /C1 [0 1 0] /N 1 >>] >> >>",
    contents="/Gray cs 0.49019607843137253 sc 0 0 10 10 re f " +
      "q 1 0 0 rg 20 0 10 10 re f Q 40 0 10 10 re f " +
      "/DeviceCMYK cs 60 0 10 10 re f /Spot cs 80 0 10 10 re f",
  )
  guard page.items
    is [Path(gray), Path(red), Path(restored), Path(cmyk), Path(spot)] else {
    fail("missing colour state paints")
  }
  assert_eq(gray.fill_color, "#8F8F8F")
  assert_eq(red.fill_color, "#FF0000")
  assert_eq(restored.fill_color, gray.fill_color)
  assert_eq(cmyk.fill_color, "#2C2E35")
  assert_eq(spot.fill_color, "#00FF00")
}

///|
test "Form ColorSpace names resolve in the child scope without leaking" {
  let viewer = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R " +
    "/Resources << /ColorSpace << /Colour [/CalGray << /WhitePoint [1 1 1] /Gamma 2 >>] >> " +
    "/XObject << /Form 5 0 R >> >> >>",
    annotation_test_stream(
      "",
      "/Colour cs 0.49019607843137253 sc 0 0 10 10 re f " +
      "/Form Do 40 0 10 10 re f",
    ),
    annotation_test_stream(
      "/Type /XObject /Subtype /Form /BBox [0 0 100 100] " +
      "/Resources << /ColorSpace << /Colour /DeviceRGB >> >>",
      "/Colour cs 0.2 0.5 0.8 sc 20 0 10 10 re f",
    ),
  ])
  guard viewer.page(1).unwrap().items is [Path(first), Path(child), Path(last)] else {
    fail("missing Form paints")
  }
  assert_eq(first.fill_color, "#8F8F8F")
  assert_eq(child.fill_color, "#3380CC")
  assert_eq(last.fill_color, first.fill_color)
}

///|
test "calibrated fill and stroke reach a luminosity Form soft mask" {
  let page = annotation_test_page(
    [],
    resources="<< /ExtGState << /GS << /SMask << /S /Luminosity /G 5 0 R >> >> >> >>",
    contents="/GS gs 1 0 0 rg 0 0 100 100 re f",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 100 100] " +
        "/Group << /S /Transparency /CS /DeviceRGB >> " +
        "/Resources << /ColorSpace << /Gray [/CalGray << /WhitePoint [1 1 1] /Gamma 2 >>] " +
        "/Cal [/CalRGB << /WhitePoint [1 1 1] >>] >> >>",
        "/Gray cs 0.49019607843137253 sc /Cal CS 0.1 0.2 0.3 SC 0 0 50 50 re B",
      ),
    ],
  )
  guard page.items is [Path(path)] && path.soft_mask is Some(mask) else {
    fail("missing luminosity soft mask")
  }
  assert_true(mask.luminosity)
  let prefix = "data:image/svg+xml;base64,"
  assert_true(mask.data_uri.has_prefix(prefix))
  let svg = @utf8.decode(@base64.decode(mask.data_uri[prefix.length():]))
  assert_true(svg.contains("fill=\"#8F8F8F\""))
  assert_true(svg.contains("stroke=\"#009397\""))
}

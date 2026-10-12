///|
test "graphics diagnostics report SVG compatibility branches without tainting Canvas" {
  let page = annotation_test_page([], contents="0 w 10 10 m 40 40 l S")
  assert_eq(page.graphics_diagnostics().length(), 0)
  let diagnostics = page.graphics_diagnostics(renderer="svg")
  assert_eq(diagnostics.length(), 1)
  assert_eq(diagnostics[0].code, "PDF_SVG_HAIRLINE")
  assert_true(page.render_svg().contains("pdf-renderer-diagnostics"))
}

///|
test "graphics diagnostics keep unavailable image failures visible" {
  let page = annotation_test_page(
    [],
    contents="/Broken Do",
    resources="<< /XObject << /Broken 5 0 R >> >>",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode",
        "broken",
      ),
    ],
  )
  let diagnostics = page.graphics_diagnostics()
  assert_eq(diagnostics.length(), 1)
  assert_eq(diagnostics[0].code, "PDF_IMAGE_DECODE")
}

///|
test "collector retains rendering intent and explicit device BG UCR functions" {
  let page = annotation_test_page(
    [],
    contents="/E gs /Saturation ri .2 .3 .4 rg 10 10 20 20 re f",
    resources="<< /ExtGState << /E << /BG << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 2 >> /UCR << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 1 >> >> >> >>",
  )
  let source = stroke_test_path(page).fill_source
  assert_eq(source.rendering_intent, "/Saturation")
  let values = source.process_cmyk.unwrap()
  assert_true((values[0] - 0.2).abs() < 0.000001)
  assert_true((values[1] - 0.1).abs() < 0.000001)
  assert_true(values[2].abs() < 0.000001)
  assert_true((values[3] - 0.36).abs() < 0.000001)
}

///|
test "group boundary retains caller rendering intent" {
  let page = annotation_test_page(
    [],
    contents="/Perceptual ri /F Do",
    resources="<< /XObject << /F 5 0 R >> >>",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 10 10] /Group << /S /Transparency /I true /CS /DeviceRGB >> /Resources << >>",
        "0 0 10 10 re f",
      ),
    ],
  )
  assert_eq(
    stroke_test_path(page).group.unwrap().rendering_intent,
    "/Perceptual",
  )
}

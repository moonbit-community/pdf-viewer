///|
test "ICC source catalog is page scoped deduplicated and preserves raw samples" {
  let page = annotation_test_page(
    [],
    resources="<< /ColorSpace << /A [/ICCBased 5 0 R] /B [/ICCBased 5 0 R] >> >>",
    contents="/A cs .2 .5 .8 sc 0 0 10 10 re f /B cs .8 .5 .2 sc 20 0 10 10 re f",
    extra=[icc_test_stream(icc_test_rgb_gamma22, "/N 3")],
  )
  assert_eq(page.icc_profiles.length(), 1)
  let id = page.icc_profiles[0].id
  assert_eq(
    @base64.decode(page.icc_profiles[0].data_base64),
    icc_test_rgb_gamma22,
  )
  guard page.items is [Path(a), Path(b)] else { fail("missing ICC paints") }
  assert_eq(a.fill_source.icc_profile_id, Some(id))
  assert_eq(b.fill_source.icc_profile_id, Some(id))
  assert_eq(a.fill_source.components, [0.2, 0.5, 0.8])
  assert_eq(page.blend_profile_id, None)
  guard page.canvas_plan() is Object(fields) else { fail("missing plan") }
  assert_true(fields.contains("icc_profiles"))
}

///|
test "actual page ICC blend profile retains component arity and catalog ID" {
  let viewer = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Group << /S /Transparency /CS [/ICCBased 5 0 R] >> /Contents 4 0 R /Resources << >> >>",
    annotation_test_stream("", "0 1 1 0 k 0 0 50 50 re f"),
    icc_test_stream(icc_test_cmyk, "/N 4"),
  ])
  let page = viewer.page(1).unwrap()
  assert_eq(page.blend_space, "DeviceCMYK")
  assert_eq(page.icc_profiles.length(), 1)
  assert_eq(page.blend_profile_id, Some(page.icc_profiles[0].id))
}

///|
test "Form group ICC resolves its own resource names and shares page catalog" {
  let page = annotation_test_page(
    [],
    resources="<< /XObject << /Fm 5 0 R >> >>",
    contents="/Fm Do /Fm Do",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 50 50] " +
        "/Group << /S /Transparency /CS /Blend >> /Resources << /ColorSpace << /Blend [/ICCBased 6 0 R] >> >>",
        "0 1 1 0 k 0 0 50 50 re f",
      ),
      icc_test_stream(icc_test_cmyk, "/N 4"),
    ],
  )
  assert_eq(page.icc_profiles.length(), 1)
  guard page.items is [Path(a), Path(b)] else { fail("missing Form paints") }
  assert_eq(a.group.unwrap().color_space, "DeviceCMYK")
  assert_eq(a.group.unwrap().icc_profile_id, Some(page.icc_profiles[0].id))
  assert_eq(b.group.unwrap().icc_profile_id, a.group.unwrap().icc_profile_id)
}

///|
test "matching OutputIntent is actual profile fallback for DeviceCMYK group" {
  let viewer = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /OutputIntents [<< /S /GTS_PDFX /DestOutputProfile 5 0 R >>] >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Group << /S /Transparency /CS /DeviceCMYK >> /Contents 4 0 R /Resources << >> >>",
    annotation_test_stream("", "0 1 1 0 k 0 0 50 50 re f"),
    icc_test_stream(icc_test_cmyk, "/N 4"),
  ])
  let page = viewer.page(1).unwrap()
  assert_eq(page.blend_space, "DeviceCMYK")
  assert_eq(page.blend_profile_id, Some("icc-0"))
  let context = pdf_resource_build_context()
  context.icc_profile_bytes = 33554432
  assert_eq(
    pdf_colour_register_icc(viewer.document, @syntax.PdfIndirect(5), 4, context),
    None,
  )
  assert_eq(context.icc_profiles.length(), 0)
}

///|
test "Lab source transport retains original components and reference white" {
  let source = pdf_colour_source(
    @pdflite.PdfLab(
      { x: 0.95047, y: 1.0, z: 1.08883, },
      { x: 0.0, y: 0.0, z: 0.0, },
      [],
    ),
    @pdflite.PdfContentColourFloats([60.0, 20.0, -15.0]),
  )
  assert_eq(source.components, [60.0, 20.0, -15.0])
  assert_true(source.whitepoint_xyy.unwrap()[0] > 0.31)
  assert_eq(source.icc_profile_id, None)
}

///|
test "embedded ICC bytes share bounded page catalog" {
  let context = pdf_resource_build_context()
  let a = pdf_colour_register_icc_bytes(icc_test_rgb_gamma22, 3, context)
  let b = pdf_colour_register_icc_bytes(icc_test_rgb_gamma22, 3, context)
  assert_eq(a, Some("icc-0"))
  assert_eq(a, b)
  assert_eq(context.icc_profiles.length(), 1)
  assert_eq(
    pdf_colour_register_icc_bytes(icc_test_rgb_gamma22, 4, context),
    None,
  )
}

///|
test "shading ICC metadata follows whole tint without evaluating dummy tint" {
  let viewer = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 0 /Kids [] >>",
    icc_test_stream(icc_test_rgb_gamma22, "/N 3"),
  ])
  let terminal = @pdflite.PdfICCBased(
    3,
    @pdflite.PdfDeviceRGB,
    [],
    None,
    @syntax.PdfIndirect(3),
  )
  let space = @pdflite.PdfSeparation(
    pdf_name_key("/Spot"),
    terminal,
    @syntax.PdfNull,
  )
  let context = pdf_resource_build_context()
  let source = pdf_colour_shading_source(
    viewer.document,
    space,
    context,
    rendering_intent="/Saturation",
  ).unwrap()
  assert_eq(source.space, "ICCBased")
  assert_eq(source.components.length(), 3)
  assert_eq(source.icc_profile_id, Some("icc-0"))
  assert_eq(source.component_ranges, Some([0.0, 1.0, 0.0, 1.0, 0.0, 1.0]))
  assert_eq(source.rendering_intent, "/Saturation")
}

///|
test "shading terminal device metadata does not retain dummy process vector" {
  let viewer = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Count 0 /Kids [] >>",
  ])
  let source = pdf_colour_shading_source(
    viewer.document,
    @pdflite.PdfDeviceRGB,
    pdf_resource_build_context(),
  ).unwrap()
  assert_eq(source.space, "DeviceRGB")
  assert_eq(source.process_cmyk, None)
  assert_eq(source.component_ranges, Some([0.0, 1.0, 0.0, 1.0, 0.0, 1.0]))
}

///|
test "invalid explicit ICC group profile is diagnostic not a device fallback" {
  let page = annotation_test_page(
    [],
    resources="<< /XObject << /F 5 0 R >> >>",
    contents="/F Do",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 10 10] /Resources << >> /Group << /S /Transparency /I true /CS [/ICCBased 6 0 R] >>",
        "0 0 10 10 re f",
      ),
      annotation_test_stream("/N 3", "not an ICC profile"),
    ],
  )
  assert_eq(
    stroke_test_path(page).group.unwrap().color_space,
    "ICCBasedUnavailable",
  )
  assert_true(
    page
    .graphics_diagnostics()
    .any(d => d.code == "PDF_ICC_GROUP_PROFILE_UNAVAILABLE"),
  )
}

///|
test "invalid explicit ICC page group keeps its unavailable identity" {
  let viewer = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Group << /S /Transparency /CS [/ICCBased 5 0 R] >> /Contents 4 0 R /Resources << >> >>",
    annotation_test_stream("", "0 0 10 10 re f"),
    annotation_test_stream("/N 5", "invalid component count"),
  ])
  let page = viewer.page(1).unwrap()
  assert_eq(page.blend_space, "ICCBasedUnavailable")
  assert_true(
    page
    .graphics_diagnostics()
    .any(d => d.code == "PDF_ICC_GROUP_PROFILE_UNAVAILABLE" && d.item == -1),
  )
}

///|
test "unavailable ICC source retains clipped legal alternate inside valid ICC group" {
  let viewer = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Group << /S /Transparency /CS [/ICCBased 5 0 R] >> /Resources << /ColorSpace << /C [/ICCBased 6 0 R] >> >> /Contents 4 0 R >>",
    annotation_test_stream("", "/C cs -.2 .5 1.2 scn 0 0 50 50 re f"),
    icc_test_stream(icc_test_rgb_gamma22, "/N 3"),
    annotation_test_stream(
      "/N 3 /Alternate /DeviceRGB /Range [0 1 .1 .4 0 1]", "not an ICC profile",
    ),
  ])
  let page = viewer.page(1).unwrap()
  assert_true(page.blend_profile_id is Some(_))
  let source = stroke_test_path(page).fill_source
  assert_eq(source.space, "ICCBased")
  assert_eq(source.icc_profile_id, None)
  let alternate = source.alternate.unwrap()
  assert_eq(alternate.space, "DeviceRGB")
  assert_eq(alternate.components, [0.0, 0.4, 1.0])
}

///|
test "ICC alternate sampler retains original components and calibrated mapping" {
  let viewer = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources << /ColorSpace << /C [/ICCBased 5 0 R] >> >> /Contents 4 0 R >>",
    annotation_test_stream("", "/C cs .2 .5 .8 scn 0 0 50 50 re f"),
    annotation_test_stream(
      "/N 3 /Alternate [/CalRGB << /WhitePoint [.9642 1 .8249] /Gamma [.5 2 3] /Matrix [.9642 0 0 0 1 0 0 0 .8249] >>]",
      "bad",
    ),
  ])
  let source = stroke_test_path(viewer.page(1).unwrap()).fill_source
  assert_eq(source.components, [0.2, 0.5, 0.8])
  let alternate = source.alternate.unwrap()
  assert_eq(alternate.components, source.components)
  let calibration = alternate.calibration.unwrap()
  assert_eq(calibration.gamma, [0.5, 2.0, 3.0])
  assert_true((calibration.pcs_matrix[0] - 0.9642).abs() < 0.000001)
}

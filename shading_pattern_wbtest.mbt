///|
fn shading_pattern_test_page(
  ext : String,
  contents? : String = "/Pattern cs /P scn 0 0 100 100 re f",
  background? : String = "",
  matrix? : String = "",
  extra? : Array[String] = [],
) -> PdfPageModel raise {
  annotation_test_page(
    [],
    contents~,
    resources="<< /Pattern << /P 5 0 R >> /ExtGState << /Outer << /ca 0.25 /BM /Screen >> >> >>",
    extra=[
      "<< /Type /Pattern /PatternType 2 /ExtGState << \{ext} >> \{matrix} /Shading << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [25 0 75 0] \{background} /Function << /FunctionType 2 /Domain [0 1] /C0 [0.4 0.8 0.6] /C1 [0.4 0.8 0.6] /N 1 >> >> >>",
      ..extra,
    ],
  )
}

///|
test "shading pattern transparency resets stream state then applies ExtGState once" {
  let page = shading_pattern_test_page(
    "/ca 0.5 /BM /Multiply /AIS true /LW 500",
    contents="/Outer gs /Pattern cs /P scn 0 0 100 100 re f",
  )
  let path = stroke_test_path(page)
  assert_eq(path.fill_alpha, 0.25)
  assert_eq(path.blend_mode, "screen")
  let state = path.shading_pattern.unwrap().pattern_state.unwrap()
  assert_eq(state.fill_alpha, 0.5)
  assert_eq(state.blend_mode, "multiply")
  assert_true(state.alpha_is_shape)
  let defaults = stroke_test_path(
    shading_pattern_test_page(
      "",
      contents="/Outer gs /Pattern cs /P scn 0 0 100 100 re f",
    ),
  ).shading_pattern.unwrap().pattern_state.unwrap()
  assert_eq(defaults.fill_alpha, 1.0)
  assert_eq(defaults.blend_mode, "normal")
}

///|
test "shading pattern plan has ordered Background and sh in one knockout scene" {
  let page = shading_pattern_test_page(
    "/ca 0.5 /BM /Multiply",
    background="/Background [0.1 0.9 0.2] /BBox [10 20 90 80]",
  )
  let json = pdf_canvas_shading_plan(
    stroke_test_path(page).shading_pattern,
    page,
  )
  guard json is Object(resource) &&
    resource.get("pattern_plan") is Some(Object(scene)) else {
    fail("missing implicit scene")
  }
  guard scene.get("items") is Some(Array([Object(bg), Object(sh)])) else {
    fail("expected Background then sh")
  }
  assert_eq(bg.get("kind"), Some(Json::string("path")))
  assert_eq(sh.get("kind"), Some(Json::string("shading")))
  assert_eq(bg.get("groups"), sh.get("groups"))
  guard bg.get("groups") is Some(Array([Object(group)])) else {
    fail("missing group")
  }
  assert_eq(group.get("knockout"), Some(Json::boolean(true)))
  assert_eq(group.get("isolated"), Some(Json::boolean(false)))
  guard bg.get("paint") is Some(Object(paint)) else {
    fail("missing background")
  }
  assert_eq(paint.get("fill_alpha"), Some(Json::number(1.0)))
  assert_eq(
    paint.get("svg_path"),
    Some(Json::string("M10 180 L90 180 L90 120 L10 120 Z")),
  )
}

///|
test "shading pattern SMask retains structured form and complete pattern matrix" {
  let page = shading_pattern_test_page(
    "/SMask << /S /Luminosity /G 6 0 R >>",
    matrix="/Matrix [2 0 0 3 10 20]",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Matrix [1 0 0 1 4 5] /Group << /S /Transparency /I true /CS /DeviceGray >> /Resources << >>",
        "0.5 g 0 0 100 100 re f",
      ),
    ],
  )
  let resource = stroke_test_path(page).shading_pattern.unwrap()
  assert_eq(resource.matrix, [2, 0, 0, 3, 10, 20])
  let mask = resource.pattern_state.unwrap().soft_mask.unwrap()
  assert_true(mask.page is Some(_))
  assert_true(mask.luminosity)
  assert_eq(mask.matrix, [2, 0, 0, 3, 18, 35])
  assert_true(page.canvas_plan().stringify().contains("pattern_plan"))
}

///|
test "invalid shading pattern SMask remains a public shading diagnostic" {
  let page = shading_pattern_test_page("/SMask << /S /Alpha >>")
  let resource = stroke_test_path(page).shading_pattern.unwrap()
  assert_eq(resource.kind, "unsupported")
  assert_true(resource.raster.unwrap().error.unwrap().contains("SMask"))
}

///|
test "shading pattern ExtGState indirect dictionary resolves before replay" {
  let page = annotation_test_page(
    [],
    contents="/Pattern cs /P scn 0 0 100 100 re f",
    resources="<< /Pattern << /P 5 0 R >> >>",
    extra=[
      "<< /Type /Pattern /PatternType 2 /ExtGState 6 0 R /Shading << /ShadingType 2 /ColorSpace /DeviceGray /Coords [0 0 100 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 1 >> >> >>",
      "<< /Type /ExtGState /ca 0.375 /BM /Screen >>",
    ],
  )
  let state = stroke_test_path(page).shading_pattern.unwrap().pattern_state.unwrap()
  assert_eq(state.fill_alpha, 0.375)
  assert_eq(state.blend_mode, "screen")
}

///|
test "Canvas shading plan retains raster once and omits legacy SVG mesh and stops" {
  let page = shading_pattern_test_page("/ca 0.5")
  let resource = stroke_test_path(page).shading_pattern.unwrap()
  assert_true(!resource.stops.is_empty())
  let json = pdf_canvas_shading_plan(Some(resource), page)
  guard json is Object(wrapper) &&
    wrapper.get("pattern_plan") is Some(Object(plan)) &&
    plan.get("items") is Some(Array([Object(item)])) &&
    item.get("paint") is Some(Object(paint)) &&
    paint.get("shading") is Some(Object(shading)) else {
    fail("missing shading scene")
  }
  assert_eq(wrapper.get("raster"), None)
  assert_eq(shading.get("mesh"), None)
  assert_eq(shading.get("stops"), None)
  assert_true(shading.get("raster") is Some(_))
}

///|
test "Canvas tiling plan omits SVG cell when structured page exists" {
  let page = annotation_test_page(
    [],
    contents="/Pattern cs /P scn 0 0 100 100 re f",
    resources="<< /Pattern << /P 5 0 R >> >>",
    extra=[
      annotation_test_stream(
        "/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 8 8] /XStep 8 /YStep 8 /Resources << >>",
        "1 0 0 rg 0 0 4 8 re f",
      ),
    ],
  )
  let pattern = stroke_test_path(page).pattern.unwrap()
  assert_true(!pattern.tile_svg.is_empty())
  guard pdf_canvas_pattern_plan(Some(pattern), page) is Object(plan) else {
    fail("missing plan")
  }
  assert_eq(plan.get("tile_svg"), None)
  assert_true(plan.get("tile_plan") is Some(Object(_)))
}

///|
test "shading Background keeps initial overprint before inner ExtGState" {
  let page = annotation_test_page(
    [],
    contents="/Initial gs /F Do",
    resources="<< /XObject << /F 5 0 R >> /ExtGState << /Initial << /op true /OPM 1 >> >> >>",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Resources << /Pattern << /P 6 0 R >> >>",
        "/Pattern cs /P scn 0 0 100 100 re f",
      ),
      "<< /Type /Pattern /PatternType 2 /ExtGState << /op false /OPM 0 >> /Shading << /ShadingType 2 /ColorSpace /DeviceCMYK /Background [0 1 0 0] /Coords [25 0 75 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [0 0 1 0] /C1 [0 0 1 0] /N 1 >> >> >>",
    ],
  )
  let state = stroke_test_path(page).shading_pattern.unwrap().pattern_state.unwrap()
  assert_true(state.background_overprint)
  assert_eq(state.background_overprint_mode, 1)
  assert_true(!state.fill_overprint)
  assert_eq(state.overprint_mode, 0)
}

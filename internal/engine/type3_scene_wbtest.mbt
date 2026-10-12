///|
fn type3_scene_test_page(
  charproc : String,
  contents? : String = "BT /F1 100 Tf 40 50 Td (A) Tj ET",
  font_resources? : String = "<< >>",
  page_resources? : String = "",
  extra? : Array[String] = [],
) -> PdfPageModel raise {
  let resource_entry = if font_resources == "" {
    ""
  } else {
    "/Resources " + font_resources
  }
  annotation_test_page(
    [],
    contents~,
    resources="<< /Font << /F1 5 0 R >> \{page_resources} >>",
    extra=[
      "<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1000 1000] /FontMatrix [.001 0 0 .001 0 0] /FirstChar 65 /LastChar 65 /Widths [1000] /Encoding << /Type /Encoding /Differences [65 /A] >> /CharProcs << /A 6 0 R >> \{resource_entry} >>",
      annotation_test_stream("", charproc),
      ..extra,
    ],
  )
}

///|
test "Type3 scenes preserve two internal colors independently of Tr and outer fill" {
  for mode in [0, 1, 2, 4, 5, 6, 7] {
    let page = type3_scene_test_page(
      "1000 0 d0 1 0 0 rg 0 0 500 1000 re f 0 0 1 rg 500 0 500 1000 re f",
      contents="0 1 0 rg BT /F1 100 Tf \{mode} Tr 40 50 Td (A) Tj ET",
    )
    let glyph = text_stroke_test_item(page)
    guard glyph.type3_scene is Some(scene) else { fail("missing Type3 scene") }
    guard scene.items is [Path(red), Path(blue)] else {
      fail("missing internal paints")
    }
    assert_eq(red.fill_source.components, [1.0, 0.0, 0.0])
    assert_eq(blue.fill_source.components, [0.0, 0.0, 1.0])
    assert_eq(red.fill_color, "#FF0000")
    assert_eq(blue.fill_color, "#0000FF")
    assert_eq(glyph.fill_color, "#00FF00")
    assert_eq(scene.origin_x, page.origin_x)
    assert_eq(scene.width, page.width)
    assert_eq(scene.height, page.height)
    assert_eq(red.svg_path, "M 40 150 L 90 150 L 90 50 L 40 50 Z")
    assert_eq(page.text_layer().items.length(), 1)
    assert_eq(glyph.type3_scene_unresolved, None)
    assert_eq(page.graphics_diagnostics().length(), 0)
    assert_true(
      page
      .graphics_diagnostics(renderer="svg")
      .any(d => d.code == "PDF_SVG_TYPE3_SCENE"),
    )
    let plan = invisible_test_canvas_items(page)
    assert_eq(plan.length(), 1)
    guard plan[0] is Object(fields) else { fail("missing glyph paint") }
    assert_true(fields.get("type3_plan") is Some(Object(_)))
    assert_true(fields.get("text_svg") is Some(Null))
  }
}

///|
test "Type3 scene alpha blend and mask overrides replace inherited state" {
  let page = type3_scene_test_page(
    "1000 0 d0 1 0 0 rg 0 0 400 1000 re f /Inner gs 0 0 1 rg 600 0 400 1000 re f",
    contents="30 40 100 120 re W n /Outer gs BT /F1 100 Tf 40 50 Td (A) Tj ET",
    font_resources="<< /ExtGState << /Inner << /ca .8 /BM /Screen /SMask /None >> >> >>",
    page_resources="/ExtGState << /Outer << /ca .4 /BM /Multiply /SMask << /S /Alpha /G 7 0 R >> >> >>",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 200 200] /Group << /S /Transparency /I true >> /Resources << >>",
        "0 0 200 200 re f",
      ),
    ],
  )
  let glyph = text_stroke_test_item(page)
  let scene = glyph.type3_scene.unwrap()
  guard scene.items is [Path(first), Path(second)] else {
    fail("missing paints")
  }
  assert_eq(glyph.fill_alpha, 0.4)
  assert_eq(first.fill_alpha, 0.4)
  assert_eq(second.fill_alpha, 0.8)
  assert_eq(first.blend_mode, "multiply")
  assert_eq(second.blend_mode, "screen")
  assert_true(first.soft_mask is Some(_))
  assert_eq(second.soft_mask, None)
  assert_eq(first.clips, glyph.clips)
  assert_eq(first.group_path.length(), 0)
}

///|
test "Type3 d1 stencil ignores direct and Form color setters" {
  let page = type3_scene_test_page(
    "1000 0 0 0 1000 1000 d1 1 0 0 rg 0 0 500 1000 re f /Fm Do",
    contents="0 .6 .2 rg BT /F1 100 Tf 1 Tr 40 50 Td (A) Tj ET",
    font_resources="<< /XObject << /Fm 7 0 R >> >>",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 1000 1000] /Resources << >>", "0 0 1 rg 500 0 500 1000 re f",
      ),
    ],
  )
  let scene = text_stroke_test_item(page).type3_scene.unwrap()
  guard scene.items is [Path(first), Path(second)] else {
    fail("missing paints")
  }
  assert_eq(first.fill_source.components, [0.0, 0.6, 0.2])
  assert_eq(second.fill_source.components, first.fill_source.components)
  assert_eq(second.fill_color, first.fill_color)
}

///|
test "Type3 absent font resources inherit invocation resources" {
  let page = type3_scene_test_page(
    "1000 0 d0 /Fm Do",
    font_resources="",
    page_resources="/XObject << /Fm 7 0 R >> >>",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 1000 1000] /Resources << >>", "0 1 1 0 k 0 0 1000 1000 re f",
      ),
    ],
  )
  let scene = text_stroke_test_item(page).type3_scene.unwrap()
  guard scene.items is [Path(path)] else { fail("missing inherited Form") }
  assert_eq(path.fill_source.space, "DeviceCMYK")
  assert_eq(path.fill_source.components, [0.0, 1.0, 1.0, 0.0])
}

///|
test "Type3 recursive CharProcs are a bounded explicit diagnostic" {
  let page = type3_scene_test_page(
    "1000 0 d0 BT /F1 1000 Tf (A) Tj ET",
    font_resources="<< /Font << /F1 5 0 R >> >>",
  )
  let glyph = text_stroke_test_item(page)
  assert_eq(glyph.type3_scene, None)
  assert_true(glyph.type3_scene_unresolved is Some(_))
  assert_true(page.graphics_diagnostics().any(d => d.code == "PDF_TYPE3_SCENE"))
}

///|
test "Type3 scene retains internal ICC source catalog and CMYK group paints" {
  let page = type3_scene_test_page(
    "1000 0 d0 /Rgb cs .2 .4 .8 sc 0 0 500 1000 re f /Fm Do",
    font_resources="<< /ColorSpace << /Rgb [/ICCBased 7 0 R] >> /XObject << /Fm 8 0 R >> >>",
    extra=[
      icc_test_stream(icc_test_rgb_gamma22, "/N 3"),
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 1000 1000] /Group << /S /Transparency /CS /DeviceCMYK /I true >> /Resources << >>",
        "1 0 0 0 k 500 0 500 1000 re f",
      ),
    ],
  )
  let scene = text_stroke_test_item(page).type3_scene.unwrap()
  guard scene.items is [Path(rgb), Path(cmyk)] else { fail("missing paints") }
  assert_eq(rgb.fill_source.icc_profile_id, Some("icc-0"))
  assert_eq(scene.icc_profiles.length(), 1)
  let serialized = invisible_test_canvas_items(page)
  guard serialized[0] is Object(glyph) &&
    glyph.get("type3_plan") is Some(Object(plan)) else {
    fail("missing scene plan")
  }
  assert_true(plan.get("icc_profiles") is Some(Array([])))
  guard scene.canvas_plan() is Object(standalone) else {
    fail("missing standalone plan")
  }
  assert_true(standalone.get("icc_profiles") is Some(Array([_])))
  assert_eq(cmyk.fill_source.components, [1.0, 0.0, 0.0, 0.0])
  assert_eq(cmyk.group.unwrap().color_space, "DeviceCMYK")
  assert_true(cmyk.group.unwrap().isolated)
}

///|
test "Type3 rendering mode 3 preserves text but has no CharProc paint" {
  let page = type3_scene_test_page(
    "1000 0 d0 1 0 0 rg 0 0 1000 1000 re f",
    contents="BT /F1 100 Tf 3 Tr 40 50 Td (A) Tj ET",
  )
  let glyph = text_stroke_test_item(page)
  assert_eq(glyph.type3_scene.unwrap().items.length(), 0)
  assert_eq(page.text_layer().items.length(), 1)
}

///|
test "Type3 d1 preserves separate inherited stroking and nonstroking colors" {
  let page = type3_scene_test_page(
    "1000 0 0 0 1000 1000 d1 100 w 1 0 0 rg 0 0 1 RG 100 100 800 800 re B",
    contents=".1 .2 .3 rg .4 .5 .6 RG BT /F1 100 Tf 40 50 Td (A) Tj ET",
  )
  let scene = text_stroke_test_item(page).type3_scene.unwrap()
  guard scene.items is [Path(path)] else { fail("missing stencil") }
  assert_eq(path.fill_source.components, [0.1, 0.2, 0.3])
  assert_eq(path.stroke_source.components, [0.4, 0.5, 0.6])
}

///|
test "retained Type3 scene uses the active font Resources under Form shadowing" {
  let page = annotation_test_page(
    [],
    contents="BT /F1 100 Tf ET /Fm Do",
    resources="<< /Font << /F1 5 0 R >> /XObject << /Fm 7 0 R >> >>",
    extra=[
      "<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1000 1000] /FontMatrix [.001 0 0 .001 0 0] /FirstChar 65 /LastChar 65 /Widths [1000] /Encoding << /Differences [65 /A] >> /CharProcs << /A 6 0 R >> /Resources << /ExtGState << /G << /ca .25 >> >> >> >>",
      annotation_test_stream("", "1000 0 d0 /G gs 0 0 1000 1000 re f"),
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 200 200] /Resources << /Font << /F1 8 0 R >> /ExtGState << /G << /ca .75 >> >> >>",
        "BT 40 50 Td (A) Tj ET",
      ),
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ],
  )
  let glyph = text_stroke_test_item(page)
  let scene = glyph.type3_scene.unwrap()
  guard scene.items is [Path(paint)] else { fail("missing active Type3 paint") }
  assert_eq(paint.fill_alpha, 0.25)
  assert_eq(paint.svg_path, "M 40 150 L 140 150 L 140 50 L 40 50 Z")
  assert_eq(glyph.type3_scene_unresolved, None)
}

///|
test "Type3 scenes forward Standard14 host overrides to nested text" {
  let document = provenance_test_document(
    "BT /F1 100 Tf 40 50 Td (A) Tj ET",
    font="<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1000 1000] /FontMatrix [.001 0 0 .001 0 0] /FirstChar 65 /LastChar 65 /Widths [1000] /Encoding << /Differences [65 /A] >> /CharProcs << /A 6 0 R >> /Resources << /Font << /Nested << /Subtype /Type1 /BaseFont /Helvetica >> >> >> >>",
    extra_objects=[
      annotation_test_stream(
        "", "1000 0 d0 BT /Nested 100 Tf 1 Tr 2 .3 .6 1 10 20 Tm (A) Tj ET",
      ),
    ],
  )
  let plain = document.page(1).unwrap()
  let plain_scene = text_stroke_test_item(plain).type3_scene.unwrap()
  assert_true(
    text_stroke_test_item(plain_scene).stroke.unwrap().svg_path is Some(_),
  )
  let overridden = document
    .with_font_fallbacks([
      {
        pdf_name: "/Nested",
        family: "Test Host Sans",
        weight: None,
        style: None,
      },
    ])
    .page(1)
    .unwrap()
  let scene = text_stroke_test_item(overridden).type3_scene.unwrap()
  let nested = text_stroke_test_item(scene)
  assert_eq(scene.fonts[0].family, "Test Host Sans")
  assert_eq(nested.stroke.unwrap().svg_path, None)
  assert_eq(
    nested.stroke.unwrap().unresolved,
    Some("affine-text-pen-requires-glyph-outline"),
  )
  assert_eq(scene.fonts[0].data_uri, None)
}

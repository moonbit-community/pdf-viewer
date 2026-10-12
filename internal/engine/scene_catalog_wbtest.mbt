///|
test "nested mask and pattern scenes inherit one byte-identical ICC catalog" {
  let page = annotation_test_page(
    [],
    contents="/RGB cs .2 .4 .8 sc 0 0 10 10 re f /G gs /Pattern cs /P scn 20 20 30 30 re f 60 20 30 30 re f",
    resources="<< /ColorSpace << /RGB [/ICCBased 7 0 R] >> /Pattern << /P 5 0 R >> /ExtGState << /G << /SMask << /S /Luminosity /G 6 0 R >> >> >> >>",
    extra=[
      annotation_test_stream(
        "/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 10 10] /XStep 10 /YStep 10 /Resources << /XObject << /Fm 8 0 R >> >>",
        "/Fm Do",
      ),
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 200 200] /Group << /S /Transparency /CS [/ICCBased 7 0 R] /I true >> /Resources << /ColorSpace << /RGB [/ICCBased 7 0 R] >> >>",
        "/RGB cs .5 .5 .5 sc 0 0 200 200 re f",
      ),
      icc_test_stream(icc_test_rgb_gamma22, "/N 3"),
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 10 10] /Group << /S /Transparency /CS [/ICCBased 7 0 R] /I true >> /Resources << >>",
        ".2 .4 .8 rg 0 0 10 10 re f",
      ),
    ],
  )
  assert_eq(page.icc_profiles.length(), 1)
  let profile = page.icc_profiles[0]
  let serialized = page.canvas_plan()
  assert_eq(
    serialized.stringify().split(profile.data_base64).collect().length(),
    2,
  )
  guard serialized is Object(root) && root.get("items") is Some(Array(items)) else {
    fail("missing plan")
  }
  for index in [1, 2] {
    guard items[index] is Object(item) &&
      item.get("mask") is Some(Object(mask)) &&
      mask.get("plan") is Some(Object(mask_page)) &&
      item.get("pattern") is Some(Object(pattern)) &&
      pattern.get("tile_plan") is Some(Object(tile)) else {
      fail("missing nested scenes")
    }
    assert_true(mask_page.get("icc_profiles") is Some(Array([])))
    assert_true(tile.get("icc_profiles") is Some(Array([])))
    assert_eq(mask_page.get("blend_profile_id"), Some(profile.id.to_json()))
    assert_true(tile.get("items").unwrap().stringify().contains(profile.id))
  }
  let mask_model = stroke_test_path(page, index=1).soft_mask.unwrap().page.unwrap()
  guard mask_model.canvas_plan() is Object(standalone) else {
    fail("missing standalone")
  }
  assert_true(standalone.get("icc_profiles") is Some(Array([_])))
}

///|
test "catalog deduplication compares bytes as well as profile IDs" {
  let page = annotation_test_page([], contents="0 0 1 1 re f")
  let profile : PdfIccProfile = {
    id: "same-id",
    components: 3,
    data_base64: "original",
  }
  let page = { ..page, icc_profiles: [profile], }
  let different = { ..profile, data_base64: "different", }
  guard pdf_canvas_plan(page, 1.0, 0, [different]) is Object(plan) else {
    fail("missing plan")
  }
  assert_true(plan.get("icc_profiles") is Some(Array([_])))
  guard pdf_canvas_plan(page, 1.0, 0, [profile]) is Object(dedup) else {
    fail("missing plan")
  }
  assert_true(dedup.get("icc_profiles") is Some(Array([])))
}

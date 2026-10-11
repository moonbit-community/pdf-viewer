///|
test "explicit soft-mask ICC failure retains its profile diagnostic" {
  let page = annotation_test_page(
    [],
    contents="/M gs 1 0 0 rg 0 0 20 20 re f",
    resources="<< /ExtGState << /M << /SMask << /S /Luminosity /G 5 0 R >> >> >> >>",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 20 20] /Group << /S /Transparency /CS [/ICCBased 6 0 R] /I true >> /Resources << >>",
        ".5 .5 .5 rg 0 0 20 20 re f",
      ),
      annotation_test_stream("/N 3 /Alternate /DeviceRGB", "invalid profile"),
    ],
  )
  let mask_page = stroke_test_path(page).soft_mask.unwrap().page.unwrap()
  assert_eq(mask_page.blend_space, "ICCBasedUnavailable")
  assert_true(
    mask_page
    .graphics_diagnostics()
    .any(value => value.code == "PDF_ICC_GROUP_PROFILE_UNAVAILABLE"),
  )
  assert_true(
    page.canvas_plan().stringify().contains("PDF_ICC_GROUP_PROFILE_UNAVAILABLE"),
  )
}

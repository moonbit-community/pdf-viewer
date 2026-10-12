///|
test "group invocation owns alpha blend and transformed bounds" {
  let page = annotation_test_page(
    [],
    contents="/Half gs q 2 0 0 3 10 20 cm /F Do /F Do Q",
    resources="<< /ExtGState << /Half << /ca 0.5 /CA 0.25 /BM /Multiply >> >> /XObject << /F 5 0 R >> >>",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 20 30] /Group << /S /Transparency /I true /CS /DeviceRGB >> /Resources << >>",
        "0 0 10 10 re f",
      ),
    ],
  )
  let a = stroke_test_path(page)
  let b = stroke_test_path(page, index=1)
  let ga = a.group.unwrap()
  let gb = b.group.unwrap()
  assert_true(ga.id != gb.id)
  assert_eq(ga.alpha, 0.5)
  assert_eq(ga.blend_mode, "multiply")
  assert_eq(a.fill_alpha, 1.0)
  assert_eq(a.stroke_alpha, 1.0)
  assert_eq(a.blend_mode, "normal")
  assert_eq(
    ga.bounds,
    Some({ min_x: 10.0, min_y: 20.0, max_x: 50.0, max_y: 110.0, }),
  )
}

///|
test "non-group Forms preserve alpha and scope repeated child groups" {
  let page = annotation_test_page(
    [],
    contents="/Half gs /Outer Do /Outer Do",
    resources="<< /ExtGState << /Half << /ca 0.5 >> >> /XObject << /Outer 5 0 R >> >>",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 20 30] /Resources << /XObject << /Inner 6 0 R >> >>",
        "0 0 5 5 re f /Inner Do",
      ),
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 20 30] /Group << /S /Transparency >> /Resources << >>",
        "0 0 10 10 re f",
      ),
    ],
  )
  assert_eq(stroke_test_path(page).fill_alpha, 0.5)
  let a = stroke_test_path(page, index=1)
  let b = stroke_test_path(page, index=3)
  assert_true(a.group.unwrap().id != b.group.unwrap().id)
  assert_eq(a.group.unwrap().alpha, 0.5)
}

///|
test "blend preference arrays skip unknown names and AIS remains at group boundary" {
  let page = annotation_test_page(
    [],
    contents="/Mix gs 0 0 10 10 re f /F Do",
    resources="<< /ExtGState << /Mix << /BM [/Unknown /ColorDodge /Multiply] /AIS true >> >> /XObject << /F 5 0 R >> >>",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 20 30] /Group << /S /Transparency >> /Resources << >>",
        "0 0 10 10 re f",
      ),
    ],
  )
  assert_eq(stroke_test_path(page).blend_mode, "color-dodge")
  assert_true(stroke_test_path(page).alpha_is_shape)
  let group = stroke_test_path(page, index=1)
  assert_true(group.group.unwrap().alpha_is_shape)
  assert_true(!group.alpha_is_shape)
  assert_eq(
    pdf_svg_blend_mode(@syntax.PdfNameObject(pdf_name_key("/Unknown"))),
    "normal",
  )
}

///|
test "page blend space and inherited Form blend space remain distinct" {
  let page = page_box_test_page(
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R /Resources << >> /Group << /S /Transparency /CS /DeviceCMYK >> >>",
  )
  assert_eq(page.blend_space, "DeviceCMYK")
  let nested = annotation_test_page(
    [],
    contents="/F Do",
    resources="<< /XObject << /F 5 0 R >> >>",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 20 20] /Group << /S /Transparency >> /Resources << >>",
        "0 0 10 10 re f",
      ),
    ],
  )
  assert_eq(stroke_test_path(nested).group.unwrap().color_space, "")
}

///|
test "OPM is independent from op and restored by q Q" {
  let page = annotation_test_page(
    [],
    contents="/OP1 gs 0 0 10 10 re f q /OP0 gs 20 0 10 10 re f Q 40 0 10 10 re f",
    resources="<< /ExtGState << /OP1 << /OP true /op false /OPM 1 >> /OP0 << /OPM 0 >> >> >>",
  )
  assert_eq(stroke_test_path(page).overprint_mode, 1)
  assert_true(!stroke_test_path(page).fill_overprint)
  assert_true(stroke_test_path(page).stroke_overprint)
  assert_eq(stroke_test_path(page, index=1).overprint_mode, 0)
  assert_eq(stroke_test_path(page, index=2).overprint_mode, 1)
}

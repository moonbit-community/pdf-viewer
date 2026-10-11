///|
test "device colour operators and image reader use same-arity scoped defaults" {
  let page = annotation_test_page(
    [],
    resources="<< /ColorSpace << /DefaultRGB [/CalRGB << /WhitePoint [1 1 1] /Gamma [2 2 2] >>] /DefaultGray [/CalGray << /WhitePoint [1 1 1] /Gamma 2 >>] >> >>",
    contents=".2 .4 .6 rg .3 G 0 0 10 10 re B",
  )
  let path = stroke_test_path(page)
  assert_eq(path.fill_source.space, "CalRGB")
  assert_eq(path.fill_source.components, [0.2, 0.4, 0.6])
  assert_eq(path.stroke_source.space, "CalGray")
  assert_eq(path.stroke_source.components, [0.3])
}

///|
test "DeviceCMYK cs preserves original black with ICC default and resource alias" {
  let page = annotation_test_page(
    [],
    resources="<< /ColorSpace << /DefaultCMYK [/ICCBased 5 0 R] /Alias /DeviceCMYK >> >>",
    contents="/Alias cs 0 0 10 10 re f",
    extra=[icc_test_stream(icc_test_cmyk, "/N 4")],
  )
  let path = stroke_test_path(page)
  assert_eq(path.fill_source.space, "ICCBased")
  assert_eq(path.fill_source.components, [0.0, 0.0, 0.0, 1.0])
}

///|
test "malformed default arity Lab and cyclic resource aliases fail safely" {
  for default in ["/DeviceGray", "[/Lab << /WhitePoint [1 1 1] >>]", "/Loop"] {
    let page = annotation_test_page(
      [],
      resources="<< /ColorSpace << /DefaultRGB " +
        default +
        " /Loop /Loop >> >>",
      contents=".2 .4 .6 rg 0 0 10 10 re f",
    )
    assert_eq(stroke_test_path(page).fill_source.space, "DeviceRGB")
  }
  let page = annotation_test_page(
    [],
    resources="<< /ColorSpace << /A /B /B /A >> >>",
    contents="/A cs 0 0 10 10 re f",
  )
  assert_eq(stroke_test_path(page).fill_source.space, "DeviceGray")
}

///|
test "default initial gray and Form inheritance are resolved only at selection" {
  let page = annotation_test_page(
    [],
    resources="<< /ColorSpace << /DefaultGray [/CalGray << /WhitePoint [1 1 1] /Gamma 2 >>] /DefaultRGB [/CalRGB << /WhitePoint [1 1 1] /Gamma [2 2 2] >>] >> /XObject << /F 5 0 R >> >>",
    contents="0 0 10 10 re f .2 .4 .6 rg /F Do",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 20 20] /Resources << /ColorSpace << /DefaultRGB [/CalRGB << /WhitePoint [1 1 1] /Gamma [3 3 3] >>] >> >>",
        "0 0 10 10 re f .2 .4 .6 rg 10 0 10 10 re f",
      ),
    ],
  )
  guard page.items is [Path(initial), Path(inherited), Path(local)] else {
    fail("missing default-space paints")
  }
  assert_eq(initial.fill_source.space, "CalGray")
  assert_eq(inherited.fill_source.components, local.fill_source.components)
  assert_true(inherited.fill_source.pcs_xyz != local.fill_source.pcs_xyz)
}

///|
test "default Indexed base and selected whole Separation alternate are mapped" {
  let page = annotation_test_page(
    [],
    resources="<< /ColorSpace << /DefaultRGB [/CalRGB << /WhitePoint [1 1 1] /Gamma [2 2 2] >>] /S [/Separation /Spot /DeviceRGB << /FunctionType 2 /Domain [0 1] /C0 [0 0 0] /C1 [1 1 1] /N 1 >>] >> >>",
    contents="/S cs .5 scn 0 0 10 10 re f",
  )
  let alternate = stroke_test_path(page).fill_source.alternate.unwrap()
  assert_eq(alternate.space, "CalRGB")
  assert_eq(alternate.components, [0.5, 0.5, 0.5])
}

///|
test "DefaultRGB applies to image dictionaries and Indexed base samples" {
  let direct = annotation_test_page(
    [],
    resources="<< /ColorSpace << /DefaultRGB [/CalRGB << /WhitePoint [1 1 1] /Gamma [2 2 2] >>] >> /XObject << /Im 5 0 R >> >>",
    contents="/Im Do",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /Filter /ASCIIHexDecode",
        "808080>",
      ),
    ],
  )
  let indexed = annotation_test_page(
    [],
    resources="<< /ColorSpace << /DefaultRGB [/CalRGB << /WhitePoint [1 1 1] /Gamma [2 2 2] >>] >> /XObject << /Im 5 0 R >> >>",
    contents="/Im Do",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace [/Indexed /DeviceRGB 0 <808080>] /Filter /ASCIIHexDecode",
        "00>",
      ),
    ],
  )
  guard direct.items is [Image(a)] && indexed.items is [Image(b)] else {
    fail("missing default-space images")
  }
  let pixels = colour_image_scanlines(a.resource.unwrap())
  assert_eq(pixels, colour_image_scanlines(b.resource.unwrap()))
  assert_true(pixels != [0, 128, 128, 128])
}

///|
test "all six device operators preserve components under default substitution" {
  for
    (op, expected, values, stroke) in [
      (".25 g", "CalGray", [0.25], false),
      (".25 G", "CalGray", [0.25], true),
      (".2 .4 .6 rg", "CalRGB", [0.2, 0.4, 0.6], false),
      (".2 .4 .6 RG", "CalRGB", [0.2, 0.4, 0.6], true),
      (".1 .2 .3 .4 k", "ICCBased", [0.1, 0.2, 0.3, 0.4], false),
      (".1 .2 .3 .4 K", "ICCBased", [0.1, 0.2, 0.3, 0.4], true),
    ] {
    let page = annotation_test_page(
      [],
      resources="<< /ColorSpace << /DefaultGray [/CalGray << /WhitePoint [1 1 1] >>] /DefaultRGB [/CalRGB << /WhitePoint [1 1 1] >>] /DefaultCMYK [/ICCBased 5 0 R] >> >>",
      contents=op + " 0 0 10 10 re B",
      extra=[icc_test_stream(icc_test_cmyk, "/N 4")],
    )
    let path = stroke_test_path(page)
    let source = if stroke { path.stroke_source } else { path.fill_source }
    assert_eq(source.space, expected)
    assert_eq(source.components, values)
  }
}

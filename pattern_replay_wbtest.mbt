///|
test "tiling pattern matrix uses content stream base rather than paint CTM" {
  let page = annotation_test_page(
    [],
    contents="3 1 2 4 20 30 cm /Pattern cs /P scn 0 0 30 30 re f",
    resources="<< /Pattern << /P 5 0 R >> >>",
    extra=[
      annotation_test_stream(
        "/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 8 8] /XStep 8 /YStep 8 /Matrix [2 0 0 2 5 7] /Resources << >>",
        "0 0 4 8 re f",
      ),
    ],
  )
  assert_eq(stroke_test_path(page).pattern.unwrap().matrix, [2, 0, 0, 2, 5, 7])
}

///|
test "pattern cells retain text nested Forms and signed lattice steps" {
  let page = annotation_test_page(
    [],
    contents="/Pattern cs /P scn 0 0 200 200 re f",
    resources="<< /Pattern << /P 5 0 R >> >>",
    extra=[
      annotation_test_stream(
        "/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [2 3 22 23] /XStep -20 /YStep -20 /Resources << /Font << /F 6 0 R >> /XObject << /Inner 7 0 R >> >>",
        "BT /F 10 Tf 3 8 Td (A) Tj ET /Inner Do",
      ),
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 20 20] /Group << /S /Transparency /I true >> /Resources << >>",
        "1 0 0 rg 3 3 5 5 re f",
      ),
    ],
  )
  let pattern = stroke_test_path(page).pattern.unwrap()
  assert_eq(pattern.x_step, -20)
  let tile = pattern.tile_page.unwrap()
  assert_true(tile.items is [Text(_), Path({ group: Some(_), .. })])
  assert_true(
    pattern.tile_svg.contains("data-pdf-font-outline=\"standard14:Helvetica\""),
  )
  assert_true(text_stroke_test_item(tile).fill_path is Some(_))
  assert_eq(tile.origin_x, 2)
}

///|
test "uncolored cell retains its actual base components before glyph lowering" {
  let page = annotation_test_page(
    [],
    contents="/PCS cs 1 0 0 0 /P scn 0 0 100 100 re f",
    resources="<< /ColorSpace << /PCS [/Pattern /DeviceCMYK] >> /Pattern << /P 5 0 R >> >>",
    extra=[
      annotation_test_stream(
        "/Type /Pattern /PatternType 1 /PaintType 2 /TilingType 1 /BBox [0 0 8 8] /XStep 8 /YStep 8 /Resources << >>",
        "0 0 4 8 re f",
      ),
    ],
  )
  let tile = stroke_test_path(page).pattern.unwrap().tile_page.unwrap()
  let paint = stroke_test_path(tile)
  assert_eq(paint.fill_source.space, "DeviceCMYK")
  assert_eq(paint.fill_source.components, [1, 0, 0, 0])
}

///|
test "spot source retains whole alternate components and None never paints SVG" {
  let page = annotation_test_page(
    [],
    contents="/Spot cs .5 scn 0 0 20 20 re f /None cs 0 scn 30 0 20 20 re f",
    resources="<< /ColorSpace << /Spot [/Separation /Ink /DeviceCMYK << /FunctionType 2 /Domain [0 1] /C0 [0 0 0 0] /C1 [1 0 0 0] /N 1 >>] /None [/Separation /None /DeviceRGB << /FunctionType 2 /Domain [0 1] /C0 [1 1 1] /C1 [0 0 0] /N 1 >>] >> >>",
  )
  let alternate = stroke_test_path(page).fill_source.alternate.unwrap()
  assert_eq(alternate.space, "DeviceCMYK")
  assert_eq(alternate.components, [0.5, 0, 0, 0])
  let none = stroke_test_path(page, index=1)
  assert_true(!none.fill_source.paints)
  assert_eq(none.fill_alpha, 0)
}

///|
test "pattern cells inherit stream-entry state and reset only transparency" {
  let page = annotation_test_page(
    [],
    contents="3 w /Perceptual ri 1 0 0 RG /Half gs /F Do",
    resources="<< /ExtGState << /Half << /CA .5 /ca .5 /BM /Multiply >> >> /XObject << /F 5 0 R >> >>",
    extra=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 20 20] /Resources << /Pattern << /P 6 0 R >> >>",
        "19 w /Saturation ri 0 0 1 RG /Pattern cs /P scn 0 0 20 20 re f",
      ),
      annotation_test_stream(
        "/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 10 10] /XStep 10 /YStep 10 /Resources << >>",
        "0 5 m 10 5 l S",
      ),
    ],
  )
  let tile = stroke_test_path(page).pattern.unwrap().tile_page.unwrap()
  let line = stroke_test_path(tile)
  assert_eq(line.stroke.unwrap().line_width, 3.0)
  assert_eq(line.stroke_color, "#FF0000")
  assert_eq(line.stroke_source.rendering_intent, "/Perceptual")
  assert_eq(line.stroke_alpha, 1.0)
  assert_eq(line.blend_mode, "normal")
}

///|
test "page-defined pattern does not inherit paint-site line width" {
  let page = annotation_test_page(
    [],
    contents="19 w /Pattern cs /P scn 0 0 20 20 re f",
    resources="<< /Pattern << /P 5 0 R >> >>",
    extra=[
      annotation_test_stream(
        "/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 10 10] /XStep 10 /YStep 10 /Resources << >>",
        "0 5 m 10 5 l S",
      ),
    ],
  )
  let line = stroke_test_path(
    stroke_test_path(page).pattern.unwrap().tile_page.unwrap(),
  )
  assert_eq(line.stroke.unwrap().line_width, 1.0)
  assert_eq(line.stroke_color, "#000000")
}

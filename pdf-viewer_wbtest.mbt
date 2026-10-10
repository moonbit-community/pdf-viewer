// Whitebox tests run within the package scope.
// Use them to validate internal helpers or invariants.
// Keep them focused; public behavior belongs in `_test.mbt`.

///|
test "raw PDF pixels become a browser-readable PNG" {
  let data = try! @core.pdf_bytes_of_int_array([255, 0, 128])
  let png = try! pdf_png_of_raw_image(1, 1, @pdflite.PdfBPP24, data)
  assert_true(png.length() > 24)
  assert_eq(png[0].to_int(), 137)
  let parsed = try! @pdflite.pdf_read_png(png)
  assert_eq(parsed.width, 1)
  assert_eq(parsed.height, 1)
  assert_eq(parsed.color_type, 2)
}

///|
test "embedded CFF and Type 1 programs are preserved without invalid browser font faces" {
  let cff = pdf_font_resource_from_bytes(
    "F1",
    "ABCDEE+ExampleSans",
    Some(Bytes::from_array([1, 0, 4, 4, 0])),
    "F1",
  )
  assert_eq(cff.mime_type, "font/otf")
  assert_eq(cff.format, "cff")
  assert_true(cff.data_uri is Some(_))
  assert_eq(cff.family, "sans-serif")
  let type1 = pdf_font_resource_from_bytes(
    "F2",
    "ExampleSerif",
    Some(Bytes::from_array([128, 1, 2, 3])),
    "F2",
  )
  assert_eq(type1.format, "type1")
  assert_eq(type1.family, "serif")
  let truetype = pdf_font_resource_from_bytes(
    "F3",
    "ExampleSans",
    Some(Bytes::from_array([0, 1, 0, 0, 0])),
    "F3",
  )
  assert_eq(truetype.format, "truetype")
  assert_true(truetype.family.has_prefix("pdf-font-"))
  let wrapped = pdf_font_resource_from_bytes(
    "F4",
    "ExampleSerif",
    Some(Bytes::from_array([79, 84, 84, 79, 0])),
    "F4",
  )
  assert_eq(wrapped.format, "opentype")
  assert_true(wrapped.family.has_prefix("pdf-font-"))
}

///|
test "host font fallback replaces only the requested unembedded font" {
  let fallback : PdfFontFallback = {
    pdf_name: "Helvetica",
    family: "Arial",
    weight: Some("600"),
    style: Some("normal"),
  }
  let resource = pdf_font_resource_from_bytes(
    "F1",
    "Helvetica",
    None,
    "F1",
    fallback=Some(fallback),
  )
  assert_eq(resource.family, "Arial")
  assert_eq(resource.weight, "600")
  assert_eq(resource.style, "normal")
  let embedded = pdf_font_resource_from_bytes(
    "F2",
    "Helvetica",
    Some(Bytes::from_array([0, 1, 0, 0, 0])),
    "F2",
    fallback=Some(fallback),
  )
  assert_true(embedded.family.has_prefix("pdf-font-"))
}

///|
test "standard 14 resources expose AFM metrics and host font stacks" {
  let times = pdf_font_resource_from_bytes(
    "F1",
    "/Times-BoldItalic",
    None,
    "F1",
  )
  assert_eq(times.standard_font, Some("Times-BoldItalic"))
  assert_true(times.family.contains("Nimbus Roman"))
  guard times.metrics is Some(metrics) else { fail("missing AFM metrics") }
  assert_eq(metrics.units_per_em, 1000)
  assert_true(metrics.ascent > 0)
  assert_true(metrics.descent < 0)
  assert_true(metrics.widths.length() > 100)

  let symbol = pdf_font_resource_from_bytes("F2", "/Symbol", None, "F2")
  assert_eq(symbol.standard_font, Some("Symbol"))
  assert_true(symbol.family.contains("Standard Symbols PS"))
}

///|
test "undefined standard font codes do not become SVG control characters" {
  assert_eq(
    pdf_standard14_display_text(Some(@pdflite.PdfHelvetica), 0x00, "\u0000"),
    "",
  )
  assert_eq(
    pdf_standard14_display_text(Some(@pdflite.PdfHelvetica), 0x81, "\u0081"),
    "•",
  )
  assert_eq(
    pdf_standard14_display_text(Some(@pdflite.PdfSymbol), 0x80, "\u0080"),
    "",
  )
  assert_eq(pdf_standard14_display_text(None, 0x00, "\u0000"), "\u0000")
}

///|
test "viewer corrects pdflite's placeholder default paint colour" {
  assert_eq(
    pdf_colour_hex_for_paint_in_space(
      @pdflite.PdfDeviceGray,
      @pdflite.PdfContentColourFloats([1.0]),
      false,
    ),
    "#000000",
  )
  assert_eq(
    pdf_colour_hex_for_paint_in_space(
      @pdflite.PdfDeviceGray,
      @pdflite.PdfContentColourFloats([1.0]),
      true,
    ),
    "#FFFFFF",
  )
}

///|
test "type3 glyph mapping follows the source text quad" {
  let matrix = pdf_type3_page_matrix(
    {
      p0: { x: 100.0, y: 200.0, },
      p1: { x: 100.0, y: 212.0, },
      p2: { x: 112.0, y: 212.0, },
      p3: { x: 112.0, y: 200.0, },
    },
    { min_x: 0.0, min_y: 0.0, max_x: 750.0, max_y: 750.0, },
  )
  let bottom_left = matrix.apply(@geometry.point2(0.0, 0.0))
  let top_right = matrix.apply(@geometry.point2(750.0, 750.0))
  assert_eq(bottom_left.x, 100.0)
  assert_eq(bottom_left.y, 200.0)
  assert_eq(top_right.x, 112.0)
  assert_eq(top_right.y, 212.0)
}

///|
test "TrueType outline serialization preserves quadratic contours" {
  let contour : Array[PdfViewerTrueTypePoint] = [
    { x: 0.0, y: 0.0, on_curve: true, },
    { x: 500.0, y: 1000.0, on_curve: false, },
    { x: 1000.0, y: 0.0, on_curve: true, },
  ]
  let path = pdf_viewer_ttf_path_of_contours(
    [contour][:],
    1000,
    @geometry.transform_identity_matrix,
    0.0,
    0.0,
    1000.0,
  )
  assert_true(path.has_prefix("M "))
  assert_true(path.contains(" Q "))
  assert_true(path.has_suffix(" Z"))
}

///|
test "colour-key masks become transparent RGBA PNG pixels" {
  let data = try! @core.pdf_bytes_of_int_array([255, 0, 0, 0, 0, 255])
  let png = try! pdf_png_of_raw_image_with_color_key(
    2,
    1,
    @pdflite.PdfBPP24,
    data,
    [255.0, 255.0, 0.0, 255.0, 0.0, 255.0],
  )
  let parsed = try! @pdflite.pdf_read_png(png)
  assert_eq(parsed.width, 2)
  assert_eq(parsed.height, 1)
  assert_eq(parsed.color_type, 6)
}

///|
test "soft mask SVG keeps transfer-function backdrop pixels" {
  let page : PdfPageModel = {
    number: 1,
    origin_x: 0.0,
    origin_y: 0.0,
    width: 100.0,
    height: 100.0,
    user_unit: 1.0,
    rotation: 0,
    fonts: [],
    items: [],
    annotations: [],
    text: "",
  }
  let mask : PdfSoftMaskResource = {
    data_uri: "data:image/svg+xml;base64,AA==",
    bounds: { min_x: 10.0, min_y: 10.0, max_x: 20.0, max_y: 20.0, },
    luminosity: false,
    background: "#808080",
  }
  let output = StringBuilder()
  pdf_svg_soft_mask_defs(output, 4, page, Some(mask), 1.0)
  let svg = output.to_string()
  assert_true(svg.contains("fill=\"#808080\""))
  assert_true(svg.contains("mask-type=\"luminance\""))
}

///|
test "soft mask transfer table applies to 8-bit samples" {
  let table : Array[Int] = Array(capacity=256)
  for index in 0..<=256 {
    table.push(255 - index)
  }
  assert_eq(pdf_apply_transfer_map(0, Some(table)), 255)
  assert_eq(pdf_apply_transfer_map(255, Some(table)), 0)
}

///|
test "adjacent soft-masked paint items share one compositor group" {
  let mask : PdfSoftMaskResource = {
    data_uri: "data:image/svg+xml;base64,AA==",
    bounds: { min_x: 0.0, min_y: 0.0, max_x: 100.0, max_y: 100.0, },
    luminosity: false,
    background: "#000000",
  }
  let text_a : PdfTextItem = {
    glyph_transform: None,
    index: 0,
    text: "A",
    charcode: 65,
    advance_x: 10.0,
    advance_y: 0.0,
    vertical: false,
    bounds: { min_x: 10.0, min_y: 70.0, max_x: 20.0, max_y: 80.0, },
    quad: {
      p0: { x: 10.0, y: 70.0, },
      p1: { x: 20.0, y: 70.0, },
      p2: { x: 20.0, y: 80.0, },
      p3: { x: 10.0, y: 80.0, },
    },
    font: "Helvetica",
    font_size: 10.0,
    rendering_mode: 0,
    fill_color: "#000000",
    stroke_color: "#000000",
    fill_alpha: 1.0,
    blend_mode: "normal",
    clip_path: None,
    soft_mask: Some(mask),
    group: None,
    group_path: [],
    type3_outline: None,
  }
  let text_b : PdfTextItem = {
    ..text_a,
    index: 1,
    text: "B",
    bounds: { min_x: 25.0, min_y: 70.0, max_x: 35.0, max_y: 80.0, },
    quad: {
      p0: { x: 25.0, y: 70.0, },
      p1: { x: 35.0, y: 70.0, },
      p2: { x: 35.0, y: 80.0, },
      p3: { x: 25.0, y: 80.0, },
    },
  }
  let page : PdfPageModel = {
    number: 1,
    origin_x: 0.0,
    origin_y: 0.0,
    width: 100.0,
    height: 100.0,
    user_unit: 1.0,
    rotation: 0,
    fonts: [],
    items: [PdfPageItem::Text(text_a), PdfPageItem::Text(text_b)],
    annotations: [],
    text: "AB",
  }
  let svg = try! pdf_render_page_svg(page, 1.0, 0)
  assert_eq(svg.split("<g mask=").length(), 2)
  assert_eq(svg.split("data:image/svg+xml;base64,AA==").length(), 2)
}

///|
test "svg preserves transparency group metadata and isolation" {
  let group : PdfTransparencyGroup = {
    id: "/Fm0",
    isolated: true,
    knockout: false,
  }
  let item : PdfTextItem = {
    glyph_transform: None,
    index: 0,
    text: "A",
    charcode: 65,
    advance_x: 10.0,
    advance_y: 0.0,
    vertical: false,
    bounds: { min_x: 10.0, min_y: 70.0, max_x: 20.0, max_y: 80.0, },
    quad: {
      p0: { x: 10.0, y: 70.0, },
      p1: { x: 20.0, y: 70.0, },
      p2: { x: 20.0, y: 80.0, },
      p3: { x: 10.0, y: 80.0, },
    },
    font: "Helvetica",
    font_size: 10.0,
    rendering_mode: 0,
    fill_color: "#000000",
    stroke_color: "#000000",
    fill_alpha: 1.0,
    blend_mode: "normal",
    clip_path: None,
    soft_mask: None,
    group: Some(group),
    group_path: [group],
    type3_outline: None,
  }
  let page : PdfPageModel = {
    number: 1,
    origin_x: 0.0,
    origin_y: 0.0,
    width: 100.0,
    height: 100.0,
    user_unit: 1.0,
    rotation: 0,
    fonts: [],
    items: [PdfPageItem::Text(item)],
    annotations: [],
    text: "A",
  }
  let svg = try! pdf_render_page_svg(page, 1.0, 0)
  assert_true(
    svg.contains("data-pdf-group-id=\"/Fm0\" data-pdf-group-isolated=\"true\""),
  )
  assert_true(svg.contains("style=\"isolation:isolate\""))
}

///|
test "rotated text uses its source quadrilateral" {
  let item : PdfTextItem = {
    glyph_transform: None,
    index: 0,
    text: "A",
    charcode: 65,
    advance_x: 10.0,
    advance_y: 0.0,
    vertical: false,
    bounds: { min_x: 0.0, min_y: 20.0, max_x: 10.0, max_y: 30.0, },
    quad: {
      p0: { x: 10.0, y: 20.0, },
      p1: { x: 0.0, y: 20.0, },
      p2: { x: 0.0, y: 30.0, },
      p3: { x: 10.0, y: 30.0, },
    },
    font: "Helvetica",
    font_size: 10.0,
    rendering_mode: 0,
    fill_color: "#000000",
    stroke_color: "#000000",
    fill_alpha: 1.0,
    blend_mode: "normal",
    clip_path: None,
    soft_mask: None,
    group: None,
    group_path: [],
    type3_outline: None,
  }
  let page : PdfPageModel = {
    number: 1,
    origin_x: 0.0,
    origin_y: 0.0,
    width: 100.0,
    height: 100.0,
    user_unit: 1.0,
    rotation: 0,
    fonts: [],
    items: [],
    annotations: [],
    text: "A",
  }
  let output = StringBuilder()
  pdf_svg_text(output, page, [item], 1.0)
  assert_true(output.to_string().contains("rotate(-90)"))
}

///|
test "visual quads become affine SVG image transforms" {
  let page : PdfPageModel = {
    number: 1,
    origin_x: 10.0,
    origin_y: 20.0,
    width: 100.0,
    height: 80.0,
    user_unit: 1.0,
    rotation: 0,
    fonts: [],
    items: [],
    annotations: [],
    text: "",
  }
  let item : PdfVisualItem = {
    index: 0,
    bounds: { min_x: 10.0, min_y: 20.0, max_x: 30.0, max_y: 50.0, },
    quad: {
      p0: { x: 10.0, y: 20.0, },
      p1: { x: 10.0, y: 50.0, },
      p2: { x: 30.0, y: 50.0, },
      p3: { x: 30.0, y: 20.0, },
    },
    name: "Im0",
    resource: Some({
      name: "Im0",
      mime_type: "image/png",
      data_uri: Some("data:image/png;base64,AA=="),
      mask_data_uri: None,
      alpha_mask_data_uri: None,
      width: Some(1),
      height: Some(1),
      interpolate: false,
      alpha_mask_width: None,
      alpha_mask_height: None,
    }),
    shading: None,
    fill_color: "#000000",
    fill_alpha: 1.0,
    stroke_alpha: 1.0,
    blend_mode: "normal",
    clip_path: None,
    soft_mask: None,
    group: None,
    group_path: [],
  }
  let output = StringBuilder()
  pdf_svg_image(output, page, item, 1.0)
  assert_true(
    output.to_string().contains("transform=\"matrix(20 0 0 30 0 50)\""),
  )
}

///|
test "viewport matrix follows pdfjs for a nonzero media box" {
  let page : PdfPageModel = {
    number: 1,
    origin_x: 10.0,
    origin_y: 20.0,
    width: 200.0,
    height: 100.0,
    user_unit: 1.0,
    rotation: 0,
    fonts: [],
    items: [],
    annotations: [],
    text: "",
  }
  let viewport = page.viewport(scale=2.0, rotation=0)
  assert_eq(viewport.width, 400.0)
  assert_eq(viewport.height, 200.0)
  assert_eq(viewport.matrix, [2.0, 0.0, 0.0, -2.0, -20.0, 240.0])
  assert_true(viewport.transform.contains("matrix(2"))
  let viewport_point = viewport.convert_to_viewport_point({ x: 10.0, y: 20.0, })
  assert_eq(viewport_point, { x: 0.0, y: 200.0, })
  let pdf_point = viewport.convert_to_pdf_point(viewport_point)
  assert_eq(pdf_point, { x: 10.0, y: 20.0, })
}

///|
test "svg rotation uses the unrotated page dimensions" {
  let page : PdfPageModel = {
    number: 1,
    origin_x: 0.0,
    origin_y: 0.0,
    width: 200.0,
    height: 100.0,
    user_unit: 1.0,
    rotation: 0,
    fonts: [],
    items: [],
    annotations: [],
    text: "",
  }
  let output = try! pdf_render_page_svg(page, 1.0, 90)
  assert_true(output.contains("viewBox=\"0 0 100 200\""))
  assert_true(output.contains("transform=\"translate(100 0) rotate(90)\""))
}

///|
test "path serialization preserves a rotated target quad" {
  let path = @shape.pdf_shape_rectangle(0.0, 0.0, 10.0, 20.0)
  let svg = pdf_svg_path_of_shape_with_quad(path, 0.0, 0.0, 200.0, {
    p0: { x: 100.0, y: 100.0, },
    p1: { x: 80.0, y: 100.0, },
    p2: { x: 80.0, y: 110.0, },
    p3: { x: 100.0, y: 110.0, },
  })
  assert_true(svg.contains("M 100 100 L 100 90"))
}

///|
test "svg preserves paint opacity and blend mode" {
  let item : PdfTextItem = {
    glyph_transform: None,
    index: 0,
    text: "A",
    charcode: 65,
    advance_x: 10.0,
    advance_y: 0.0,
    vertical: false,
    bounds: { min_x: 0.0, min_y: 20.0, max_x: 10.0, max_y: 30.0, },
    quad: {
      p0: { x: 0.0, y: 20.0, },
      p1: { x: 10.0, y: 20.0, },
      p2: { x: 10.0, y: 30.0, },
      p3: { x: 0.0, y: 30.0, },
    },
    font: "Helvetica",
    font_size: 10.0,
    rendering_mode: 0,
    fill_color: "#000000",
    stroke_color: "#000000",
    fill_alpha: 0.5,
    blend_mode: "multiply",
    clip_path: None,
    soft_mask: None,
    group: None,
    group_path: [],
    type3_outline: None,
  }
  let page : PdfPageModel = {
    number: 1,
    origin_x: 0.0,
    origin_y: 0.0,
    width: 100.0,
    height: 100.0,
    user_unit: 1.0,
    rotation: 0,
    fonts: [],
    items: [],
    annotations: [],
    text: "A",
  }
  let output = StringBuilder()
  pdf_svg_text(output, page, [item], 1.0)
  let svg = output.to_string()
  assert_true(svg.contains("fill-opacity=\"0.5\""))
  assert_true(svg.contains("mix-blend-mode:multiply"))
}

///|
test "svg maps stroked PDF text rendering mode" {
  let item : PdfTextItem = {
    glyph_transform: None,
    index: 0,
    text: "A",
    charcode: 65,
    advance_x: 10.0,
    advance_y: 0.0,
    vertical: false,
    bounds: { min_x: 0.0, min_y: 20.0, max_x: 10.0, max_y: 30.0, },
    quad: {
      p0: { x: 0.0, y: 20.0, },
      p1: { x: 10.0, y: 20.0, },
      p2: { x: 10.0, y: 30.0, },
      p3: { x: 0.0, y: 30.0, },
    },
    font: "Helvetica",
    font_size: 10.0,
    rendering_mode: 1,
    fill_color: "#123456",
    stroke_color: "#ABCDEF",
    fill_alpha: 1.0,
    blend_mode: "normal",
    clip_path: None,
    soft_mask: None,
    group: None,
    group_path: [],
    type3_outline: None,
  }
  let page : PdfPageModel = {
    number: 1,
    origin_x: 0.0,
    origin_y: 0.0,
    width: 100.0,
    height: 100.0,
    user_unit: 1.0,
    rotation: 0,
    fonts: [],
    items: [],
    annotations: [],
    text: "A",
  }
  let output = StringBuilder()
  pdf_svg_text(output, page, [item], 1.0)
  let svg = output.to_string()
  assert_true(svg.contains("fill=\"none\""))
  assert_true(svg.contains("stroke=\"#ABCDEF\""))
}

///|
test "stroke widths include the paint CTM scale" {
  let ctm : @geometry.TransformMatrix = {
    a: 2.0,
    b: 0.0,
    c: 0.0,
    d: 2.0,
    e: 0.0,
    f: 0.0,
  }
  assert_true((pdf_ctm_stroke_scale(ctm) - 2.0).abs() < 0.000001)
}

///|
test "svg paints a path pattern through a reusable definition" {
  let item : PdfPathItem = {
    index: 3,
    bounds: { min_x: 0.0, min_y: 0.0, max_x: 10.0, max_y: 10.0, },
    svg_path: "M 0 0 L 10 0 L 10 10 L 0 10 Z",
    filled: true,
    stroked: false,
    fill_color: "#000000",
    stroke_color: "none",
    fill_alpha: 1.0,
    stroke_alpha: 1.0,
    line_width: 1.0,
    line_cap: 0,
    line_join: 0,
    dash_array: [],
    dash_phase: 0.0,
    pattern: Some({
      name: "/p",
      bbox: { min_x: 0.0, min_y: 0.0, max_x: 2.0, max_y: 2.0, },
      x_step: 2.0,
      y_step: 2.0,
      matrix: [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
      tile_svg: "<path d=\"M 0 0 L 1 1\" fill=\"none\"/>",
      tile_parts: [],
      shading: None,
    }),
    shading_pattern: None,
    stroke_pattern: None,
    blend_mode: "normal",
    clip_path: None,
    soft_mask: None,
    group: None,
    group_path: [],
  }
  let page : PdfPageModel = {
    number: 1,
    origin_x: 0.0,
    origin_y: 0.0,
    width: 100.0,
    height: 100.0,
    user_unit: 1.0,
    rotation: 0,
    fonts: [],
    items: [],
    annotations: [],
    text: "",
  }
  let output = StringBuilder()
  pdf_svg_path(output, page, item, 1.0)
  let svg = output.to_string()
  assert_true(svg.contains("<pattern id=\"pdf-pattern-3\""))
  assert_true(svg.contains("patternTransform=\"matrix(1 0 0 -1 0 100)\""))
  assert_true(svg.contains("fill=\"url(#pdf-pattern-3)\""))
}

///|
test "shading pattern keeps its own matrix outside the path CTM" {
  let shading : PdfShadingResource = {
    name: "S0",
    kind: "mesh",
    coords: [],
    matrix: [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
    stops: [],
    mesh: [],
    extend_start: true,
    extend_end: true,
  }
  let pattern : PdfPatternResource = {
    name: "P0",
    bbox: { min_x: 0.0, min_y: 0.0, max_x: 1.0, max_y: 1.0, },
    x_step: 1.0,
    y_step: 1.0,
    matrix: [2.0, 0.0, 0.0, 2.0, 150.0, 300.0],
    tile_svg: "",
    tile_parts: [],
    shading: Some(shading),
  }
  let transformed = pdf_pattern_resource_with_ctm(pattern, {
    a: 0.24,
    b: 0.0,
    c: 0.0,
    d: 0.24,
    e: 0.0,
    f: 0.0,
  })
  assert_eq(transformed.matrix, [2.0, 0.0, 0.0, 2.0, 150.0, 300.0])
  guard transformed.shading is Some(shading) else {
    fail("shading pattern should retain its shading resource")
  }
  assert_eq(shading.matrix, [2.0, 0.0, 0.0, 2.0, 150.0, 300.0])
}

///|
test "svg lowers a mesh shading triangle" {
  let item : PdfVisualItem = {
    index: 11,
    bounds: { min_x: 0.0, min_y: 0.0, max_x: 20.0, max_y: 20.0, },
    quad: {
      p0: { x: 0.0, y: 0.0, },
      p1: { x: 0.0, y: 20.0, },
      p2: { x: 20.0, y: 20.0, },
      p3: { x: 20.0, y: 0.0, },
    },
    name: "Mesh0",
    resource: None,
    shading: Some({
      name: "Mesh0",
      kind: "mesh",
      coords: [],
      matrix: [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
      stops: [],
      mesh: [
        {
          p0: { x: 0.0, y: 0.0, },
          p1: { x: 20.0, y: 0.0, },
          p2: { x: 0.0, y: 20.0, },
          c0: "#FF0000",
          c1: "#00FF00",
          c2: "#0000FF",
        },
      ],
      extend_start: true,
      extend_end: true,
    }),
    fill_color: "#000000",
    fill_alpha: 1.0,
    stroke_alpha: 1.0,
    blend_mode: "normal",
    clip_path: None,
    soft_mask: None,
    group: None,
    group_path: [],
  }
  let page : PdfPageModel = {
    number: 1,
    origin_x: 0.0,
    origin_y: 0.0,
    width: 20.0,
    height: 20.0,
    user_unit: 1.0,
    rotation: 0,
    fonts: [],
    items: [],
    annotations: [],
    text: "",
  }
  let output = StringBuilder()
  pdf_svg_shading(output, page, item, 1.0)
  let svg = output.to_string()
  assert_true(svg.contains("data-pdf-kind=\"mesh-shading\""))
  assert_true(svg.split("<polygon").length() > 10)
  assert_true(svg.contains("fill=\"#AA2B2B\""))
  assert_true(svg.contains("stroke-width=\"0.08\""))
}

///|
test "mesh SVG expansion stays bounded for large sources" {
  assert_eq(pdf_mesh_subdivision_steps(1), 4)
  assert_eq(pdf_mesh_subdivision_steps(1001), 3)
  assert_eq(pdf_mesh_subdivision_steps(2001), 2)
}

///|
test "svg places clipping definitions before painted elements" {
  let item : PdfTextItem = {
    glyph_transform: None,
    index: 7,
    text: "A",
    charcode: 65,
    advance_x: 10.0,
    advance_y: 0.0,
    vertical: false,
    bounds: { min_x: 0.0, min_y: 20.0, max_x: 10.0, max_y: 30.0, },
    quad: {
      p0: { x: 0.0, y: 20.0, },
      p1: { x: 10.0, y: 20.0, },
      p2: { x: 10.0, y: 30.0, },
      p3: { x: 0.0, y: 30.0, },
    },
    font: "Helvetica",
    font_size: 10.0,
    rendering_mode: 0,
    fill_color: "#000000",
    stroke_color: "#000000",
    fill_alpha: 1.0,
    blend_mode: "normal",
    clip_path: Some("M 0 0 L 10 0 L 10 10 L 0 10 Z"),
    soft_mask: None,
    group: None,
    group_path: [],
    type3_outline: None,
  }
  let page : PdfPageModel = {
    number: 1,
    origin_x: 0.0,
    origin_y: 0.0,
    width: 100.0,
    height: 100.0,
    user_unit: 1.0,
    rotation: 0,
    fonts: [],
    items: [],
    annotations: [],
    text: "A",
  }
  let output = StringBuilder()
  pdf_svg_text(output, page, [item], 1.0)
  let svg = output.to_string()
  assert_true(svg.has_prefix("<defs><clipPath"))
  assert_true(svg.contains("</defs><g clip-path=\"url(#pdf-clip-7)\"><text"))
  assert_true(!svg.contains("<text<defs>"))
}

///|
test "inline raw pixels become a browser resource" {
  let font = @pdflite.PdfFontStandard({
    font: @pdflite.PdfHelvetica,
    encoding: @pdflite.PdfWinAnsiEncoding,
  })
  let pack = @pdflite.pdf_fontpack_of_standard_font(font)
  let paper = @geometry.paper_size_make(@geometry.PdfPoint, 20.0, 20.0)
  let document = @pdflite.pdf_texttopdf_typeset(
    pack,
    8.0,
    paper,
    @utf8.encode("test"),
  )
  let name = fn(text : String) -> @core.PdfName {
    @core.pdf_name_of_bytes(@utf8.encode(text))
  }
  let dictionary : @syntax.PdfObject = @syntax.PdfDictionary([
    (name("/Width"), @syntax.PdfInteger(1)),
    (name("/Height"), @syntax.PdfInteger(1)),
    (name("/BitsPerComponent"), @syntax.PdfInteger(8)),
    (name("/ColorSpace"), @syntax.PdfNameObject(name("/DeviceRGB"))),
  ])
  let data = try! @core.pdf_bytes_of_int_array([255, 0, 0])
  let resource = pdf_inline_image_resource_of(
    document,
    @syntax.PdfDictionary([]),
    "inline-image-0",
    dictionary,
    data,
  )
  guard resource is Some(resource) else { fail("inline image should decode") }
  assert_eq(resource.mime_type, "image/png")
  guard resource.data_uri is Some(uri) else { fail("PNG data URI missing") }
  assert_true(uri.has_prefix("data:image/png;base64,"))
}

///|
test "inline ImageMask keeps a browser mask resource" {
  let font = @pdflite.PdfFontStandard({
    font: @pdflite.PdfHelvetica,
    encoding: @pdflite.PdfWinAnsiEncoding,
  })
  let pack = @pdflite.pdf_fontpack_of_standard_font(font)
  let paper = @geometry.paper_size_make(@geometry.PdfPoint, 20.0, 20.0)
  let document = @pdflite.pdf_texttopdf_typeset(
    pack,
    8.0,
    paper,
    @utf8.encode("test"),
  )
  let name = fn(text : String) -> @core.PdfName {
    @core.pdf_name_of_bytes(@utf8.encode(text))
  }
  let dictionary : @syntax.PdfObject = @syntax.PdfDictionary([
    (name("/W"), @syntax.PdfInteger(8)),
    (name("/H"), @syntax.PdfInteger(1)),
    (name("/IM"), @syntax.PdfBoolean(true)),
  ])
  let data = try! @core.pdf_bytes_of_int_array([0b1010_0000])
  let resource = pdf_inline_image_resource_of(
    document,
    @syntax.PdfDictionary([]),
    "inline-mask",
    dictionary,
    data,
  )
  guard resource is Some(resource) else {
    fail("inline ImageMask should decode")
  }
  assert_eq(resource.mime_type, "image/mask")
  guard resource.mask_data_uri is Some(mask) else {
    fail("inline ImageMask data URI missing")
  }
  assert_true(mask.has_prefix("data:image/png;base64,"))
  let item : PdfVisualItem = {
    index: 4,
    bounds: { min_x: 0.0, min_y: 0.0, max_x: 8.0, max_y: 1.0, },
    quad: {
      p0: { x: 0.0, y: 0.0, },
      p1: { x: 0.0, y: 1.0, },
      p2: { x: 8.0, y: 1.0, },
      p3: { x: 8.0, y: 0.0, },
    },
    name: "inline-mask",
    resource: Some(resource),
    shading: None,
    fill_color: "#0033CC",
    fill_alpha: 1.0,
    stroke_alpha: 1.0,
    blend_mode: "normal",
    clip_path: None,
    soft_mask: None,
    group: None,
    group_path: [],
  }
  let page : PdfPageModel = {
    number: 1,
    origin_x: 0.0,
    origin_y: 0.0,
    width: 20.0,
    height: 20.0,
    user_unit: 1.0,
    rotation: 0,
    fonts: [],
    items: [],
    annotations: [],
    text: "",
  }
  let output = StringBuilder()
  pdf_svg_image(output, page, item, 1.0)
  assert_true(output.to_string().contains("data:image/svg+xml;base64,"))
}

///|
fn inline_image_viewer_fixture(
  dictionary : @syntax.PdfObject,
  decode_parms : @syntax.PdfObject?,
  encoded : Bytes,
) -> PdfViewerDocument raise {
  let font = @pdflite.PdfFontStandard({
    font: @pdflite.PdfHelvetica,
    encoding: @pdflite.PdfWinAnsiEncoding,
  })
  let pack = @pdflite.pdf_fontpack_of_standard_font(font)
  let paper = @geometry.paper_size_make(@geometry.PdfPoint, 40.0, 40.0)
  let document = @pdflite.pdf_texttopdf_typeset(
    pack,
    8.0,
    paper,
    @utf8.encode("inline image"),
  )
  let page = document.pages_of_pagetree()[0]
  let ops : Array[@content.PdfContentOp] = [
    @content.Op_InlineImage(dictionary, decode_parms, encoded),
  ]
  let changed_page = {
    ..page,
    resources: @syntax.PdfDictionary([]),
    content: [@pdflite.pdf_content_stream_of_ops(ops)],
  }
  let document = document.change_pages([changed_page])
  open_document(@pdflite.pdf_write_document(document))
}

///|
fn inline_fixture_name(text : String) -> @core.PdfName {
  @core.pdf_name_of_bytes(@utf8.encode(text))
}

///|
fn inline_ccitt_viewer_fixture() -> PdfViewerDocument raise {
  let dictionary : @syntax.PdfObject = @syntax.PdfDictionary([
    (inline_fixture_name("/W"), @syntax.PdfInteger(8)),
    (inline_fixture_name("/H"), @syntax.PdfInteger(2)),
    (
      inline_fixture_name("/CS"),
      @syntax.PdfNameObject(inline_fixture_name("/G")),
    ),
    (inline_fixture_name("/BPC"), @syntax.PdfInteger(1)),
    (
      inline_fixture_name("/F"),
      @syntax.PdfNameObject(inline_fixture_name("/CCITTFaxDecode")),
    ),
  ])
  let decode_parms : @syntax.PdfObject = @syntax.PdfDictionary([
    (inline_fixture_name("/K"), @syntax.PdfInteger(-1)),
    (inline_fixture_name("/Columns"), @syntax.PdfInteger(8)),
    (inline_fixture_name("/Rows"), @syntax.PdfInteger(2)),
  ])
  let raw = try! @core.pdf_bytes_of_int_array([0xF0, 0x00])
  let encoded = try! @pdflite.pdf_ccitt_g4_encode(8, 2, raw)
  inline_image_viewer_fixture(dictionary, Some(decode_parms), encoded)
}

///|
fn inline_ccitt_g3_viewer_fixture() -> PdfViewerDocument raise {
  let dictionary : @syntax.PdfObject = @syntax.PdfDictionary([
    (inline_fixture_name("/W"), @syntax.PdfInteger(8)),
    (inline_fixture_name("/H"), @syntax.PdfInteger(2)),
    (
      inline_fixture_name("/CS"),
      @syntax.PdfNameObject(inline_fixture_name("/G")),
    ),
    (inline_fixture_name("/BPC"), @syntax.PdfInteger(1)),
    (
      inline_fixture_name("/F"),
      @syntax.PdfNameObject(inline_fixture_name("/CCITTFaxDecode")),
    ),
  ])
  let decode_parms : @syntax.PdfObject = @syntax.PdfDictionary([
    (inline_fixture_name("/K"), @syntax.PdfInteger(0)),
    (inline_fixture_name("/Columns"), @syntax.PdfInteger(8)),
    (inline_fixture_name("/Rows"), @syntax.PdfInteger(2)),
  ])
  let raw = try! @core.pdf_bytes_of_int_array([0xF0, 0x00])
  let encoded = try! @pdflite.pdf_ccitt_encode(8, 2, raw)
  inline_image_viewer_fixture(dictionary, Some(decode_parms), encoded)
}

///|
fn inline_decode_viewer_fixture() -> PdfViewerDocument raise {
  let dictionary : @syntax.PdfObject = @syntax.PdfDictionary([
    (inline_fixture_name("/W"), @syntax.PdfInteger(4)),
    (inline_fixture_name("/H"), @syntax.PdfInteger(1)),
    (
      inline_fixture_name("/CS"),
      @syntax.PdfNameObject(inline_fixture_name("/G")),
    ),
    (inline_fixture_name("/BPC"), @syntax.PdfInteger(1)),
    (
      inline_fixture_name("/Decode"),
      @syntax.PdfArray([@syntax.PdfInteger(1), @syntax.PdfInteger(0)]),
    ),
  ])
  let raw = try! @core.pdf_bytes_of_int_array([0xA0])
  inline_image_viewer_fixture(dictionary, None, raw)
}

///|
fn inline_mask_viewer_fixture() -> PdfViewerDocument raise {
  let dictionary : @syntax.PdfObject = @syntax.PdfDictionary([
    (inline_fixture_name("/W"), @syntax.PdfInteger(4)),
    (inline_fixture_name("/H"), @syntax.PdfInteger(1)),
    (inline_fixture_name("/IM"), @syntax.PdfBoolean(true)),
  ])
  let raw = try! @core.pdf_bytes_of_int_array([0xA0])
  inline_image_viewer_fixture(dictionary, None, raw)
}

///|
fn inline_predictor_viewer_fixture() -> PdfViewerDocument raise {
  let dictionary : @syntax.PdfObject = @syntax.PdfDictionary([
    (inline_fixture_name("/W"), @syntax.PdfInteger(2)),
    (inline_fixture_name("/H"), @syntax.PdfInteger(2)),
    (
      inline_fixture_name("/CS"),
      @syntax.PdfNameObject(inline_fixture_name("/G")),
    ),
    (inline_fixture_name("/BPC"), @syntax.PdfInteger(8)),
    (
      inline_fixture_name("/F"),
      @syntax.PdfNameObject(inline_fixture_name("/FlateDecode")),
    ),
  ])
  let decode_parms : @syntax.PdfObject = @syntax.PdfDictionary([
    (inline_fixture_name("/Predictor"), @syntax.PdfInteger(12)),
    (inline_fixture_name("/Colors"), @syntax.PdfInteger(1)),
    (inline_fixture_name("/BitsPerComponent"), @syntax.PdfInteger(8)),
    (inline_fixture_name("/Columns"), @syntax.PdfInteger(2)),
  ])
  let raw = try! @core.pdf_bytes_of_int_array([10, 20, 30, 40])
  let predicted = try! @pdflite.pdf_encode_predictor(12, 1, 8, 2, raw)
  let encoded = @flate.pdf_flate_encode(predicted)
  inline_image_viewer_fixture(dictionary, Some(decode_parms), encoded)
}

///|
test "inline CCITT preserves DecodeParms through the viewer image path" {
  let viewer = inline_ccitt_viewer_fixture()
  let page = viewer.page(1).unwrap()
  guard page.items is [PdfPageItem::Image(image), ..] else {
    fail("inline CCITT should produce an image item")
  }
  guard image.resource is Some(resource) else {
    fail("inline CCITT should decode into a browser resource")
  }
  guard resource.data_uri is Some(uri) else {
    fail("inline CCITT should produce PNG data")
  }
  assert_true(uri.has_prefix("data:image/png;base64,"))
  let rendered = try! page.render_svg(scale=1.0, rotation=0)
  assert_true(rendered.contains("data:image/png;base64,"))
}

///|
test "inline CCITT Group 3 decodes through the page model" {
  let viewer = inline_ccitt_g3_viewer_fixture()
  let page = viewer.page(1).unwrap()
  guard page.items is [PdfPageItem::Image(image), ..] else {
    fail("inline Group 3 should produce an image item")
  }
  guard image.resource is Some(resource) else {
    fail("inline Group 3 should produce a resource")
  }
  guard resource.data_uri is Some(uri) else {
    fail("inline Group 3 should produce PNG data")
  }
  let png = try! @base64.decode(uri[22:])
  let parsed = try! @pdflite.pdf_read_png(png)
  let scanlines = try! @flate.pdf_flate_decode(parsed.idat)
  assert_eq(parsed.width, 8)
  assert_eq(parsed.height, 2)
  assert_eq(scanlines.length(), 2 * (1 + 8 * 3))
  assert_eq(scanlines[0].to_int(), 0)
  assert_eq(scanlines[1].to_int(), 255)
  assert_eq(scanlines[4].to_int(), 255)
  assert_eq(scanlines[1 + 8 * 3].to_int(), 0)
  assert_eq(scanlines[1 + 8 * 3 + 1].to_int(), 0)
}

///|
test "inline one-bit Decode array is reflected in browser pixels" {
  let viewer = inline_decode_viewer_fixture()
  let page = viewer.page(1).unwrap()
  guard page.items is [PdfPageItem::Image(image), ..] else {
    fail("inline Decode image should produce an image item")
  }
  guard image.resource is Some(resource) else {
    fail("inline Decode image should produce a resource")
  }
  guard resource.data_uri is Some(uri) else {
    fail("inline Decode image should produce PNG data")
  }
  let png = try! @base64.decode(uri[22:])
  let parsed = try! @pdflite.pdf_read_png(png)
  let scanlines = try! @flate.pdf_flate_decode(parsed.idat)
  assert_eq(parsed.width, 4)
  assert_eq(parsed.height, 1)
  assert_eq(scanlines.length(), 1 + 4 * 3)
  assert_eq(scanlines[1].to_int(), 0)
  assert_eq(scanlines[4].to_int(), 255)
  assert_eq(scanlines[7].to_int(), 0)
  assert_eq(scanlines[10].to_int(), 255)
}

///|
test "inline ImageMask survives the serialized viewer path" {
  let viewer = inline_mask_viewer_fixture()
  let page = viewer.page(1).unwrap()
  guard page.items is [PdfPageItem::Image(image), ..] else {
    fail("inline ImageMask should produce an image item")
  }
  guard image.resource is Some(resource) else {
    fail("inline ImageMask should produce a resource")
  }
  assert_eq(resource.mime_type, "image/mask")
  guard resource.mask_data_uri is Some(uri) else {
    fail("inline ImageMask should produce a mask PNG")
  }
  let png = try! @base64.decode(uri[22:])
  let parsed = try! @pdflite.pdf_read_png(png)
  let scanlines = try! @flate.pdf_flate_decode(parsed.idat)
  assert_eq(parsed.width, 4)
  assert_eq(parsed.height, 1)
  assert_eq(parsed.color_type, 2)
  assert_eq(scanlines.length(), 1 + 4 * 3)
  assert_eq(scanlines[1].to_int(), 0)
  assert_eq(scanlines[4].to_int(), 255)
  assert_eq(scanlines[7].to_int(), 0)
  assert_eq(scanlines[10].to_int(), 255)
}

///|
test "inline Flate PNG predictor is decoded before SVG PNG encoding" {
  let viewer = inline_predictor_viewer_fixture()
  let page = viewer.page(1).unwrap()
  guard page.items is [PdfPageItem::Image(image), ..] else {
    fail("inline predictor image should produce an image item")
  }
  guard image.resource is Some(resource) else {
    fail("inline predictor image should produce a resource")
  }
  guard resource.data_uri is Some(uri) else {
    fail("inline predictor image should produce PNG data")
  }
  let png = try! @base64.decode(uri[22:])
  let parsed = try! @pdflite.pdf_read_png(png)
  let scanlines = try! @flate.pdf_flate_decode(parsed.idat)
  assert_eq(parsed.width, 2)
  assert_eq(parsed.height, 2)
  assert_eq(scanlines.length(), 2 * (1 + 2 * 3))
  assert_eq(scanlines[1].to_int(), 10)
  assert_eq(scanlines[4].to_int(), 20)
  assert_eq(scanlines[8].to_int(), 30)
  assert_eq(scanlines[11].to_int(), 40)
}

///|
fn page_box_test_page(page_dictionary : String) -> PdfPageModel raise {
  let viewer = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    page_dictionary,
    annotation_test_stream("", ""),
  ])
  viewer.page(1).unwrap()
}

///|
test "page view intersects crop box and applies user unit" {
  let page = page_box_test_page(
    "<< /Type /Page /Parent 2 0 R /MediaBox [10 20 210 320] " +
    "/CropBox [-10 0 100 200] /UserUnit 2 /Contents 4 0 R /Resources << >> >>",
  )
  assert_eq(page.origin_x, 10.0)
  assert_eq(page.origin_y, 20.0)
  assert_eq(page.width, 90.0)
  assert_eq(page.height, 180.0)
  assert_eq(page.user_unit, 2.0)
  let viewport = page.viewport(scale=1.0, rotation=0)
  assert_eq(viewport.scale, 1.0)
  assert_eq(viewport.user_unit, 2.0)
  assert_eq(viewport.width, 180.0)
  assert_eq(viewport.height, 360.0)
  assert_eq(viewport.matrix, [2.0, 0.0, 0.0, -2.0, -20.0, 400.0])
  assert_eq(viewport.convert_to_viewport_point({ x: 10.0, y: 20.0, }), {
    x: 0.0,
    y: 360.0,
  })
  let svg = try! page.render_svg(scale=1.0, rotation=0)
  assert_true(svg.contains("viewBox=\"0 0 180 360\""))
}

///|
test "invalid or disjoint crop boxes fall back to media box" {
  let invalid = page_box_test_page(
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 120] " +
    "/CropBox [0 0 0 120] /UserUnit -2 /Contents 4 0 R /Resources << >> >>",
  )
  assert_eq(invalid.origin_x, 0.0)
  assert_eq(invalid.origin_y, 0.0)
  assert_eq(invalid.width, 100.0)
  assert_eq(invalid.height, 120.0)
  assert_eq(invalid.user_unit, 1.0)
  let disjoint = page_box_test_page(
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 120] " +
    "/CropBox [200 200 300 300] /Contents 4 0 R /Resources << >> >>",
  )
  assert_eq(disjoint.width, 100.0)
  assert_eq(disjoint.height, 120.0)
}

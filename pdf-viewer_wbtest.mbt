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
    index: 0,
    text: "A",
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
    index: 0,
    text: "A",
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
  }
  let page : PdfPageModel = {
    number: 1,
    origin_x: 0.0,
    origin_y: 0.0,
    width: 100.0,
    height: 100.0,
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
    index: 0,
    text: "A",
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
  }
  let page : PdfPageModel = {
    number: 1,
    origin_x: 0.0,
    origin_y: 0.0,
    width: 100.0,
    height: 100.0,
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
    }),
    shading: None,
    fill_color: "#000000",
    fill_alpha: 1.0,
    stroke_alpha: 1.0,
    blend_mode: "normal",
    clip_path: None,
    soft_mask: None,
    group: None,
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
    index: 0,
    text: "A",
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
  }
  let page : PdfPageModel = {
    number: 1,
    origin_x: 0.0,
    origin_y: 0.0,
    width: 100.0,
    height: 100.0,
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
    index: 0,
    text: "A",
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
  }
  let page : PdfPageModel = {
    number: 1,
    origin_x: 0.0,
    origin_y: 0.0,
    width: 100.0,
    height: 100.0,
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
    }),
    blend_mode: "normal",
    clip_path: None,
    soft_mask: None,
    group: None,
  }
  let page : PdfPageModel = {
    number: 1,
    origin_x: 0.0,
    origin_y: 0.0,
    width: 100.0,
    height: 100.0,
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
test "svg places clipping definitions before painted elements" {
  let item : PdfTextItem = {
    index: 7,
    text: "A",
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
  }
  let page : PdfPageModel = {
    number: 1,
    origin_x: 0.0,
    origin_y: 0.0,
    width: 100.0,
    height: 100.0,
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
  }
  let page : PdfPageModel = {
    number: 1,
    origin_x: 0.0,
    origin_y: 0.0,
    width: 20.0,
    height: 20.0,
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

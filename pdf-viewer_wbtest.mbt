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
    fill_alpha: 1.0,
    blend_mode: "normal",
    clip_path: None,
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
    fill_alpha: 0.5,
    blend_mode: "multiply",
    clip_path: None,
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
      tile_svg: "<path d=\"M 0 0 L 1 1\" fill=\"none\"/>",
    }),
    blend_mode: "normal",
    clip_path: None,
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
    fill_alpha: 1.0,
    blend_mode: "normal",
    clip_path: Some("M 0 0 L 10 0 L 10 10 L 0 10 Z"),
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
  assert_true(svg.contains("</defs><text clip-path=\"url(#pdf-clip-7)\""))
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

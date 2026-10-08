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
    text: "A",
  }
  let output = StringBuilder()
  pdf_svg_text(output, page, [item], 1.0)
  assert_true(output.to_string().contains("rotate(-90)"))
}

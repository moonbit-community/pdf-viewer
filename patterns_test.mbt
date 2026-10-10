///|
test "public page model and SVG keep fill and stroke tiling paints independent" {
  let contents = "/Cs cs 1 0 0 /P1 scn /Cs CS 0 0 1 /P1 SCN " +
    "10 10 40 40 re B 0 1 0 rg 60 10 20 20 re f"
  let cell = "0 0 5 10 re f"
  let objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R " +
    "/Resources << /Pattern << /P1 5 0 R >> /ColorSpace << /Cs [/Pattern /DeviceRGB] >> >> >>",
    "<< /Length \{contents.length()} >>\nstream\n\{contents}\nendstream",
    "<< /Type /Pattern /PatternType 1 /PaintType 2 /TilingType 1 " +
    "/BBox [0 0 10 10] /XStep 10 /YStep 10 /Resources << >> " +
    "/Length \{cell.length()} >>\nstream\n\{cell}\nendstream",
  ]
  let pdf = StringBuilder()
  pdf.write_string("%PDF-1.7\n")
  let offsets : Array[Int] = []
  for index, object in objects {
    offsets.push(pdf.to_string().length())
    pdf.write_string("\{index + 1} 0 obj\n\{object}\nendobj\n")
  }
  let xref = pdf.to_string().length()
  pdf.write_string("xref\n0 6\n0000000000 65535 f \n")
  for offset in offsets {
    pdf.write_string(offset.to_string().pad_start(10, '0') + " 00000 n \n")
  }
  pdf.write_string(
    "trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n\{xref}\n%%EOF\n",
  )
  let document = @pdf-viewer.open_document(@utf8.encode(pdf.to_string()))
  let page = document.page(1).unwrap()
  guard page.operator_list()
    is [@pdf-viewer.Path(both), @pdf-viewer.Path(plain)] else {
    fail("missing public path items")
  }
  guard both.pattern is Some(fill) && both.stroke_pattern is Some(stroke) else {
    fail("missing independent pattern resources")
  }
  assert_true(fill.tile_svg.contains("fill=\"#FF0000\""))
  assert_true(stroke.tile_svg.contains("fill=\"#0000FF\""))
  assert_eq(plain.fill_color, "#00FF00")
  assert_true(plain.pattern is None)
  assert_true(plain.stroke_pattern is None)
  let svg = page.render_svg()
  assert_true(svg.contains("fill=\"url(#pdf-pattern-0)\""))
  assert_true(svg.contains("stroke=\"url(#pdf-stroke-pattern-0)\""))
  assert_true(svg.contains("fill=\"#00FF00\""))
}

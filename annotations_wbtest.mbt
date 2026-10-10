///|
/// Build an ASCII PDF with an actual xref table. Tests go through the public
/// byte-reader/page/renderer path rather than constructing viewer models.
fn annotation_test_document(objects : Array[String]) -> PdfViewerDocument raise {
  let output = StringBuilder()
  output.write_string("%PDF-1.7\n")
  let offsets : Array[Int] = []
  for index, object in objects {
    offsets.push(output.to_string().length())
    output.write_string("\{index + 1} 0 obj\n\{object}\nendobj\n")
  }
  let xref = output.to_string().length()
  output.write_string("xref\n0 \{objects.length() + 1}\n0000000000 65535 f \n")
  for offset in offsets {
    output.write_string(offset.to_string().pad_start(10, '0') + " 00000 n \n")
  }
  output.write_string(
    "trailer\n<< /Size \{objects.length() + 1} /Root 1 0 R >>\nstartxref\n\{xref}\n%%EOF\n",
  )
  open_document(@utf8.encode(output.to_string()))
}

///|
fn annotation_test_stream(dictionary : String, contents : String) -> String {
  "<< /Length \{contents.length()} \{dictionary} >>\nstream\n\{contents}\nendstream"
}

///|
fn annotation_test_page(
  annotations : Array[String],
  extra? : Array[String] = [],
  contents? : String = "",
  resources? : String = "<< >>",
) -> PdfPageModel raise {
  let references = [
    for i in 0..<annotations.length() => "\{i + 5} 0 R"
  ].join(" ")
  let viewer = annotation_test_document(
    [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources \{resources} /Annots [\{references}] >>",
      annotation_test_stream("", contents),
      ..annotations,
      ..extra,
    ],
  )
  guard viewer.page(1) is Some(page) else { fail("missing test page") }
  page
}

///|
test "annotation colors retain normalized components and explicit transparency" {
  let colors = ["[1 0.5 0]", "[0.5]", "[0 1 1 0]", "[]", "[-1 2 0]"]
  let page = annotation_test_page(
    [
      for color in colors => {
        "<< /Subtype /Square /Rect [10 10 30 30] /C \{color} >>"
      }
    ],
  )
  assert_eq(page.annotations.map(a => a.color), [
    Some("#FF8000"),
    Some("#808080"),
    Some("#FF2E17"),
    Some("none"),
    Some("#00FF00"),
  ])
  let svg = pdf_render_page_svg(page, 1.0, 0)
  assert_true(svg.contains("stroke=\"#FF8000\""))
  assert_true(svg.contains("stroke=\"none\""))
}

///|
test "annotation flags separate screen visibility and printing" {
  let page = annotation_test_page(
    [
      for flag in [0, 4, 6, 5, 36] => {
        "<< /Subtype /Square /Rect [10 10 30 30] /F \{flag} >>"
      }
    ],
  )
  assert_eq(page.annotations.map(a => a.visible), [
    true, true, false, false, false,
  ])
  assert_eq(page.annotations.map(a => a.print), [
    false, true, false, false, true,
  ])
  let svg = pdf_render_page_svg(page, 1.0, 0)
  assert_true(svg.contains("data-pdf-annotation-index=\"1\""))
  assert_true(!svg.contains("data-pdf-annotation-index=\"2\""))
  assert_true(!svg.contains("data-pdf-annotation-index=\"4\""))
}

///|
test "markup quads survive popup children and malformed siblings" {
  let page = annotation_test_page([
    "<< /Subtype /Highlight /Rect [10 10 90 40] /C [1 0 0] /Popup 6 0 R /QuadPoints [10 40 90 40 10 30 90 30 10 20 50 20 10 10 50 10] >>",
    "<< /Subtype /Popup /Parent 5 0 R /Rect [100 100 120 120] >>", "<< /Subtype /Square /Rect (malformed) >>",
    "<< /Subtype /Line /Rect [10 50 90 60] /L [10 50 90 60] >>",
  ])
  assert_eq(page.annotations.length(), 2)
  assert_eq(page.annotations[0].subtype, "highlight")
  assert_eq(page.annotations[0].quad_points.length(), 2)
  assert_eq(page.annotations[0].quad_points[0].p3, { x: 10.0, y: 40.0, })
  assert_eq(page.annotations[1].line_points, [
    { x: 10.0, y: 50.0, },
    { x: 90.0, y: 60.0, },
  ])
  assert_eq(page.annotations[1].index, 3)
  let svg = pdf_render_page_svg(page, 1.0, 0)
  assert_eq(svg.split("<polygon ").length() - 1, 2)
}

///|
test "appearance rotation and shear fit a nonuniform annotation rectangle" {
  let page = annotation_test_page(
    ["<< /Subtype /Square /Rect [40 50 100 130] /AP << /N 6 0 R >> >>"],
    extra=[
      annotation_test_stream(
        "/BBox [0 0 20 10] /Matrix [0 1 -1 0 3 4]", "1 0 0 rg 0 0 20 10 re f",
      ),
    ],
  )
  let svg = pdf_render_page_svg(page, 1.0, 0)
  // Local (0,0), (20,0), (0,10), (20,10) map to the four /Rect corners.
  assert_true(svg.contains("transform=\"matrix(0 -4 6 0 40 150)\""))
  let shear_page = annotation_test_page(
    ["<< /Subtype /Square /Rect [40 50 100 130] /AP << /N 6 0 R >> >>"],
    extra=[
      annotation_test_stream(
        "/BBox [0 0 10 10] /Matrix [1 1 2 1 3 4]", "0 0 10 10 re f",
      ),
    ],
  )
  let svg = pdf_render_page_svg(shear_page, 1.0, 0)
  assert_true(svg.contains("transform=\"matrix(2 -4 -4 4 80 110)\""))
}

///|
test "appearance states preserve empty streams and missing BBox defaults" {
  let page = annotation_test_page(
    [
      "<< /Subtype /Square /Rect [40 50 100 130] /AP << /N << /Off 7 0 R /On 8 0 R >> >> /AS /Off >>",
      "<< /Subtype /Square /Rect [40 50 100 130] /AP << /N 8 0 R >> >>",
    ],
    extra=[
      annotation_test_stream("/BBox [0 0 20 10]", ""),
      annotation_test_stream("", "1 0 0 rg 0 0 60 80 re f"),
    ],
  )
  guard page.annotations[0].appearance is Some(empty) else {
    fail("empty AP lost")
  }
  assert_true(!empty.svg.contains("<path"))
  guard page.annotations[1].appearance is Some(default_bbox) else {
    fail("missing BBox AP lost")
  }
  assert_eq(default_bbox.bbox, {
    min_x: 0.0,
    min_y: 0.0,
    max_x: 60.0,
    max_y: 80.0,
  })
  let svg = pdf_render_page_svg(page, 1.0, 0)
  assert_eq(
    svg.split("data-pdf-annotation-appearance=\"true\"").length() - 1,
    2,
  )
  assert_true(!svg.contains("<rect data-pdf-annotation"))
  assert_true(default_bbox.svg.contains("overflow=\"hidden\""))
}

///|
test "appearance clip IDs are distinct from page content and other appearances" {
  let clipped = "0 0 10 10 re W n 1 0 0 rg 0 0 30 30 re f"
  let page = annotation_test_page(
    [
      "<< /Subtype /Square /Rect [10 10 30 30] /AP << /N 7 0 R >> >>", "<< /Subtype /Square /Rect [50 10 90 30] /AP << /N 7 0 R >> >>",
    ],
    extra=[annotation_test_stream("/BBox [0 0 20 20]", clipped)],
    contents=clipped,
  )
  let svg = pdf_render_page_svg(page, 1.0, 0)
  let ids : Map[String, Bool] = Map([])
  for fragment in svg.split("<clipPath id=\"").drop(1) {
    let id = fragment.split("\"").next().unwrap().to_owned()
    assert_true(!ids.contains(id), msg="duplicate clip ID: \{id}")
    ids[id] = true
    assert_true(svg.contains("url(#\{id})"))
  }
  assert_true(ids.length() >= 3)
}

///|
test "appearance fonts use their own resource dictionaries" {
  let text = "BT /F1 12 Tf 2 4 Td (A) Tj ET"
  let page = annotation_test_page(
    [
      "<< /Subtype /FreeText /Rect [10 10 50 30] /AP << /N 7 0 R >> >>", "<< /Subtype /FreeText /Rect [60 10 100 30] /AP << /N 8 0 R >> >>",
    ],
    extra=[
      annotation_test_stream(
        "/BBox [0 0 40 20] /Resources << /Font << /F1 10 0 R >> >>", text,
      ),
      annotation_test_stream(
        "/BBox [0 0 40 20] /Resources << /Font << /F1 11 0 R >> >>", text,
      ),
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman >>",
    ],
    contents=text,
    resources="<< /Font << /F1 9 0 R >> >>",
  )
  assert_eq(page.fonts[0].standard_font, Some("Helvetica"))
  guard page.annotations[0].appearance is Some(first) else {
    fail("first AP missing")
  }
  guard page.annotations[1].appearance is Some(second) else {
    fail("second AP missing")
  }
  assert_true(
    first.svg.contains("data-pdf-font-outline=\"standard14:Courier\""),
  )
  assert_true(
    second.svg.contains("data-pdf-font-outline=\"standard14:Times-Roman\""),
  )
}

///|
test "annotation strings decode PDFDocEncoding and UTF16BE" {
  let page = annotation_test_page([
    "<< /Subtype /Text /Rect [10 10 30 30] /T (Author) /Contents <FEFF4F60597D> /Subj <80> >>",
    "<< /Subtype /Widget /Rect [10 40 80 60] /FT /Tx /T <FEFF540D5B57> /V <FEFF4F60597D> >>",
  ])
  assert_eq(page.annotations[0].contents, Some("你好"))
  assert_eq(page.annotations[0].subject, Some("•"))
  assert_eq(page.annotations[0].field_name, None)
  assert_eq(page.annotations[1].field_name, Some("名字"))
  assert_eq(page.annotations[1].field_value, Some("你好"))
}

///|
test "nested appearance Forms retain their own fonts and outer transparency group" {
  let page = annotation_test_page(
    ["<< /Subtype /FreeText /Rect [10 10 100 50] /AP << /N 6 0 R >> >>"],
    extra=[
      annotation_test_stream(
        "/BBox [0 0 90 40] /Group << /S /Transparency /I true /K true >> /Resources << /Font << /F1 8 0 R >> /XObject << /Form 7 0 R >> >>",
        "BT /F1 12 Tf 2 4 Td (A) Tj ET /Form Do",
      ),
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 90 40] /Resources << /Font << /F1 9 0 R >> >>",
        "BT /F1 12 Tf 20 4 Td (B) Tj ET",
      ),
      "<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman >>",
    ],
  )
  guard page.annotations[0].appearance is Some(appearance) else {
    fail("missing AP")
  }
  assert_true(
    appearance.svg.contains("data-pdf-font-outline=\"standard14:Courier\""),
  )
  assert_true(
    appearance.svg.contains("data-pdf-font-outline=\"standard14:Times-Roman\""),
  )
  assert_true(appearance.svg.contains(">A</title>"))
  assert_true(appearance.svg.contains(">B</title>"))
  assert_true(appearance.svg.contains("data-pdf-group-isolated=\"true\""))
  assert_true(appearance.svg.contains("data-pdf-group-knockout=\"true\""))
  assert_true(appearance.svg.contains("isolation:isolate"))
}

///|
test "degenerate appearance boxes use translation without a geometry fallback" {
  let page = annotation_test_page(
    ["<< /Subtype /Square /Rect [40 50 100 130] /AP << /N 6 0 R >> >>"],
    extra=[
      annotation_test_stream(
        "/BBox [0 0 0 10] /Matrix [1 0 0 1 3 4]", "0 0 20 20 re f",
      ),
    ],
  )
  let svg = pdf_render_page_svg(page, 2.0, 0)
  assert_true(svg.contains("transform=\"matrix(2 0 0 2 86 272)\""))
  assert_true(!svg.contains("<rect data-pdf-annotation"))
}

///|
test "radio fallbacks compare widget identity with the inherited group value" {
  let page = annotation_test_page(
    [
      "<< /Subtype /Widget /Rect [10 10 30 30] /Parent 9 0 R /AS /Off /AP << /N << /Off null /A null >> >> >>",
      "<< /Subtype /Widget /Rect [40 10 60 30] /Parent 9 0 R /AS /Off /AP << /N << /Off null /B null >> >> >>",
      "<< /Subtype /Widget /Rect [70 10 90 30] /Parent 9 0 R /AS /Off >>", "<< /Subtype /Widget /Rect [100 10 120 30] /Parent 9 0 R >>",
    ],
    extra=[
      "<< /FT /Btn /Ff 32768 /T (Choice) /V /B /Kids [5 0 R 6 0 R 7 0 R 8 0 R] >>",
    ],
  )
  assert_eq(page.annotations.map(a => a.field_value), [
    Some("B"),
    Some("B"),
    Some("B"),
    Some("B"),
  ])
  assert_eq(page.annotations.map(a => a.button_checked), [
    Some(false),
    Some(true),
    Some(false),
    Some(false),
  ])
  assert_eq(page.annotations[1].button_value, Some("B"))
  let svg = pdf_render_page_svg(page, 1.0, 0)
  assert_eq(svg.split("data-pdf-button-checked=\"true\"").length() - 1, 1)
  assert_eq(svg.split("<circle ").length() - 1, 5)
  assert_true(!svg.contains("<rect data-pdf-annotation"))
}

///|
test "checkbox fallback respects local AS and case-sensitive on-state names" {
  let page = annotation_test_page([
    "<< /Subtype /Widget /Rect [10 10 30 30] /FT /Btn /V /Yes /AS /Off >>", "<< /Subtype /Widget /Rect [40 10 60 30] /FT /Btn /V /Off /AS /Yes >>",
    "<< /Subtype /Widget /Rect [70 10 90 30] /FT /Btn /V /off >>", "<< /Subtype /Widget /Rect [100 10 120 30] /FT /Btn /V /Off >>",
  ])
  assert_eq(page.annotations.map(a => a.button_checked), [
    Some(false),
    Some(true),
    Some(true),
    Some(false),
  ])
  let svg = pdf_render_page_svg(page, 1.0, 0)
  assert_eq(svg.split("data-pdf-button-checked=\"true\"").length() - 1, 2)
}

///|
test "embedded appearance font programs get independent CSS families" {
  // Small font-program stubs verify resource transfer and family scoping;
  // glyph-program correctness is tested separately by outline tests.
  let page = annotation_test_page(
    [
      "<< /Subtype /FreeText /Rect [10 10 50 30] /AP << /N 7 0 R >> >>", "<< /Subtype /FreeText /Rect [60 10 100 30] /AP << /N 8 0 R >> >>",
    ],
    extra=[
      annotation_test_stream(
        "/BBox [0 0 40 20] /Resources << /Font << /F1 9 0 R >> >>", "BT /F1 12 Tf 2 4 Td (A) Tj ET",
      ),
      annotation_test_stream(
        "/BBox [0 0 40 20] /Resources << /Font << /F1 10 0 R >> >>", "BT /F1 12 Tf 2 4 Td (A) Tj ET",
      ),
      "<< /Type /Font /Subtype /TrueType /BaseFont /CustomA /FirstChar 65 /LastChar 65 /Widths [600] /FontDescriptor 11 0 R >>",
      "<< /Type /Font /Subtype /TrueType /BaseFont /CustomB /FirstChar 65 /LastChar 65 /Widths [600] /FontDescriptor 12 0 R >>",
      "<< /Type /FontDescriptor /FontName /CustomA /FontBBox [0 0 600 800] /Ascent 800 /Descent 0 /FontFile2 13 0 R >>",
      "<< /Type /FontDescriptor /FontName /CustomB /FontBBox [0 0 600 800] /Ascent 800 /Descent 0 /FontFile2 14 0 R >>",
      annotation_test_stream("", "OTTO-appearance-a"),
      annotation_test_stream("", "OTTO-appearance-b"),
    ],
  )
  guard page.annotations[0].appearance is Some(first) else {
    fail("first AP missing")
  }
  guard page.annotations[1].appearance is Some(second) else {
    fail("second AP missing")
  }
  assert_true(first.svg.contains("@font-face{font-family:'pdf-font-p1-a0-f0'"))
  assert_true(second.svg.contains("@font-face{font-family:'pdf-font-p1-a1-f0'"))
  assert_true(first.svg.contains("font-family=\"pdf-font-p1-a0-f0\""))
  assert_true(second.svg.contains("font-family=\"pdf-font-p1-a1-f0\""))
  assert_true(
    first.svg.contains(
      "data:font/otf;base64," +
      @base64.encode(@utf8.encode("OTTO-appearance-a")),
    ),
  )
  assert_true(
    second.svg.contains(
      "data:font/otf;base64," +
      @base64.encode(@utf8.encode("OTTO-appearance-b")),
    ),
  )
  assert_true(
    !first.svg.contains(@base64.encode(@utf8.encode("OTTO-appearance-b"))),
  )
}

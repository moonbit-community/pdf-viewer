///|
test "prepared annotations retain scoped appearance fonts without page font copies" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /Body 5 0 R >> >> /Annots [6 0 R 7 0 R] >>",
    annotation_test_stream("", "BT /Body 12 Tf 20 180 Td (BODY) Tj ET"),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    "<< /Type /Annot /Subtype /Widget /FT /Tx /Rect [20 40 120 60] /AP << /N 9 0 R >> >>",
    "<< /Type /Annot /Subtype /Widget /FT /Tx /F 24 /Rect [20 80 120 100] /AP << /N 9 0 R >> >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>",
    annotation_test_stream(
      "/Type /XObject /Subtype /Form /BBox [0 0 100 20] /Resources << /Font << /Own 8 0 R >> >>",
      "BT /Own 10 Tf 4 4 Td (OWN) Tj ET",
    ),
  ])
  let public_page = document.page(1).unwrap()
  let (page, program) = prepare_canvas_page(document, 1).unwrap()
  let complete = public_page.canvas_plan()
  let prepared = program.canvas_plan(page, 1.0, 0)
  let defs = StringBuilder()
  pdf_svg_fonts(defs, public_page)
  let body_fonts = defs.to_string()
  assert_true(body_fonts.length() > 0)
  guard complete
    is {
      "annotation_svg": String(old_svg),
      "annotation_fragments": Array(old_fragments),
      ..
    } else {
    fail("Expected complete annotation projections")
  }
  guard prepared
    is {
      "annotation_svg": String(new_svg),
      "annotation_fragments": Array(new_fragments),
      ..
    } else {
    fail("Expected prepared annotation projections")
  }
  assert_true(old_svg.contains(body_fonts))
  assert_true(!new_svg.contains(body_fonts))
  assert_eq(new_svg, old_svg.replace(old=body_fonts, new=""))
  assert_eq(new_fragments.length(), 2)
  for index, fragment in new_fragments {
    guard old_fragments[index] is { "svg": String(old), .. } else {
      fail("Expected original annotation SVG")
    }
    guard fragment is { "svg": String(next), .. } else {
      fail("Expected prepared annotation SVG")
    }
    assert_eq(next, old.replace(old=body_fonts, new=""))
    let appearance = page.annotations[index].appearance.unwrap()
    assert_true(next.contains(appearance.svg))
    assert_true(appearance.svg.contains("@font-face"))
    assert_true(next.contains("pdf-font-p1-a\{index}-f0"))
    guard fragment is { "no_zoom": zoom, "no_rotate": rotate, .. } else {
      fail("Expected annotation viewport flags")
    }
    assert_true(
      old_fragments[index] is { "no_zoom": value, .. } && value == zoom,
    )
    assert_true(
      old_fragments[index] is { "no_rotate": value, .. } && value == rotate,
    )
  }
  assert_eq(page.annotations, public_page.annotations)
}

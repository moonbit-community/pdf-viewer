///|
fn text_stroke_test_item(
  page : PdfPageModel,
  index? : Int = 0,
) -> PdfTextItem raise {
  let text = page.items.filter_map(item => {
    match item {
      Text(value) => Some(value)
      _ => None
    }
  })
  guard text.get(index) is Some(item) else { fail("missing text") }
  item
}

///|
test "text strokes remove only CTM from A1 embedded glyph geometry" {
  let viewer = type1_test_clip_document(
    "q 3 .5 1 2 20 30 cm 4 w [6 3] 2 d 1 J 2 j 8 M BT /F1 10 Tf 2 .3 .6 1 4 5 Tm 2 Tr (A) Tj ET Q",
  )
  guard viewer.page(1) is Some(page) else { fail("missing page") }
  let item = text_stroke_test_item(page)
  guard item.stroke is Some(stroke) else { fail("missing text stroke") }
  assert_eq(stroke.transform, [3.0, -0.5, -1.0, 2.0, 20.0, 170.0])
  assert_eq(stroke.line_width, 4.0)
  assert_eq(stroke.dash_array, [6.0, 3.0])
  assert_eq(stroke.dash_phase, 2.0)
  assert_eq(stroke.line_cap, 1)
  assert_eq(stroke.line_join, 2)
  assert_eq(stroke.miter_limit, 8.0)
  assert_eq(stroke.fallback_scale, None)
  assert_eq(stroke.unresolved, None)
  guard stroke.svg_path is Some(path) else { fail("missing outline") }
  let coordinates = path.split(" ").collect()
  assert_true(
    (@string.parse_double(coordinates[1].view()) - 4.0).abs() < 0.000001,
  )
  assert_true(
    (@string.parse_double(coordinates[2].view()) + 5.0).abs() < 0.000001,
  )
  assert_true(
    (@string.parse_double(coordinates[4].view()) - 14.0).abs() < 0.000001,
  )
  assert_true(
    (@string.parse_double(coordinates[5].view()) + 6.5).abs() < 0.000001,
  )
  for scale in [0.5, 1.0, 2.0] {
    let svg = pdf_render_page_svg(page, scale, 0)
    assert_true(svg.contains("stroke-width=\"4\""))
    assert_true(svg.contains("stroke-dasharray=\"6 3\""))
    assert_true(svg.contains("stroke-dashoffset=\"2\""))
    assert_true(svg.contains("stroke-linecap=\"round\""))
    assert_true(svg.contains("stroke-linejoin=\"bevel\""))
    assert_true(svg.contains("stroke-miterlimit=\"8\""))
    assert_true(svg.contains("matrix(3 -0.5 -1 2 20 170)"))
  }
}

///|
test "text stroke state restores with q and Q independently of text placement" {
  let viewer = type1_test_clip_document(
    "2 w [4 2] 1 d q -2 .5 .25 1 150 20 cm 5 w [7 3] 2 d BT /F1 20 Tf 1 Tr 1 0 0 1 5 10 Tm (A) Tj ET Q BT /F1 40 Tf 1 Tr 1 0 0 1 10 20 Tm (A) Tj ET",
  )
  guard viewer.page(1) is Some(page) else { fail("missing page") }
  guard text_stroke_test_item(page).stroke is Some(a) else {
    fail("missing stroke")
  }
  guard text_stroke_test_item(page, index=1).stroke is Some(b) else {
    fail("missing stroke")
  }
  assert_eq(a.line_width, 5.0)
  assert_eq(a.dash_array, [7.0, 3.0])
  assert_eq(a.transform, [-2.0, -0.5, -0.25, 1.0, 150.0, 180.0])
  assert_eq(b.line_width, 2.0)
  assert_eq(b.dash_array, [4.0, 2.0])
  assert_eq(b.dash_phase, 1.0)
  assert_eq(b.transform, [1.0, 0.0, 0.0, 1.0, 0.0, 200.0])
}

///|
test "text rendering modes retain pens only when Tr strokes" {
  for mode in 0..<8 {
    let viewer = type1_test_clip_document(
      "BT /F1 20 Tf \{mode} Tr 10 20 Td (A) Tj ET",
    )
    guard viewer.page(1) is Some(page) else { fail("missing page") }
    let item = text_stroke_test_item(page)
    assert_eq(
      item.stroke is Some(_),
      mode == 1 || mode == 2 || mode == 5 || mode == 6,
    )
  }
}

///|
test "fallback text uses the graphics pen under a full CTM" {
  let document = provenance_test_document(
    "q 3 .5 1 2 20 30 cm /G gs 2 w [6 3] 2 d 1 J 2 j 8 M BT /F1 10 Tf 0 1 -1 0 10 20 Tm 2 Tr (A) Tj ET Q",
    resources="<< /Font << /F1 5 0 R >> /ExtGState << /G << /ca .8 /CA .35 >> >> >>",
  )
  let page = document
    .with_font_fallbacks([
      { pdf_name: "/F1", family: "Test Host Sans", weight: None, style: None, },
    ])
    .page(1)
    .unwrap()
  let item = text_stroke_test_item(page)
  guard item.stroke is Some(stroke) else { fail("missing stroke") }
  assert_eq(stroke.svg_path, None)
  assert_eq(stroke.fallback_scale, Some(10.0))
  assert_eq(stroke.stroke_alpha, 0.35)
  assert_eq(item.fill_alpha, 0.8)
  assert_eq(stroke.unresolved, None)
  let svg = pdf_render_page_svg(page, 1.0, 0)
  assert_true(svg.contains("stroke-width=\"0.2\""))
  assert_true(svg.contains("stroke-opacity=\"0.35\""))
  assert_true(svg.contains("stroke-dashoffset=\"0.2\""))
  assert_true(svg.contains("stroke-linecap=\"round\""))
  assert_true(svg.contains("stroke-linejoin=\"bevel\""))
  assert_true(!svg.contains("data-pdf-text-stroke-unresolved"))
}

///|
test "fallback anisotropic text matrix exposes the missing outline boundary" {
  let document = provenance_test_document(
    "3 w BT /F1 20 Tf 2 .3 .6 1 10 20 Tm 2 Tr (A) Tj ET",
  )
  let page = document
    .with_font_fallbacks([
      {
        pdf_name: "/Helvetica",
        family: "Test Host Sans",
        weight: None,
        style: None,
      },
    ])
    .page(1)
    .unwrap()
  guard text_stroke_test_item(page).stroke is Some(stroke) else {
    fail("missing stroke")
  }
  assert_eq(stroke.svg_path, None)
  assert_eq(stroke.fallback_scale, None)
  assert_eq(stroke.unresolved, Some("affine-text-pen-requires-glyph-outline"))
  assert_true(
    page
    .graphics_diagnostics()
    .any(diagnostic => {
      diagnostic.code == "PDF_TEXT_STROKE_GEOMETRY" &&
      diagnostic.message.contains("affine text stroke is approximate")
    }),
  )
  assert_true(
    pdf_render_page_svg(page, 1.0, 0).contains(
      "data-pdf-text-stroke-unresolved=\"affine-text-pen-requires-glyph-outline\"",
    ),
  )
}

///|
test "text stroke similarity accepts rotation reflection and rejects shear" {
  assert_eq(
    pdf_text_stroke_similarity_scale(
      Some({ a: 0.0, b: 20.0, c: 20.0, d: 0.0, e: 7.0, f: 8.0, }),
    ),
    Some(20.0),
  )
  assert_eq(
    pdf_text_stroke_similarity_scale(
      Some({ a: 10.0, b: 0.0, c: 1.0, d: 10.0, e: 0.0, f: 0.0, }),
    ),
    None,
  )
  assert_eq(
    pdf_text_stroke_similarity_scale(
      Some({ a: 0.0, b: 0.0, c: 0.0, d: 0.0, e: 0.0, f: 0.0, }),
    ),
    None,
  )
}

///|
test "Type 3 charproc paint is not reinterpreted as a text pen" {
  let page = annotation_test_page(
    [],
    contents="3 w BT /F1 20 Tf 1 Tr 10 20 Td (A) Tj ET",
    resources="<< /Font << /F1 5 0 R >> >>",
    extra=[
      "<< /Type /Font /Subtype /Type3 /FontBBox [0 0 500 700] /FontMatrix [.001 0 0 .001 0 0] /FirstChar 65 /LastChar 65 /Widths [500] /Encoding << /Type /Encoding /Differences [65 /A] >> /CharProcs << /A 6 0 R >> /Resources << >> >>",
      annotation_test_stream("", "500 0 d0 0 0 400 700 re f"),
    ],
  )
  let item = text_stroke_test_item(page)
  assert_eq(item.stroke, None)
  assert_true(item.type3_outline is Some(_))
}

///|
test "singular text CTM retains local glyph and pen without inverse failure" {
  let viewer = type1_test_clip_document(
    "0 0 .2 1 30 0 cm 3 w BT /F1 20 Tf 1 Tr 10 20 Td (A) Tj ET",
  )
  guard viewer.page(1) is Some(page) else { fail("missing page") }
  guard text_stroke_test_item(page).stroke is Some(stroke) else {
    fail("missing stroke")
  }
  assert_true(stroke.svg_path is Some(_))
  assert_eq(stroke.transform, [0.0, 0.0, -0.2, 1.0, 30.0, 200.0])
  assert_eq(stroke.unresolved, None)
  assert_true(
    pdf_render_page_svg(page, 1.0, 0).contains("matrix(0 0 -0.2 1 30 200)"),
  )
}

///|
test "all Standard14 independent text pens use the selected A1 program" {
  for face in standard14_test_faces() {
    let document = provenance_test_document(
      "q -3 .5 1 2 150 30 cm 4 w [6 3] 2 d BT /F1 10 Tf 2 .3 .6 1 4 5 Tm 2 Tr (A) Tj ET Q",
      font="<< /Subtype /Type1 /BaseFont /" + face.name() + " >>",
    )
    let page = document.page(1).unwrap()
    let stroke = text_stroke_test_item(page).stroke.unwrap()
    let entry = pdf_collected_entries_of_page(
        document.document,
        document.pages[0],
      )[0]
    let pen_matrix = pdf_glyph_transform(
      { ..entry.state, ctm: @geometry.transform_identity_matrix, },
      entry.text_glyph.unwrap(),
    )
    assert_eq(
      stroke.svg_path,
      pdf_standard14_path_of_pdf_glyph(
        entry.state.text_state.current_font,
        65,
        Some(pen_matrix),
        0.0,
        0.0,
        0.0,
      ),
    )
    assert_true(stroke.svg_path is Some(path) && !path.is_empty())
    assert_eq(stroke.transform, [-3.0, -0.5, -1.0, 2.0, 150.0, 170.0])
    assert_eq(stroke.line_width, 4.0)
    assert_eq(stroke.dash_array, [6.0, 3.0])
    assert_eq(stroke.dash_phase, 2.0)
    assert_eq(stroke.fallback_scale, None)
    assert_eq(stroke.unresolved, None)
    assert_true(
      !page
      .graphics_diagnostics()
      .any(d => d.code == "PDF_TEXT_STROKE_GEOMETRY"),
    )
  }
}

///|
test "independent TrueType pens retain active missing-Tf and ExtGState bindings" {
  let document = truetype_test_document(truetype_test_fixture())
  document.document.add_object_given_number(
    9,
    font_scope_test_child_font(document),
  )
  document.pages[0] = {
    ..document.pages[0],
    resources: document.pages[0].resources.add_dict_entry(
      pdf_name_key("/ExtGState"),
      @syntax.PdfDictionary([
        (
          pdf_name_key("/GS"),
          @syntax.PdfDictionary([
            (
              pdf_name_key("/Font"),
              @syntax.PdfArray([@syntax.PdfIndirect(9), @syntax.PdfInteger(10)]),
            ),
          ]),
        ),
      ]),
    ),
  }
  font_scope_test_content(
    document, "BT /F1 10 Tf 1 Tr 1 0 0 1 20 100 Tm /Missing 10 Tf (A) Tj q /GS gs 1 0 0 1 30 100 Tm (A) Tj Q 1 0 0 1 40 100 Tm (A) Tj ET",
  )
  let page = document.page(1).unwrap()
  for index, expected in ["L 21 -100", "L 32 -100", "L 41 -100"] {
    let stroke = text_stroke_test_item(page, index~).stroke.unwrap()
    assert_true(stroke.svg_path.unwrap().contains(expected))
    assert_eq(stroke.unresolved, None)
  }
}

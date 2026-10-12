///|
test "annotation interaction data resolves links and preserves raw popup indices" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /Dests << /chapter [4 0 R /XYZ 25 160 1.5] /loop /loop >> >>",
    "<< /Type /Pages /Count 2 /Kids [3 0 R 4 0 R] >>", "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> /Annots [5 0 R 6 0 R 7 0 R 8 0 R 9 0 R 10 0 R 11 0 R 12 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> >>", "<< /Subtype /Link /Rect [10 20 30 40] /Dest /chapter >>",
    "<< /Subtype /Popup /Parent 7 0 R /Rect [100 100 180 180] /Open true >>", "<< /Subtype /Text /Rect [50 60 70 80] /Popup 6 0 R /T (Author) /Contents (<b>plain text</b>) /Subj (Review) >>",
    "<< /Subtype /Link /Rect [10 90 30 110] /A << /S /GoToR /D [0 /Fit] >> >>", "<< /Subtype /Square /Rect (bad) >>",
    "<< /Subtype /Link /Rect [10 120 30 140] /A << /S /GoTo /D [4 0 R /FitH 150] >> >>",
    "<< /Subtype /Link /Rect [40 120 60 140] /A << /S /JavaScript /JS (alert(1)) >> >>",
    "<< /Subtype /Link /Rect [70 120 90 140] /Dest /loop >>",
  ])
  guard document.annotation_layer_json(1) is Some(Json::Array(items)) else {
    fail("missing interactions")
  }
  assert_eq(items.length(), 6)
  assert_true(
    items[0]
    is {
      "index": 0,
      "link": {
        "destination": {
          "page": 2,
          "kind": "XYZ",
          "zoom": 1.5,
          "name": "chapter",
          ..
        },
        ..
      },
      ..
    },
  )
  assert_true(
    items[1]
    is {
      "index": 2,
      "title": "Author",
      "contents": "<b>plain text</b>",
      "subject": "Review",
      "popup_open": true,
      ..
    },
  )
  assert_true(
    items[2]
    is {
      "index": 3,
      "link": { "destination": { "remote": true, "resolved": false, .. }, .. },
      ..
    },
  )
  assert_true(
    items[3]
    is {
      "index": 5,
      "link": {
        "destination": { "page": 2, "kind": "FitH", "top": 150, .. },
        ..
      },
      ..
    },
  )
  assert_true(items[4] is { "link": { "kind": "unsupported", .. }, .. })
  assert_true(
    items[5]
    is {
      "link": { "destination": { "name": "loop", "resolved": false, .. }, .. },
      ..
    },
  )
  assert_eq(document.annotation_layer_json(0), None)
  assert_eq(document.annotation_layer_json(3), None)
}

///|
test "annotation metadata does not decode appearances and retains link quads" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> /Annots [4 0 R] >>",
    "<< /Subtype /Link /Rect [10 10 90 40] /QuadPoints [10 40 90 40 10 30 90 30 10 20 50 20 10 10 50 10] /AP << /N 5 0 R >> /A << /S /URI /URI (https://example.com/) >> >>",
    annotation_test_stream("/BBox [0 0 80 30] /Filter /FlateDecode", "broken"),
  ])
  guard document.annotation_layer_json(1) is Some(Json::Array([item])) else {
    fail("missing annotation")
  }
  assert_true(
    item
    is {
      "link": { "kind": "uri", "uri": "https://example.com/", .. },
      "quad_points": Array([_, _]),
      ..
    },
  )
}

///|
test "print intent selects NoView printable appearances without mutating screen model" {
  let page = annotation_test_page(
    [
      for flag in [0, 4, 6, 5, 36] => {
        "<< /Subtype /Square /Rect [10 10 30 30] /F \{flag} >>"
      }
    ],
  )
  let printed = page.with_print_annotations().render_svg()
  assert_true(!printed.contains("data-pdf-annotation-index=\"0\""))
  assert_true(printed.contains("data-pdf-annotation-index=\"1\""))
  assert_true(!printed.contains("data-pdf-annotation-index=\"2\""))
  assert_true(!printed.contains("data-pdf-annotation-index=\"3\""))
  assert_true(printed.contains("data-pdf-annotation-index=\"4\""))
  assert_eq(page.annotations.map(annotation => annotation.visible), [
    true, true, false, false, false,
  ])
}

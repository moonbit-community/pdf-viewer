///|
test "standard fonts apply Tw to each source single-byte space" {
  let page = annotation_test_page(
    [],
    contents="BT /F1 10 Tf 7 Tw 1 Tc 50 Tz 20 50 Td ( A ) Tj ET",
    resources="<< /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >>",
  )
  let text = page.text_content().items
  let expected = [5.39, 3.835, 5.39]
  assert_eq(text.length(), 3)
  for index, item in text {
    assert_true((item.advance_x - expected[index]).abs() < 0.000001)
  }
}

///|
test "simple fonts use source codes for Tw even when ToUnicode changes spaces" {
  let widths = [ for _ in 0..<34 => "500" ].join(" ")
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream(
      "", "BT /F1 10 Tf 7 Tw 1 Tc 50 Tz 20 50 Td ( A ) Tj ET",
    ),
    "<< /Type /Font /Subtype /TrueType /BaseFont /SpacingProbe /Encoding /WinAnsiEncoding /FirstChar 32 /LastChar 65 /Widths [\{widths}] /FontDescriptor << /FontBBox [0 -200 1000 800] /Ascent 800 /Descent -200 >> /ToUnicode 6 0 R >>",
    annotation_test_stream(
      "", "2 beginbfchar <20> <0058> <41> <0020> endbfchar",
    ),
  ])
  let text = document.page(1).unwrap().text_content().items
  assert_eq([ for item in text => item.text ], ["X", " ", "X"])
  assert_eq([ for item in text => item.advance_x ], [6.5, 3.0, 6.5])
}

///|
test "Type 3 spaces apply Tw after FontMatrix width conversion" {
  let widths = [ for _ in 0..<34 => "500" ].join(" ")
  let page = annotation_test_page(
    [],
    contents="BT /F1 10 Tf 7 Tw 1 Tc 50 Tz 20 50 Td ( A ) Tj ET",
    resources="<< /Font << /F1 << /Type /Font /Subtype /Type3 /FontBBox [0 0 500 700] /FontMatrix [0.001 0 0 0.001 0 0] /FirstChar 32 /LastChar 65 /Widths [\{widths}] /Encoding << /Type /Encoding /Differences [32 /space 65 /A] >> /CharProcs << /space 5 0 R /A 6 0 R >> /Resources << >> >> >> >>",
    extra=[
      annotation_test_stream("", "500 0 d0"),
      annotation_test_stream("", "500 0 d0 0 0 500 700 re f"),
    ],
  )
  let text = page.text_content().items
  assert_eq([ for item in text => item.advance_x ], [6.5, 3.0, 6.5])
  assert_eq(text[1].glyph_transform, Some([5.0, 0.0, 0.0, 10.0, 26.5, 50.0]))
}

///|
test "predefined UTF8 UTF16 and UTF32 spaces retain source length for Tw" {
  for
    (encoding, contents, advance) in [
      ("UniCNS-UTF8-H", "<2020>", 6.5),
      ("UniCNS-UTF16-H", "<00200020>", 3.0),
      ("UniCNS-UTF32-H", "<0000002000000020>", 3.0),
    ] {
    let page = builtin_cmap_test_document(
        "BT /F1 10 Tf 7 Tw 1 Tc 50 Tz 20 50 Td \{contents} Tj ET",
        encoding,
      )
      .page(1)
      .unwrap()
    let text = page.text_content().items
    assert_eq(text.length(), 2, msg=encoding)
    assert_eq([ for item in text => item.text ], [" ", " "], msg=encoding)
    assert_eq(
      [
        for item in text => item.advance_x
      ],
      [advance, advance],
      msg=encoding,
    )
    assert_eq(
      text[1].glyph_transform,
      Some([5.0, 0.0, 0.0, 10.0, 20.0 + advance, 50.0]),
      msg=encoding,
    )
  }
}

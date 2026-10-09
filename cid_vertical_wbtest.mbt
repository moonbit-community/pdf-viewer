///|
fn cid_vertical_test_document(contents : String) -> PdfViewerDocument raise {
  cid_layout_test_document(
    contents,
    cmap="/CMapType 1 def /WMode 1 def\n" +
      "1 begincodespacerange <0000> <FFFF> endcodespacerange\n" +
      "3 begincidchar <0041> 1 <0042> 2 <0043> 3 endcidchar\n",
    widths2="[1 [-800 300 700] 2 2 -1100 250 900]",
    default_width2="[900 -1200]",
  )
}

///|
test "vertical CID metrics index CIDs and preserve W2 and DW2 signs" {
  let page = cid_vertical_test_document(
      "BT /F1 10 Tf 2 Tc 7 Tw 50 Tz 20 100 Td <004100420043> Tj ET",
    )
    .page(1)
    .unwrap()
  let text = page.text_content().items
  assert_eq([ for item in text => item.advance_y ], [-6.0, -9.0, -10.0])
  assert_eq([ for item in text => item.advance_x ], [0.0, 0.0, 0.0])
  assert_eq([ for item in text => item.text ], ["A", "B", "C"])
  assert_eq(text[0].glyph_transform, Some([5.0, 0.0, 0.0, 10.0, 18.5, 93.0]))
  assert_eq(text[1].glyph_transform, Some([5.0, 0.0, 0.0, 10.0, 18.75, 85.0]))
  assert_eq(text[2].glyph_transform, Some([5.0, 0.0, 0.0, 10.0, 18.25, 76.0]))
  assert_eq(text[2].bounds.max_x - text[2].bounds.min_x, 3.5)
}

///|
test "vertical TJ adjustments update the next text operator and selection" {
  let document = cid_vertical_test_document(
    "BT /F1 10 Tf 20 100 Td <0041> Tj [100 <0042> -200] TJ <0043> Tj ET",
  )
  let page = document.page(1).unwrap()
  let text = page.text_content().items
  assert_eq(text[0].glyph_transform, Some([10.0, 0.0, 0.0, 10.0, 17.0, 93.0]))
  assert_eq(text[1].glyph_transform, Some([10.0, 0.0, 0.0, 10.0, 17.5, 82.0]))
  assert_eq(text[2].glyph_transform, Some([10.0, 0.0, 0.0, 10.0, 16.5, 73.0]))
  let collected = pdf_collected_entries_of_page(
    document.document,
    document.pages[0],
  )
  assert_eq(collected.last().unwrap().state.text_state.text_matrix.f, 70.0)
  let selection = pdf_select_page(page, {
    min_x: 16.5,
    min_y: 73.0,
    max_x: 23.5,
    max_y: 81.0,
  })
  assert_true(selection.text.contains("C"))
}

///|
test "vertical default displacement remains independent of horizontal width" {
  let page = annotation_test_page(
    [],
    contents="BT /F1 10 Tf 20 100 Td <00410042> Tj <0043> Tj ET",
    resources="<< /Font << /F1 << /Type /Font /Subtype /Type0 /BaseFont /Vertical /Encoding /Identity-V /DescendantFonts [<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Vertical /DW 700 /W [65 [400 600]] /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor << /FontBBox [0 -200 1000 800] /Ascent 800 /Descent -200 >> >>] >> >> >>",
  )
  let text = page.text_content().items
  assert_eq([ for item in text => item.advance_y ], [-10.0, -10.0, -10.0])
  assert_eq(text[0].glyph_transform, Some([10.0, 0.0, 0.0, 10.0, 18.0, 91.2]))
  assert_eq(text[1].glyph_transform, Some([10.0, 0.0, 0.0, 10.0, 17.0, 81.2]))
  assert_eq(text[2].glyph_transform, Some([10.0, 0.0, 0.0, 10.0, 16.5, 71.2]))
}

///|
test "vertical CMap word spacing uses a source one-byte space only" {
  let page = cid_layout_test_document(
      "BT /F1 10 Tf 7 Tw 1 Tc 50 Tz 20 100 Td <20> Tj <0020> Tj <41> Tj ET",
      cmap="/WMode 1 def 2 begincodespacerange <20> <7F> <0000> <00FF> endcodespacerange " +
        "2 begincidchar <20> 0 <41> 1 endcidchar",
      tounicode="2 beginbfchar <20> <0020> <41> <0041> endbfchar",
    )
    .page(1)
    .unwrap()
  let text = page.text_content().items
  assert_eq([ for item in text => item.advance_y ], [-2.0, -9.0, -9.0])
  assert_eq(text[1].glyph_transform, Some([5.0, 0.0, 0.0, 10.0, 19.0, 89.2]))
  assert_eq(text[2].glyph_transform, Some([5.0, 0.0, 0.0, 10.0, 18.75, 80.2]))
}

///|
test "vertical mixed-length high-bit codes draw and clip the mapped CID" {
  let document = cid_layout_test_document(
    "BT /F1 10 Tf 7 Tr 20 100 Td <41F0010203> Tj ET 0 0 200 200 re f",
    cmap="/WMode 1 def 2 begincodespacerange <41> <41> <F0000000> <F0FFFFFF> endcodespacerange " +
      "2 begincidchar <41> 1 <F0010203> 2 endcidchar",
    tounicode=cmap_text_test_tounicode(),
    widths2="[1 [-800 300 700] 2 [-1100 250 900]]",
  )
  let page = document.page(1).unwrap()
  let text = page.text_content().items
  assert_eq([ for item in text => item.text ], ["A", "\u65E5"])
  assert_eq(text[1].charcode.reinterpret_as_uint(), 0xF0010203U)
  assert_eq(text[1].glyph_transform, Some([10.0, 0.0, 0.0, 10.0, 17.5, 83.0]))
  let paths = text_clip_test_paths(page)
  assert_eq(paths.length(), 1)
  assert_eq(
    paths[0].clip_path,
    Some(
      "M 17 107 L 22 107 L 22 100 L 17 100 M 17.5 117 L 22.5 117 L 22.5 110 L 17.5 110",
    ),
  )
}

///|
test "Identity-H two-byte 0020 receives character spacing without Tw" {
  let page = annotation_test_page(
    [],
    contents="BT /F1 10 Tf 7 Tw 1 Tc 50 Tz 20 50 Td <00200020> Tj ET",
    resources="<< /Font << /F1 << /Type /Font /Subtype /Type0 /BaseFont /Horizontal /Encoding /Identity-H /DescendantFonts [<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Horizontal /DW 500 /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor << /FontBBox [0 -200 1000 800] /Ascent 800 /Descent -200 >> >>] >> >> >>",
  )
  let text = page.text_content().items
  assert_eq([ for item in text => item.advance_x ], [3.0, 3.0])
  assert_eq(text[1].glyph_transform, Some([5.0, 0.0, 0.0, 10.0, 23.0, 50.0]))
}

///|
test "vertical quotes and q Q preserve the real text matrix and line matrix" {
  let page = cid_vertical_test_document(
      "BT /F1 10 Tf 12 TL 20 100 Td <0041> Tj q <0042> Tj Q <0043> Tj <0041> ' 7 1 <0042> \" ET",
    )
    .page(1)
    .unwrap()
  let text = page.text_content().items
  assert_eq(text.length(), 5)
  assert_eq(text[2].glyph_transform, Some([10.0, 0.0, 0.0, 10.0, 16.5, 83.0]))
  assert_eq(text[3].glyph_transform, Some([10.0, 0.0, 0.0, 10.0, 17.0, 81.0]))
  assert_eq(text[4].glyph_transform, Some([10.0, 0.0, 0.0, 10.0, 17.5, 67.0]))
  assert_eq(text[4].advance_y, -10.0)
}

///|
test "vertical matrices preserve shear rotation rise and negative font sizes" {
  let page = cid_vertical_test_document(
      "2 0 0 3 5 7 cm BT /F1 -10 Tf 50 Tz 2 Ts 1 0.5 0.25 1 20 30 Tm <00410042> Tj ET",
    )
    .page(1)
    .unwrap()
  let text = page.text_content().items
  assert_eq([ for item in text => item.advance_y ], [8.0, 11.0])
  assert_eq(
    text[0].glyph_transform,
    Some([-10.0, -7.5, -5.0, -30.0, 52.5, 126.25]),
  )
  assert_eq(
    text[1].glyph_transform,
    Some([-10.0, -7.5, -5.0, -30.0, 57.0, 155.875]),
  )
}

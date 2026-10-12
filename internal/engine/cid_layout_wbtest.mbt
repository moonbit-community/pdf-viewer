///|
fn cid_layout_test_document(
  contents : String,
  cmap? : String,
  tounicode? : String,
  cmap_parent? : String,
  tounicode_parent? : String,
  widths2? : String = "[]",
  default_width2? : String = "[880 -1000]",
) -> PdfViewerDocument raise {
  let binary = type1_test_cid_binary([
    type1_test_page_charstring(),
    type1_test_page_charstring(),
    type1_test_page_charstring(),
  ])
  let font_hex = type1_test_bytes_hex(type1_test_cid_font(binary, 3))
  let cmap = cmap.unwrap_or(
    "/CMapType 1 def /WMode 0 def\n" +
    "1 begincodespacerange <0000> <FFFF> endcodespacerange\n" +
    "3 begincidchar <0041> 1 <0042> 2 <0043> 3 endcidchar\n" +
    "1 beginnotdefchar <0044> 0 endnotdefchar\n",
  )
  let tounicode = tounicode.unwrap_or(
    "1 begincodespacerange <0000> <FFFF> endcodespacerange\n" +
    "4 beginbfchar <0041> <0041> <0042> <0042> <0043> <0043> <0044> <0044> endbfchar\n",
  )
  let mut next_object = 11
  let extra_objects : Array[String] = []
  let cmap_use_cmap = match cmap_parent {
    Some(parent) => {
      let reference = "/UseCMap \{next_object} 0 R"
      extra_objects.push(annotation_test_stream("", parent))
      next_object += 1
      reference
    }
    None => ""
  }
  let tounicode_use_cmap = match tounicode_parent {
    Some(parent) => {
      let reference = "/UseCMap \{next_object} 0 R"
      extra_objects.push(annotation_test_stream("", parent))
      next_object += 1
      reference
    }
    None => ""
  }
  let objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream("", contents),
    "<< /Type /Font /Subtype /Type0 /BaseFont /CIDLayout /Encoding 8 0 R /DescendantFonts [6 0 R] /ToUnicode 10 0 R >>",
    "<< /Type /Font /Subtype /CIDFontType0 /BaseFont /CIDLayout /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /DW 700 /W [0 [400 500 300] 65 [100 100 100 100]] /W2 \{widths2} /DW2 \{default_width2} /FontDescriptor 7 0 R >>",
    "<< /Type /FontDescriptor /FontName /CIDLayout /Flags 4 /FontBBox [0 0 1000 1000] /Ascent 1000 /Descent 0 /ItalicAngle 0 /StemV 80 /FontFile 9 0 R >>",
    annotation_test_stream(cmap_use_cmap, cmap),
    annotation_test_stream("/Filter /ASCIIHexDecode", font_hex),
    annotation_test_stream(tounicode_use_cmap, tounicode),
  ]
  for object in extra_objects {
    objects.push(object)
  }
  annotation_test_document(objects)
}

///|
test "external CMap widths use CIDs and persist across Tj and TJ operators" {
  let page = cid_layout_test_document(
      "BT /F1 10 Tf 20 50 Td <00410042> Tj <0043> Tj [<0041> -200 <0042>] TJ ET",
    )
    .page(1)
    .unwrap()
  let text = page.text_content().items
  assert_eq(text.length(), 5)
  let expected_x = [20.0, 25.0, 28.0, 35.0, 42.0]
  let expected_advance = [5.0, 3.0, 7.0, 5.0, 3.0]
  assert_eq([ for item in text => item.text ], ["A", "B", "C", "A", "B"])
  for index, item in text {
    assert_eq(item.advance_x, expected_advance[index])
    assert_eq(item.bounds.max_x - item.bounds.min_x, expected_advance[index])
    assert_eq(
      item.glyph_transform,
      Some([10.0, 0.0, 0.0, 10.0, expected_x[index], 50.0]),
    )
  }
}

///|
test "external CMap text quote operators preserve line and spacing state" {
  let page = cid_layout_test_document(
      "BT /F1 10 Tf 12 TL 20 100 Td <0041> Tj <0042> ' 0 1 <00410042> \" ET",
    )
    .page(1)
    .unwrap()
  let text = page.text_content().items
  assert_eq(text.length(), 4)
  let positions = [(20.0, 100.0), (20.0, 88.0), (20.0, 76.0), (26.0, 76.0)]
  for index, item in text {
    let (x, y) = positions[index]
    assert_eq(item.glyph_transform, Some([10.0, 0.0, 0.0, 10.0, x, y]))
  }
  assert_eq([ for item in text => item.advance_x ], [5.0, 3.0, 6.0, 4.0])
}

///|
test "external CMap CID advances respect text scale shear and CTM" {
  let page = cid_layout_test_document(
      "2 0 0 3 5 7 cm BT /F1 10 Tf 50 Tz 2 Tc 1 0.5 0.25 1 20 30 Tm <00410042> Tj ET",
    )
    .page(1)
    .unwrap()
  let text = page.text_content().items
  assert_eq(text.length(), 2)
  assert_eq(text[0].advance_x, 3.5)
  assert_eq(text[1].advance_x, 2.5)
  assert_eq(text[0].glyph_transform, Some([10.0, 7.5, 5.0, 30.0, 45.0, 97.0]))
  assert_eq(text[1].glyph_transform, Some([10.0, 7.5, 5.0, 30.0, 52.0, 102.25]))
}

///|
test "external CMap notdef and default widths do not change the source font" {
  let document = cid_layout_test_document(
    "BT /F1 10 Tf 20 50 Td <00440043> Tj ET",
  )
  let page = document.page(1).unwrap()
  let text = page.text_content().items
  assert_eq([ for item in text => item.advance_x ], [4.0, 7.0])
  assert_eq(text[1].glyph_transform, Some([10.0, 0.0, 0.0, 10.0, 24.0, 50.0]))
  let source_page = document.pages[0]
  let collected = pdf_collected_entries_of_page(document.document, source_page)
  let original = collected[0].state.text_state.current_font
  assert_eq(original.content_width_of_charcode(1).0, 500.0)
  assert_eq(original.content_width_of_charcode(65).0, 100.0)
}

///|
test "external CMap text clipping uses the corrected CID glyph positions" {
  let page = cid_layout_test_document(
      "BT /F1 10 Tf 7 Tr 20 50 Td <00410042> Tj ET 0 0 150 150 re f",
    )
    .page(1)
    .unwrap()
  let paths = text_clip_test_paths(page)
  assert_eq(paths.length(), 1)
  guard paths[0].clip_path is Some(clip) else {
    fail("CID Type 1 clipping was not collected")
  }
  assert_eq(
    clip, "M 20 150 L 25 150 L 25 143 L 20 143 M 25 150 L 30 150 L 30 143 L 25 143",
  )
}

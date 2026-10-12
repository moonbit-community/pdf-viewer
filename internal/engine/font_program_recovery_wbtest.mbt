///|
fn font_program_test_document(
  bytes : Bytes,
  cff : Bool,
) -> PdfViewerDocument raise {
  let hex = StringBuilder()
  for byte in bytes {
    hex.write_string(byte.to_int().to_string(radix=16).pad_start(2, '0'))
  }
  hex.write_char('>')
  annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream(
      "", "BT /F1 10 Tf 20 100 Td (ABC) Tj ET 0 0 10 10 re f",
    ),
    "<< /Type /Font /Subtype /Type1 /BaseFont /ViewerProgram /FirstChar 65 /LastChar 67 /Widths [500 500 500] /Encoding << /Differences [65 /A /B /C] >> /FontDescriptor 6 0 R >>",
    "<< /Type /FontDescriptor /FontName /ViewerProgram /Flags 32 /FontBBox [0 0 1000 1000] /Ascent 1000 /Descent 0 /ItalicAngle 0 /StemV 80 /" +
    (if cff { "FontFile3" } else { "FontFile" }) +
    " 7 0 R >>",
    annotation_test_stream(
      (if cff { "/Subtype /Type1C " } else { "/Length1 0 " }) +
      "/Filter /ASCIIHexDecode",
      hex.to_string(),
    ),
  ])
}

///|
fn font_program_test_type1(matrix : String, damaged : Bytes) -> Bytes raise {
  let program = type1_test_program([], [
    ("A", type1_test_page_charstring()),
    ("B", damaged),
    ("C", type1_test_page_charstring()),
  ])
  @utf8.encode(
    "%!PS-AdobeFont-1.0: ViewerProgram\n/FontMatrix [" +
    matrix +
    "] def\n/Encoding StandardEncoding def\neexec\n",
  ) +
  type1_test_encrypt(b"\x00\x00\x00\x00" + program, 55665)
}

///|
test "CFF explicit missing names select notdef instead of unrelated built-in codes" {
  let document = font_program_test_document(b"\x01\x00", true)
  let pdf_font = pdf_read_font_for_viewer(
    document.document,
    @syntax.PdfIndirect(5),
  )
  let font = {
    ..cff_test_font(b"\x0E"),
    charstrings: [b"\x0E"[:], b"\x0E"[:]],
    charset: [0, cff_test_sid("B")],
    encoding: [
      for i in 0..<256 => if i == 65 { 1 } else { 0 }
    ],
  }
  assert_eq(
    pdf_cff_glyph_for_pdf_charcode(document.document, font, pdf_font, 65),
    Some(0),
  )
  assert_eq(
    pdf_cff_glyph_for_pdf_charcode(document.document, font, pdf_font, 66),
    Some(1),
  )
  guard pdf_font is @pdflite.PdfFontSimple(simple) else {
    fail("simple font missing")
  }
  let implicit = @pdflite.PdfFontSimple({
    ..simple,
    encoding: @pdflite.PdfImplicitInFontFile,
  })
  assert_eq(
    pdf_cff_glyph_for_pdf_charcode(document.document, font, implicit, 65),
    Some(1),
  )
}

///|
test "CFF bad charstrings do not poison later glyphs text or page paths" {
  let good = cff_test_program([
    cff_test_op([0, 0], 21),
    cff_test_op([500, 0, 0, 700, -500, 0], 5),
    b"\x0E",
  ])
  for bad in [b"\x1C", b"\x8B\x8B\x05\x0E", b"\x8B\x0A\x0E"] {
    let raw = cff_test_raw_font([b"\x0E", good, bad, good], [
      0,
      cff_test_sid("A"),
      cff_test_sid("B"),
      cff_test_sid("C"),
    ])
    let document = font_program_test_document(raw, true)
    let page = document.page(1).unwrap()
    assert_eq(page.text_content().text, "ABC")
    let text = page.text_content().items
    assert_true(text[0].type3_outline is Some(_))
    assert_true(text[1].type3_outline is None)
    assert_true(text[2].type3_outline is Some(_))
    assert_eq(text.map(item => item.advance_x), [5.0, 5.0, 5.0])
    assert_true(page.render_svg().contains("M 30 100 L 35 100"))
    assert_true(
      page
      .text_diagnostics()
      .any(item => {
        item.source.charcode == 66 && item.kind == MissingEmbeddedOutline
      }),
    )
  }
}

///|
test "Type 1 nonstandard FontMatrix and damaged glyphs preserve PDF advances" {
  for bad in [b"\x1C", b"\x8B\x0A\x0E", b"\x8B\x8B\x05\x0E"] {
    let raw = font_program_test_type1("0.002 0.001 0 0.003 0.05 -0.02", bad)
    let font = pdf_type1_parse_font(raw).unwrap()
    let point = font.font_matrix.apply(@geometry.point2(500.0, 700.0))
    assert_true((point.x - 1.05).abs() < 0.000001)
    assert_true((point.y - 2.58).abs() < 0.000001)
    let page = font_program_test_document(raw, false).page(1).unwrap()
    assert_eq(page.text_content().text, "ABC")
    let text = page.text_content().items
    assert_true(text[0].type3_outline.unwrap().contains("M 20.5 100.2"))
    assert_true(text[1].type3_outline is None)
    assert_true(text[2].type3_outline.unwrap().contains("M 30.5 100.2"))
    assert_eq(text.map(item => item.advance_x), [5.0, 5.0, 5.0])
  }
}

///|
test "Truncated CFF and Type 1 programs retain text host fallback and following paths" {
  for
    (bytes, cff) in [
      (b"\x01\x00\x04\x04", true),
      (b"%!PS-AdobeFont-1.0\neexec\n0000", false),
    ] {
    let page = font_program_test_document(bytes, cff).page(1).unwrap()
    assert_eq(page.text_content().text, "ABC")
    assert_true(
      page.text_content().items.all(item => item.type3_outline is None),
    )
    assert_true(page.render_svg().contains("<path"))
    assert_eq(
      page
      .text_diagnostics()
      .filter(item => item.kind == MissingEmbeddedOutline)
      .length(),
      3,
    )
  }
}

///|
test "Type 1 hint replacement retains the subroutine index and preceding drawing operands" {
  for selector in [3, 12] {
    let glyph = @core.pdf_bytes_of_int_array([
      139,
      248,
      136,
      13,
      139,
      139,
      21, // hsbw; rmoveto
      149,
      159,
      139,
      140,
      selector + 139,
      12,
      16, // dx dy index, one argument, OtherSubr
      12,
      17,
      10,
      14, // pop; callsubr; endchar
    ])
    let program = type1_test_program([(0, b"\x05\x0B")], [
      ("A", glyph),
      ("B", glyph),
      ("C", glyph),
    ])
    let raw = @utf8.encode(
        "/FontMatrix [0.001 0 0 0.001 0 0] def /Encoding StandardEncoding def eexec\n",
      ) +
      type1_test_encrypt(b"\x00\x00\x00\x00" + program, 55665)
    let font = pdf_type1_parse_font(raw).unwrap()
    let state = Ref(pdf_cff_new_state(Ref(1000)))
    assert_true(pdf_type1_run_glyph(font, "A", state, [], 0))
    assert_true(state.val.commands.contains(CffLine(10.0, 20.0)))
    let document = font_program_test_document(raw, false)
    font_scope_test_content(
      document, "BT /F1 10 Tf 4 Tr 20 100 Td (ABC) Tj ET 0 0 200 200 re f",
    )
    let page = document.page(1).unwrap()
    assert_eq(page.text_content().text, "ABC")
    assert_true(
      page.text_content().items.all(item => item.type3_outline is Some(_)),
    )
    assert_true(page.render_svg().contains("<clipPath"))
    assert_eq(document.text_recovery_diagnostics(1).unwrap(), [])
  }
}

///|
test "Type 1 flex point calls retain relative deltas and ignore the final hint position" {
  let values = [5, -3, 10, 1, -7, 9, 6, -8, -4, 3, 7, 4, 2, -5]
  let code : Array[Int] = [139, 248, 136, 13, 159, 169, 21, 139, 140, 12, 16]
  for index in 0..<7 {
    code.push(values[index * 2] + 139)
    code.push(values[index * 2 + 1] + 139)
    code.push(21)
    code.append([139, 141, 12, 16]) // OtherSubr 2 retains this flex point.
  }
  code.append([189, 239, 239, 142, 139, 12, 16]) // depth/final hint position; flex end
  code.append([12, 17, 12, 17, 12, 33, 140, 141, 5, 14])
  let glyph = @core.pdf_bytes_of_int_array(code)
  let font = pdf_type1_parse_program(
    type1_test_program([], [("A", glyph)])[:],
    @geometry.transform_identity_matrix,
    Map([]),
  ).unwrap()
  let state = Ref(pdf_cff_new_state(Ref(1000)))
  assert_true(pdf_type1_run_glyph(font, "A", state, [], 0))
  assert_true(
    state.val.commands.contains(CffCurve(35.0, 28.0, 28.0, 37.0, 34.0, 29.0)),
  )
  assert_true(
    state.val.commands.contains(CffCurve(30.0, 32.0, 37.0, 36.0, 39.0, 31.0)),
  )
  assert_true(state.val.commands.contains(CffLine(40.0, 33.0)))
}

///|
fn standard14_test_faces() -> Array[@pdflite.PdfStandardFont] {
  [
    @pdflite.PdfTimesRoman,
    @pdflite.PdfTimesBold,
    @pdflite.PdfTimesItalic,
    @pdflite.PdfTimesBoldItalic,
    @pdflite.PdfHelvetica,
    @pdflite.PdfHelveticaBold,
    @pdflite.PdfHelveticaOblique,
    @pdflite.PdfHelveticaBoldOblique,
    @pdflite.PdfCourier,
    @pdflite.PdfCourierBold,
    @pdflite.PdfCourierOblique,
    @pdflite.PdfCourierBoldOblique,
    @pdflite.PdfSymbol,
    @pdflite.PdfZapfDingbats,
  ]
}

///|
test "all fourteen pinned standard font programs parse and paint without host fonts" {
  for face in standard14_test_faces() {
    let bytes = pdf_standard14_asset(face.name()).unwrap()
    assert_true(bytes.length() > 10000)
    let program = pdf_standard14_program(face).unwrap()
    match program {
      StandardTrueType(data) => assert_eq(data, bytes)
      StandardCff(data, font) => {
        assert_eq(data, bytes)
        assert_true(font.charstrings.length() > 100)
      }
    }
    let document = provenance_test_document(
      "BT /F1 12 Tf 20 100 Td (A) Tj ET",
      font="<< /Subtype /Type1 /BaseFont /" + face.name() + " >>",
    )
    let page = document.page(1).unwrap()
    let glyph = page.text_content().items[0]
    assert_eq(page.fonts[0].standard_font, Some(face.name()))
    assert_true(page.fonts[0].data_uri is Some(_))
    assert_true(
      glyph.type3_outline
      .unwrap()
      .contains("data-pdf-font-outline=\"standard14:" + face.name() + "\""),
    )
    assert_eq(page.text_diagnostics(), [])
    let font = pdf_read_font_for_viewer(
      document.document,
      @syntax.PdfIndirect(5),
    )
    assert_true(
      (glyph.advance_x - font.content_width_of_charcode(65).0 * 0.012).abs() <
      0.000000001,
    )
    assert_eq(font.embedded_fontfile_number(), None)
  }
  assert_eq(pdf_standard14_asset("not-a-font"), None)
  assert_eq(pdf_standard14_programs.length(), 14)
}

///|
test "standard fonts use pinned outlines for text clipping and preserve independent advance" {
  for face in standard14_test_faces() {
    let document = provenance_test_document(
      "BT /F1 10 Tf 4 Tr 20 100 Td (A) Tj ET 0 0 200 200 re f",
      font="<< /Subtype /Type1 /BaseFont /" + face.name() + " >>",
    )
    let page = document.page(1).unwrap()
    let clip = text_clip_test_paths(page)[0].clip_path.unwrap()
    assert_true(!clip.is_empty())
    assert_true(
      page.text_content().items[0].type3_outline
      .unwrap()
      .contains(pdf_escape_xml(clip)),
    )
    assert_eq(page.text_diagnostics(), [])
  }
}

///|
test "standard Helvetica Differences select outlines independently of ToUnicode" {
  let document = provenance_test_document(
    "BT /F1 10 Tf 20 100 Td (A) Tj ET",
    font="<< /Subtype /Type1 /BaseFont /Helvetica /Encoding << /Differences [65 /Z] >> /ToUnicode 6 0 R >>",
    extra_objects=[
      annotation_test_stream("", "1 beginbfchar <41> <0051> endbfchar"),
    ],
  )
  let page = document.page(1).unwrap()
  assert_eq(page.text, "Q")
  let font = pdf_read_font_for_viewer(document.document, @syntax.PdfIndirect(5))
  let bytes = pdf_standard14_program_bytes(@pdflite.PdfHelvetica).unwrap()
  let gid = pdf_viewer_ttf_simple_gid(
    pdf_standard14_simple_font(font),
    bytes,
    65,
  )
  assert_eq(
    gid,
    pdf_viewer_ttf_cmap_gid(
      bytes[:],
      pdf_viewer_ttf_cmap(bytes[:], false, false).unwrap(),
      90,
    ),
  )
  assert_true(gid > 0)
  assert_true(page.text_content().items[0].type3_outline is Some(_))
  assert_eq(
    document.text_provenance(1).unwrap()[0].string_source.unwrap().bytes,
    b"A",
  )
}

///|
test "standard CFF WinAnsi accented glyphs and Symbol Dingbats encodings use program names" {
  for face in [@pdflite.PdfTimesRoman, @pdflite.PdfCourier] {
    let document = provenance_test_document(
      "BT /F1 10 Tf 20 100 Td <E9> Tj ET",
      font="<< /Subtype /Type1 /BaseFont /" +
        face.name() +
        " /Encoding /WinAnsiEncoding >>",
    )
    let page = document.page(1).unwrap()
    assert_eq(page.text, "é")
    assert_true(page.text_content().items[0].type3_outline is Some(_))
  }
  for face in [@pdflite.PdfSymbol, @pdflite.PdfZapfDingbats] {
    guard pdf_standard14_program(face) is Some(StandardCff(_, program)) else {
      fail("expected CFF program")
    }
    let font = @pdflite.PdfFontStandard({
      font: face,
      encoding: @pdflite.PdfImplicitInFontFile,
    })
    let gid = pdf_standard14_cff_gid(face, program, font, 65).unwrap()
    let name = pdf_cff_sid_text(program, program.charset[gid]).unwrap()
    assert_eq(name, if face == @pdflite.PdfSymbol { "Alpha" } else { "a10" })
  }
}

///|
test "standard program outlines use the full affine em matrix and AFM widths remain independent" {
  let face = @pdflite.PdfHelvetica
  let font = @pdflite.PdfFontStandard({
    font: face,
    encoding: @pdflite.PdfStandardEncoding,
  })
  let bytes = pdf_standard14_program_bytes(face).unwrap()
  let gid = pdf_viewer_ttf_simple_gid(
    pdf_standard14_simple_font(font),
    bytes,
    65,
  )
  let matrix : @geometry.TransformMatrix = {
    a: 10.0,
    b: 7.5,
    c: 5.0,
    d: 30.0,
    e: 46.0,
    f: 103.0,
  }
  let expected = pdf_viewer_ttf_outline_path(
    bytes, gid, matrix, 0.0, 0.0, 200.0,
  )
  assert_eq(
    pdf_standard14_path_of_pdf_glyph(font, 65, Some(matrix), 0.0, 0.0, 200.0),
    expected,
  )
  assert_true(expected.unwrap().contains("M "))
  assert_eq(font.content_width_of_charcode(65).0, 667.0)
}

///|
test "bundled standard fonts do not replace an embedded PDF program" {
  let document = truetype_test_document(truetype_test_fixture())
  let font_object = document.document
    .lookup_object_or_null(5)
    .add_dict_entry(
      pdf_name_key("/BaseFont"),
      @syntax.PdfNameObject(pdf_name_key("/Helvetica")),
    )
  document.document.add_object_given_number(5, font_object)
  let font = pdf_read_font_for_viewer(document.document, @syntax.PdfIndirect(5))
  assert_eq(font.embedded_fontfile_number(), Some(7))
  assert_eq(pdf_standard14_face_of_pdf_font(font), None)
  let page = document.page(1).unwrap()
  assert_true(
    page.text_content().items[0].type3_outline.unwrap().contains("L 21 100"),
  )
  assert_true(
    !page.text_content().items[0].type3_outline.unwrap().contains("standard14:"),
  )
  assert_eq(page.fonts[0].format, "truetype")
}

///|
test "explicit host fallback retains the requested standard face and missing clip observation" {
  let document = provenance_test_document(
    "BT /F1 10 Tf 4 Tr 20 100 Td (A) Tj ET 0 0 200 200 re f",
  )
  let overridden = document.with_font_fallbacks([
    { pdf_name: "/F1", family: "Test Host Sans", weight: None, style: None, },
  ])
  let page = overridden.page(1).unwrap()
  assert_eq(page.fonts[0].family, "Test Host Sans")
  assert_eq(page.fonts[0].data_uri, None)
  assert_eq(page.text_content().items[0].type3_outline, None)
  assert_eq(text_clip_test_paths(page)[0].clip_path, None)
  assert_eq(
    [
      for observation in page.text_diagnostics() => observation.kind
    ],
    [MissingClipOutline, HostFontFallback],
  )
  assert_eq(overridden.text_provenance(1).unwrap()[0].source.font, "/F1")
  assert_true(
    document.page(1).unwrap().text_content().items[0].type3_outline is Some(_),
  )
}

///|
test "outlined standard text retains copied controls without invalid XML labels" {
  let document = provenance_test_document(
    "BT /F1 10 Tf 20 100 Td (A) Tj ET",
    font="<< /Subtype /Type1 /BaseFont /Helvetica /ToUnicode 6 0 R >>",
    extra_objects=[
      annotation_test_stream("", "1 beginbfchar <41> <0000> endbfchar"),
    ],
  )
  let page = document.page(1).unwrap()
  assert_eq(page.text, "\u0000")
  assert_true(
    page.text_content().items[0].type3_outline is Some(path) && !path.is_empty(),
  )
  assert_true(!page.render_svg().contains("\u0000"))
  assert_eq(page.text_sources()[0].charcode, 65)
}

///|
test "standard Symbol Differences retain the implicit symbolic base and last override" {
  let face = @pdflite.PdfSymbol
  let encoding = @pdflite.PdfCustomEncoding(@pdflite.PdfImplicitInFontFile, [
    { code: 65, name: pdf_name_key("/A"), },
    { code: 65, name: pdf_name_key("/Omega"), },
  ])
  assert_eq(
    pdf_standard14_encoding_glyph_name(face, encoding, 65),
    Some(pdf_name_key("/Omega")),
  )
  assert_eq(
    pdf_standard14_encoding_glyph_name(face, encoding, 66),
    Some(pdf_name_key("/Beta")),
  )
}

///|
test "undefined standard WinAnsi slots share the bullet advance copy and outline" {
  for face in [@pdflite.PdfCourier, @pdflite.PdfHelvetica] {
    let document = provenance_test_document(
      "BT /F1 10 Tf 20 100 Td <7F818D8F909D> Tj ET",
      font="<< /Subtype /Type1 /BaseFont /" +
        face.name() +
        " /Encoding /WinAnsiEncoding >>",
    )
    let source_object = document.document.lookup_object_or_null(5)
    let page = document.page(1).unwrap()
    assert_eq(page.text, "••••••")
    let glyphs = page.text_content().items
    assert_eq(glyphs.length(), 6)
    for glyph in glyphs {
      assert_true(glyph.advance_x > 0.0)
      assert_true(glyph.type3_outline is Some(path) && !path.is_empty())
    }
    assert_eq(document.document.lookup_object_or_null(5), source_object)
    assert_eq(
      [
        for origin in provenance_test_paint_order(document) => {
          origin.source.charcode
        }
      ],
      [0x7F, 0x81, 0x8D, 0x8F, 0x90, 0x9D],
    )
  }
}

///|
test "explicit Differences and ToUnicode override the WinAnsi bullet defaults" {
  let document = provenance_test_document(
    "BT /F1 10 Tf 20 100 Td <81> Tj ET",
    font="<< /Subtype /Type1 /BaseFont /Helvetica /Encoding << /BaseEncoding /WinAnsiEncoding /Differences [129 /A] >> /ToUnicode 6 0 R >>",
    extra_objects=[
      annotation_test_stream("", "1 beginbfchar <81> <005A> endbfchar"),
    ],
  )
  let page = document.page(1).unwrap()
  assert_eq(page.text, "Z")
  let font = pdf_read_font_for_viewer(document.document, @syntax.PdfIndirect(5))
  assert_eq(
    pdf_standard14_encoding_glyph_name(
      @pdflite.PdfHelvetica,
      pdf_standard14_pdf_encoding(font),
      129,
    ),
    Some(pdf_name_key("/A")),
  )
  assert_true(
    page.text_content().items[0].type3_outline is Some(path) && !path.is_empty(),
  )
  let normalized = pdf_standard14_pdf_encoding(font)
  assert_eq(pdf_standard14_encoding_for_viewer(normalized), normalized)
}

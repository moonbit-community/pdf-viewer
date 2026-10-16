///|
test "Font programs and contours share one immutable document revision" {
  let viewer = truetype_test_document(truetype_test_fixture())
  let original = viewer.document.lookup_object_or_null(7)
  let first = viewer.page(1).unwrap()
  let cache = viewer.parsed_fonts.unwrap()
  assert_eq(cache.programs.programs.length(), 1)
  assert_true(cache.programs.contours.contains((7, 1)))
  let bytes = cache.bytes + cache.programs.bytes
  assert_true(bytes > 0 && bytes <= 0x800000)
  let second = viewer.page(1).unwrap()
  assert_eq(first.canvas_plan(), second.canvas_plan())
  assert_eq(cache.bytes + cache.programs.bytes, bytes)
  assert_eq(viewer.document.lookup_object_or_null(7), original)
  let policy = viewer.with_font_fallbacks([])
  assert_eq(policy.page(1).unwrap().canvas_plan(), first.canvas_plan())
  assert_eq(cache.bytes + cache.programs.bytes, bytes)
  let edited = viewer.with_editor_changes([])
  assert_eq(edited.parsed_fonts.unwrap().programs.programs.length(), 0)
  assert_eq(edited.parsed_fonts.unwrap().programs.contours.length(), 0)
  assert_eq(edited.page(1).unwrap().canvas_plan(), first.canvas_plan())
  assert_eq(
    truetype_test_document(truetype_test_fixture()).parsed_fonts.unwrap().programs.programs.length(),
    0,
  )
}

///|
test "Shared font bytes preserve dictionary encoding and per-paint placement" {
  let viewer = truetype_test_document(truetype_test_fixture())
  let context = pdf_resource_build_context(parsed_fonts=viewer.parsed_fonts)
  let first = pdf_read_font_for_viewer(viewer.document, @syntax.PdfIndirect(5))
  let child = font_scope_test_child_font(viewer)
  let second = pdf_read_font_for_viewer(viewer.document, child)
  for font in [first, second] {
    for
      matrix in [
        @geometry.transform_identity_matrix,
        { a: 10.0, b: 2.0, c: -3.0, d: 7.0, e: 21.0, f: 35.0, },
      ] {
      let legacy = pdf_truetype_path_of_pdf_glyph(
        viewer.document,
        font,
        Some(child),
        65,
        Some(matrix),
        7.0,
        13.0,
        200.0,
      )
      let cached = pdf_truetype_path_of_pdf_glyph(
        viewer.document,
        font,
        Some(child),
        65,
        Some(matrix),
        7.0,
        13.0,
        200.0,
        resource_context=Some(context),
      )
      assert_eq(cached, legacy)
      assert_true(cached is Some(_))
    }
  }
  assert_eq(context.font_programs.programs.length(), 1)
  assert_true(context.font_programs.contours.contains((7, 1)))
  assert_true(context.font_programs.contours.contains((7, 2)))
}

///|
test "Shared unplaced TrueType contours retain composites and empty glyphs" {
  let data = truetype_test_fixture()
  let viewer = truetype_test_document(data)
  let context = pdf_resource_build_context(parsed_fonts=viewer.parsed_fonts)
  let program = pdf_font_program(viewer.document, 7, context)
  let layout = pdf_font_program_layout(program, 7, context)
  let matrix : @geometry.TransformMatrix = {
    a: 11.0,
    b: 2.0,
    c: -3.0,
    d: 7.0,
    e: 21.0,
    f: 35.0,
  }
  for glyph in 0..<7 {
    let expected = pdf_viewer_ttf_outline_path(
      data, glyph, matrix, 7.0, 13.0, 200.0,
    )
    for _ in 0..<2 {
      let actual = match
        pdf_font_program_contours(program, layout, 7, glyph, context) {
        Some([]) => Some("")
        Some(contours) =>
          pdf_viewer_ttf_positioned_path(
            contours[:],
            layout.units_per_em.unwrap(),
            matrix,
            7.0,
            13.0,
            200.0,
          )
        None => None
      }
      assert_eq(actual, expected)
    }
  }
  assert_eq(context.font_programs.contours.length(), 7)
}

///|
test "Font programs and metadata share the existing admission budget" {
  let data = truetype_test_fixture()
  let viewer = truetype_test_document(data)
  let shared = viewer.parsed_fonts.unwrap()
  shared.bytes = 0x800000
  let context = pdf_resource_build_context(parsed_fonts=Some(shared))
  let program = pdf_font_program(viewer.document, 7, context)
  assert_eq(program.data, data)
  let layout = pdf_font_program_layout(program, 7, context)
  assert_true(
    pdf_font_program_contours(program, layout, 7, 1, context) is Some(_),
  )
  assert_eq(context.font_programs.programs.length(), 0)
  assert_eq(context.font_programs.contours.length(), 0)
  assert_eq(context.font_programs.bytes, 0)
  assert_true(program.layout is None)
  let font = pdf_read_font_for_viewer(viewer.document, @syntax.PdfIndirect(5))
  let full = pdf_parsed_font_cache()
  full.programs.bytes = 0x800000
  full.retain(5, font)
  assert_eq(full.fonts.length(), 0)
  assert_eq(full.bytes, 0)
}

///|
test "Font program admission bounds entries and glyph geometry independently" {
  let viewer = truetype_test_document(truetype_test_fixture())
  let context = pdf_resource_build_context()
  for number in 100..<229 {
    viewer.document.add_object_given_number(number, @syntax.PdfIndirect(7))
    ignore(pdf_font_program(viewer.document, number, context))
  }
  assert_eq(context.font_programs.programs.length(), 128)
  assert_true(!context.font_programs.programs.contains(228))
  let program = pdf_font_program(viewer.document, 100, context)
  let layout = pdf_font_program_layout(program, 100, context)
  for glyph in 0..<513 {
    ignore(pdf_font_program_contours(program, layout, 100, glyph, context))
  }
  assert_eq(context.font_programs.contours.length(), 512)
  assert_true(!context.font_programs.contours.contains((100, 512)))
  assert_true(context.font_programs.bytes <= 0x800000)
}

///|
test "Failed and Range-local font resources never poison a later build" {
  let viewer = truetype_test_document(truetype_test_fixture())
  let first = pdf_resource_build_context()
  let failed = try {
    ignore(pdf_font_program(viewer.document, 999, first))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_eq(first.font_programs.programs.length(), 0)
  viewer.document.add_object_given_number(999, @syntax.PdfIndirect(7))
  let original = pdf_font_program(viewer.document, 999, first)
  assert_eq(original.data, truetype_test_fixture())
  viewer.document.add_object_given_number(
    999,
    @syntax.pdf_stream(
      @syntax.PdfDictionary([(pdf_name_key("/Length"), @syntax.PdfInteger(9))]),
      @syntax.StreamGot(b"alternate"),
    ),
  )
  let second = pdf_resource_build_context()
  assert_eq(pdf_font_program(viewer.document, 999, second).data, b"alternate")
  assert_eq(original.data, truetype_test_fixture())
}

///|
test "CID map reuse preserves the reader's resolved alias-chain behavior" {
  let viewer = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream("", "BT /F1 10 Tf <0041> Tj ET"),
    "<< /Type /Font /Subtype /Type0 /BaseFont /ViewerGidTest /Encoding /Identity-H /DescendantFonts [6 0 R] >>",
    "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /ViewerGidTest /DW 600 /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor 7 0 R /CIDToGIDMap 9 0 R >>",
    "<< /Type /FontDescriptor /FontName /ViewerGidTest /Flags 32 /FontBBox [0 0 300 400] /Ascent 800 /Descent -200 /ItalicAngle 0 /StemV 80 /FontFile2 8 0 R >>",
    annotation_test_stream(
      "/Filter /ASCIIHexDecode",
      type1_test_bytes_hex(truetype_test_fixture()),
    ),
    annotation_test_stream("", ""),
  ])
  let map = Array::make(132, b'\x00')
  map[131] = b'\x02'
  let data = Bytes::from_array(map)
  viewer.document.add_object_given_number(9, @syntax.PdfIndirect(11))
  for number in 11..<90 {
    viewer.document.add_object_given_number(
      number,
      @syntax.PdfIndirect(number + 1),
    )
  }
  viewer.document.add_object_given_number(
    90,
    @syntax.pdf_stream(
      @syntax.PdfDictionary([(pdf_name_key("/Length"), @syntax.PdfInteger(132))]),
      @syntax.StreamGot(data),
    ),
  )
  let font_object = @syntax.PdfIndirect(5)
  guard pdf_read_font_for_viewer(viewer.document, font_object)
    is @pdflite.PdfFontCIDKeyed(font) else {
    fail("Expected CID font")
  }
  assert_eq(
    pdf_viewer_ttf_cid_to_gid(viewer.document, font_object, font, 65),
    2,
  )
  let context = pdf_resource_build_context(parsed_fonts=viewer.parsed_fonts)
  for _ in 0..<2 {
    assert_eq(
      pdf_viewer_ttf_cid_to_gid(
        viewer.document,
        font_object,
        font,
        65,
        resource_context=Some(context),
      ),
      2,
    )
  }
  assert_eq(context.font_programs.programs.get(9).unwrap().data, data)
}

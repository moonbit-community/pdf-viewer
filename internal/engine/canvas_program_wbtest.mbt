///|
fn canvas_program_test_document(
  charproc : String,
  contents? : String = "BT /F1 60 Tf 20 30 Td (AA) Tj ET",
) -> PdfViewerDocument raise {
  annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 2 /Kids [3 0 R 7 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream("", contents),
    "<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1000 1000] /FontMatrix [.001 0 0 .001 0 0] /FirstChar 65 /LastChar 65 /Widths [1000] /Encoding << /Type /Encoding /Differences [65 /A] >> /CharProcs << /A 6 0 R >> /Resources << >> >>",
    annotation_test_stream("", charproc),
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 8 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream("", "0 1 0 rg BT /F1 30 Tf 80 90 Td (AA) Tj ET"),
  ])
}

///|
test "Canvas programs compile glyph geometry once across placements and pages" {
  let document = canvas_program_test_document(
    "1000 0 0 0 1000 1000 d1 0 0 1000 1000 re f",
  )
  let (page, program) = prepare_canvas_page(document, 1).unwrap()
  assert_eq(program.glyphs.length(), 2)
  assert_eq(program.resources.length(), 1)
  assert_eq(document.canvas_resources.glyphs.length(), 1)
  assert_eq(document.canvas_resources.misses, 1)
  assert_eq(document.canvas_resources.hits, 1)
  let first = program.glyphs[0]
  let second = program.glyphs[1]
  assert_eq(first.resource.id, second.resource.id)
  assert_true(first.matrix != second.matrix)
  assert_true(program.canvas_plan(page, 1.0, 0) is { "version": Number(3), .. })
  let original = document.page(1).unwrap()
  assert_eq(page.text_layer(), original.text_layer())
  assert_eq(program.text_content, Some(page.text_content()))
  for rotation in [0, 90, 180, 270] {
    assert_eq(
      program.text_layer(page, 1.25, rotation),
      page.text_layer(scale=1.25, rotation~),
    )
  }
  assert_eq(page.annotations, original.annotations)
  assert_true(original.canvas_plan() is { "version": Number(1), .. })
  assert_true(
    text_stroke_test_item(original).type3_scene.unwrap().items.length() > 0,
  )
  let (other, next) = prepare_canvas_page(document, 2).unwrap()
  assert_eq(document.canvas_resources.misses, 1)
  assert_eq(document.canvas_resources.hits, 3)
  assert_eq(next.glyphs[0].resource.id, first.resource.id)
  assert_true(next.glyphs[0].matrix != first.matrix)
  assert_eq(text_stroke_test_item(other).fill_color, "#00FF00")
  assert_true(program.estimated_bytes() > 0)
}

///|
test "Canvas glyph programs preserve stencil colours fill rules and Tr semantics" {
  for mode in [0, 1, 2, 4, 5, 6, 7] {
    let document = canvas_program_test_document(
      "1000 0 0 0 1000 1000 d1 1 0 0 rg 0 0 1000 1000 re 100 100 200 200 re f*",
      contents="0 0 1 rg BT /F1 40 Tf \{mode} Tr 20 30 Td (A) Tj ET",
    )
    let (page, program) = prepare_canvas_page(document, 1).unwrap()
    assert_eq(program.glyphs.length(), 1)
    assert_true(program.glyphs[0].resource.json is { "even_odd": True, .. })
    assert_eq(text_stroke_test_item(page).fill_color, "#0000FF")
    assert_eq(text_stroke_test_item(page).rendering_mode, mode)
    assert_eq(page.text_layer(), document.page(1).unwrap().text_layer())
  }
  let document = canvas_program_test_document(
    "1000 0 0 0 1000 1000 d1 0 0 1000 1000 re f",
    contents="BT /F1 40 Tf 3 Tr 20 30 Td (A) Tj ET",
  )
  let (page, program) = prepare_canvas_page(document, 1).unwrap()
  assert_eq(program.glyphs.length(), 0)
  assert_eq(page, document.page(1).unwrap())
}

///|
test "Canvas programs retain the interpreter for stateful and complex CharProcs" {
  for
    charproc in [
      "1000 0 d0 1 0 0 rg 0 0 1000 1000 re f", "1000 0 d0 2 0 0 1 0 0 cm 0 0 1000 1000 re f",
      "1000 0 d0 0 0 1000 1000 re S", "1000 0 d0 0 0 1000 1000 re W n 0 0 1000 1000 re f",
      "1000 0 d0 0 0 500 1000 re f 500 0 500 1000 re f", "1000 0 d0 q 0 0 1000 1000 re f",
    ] {
    let document = canvas_program_test_document(charproc)
    let (page, program) = prepare_canvas_page(document, 1).unwrap()
    assert_eq(program.glyphs.length(), 0)
    assert_eq(document.canvas_resources.glyphs.length(), 0)
    assert_eq(page, document.page(1).unwrap())
  }
  for prefix in ["/GS gs", "0 1 0 0 k"] {
    let document = canvas_program_test_document(
      "1000 0 d0 0 0 1000 1000 re f",
      contents="\{prefix} BT /F1 40 Tf 20 30 Td (A) Tj ET",
    )
    let (page, program) = prepare_canvas_page(document, 1).unwrap()
    if prefix == "0 1 0 0 k" {
      assert_eq(program.glyphs.length(), 0)
    }
    assert_eq(page.text_layer(), document.page(1).unwrap().text_layer())
  }
}

///|
test "Compiled glyph cache belongs to its document and respects its byte budget" {
  let first = canvas_program_test_document("1000 0 d0 0 0 1000 1000 re f")
  let second = canvas_program_test_document("1000 0 d0 0 0 500 500 re f")
  let (_, a) = prepare_canvas_page(first, 1).unwrap()
  let (_, b) = prepare_canvas_page(second, 1).unwrap()
  assert_true(a.glyphs[0].resource.json != b.glyphs[0].resource.json)
  let limited = canvas_program_test_document("1000 0 d0 0 0 1000 1000 re f")
  limited.canvas_resources.bytes = 8 * 1024 * 1024
  let (page, program) = prepare_canvas_page(limited, 1).unwrap()
  assert_eq(limited.canvas_resources.glyphs.length(), 0)
  assert_eq(limited.canvas_resources.bytes, 8 * 1024 * 1024)
  assert_eq(program.glyphs.length(), 2)
  assert_true(
    program.canvas_plan(page, 1.0, 0) is { "glyph_resources": Array([_]), .. },
  )
  assert_true(prepare_canvas_page(first, 0) is None)
  let full = canvas_program_test_document("1000 0 d0 0 0 1000 1000 re f")
  for id in 1000..<1512 {
    full.canvas_resources.glyphs[id] = { id, bytes: 256, json: Json::null(), }
  }
  full.canvas_resources.bytes = 512 * 256
  let (_, uncached) = prepare_canvas_page(full, 1).unwrap()
  assert_eq(full.canvas_resources.glyphs.length(), 512)
  assert_eq(full.canvas_resources.bytes, 512 * 256)
  assert_eq(uncached.glyphs.length(), 2)
  assert_eq(uncached.resources.length(), 1)
  assert_eq(full.canvas_resources.misses, 1)
  let capped = pdf_canvas_program()
  for id in 1000..<17384 {
    capped.resources[id] = { id, bytes: 256, json: Json::null(), }
  }
  let context = pdf_resource_build_context()
  let entry = pdf_collected_entries_of_page(
      first.document,
      first.pages[0],
      resource_context=context,
    )[0]
  let build = {
    program: capped,
    cache: first.canvas_resources,
    outlines: Map([]),
  }
  assert_true(
    pdf_canvas_glyph_call(first.document, entry, 65, context, build) is None,
  )
  capped.resources.remove(1000)
  capped.resources[6] = a.glyphs[0].resource
  assert_true(
    pdf_canvas_glyph_call(first.document, entry, 65, context, build) is Some(_),
  )
  assert_eq(capped.resources.length(), 16384)
}

///|
test "Speculative glyph compilation bounds Flate output before parsing" {
  let document = canvas_program_test_document("600 0 d0")
  let text = @utf8.encode("600 0 d0 0 0 600 1000 re f")
  let filter = @syntax.PdfNameObject(pdf_name_key("/FlateDecode"))
  let dictionary = @syntax.pdf_dictionary([(pdf_name_key("/Filter"), filter)])
  let encoded = @syntax.pdf_stream(
    dictionary,
    @syntax.StreamGot(@font_zlib.zlib_compress(text)),
  )
  let plain = @syntax.pdf_stream(
    @syntax.pdf_dictionary([
      (pdf_name_key("/Length"), @syntax.PdfInteger(text.length())),
    ]),
    @syntax.StreamGot(text),
  )
  assert_eq(
    pdf_canvas_compile_glyph(document.document, @syntax.PdfNull, encoded, 6).unwrap().json,
    pdf_canvas_compile_glyph(document.document, @syntax.PdfNull, plain, 6).unwrap().json,
  )
  let excessive = @syntax.pdf_stream(
    dictionary,
    @syntax.StreamGot(
      @font_zlib.zlib_compress(@utf8.encode(" ".repeat(1048577))),
    ),
  )
  let bounded = try {
    ignore(
      pdf_canvas_compile_glyph(document.document, @syntax.PdfNull, excessive, 6),
    )
    false
  } catch {
    @core.FlateOutputLimitExceeded(_) => true
    _ => false
  }
  assert_true(bounded)
}

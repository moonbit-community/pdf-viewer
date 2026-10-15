///|
test "cache sizing matches serialized UTF-16 for escapes Unicode and numeric spellings" {
  let controls = StringBuilder()
  for code in 0..<32 {
    controls.write_char(code.unsafe_to_char())
  }
  let values : Array[Json] = [
    Json::null(),
    true,
    false,
    [],
    {},
    "quotes \" backslash \\ slash / 汉字 😀",
    Json::string(controls.to_string()),
    @json.parse(
      "{\"number\":1.000e+003,\"negative\":-0,\"array\":[null,true,false,1.5]}",
    ),
    { "quoted\"key": ["a\\b", { "nested": controls.to_string() }] },
  ]
  for value in values {
    assert_eq(browser_json_size(value), value.stringify().length())
  }
  let large = Json::string("data:image/png;base64," + "A".repeat(100000))
  assert_eq(browser_json_size(large), large.stringify().length())
}

///|
fn cache_test_pdf(type3? : Bool = false) -> Bytes {
  let contents = if type3 {
    "BT /F1 30 Tf 20 50 Td /P << /MCID 0 >> BDC (AA) Tj EMC ET"
  } else {
    "BT /F1 10 Tf 20 80 Td /P << /MCID 0 >> BDC (Base) Tj EMC 0 -20 Td /OC /Layer BDC /P << /MCID 1 >> BDC (Layer) Tj EMC EMC ET"
  }
  let objects = [
    "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 6 0 R /OCProperties << /OCGs [9 0 R] /D << /Order [9 0 R] /ON [9 0 R] >> >> >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> /Properties << /Layer 9 0 R >> >> >>",
    "<< /Length \{contents.length()} >>\nstream\n\{contents}\nendstream",
    if type3 {
      "<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1000 1000] /FontMatrix [.001 0 0 .001 0 0] /FirstChar 65 /LastChar 65 /Widths [600] /Encoding << /Type /Encoding /Differences [65 /A] >> /CharProcs << /A 10 0 R >> /Resources << >> >>"
    } else {
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    },
    "<< /Type /StructTreeRoot /K [7 0 R 8 0 R] >>",
    "<< /Type /StructElem /S /P /Pg 3 0 R /K 0 >>",
    "<< /Type /StructElem /S /P /Pg 3 0 R /K 1 >>",
    "<< /Type /OCG /Name (Optional text) >>",
  ]
  if type3 {
    let glyph = "600 0 0 0 600 1000 d1 0 0 600 1000 re f"
    objects.push("<< /Length \{glyph.length()} >>\nstream\n\{glyph}\nendstream")
  }
  let output = StringBuilder()
  output.write_string("%PDF-1.7\n")
  let offsets = []
  for index, object in objects {
    offsets.push(output.to_string().length())
    output.write_string("\{index + 1} 0 obj\n\{object}\nendobj\n")
  }
  let xref = output.to_string().length()
  output.write_string("xref\n0 \{objects.length() + 1}\n0000000000 65535 f \n")
  for offset in offsets {
    output.write_string(offset.to_string().pad_start(10, '0') + " 00000 n \n")
  }
  output.write_string(
    "trailer\n<< /Size \{objects.length() + 1} /Root 1 0 R >>\nstartxref\n\{xref}\n%%EOF\n",
  )
  @utf8.encode(output.to_string())
}

///|
test "compiled pages serve selection while SVG requests upgrade their cached model" {
  ignore(open_pdf(cache_test_pdf(type3=true)))
  let compact = @json.parse(
    render_page(1, 1.0, 0, omit_svg=true, compiled_canvas=true),
  )
  assert_true(
    compact is { "ok": True, "canvas": { "version": Number(2), .. }, .. },
  )
  assert_true(page_cache[1].canvas_program is Some(_))
  let bytes = page_cache_bytes.val
  let selection = @json.parse(select_page_text(1, -1, -1, -1, -1))
  assert_true(selection is { "ok": True, .. })
  assert_true(page_cache[1].canvas_program is Some(_))
  assert_eq(page_cache_bytes.val, bytes)
  let original = @json.parse(render_page(1, 1.0, 0))
  assert_true(
    original is { "ok": True, "canvas": { "version": Number(1), .. }, .. },
  )
  assert_true(page_cache[1].canvas_program is None)
  assert_eq(page_cache_bytes.val, page_cache[1].bytes)
  assert_eq(selection, @json.parse(select_page_text(1, -1, -1, -1, -1)))
  ignore(close_pdf())
  ignore(open_pdf(cache_test_pdf(type3=true)))
  let legacy = @json.parse(render_page(1, 1.0, 0, omit_svg=true))
  assert_true(
    legacy is { "ok": True, "canvas": { "version": Number(1), .. }, .. },
  )
  ignore(close_pdf())
}

///|
fn cache_test_accessibility(result : String) -> Json raise {
  let result = @json.parse(result)
  guard result is { "ok": True, "accessibility": value, .. } else {
    fail("Tagged page must render successfully")
  }
  assert_true(value is { "tagged": True, .. })
  value
}

///|
test "tagged semantic manifests survive zoom and rotation with their cached page" {
  ignore(open_pdf(cache_test_pdf()))
  let first = cache_test_accessibility(
    render_page(1, 1.0, 0, omit_svg=true, compiled_canvas=true),
  )
  assert_eq(accessibility_cache_misses.val, 1)
  assert_eq(accessibility_cache_hits.val, 0)
  assert_eq(
    cache_test_accessibility(
      render_page(1, 2.0, 90, omit_svg=true, compiled_canvas=true),
    ),
    first,
  )
  assert_eq(accessibility_cache_misses.val, 1)
  assert_eq(accessibility_cache_hits.val, 1)
  assert_true(page_cache[1].accessibility_bytes > 0)
  assert_true(page_cache_bytes.val <= 32 * 1024 * 1024)
  ignore(close_pdf())
  assert_eq(page_cache.length(), 0)
  assert_eq(page_cache_bytes.val, 0)
}

///|
test "layer font and editor changes invalidate cached semantic text" {
  ignore(open_pdf(cache_test_pdf()))
  let before = cache_test_accessibility(
    render_page(1, 1.0, 0, omit_svg=true, compiled_canvas=true),
  )
  assert_true(
    @json.parse(set_optional_content_visibility(9, false)) is { "ok": True, .. },
  )
  assert_eq(page_cache.length(), 0)
  let hidden = cache_test_accessibility(
    render_page(1, 1.0, 0, omit_svg=true, compiled_canvas=true),
  )
  assert_true(before != hidden)
  assert_eq(accessibility_cache_misses.val, 1)
  assert_true(@json.parse(set_font_fallbacks("[]")) is { "ok": True, .. })
  assert_eq(page_cache.length(), 0)
  assert_eq(
    cache_test_accessibility(
      render_page(1, 1.0, 0, omit_svg=true, compiled_canvas=true),
    ),
    hidden,
  )
  assert_true(@json.parse(apply_edits("{}")) is { "ok": False, .. })
  assert_true(page_cache[1].accessibility is Some(_))
  assert_true(@json.parse(apply_edits("[]")) is { "ok": True, .. })
  assert_eq(page_cache.length(), 0)
  assert_eq(
    cache_test_accessibility(
      render_page(1, 1.0, 0, omit_svg=true, compiled_canvas=true),
    ),
    hidden,
  )
  ignore(close_pdf())
}

///|
test "semantic hydration invalidates only metadata and respects the shared budget" {
  ignore(open_pdf(cache_test_pdf()))
  let first = cache_test_accessibility(
    render_page(1, 1.0, 0, omit_svg=true, compiled_canvas=true),
  )
  let entry = page_cache[1]
  let bytes = page_cache_bytes.val
  browser_clear_page_accessibility()
  assert_eq(page_cache.length(), 1)
  assert_eq(page_cache[1].accessibility, None)
  assert_eq(page_cache_bytes.val, bytes - entry.accessibility_bytes)
  assert_eq(
    cache_test_accessibility(
      render_page(1, 1.0, 0, omit_svg=true, compiled_canvas=true),
    ),
    first,
  )
  assert_eq(page_cache_bytes.val, bytes)
  browser_clear_page_accessibility()
  page_cache_bytes.val = 32 * 1024 * 1024
  assert_eq(
    cache_test_accessibility(
      render_page(1, 1.0, 0, omit_svg=true, compiled_canvas=true),
    ),
    first,
  )
  assert_eq(page_cache[1].accessibility, None)
  assert_eq(page_cache_bytes.val, 32 * 1024 * 1024)
  ignore(close_pdf())
}

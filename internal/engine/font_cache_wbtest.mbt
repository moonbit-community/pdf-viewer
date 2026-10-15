///|
#cfg(target="js")
test "complete document shares parsed fonts across page builds and policy views" {
  let viewer = type1_test_clip_document("")
  let cache = viewer.parsed_fonts.unwrap()
  let first_context = pdf_resource_build_context(parsed_fonts=Some(cache))
  let first = pdf_read_font_for_viewer(
    viewer.document,
    @syntax.PdfIndirect(5),
    resource_context=Some(first_context),
  )
  let second_context = pdf_resource_build_context(parsed_fonts=Some(cache))
  let second = pdf_read_font_for_viewer(
    viewer.document,
    @syntax.PdfIndirect(5),
    resource_context=Some(second_context),
  )
  assert_true(font_recovery_same_instance(first, second))
  let before = viewer.page(1).unwrap()
  let prepared = prepare_canvas_page(viewer, 1).unwrap().0
  assert_eq(prepared.text_content(), before.text_content())
  assert_eq(cache.fonts.length(), 1)
  assert_true(cache.bytes > 0 && cache.bytes <= 0x800000)
  let policy = viewer.with_font_fallbacks([])
  let policy_font = pdf_read_font_for_viewer(
    policy.document,
    @syntax.PdfIndirect(5),
    resource_context=Some(
      pdf_resource_build_context(parsed_fonts=policy.parsed_fonts),
    ),
  )
  assert_true(font_recovery_same_instance(first, policy_font))
  let edited = viewer.with_editor_changes([])
  assert_eq(edited.parsed_fonts.unwrap().fonts.length(), 0)
  let edited_font = pdf_read_font_for_viewer(
    edited.document,
    @syntax.PdfIndirect(5),
    resource_context=Some(
      pdf_resource_build_context(parsed_fonts=edited.parsed_fonts),
    ),
  )
  assert_true(!font_recovery_same_instance(first, edited_font))
  let reopened = type1_test_clip_document("")
  assert_eq(reopened.parsed_fonts.unwrap().fonts.length(), 0)
  assert_eq(cache.fonts.length(), 1)
}

///|
test "parsed font admission bounds retained entries and metadata bytes" {
  let viewer = type1_test_clip_document("")
  let font = pdf_read_font_for_viewer(viewer.document, @syntax.PdfIndirect(5))
  let cache = pdf_parsed_font_cache()
  for number in 0..<129 {
    cache.retain(number, font)
  }
  assert_eq(cache.fonts.length(), 128)
  assert_true(!cache.fonts.contains(128))
  assert_eq(cache.bytes, 128 * pdf_parsed_font_bytes(font))
  let full = pdf_parsed_font_cache()
  full.bytes = 0x800000
  full.retain(5, font)
  assert_eq(full.fonts.length(), 0)
  assert_eq(full.bytes, 0x800000)
  let oversized = match font {
    @pdflite.PdfFontSimple(simple) =>
      @pdflite.PdfFontSimple({ ..simple, widths: Array::make(1048576, 0), })
    _ => abort("Expected simple font fixture")
  }
  let empty = pdf_parsed_font_cache()
  empty.retain(5, oversized)
  assert_eq(empty.fonts.length(), 0)
  assert_eq(empty.bytes, 0)
}

///|
test "missing dictionaries and direct fonts are not retained across builds" {
  let viewer = type1_test_clip_document("")
  let cache = viewer.parsed_fonts.unwrap()
  let context = pdf_resource_build_context(parsed_fonts=Some(cache))
  let _ = pdf_read_font_for_viewer(
    viewer.document,
    @syntax.PdfIndirect(999),
    resource_context=Some(context),
  )
  assert_eq(cache.fonts.length(), 0)
  let object = viewer.document.direct(@syntax.PdfIndirect(5))
  let _ = pdf_read_font_for_viewer(
    viewer.document,
    object,
    resource_context=Some(context),
  )
  assert_eq(cache.fonts.length(), 0)
}

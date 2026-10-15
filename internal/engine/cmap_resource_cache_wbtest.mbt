///|
fn cmap_cache_test_stream(
  body : Bytes,
  parent? : Int? = None,
) -> @syntax.PdfObject raise @core.PdfError {
  let mut dictionary = @syntax.PdfDictionary([
    (pdf_name_key("/Length"), @syntax.PdfInteger(body.length())),
  ])
  if parent is Some(number) {
    dictionary = dictionary.add_dict_entry(
      pdf_name_key("/UseCMap"),
      @syntax.PdfIndirect(number),
    )
  }
  @syntax.pdf_stream(dictionary, @syntax.StreamGot(body))
}

///|
test "resolved CMaps share a document owner while preserving inheritance overrides" {
  let document = @pdflite.pdf_document_empty()
  document.add_object_given_number(
    1,
    cmap_cache_test_stream(b"1 begincidchar <41> 1 endcidchar"),
  )
  document.add_object_given_number(
    2,
    cmap_cache_test_stream(b"1 begincidchar <41> 2 endcidchar", parent=Some(1)),
  )
  let cache = pdf_parsed_font_cache()
  let first = pdf_resource_build_context(parsed_fonts=Some(cache))
  let base = pdf_viewer_cmap_recovery_for_resource(
    document,
    @syntax.PdfIndirect(1),
    Some(first),
  ).unwrap()
  assert_eq(pdf_viewer_cmap_lookup(base.cid_entries[:], 65), Some(1))
  let derived = pdf_viewer_cmap_recovery_for_resource(
    document,
    @syntax.PdfIndirect(2),
    Some(first),
  ).unwrap()
  assert_eq(pdf_viewer_cmap_lookup(derived.cid_entries[:], 65), Some(2))
  assert_eq(cache.cmaps.length(), 2)
  let bytes = cache.bytes
  let second = pdf_resource_build_context(parsed_fonts=Some(cache))
  let reused = pdf_viewer_cmap_recovery_for_resource(
    document,
    @syntax.PdfIndirect(2),
    Some(second),
  ).unwrap()
  assert_eq(pdf_viewer_cmap_lookup(reused.cid_entries[:], 65), Some(2))
  assert_eq(cache.bytes, bytes)
  assert_eq(second.cmap_cache.length(), 0)
  // A separate document with the same object number resolves independently.
  let other = @pdflite.pdf_document_empty()
  other.add_object_given_number(
    2,
    cmap_cache_test_stream(b"1 begincidchar <41> 9 endcidchar"),
  )
  let isolated = pdf_viewer_cmap_recovery_for_resource(
    other,
    @syntax.PdfIndirect(2),
    Some(pdf_resource_build_context(parsed_fonts=Some(pdf_parsed_font_cache()))),
  ).unwrap()
  assert_eq(pdf_viewer_cmap_lookup(isolated.cid_entries[:], 65), Some(9))
}

///|
test "missing CMap sources can be hydrated without retaining an unavailable result" {
  let document = @pdflite.pdf_document_empty()
  let context = pdf_resource_build_context()
  let missing = pdf_viewer_cmap_recovery_for_resource(
    document,
    @syntax.PdfIndirect(1),
    Some(context),
  ).unwrap()
  assert_true(missing.diagnostics.source_unavailable)
  assert_eq(context.cmap_cache.length(), 0)
  document.add_object_given_number(
    1,
    cmap_cache_test_stream(b"1 begincidchar <41> 7 endcidchar"),
  )
  let loaded = pdf_viewer_cmap_recovery_for_resource(
    document,
    @syntax.PdfIndirect(1),
    Some(context),
  ).unwrap()
  assert_eq(pdf_viewer_cmap_lookup(loaded.cid_entries[:], 65), Some(7))
  assert_eq(context.cmap_cache.length(), 1)
  assert_true(context.cmap_cache_bytes > 0)
}

///|
test "cyclic CMap roots retain distinct override order and cycle diagnostics" {
  let document = @pdflite.pdf_document_empty()
  document.add_object_given_number(
    1,
    cmap_cache_test_stream(b"1 begincidchar <41> 1 endcidchar", parent=Some(2)),
  )
  document.add_object_given_number(
    2,
    cmap_cache_test_stream(b"1 begincidchar <41> 2 endcidchar", parent=Some(1)),
  )
  let cache = pdf_parsed_font_cache()
  let context = pdf_resource_build_context(parsed_fonts=Some(cache))
  for number in [1, 2, 1] {
    let cmap = pdf_viewer_cmap_recovery_for_resource(
      document,
      @syntax.PdfIndirect(number),
      Some(context),
    ).unwrap()
    assert_true(cmap.diagnostics.usecmap_cycle)
    assert_eq(pdf_viewer_cmap_lookup(cmap.cid_entries[:], 65), Some(number))
  }
  assert_eq(cache.cmaps.length(), 0)
  assert_eq(context.cmap_cache.length(), 0)
}

///|
test "full shared and page CMap budgets keep parsing without retaining more" {
  let document = @pdflite.pdf_document_empty()
  document.add_object_given_number(
    1,
    cmap_cache_test_stream(b"1 begincidchar <41> 7 endcidchar"),
  )
  let cache = pdf_parsed_font_cache()
  cache.bytes = 0x800000
  let context = pdf_resource_build_context(parsed_fonts=Some(cache))
  context.cmap_cache_bytes = 0x200000
  let cmap = pdf_viewer_cmap_recovery_for_resource(
    document,
    @syntax.PdfIndirect(1),
    Some(context),
  ).unwrap()
  assert_eq(pdf_viewer_cmap_lookup(cmap.cid_entries[:], 65), Some(7))
  assert_eq(cache.cmaps.length(), 0)
  assert_eq(cache.bytes, 0x800000)
  assert_eq(context.cmap_cache.length(), 0)
  assert_eq(context.cmap_cache_bytes, 0x200000)
}

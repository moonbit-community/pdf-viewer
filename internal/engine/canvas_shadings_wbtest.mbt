///|
test "Prepared shading resources share tables while preserving invocation geometry" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 4 0 R /Resources << /Shading << /S 5 0 R >> >> >>",
    annotation_test_stream("", "q /S sh Q q 2 0 0 3 7 9 cm /S sh Q"),
    shading_cache_test_rgb,
  ])
  let (page, program) = prepare_canvas_page(document, 1).unwrap()
  assert_eq(program.shading_resources.length(), 1)
  assert_eq(program.shadings.length(), 2)
  assert_eq(program.shading_bytes, program.shading_resources[0].bytes)
  assert_true(program.estimated_bytes() >= program.shading_bytes)
  let original = document.page(1).unwrap()
  assert_eq(page.text_layer(), original.text_layer())
  let compact = program.canvas_plan(page, 1.0, 0)
  assert_true(
    compact is { "version": Number(2), "shading_resources": Array([_]), .. },
  )
  for index, entry in page.items {
    guard entry is Shading(item) else { fail("Expected shading") }
    let shading = item.shading.unwrap()
    guard original.items[index] is Shading(legacy_item) else {
      fail("Expected legacy shading")
    }
    let legacy = legacy_item.shading.unwrap()
    assert_eq(shading.raster, None)
    assert_eq(shading.matrix, legacy.matrix)
    assert_eq(shading.coords, legacy.coords)
    assert_eq(
      program.shading_resources[program.shadings[item.index]].raster,
      legacy.raster.unwrap(),
    )
  }
  guard original.items[0] is Shading(first) else {
    fail("Expected first shading")
  }
  let raster = first.shading.unwrap().raster.unwrap()
  raster.tree[0] = 999.0
  assert_true(program.shading_resources[0].raster.tree[0] != 999.0)
}

///|
test "Prepared shading identity includes raster metadata and respects both budgets" {
  let document = shading_cache_test_document([shading_cache_test_rgb])
  let shading = pdf_shading_resource_of_object(
    document,
    "/S",
    @syntax.PdfIndirect(5),
  )
  let raster = shading.raster.unwrap()
  let program = pdf_canvas_program()
  assert_eq(pdf_canvas_shading_resource(shading, 0, program).raster, None)
  let moved = {
    ..shading,
    name: "/Other",
    matrix: [2.0, 0.0, 0.0, 3.0, 7.0, 9.0],
    coords: [10.0, 20.0, 80.0, 20.0],
  }
  assert_eq(pdf_canvas_shading_resource(moved, 1, program).raster, None)
  assert_eq(program.shading_resources.length(), 1)
  for index in 1..<64 {
    let variant = {
      ..shading,
      raster: Some({ ..raster, bbox: [index.to_double(), 0.0, 100.0, 100.0], }),
    }
    assert_eq(
      pdf_canvas_shading_resource(variant, index + 1, program).raster,
      None,
    )
  }
  assert_eq(program.shading_resources.length(), 64)
  let different = {
    ..shading,
    raster: Some({ ..raster, background: Some("#112233"), }),
  }
  assert_eq(pdf_canvas_shading_resource(different, 100, program), different)
  assert_eq(pdf_canvas_shading_resource(shading, 101, program).raster, None)
  let capped = pdf_canvas_program()
  capped.shading_bytes = 8388608
  assert_eq(pdf_canvas_shading_resource(shading, 0, capped), shading)
  assert_eq(capped.shading_resources.length(), 0)
  for
    fallback in [
      { ..shading, kind: "mesh", },
      { ..shading, raster: None, },
      {
        ..shading,
        raster: Some({ ..raster, error: Some("Unsupported shading"), }),
      },
    ] {
    let empty = pdf_canvas_program()
    assert_eq(pdf_canvas_shading_resource(fallback, 0, empty), fallback)
    assert_eq(empty.shading_resources.length(), 0)
  }
}

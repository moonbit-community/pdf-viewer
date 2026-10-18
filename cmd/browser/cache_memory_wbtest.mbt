///|
test "Model cache sizing follows retained ownership without JSON projection" {
  assert_true(@json.parse(open_pdf(cache_test_pdf())) is { "ok": True, .. })
  let page = current_document.val.unwrap().page(1).unwrap()
  let budget = 32 * 1024 * 1024
  let size = browser_model_cache_size(page, budget)
  assert_true(size > 0 && size < budget)
  assert_eq(browser_model_cache_size(page, 1), 2)
  let large = { ..page, text: "A".repeat(100000), }
  assert_true(browser_model_cache_size(large, budget) >= size + 399000)
  let shared = { ..page, items: [..page.items, ..page.items], }
  let shared_size = browser_model_cache_size(shared, budget)
  assert_true(shared_size > size && shared_size < size * 2)
  let oversized = { ..page, text: "A".repeat(8388608), }
  assert_eq(browser_model_cache_size(oversized, budget), budget + 1)
  ignore(close_pdf())
}

///|
test "typed geometry cache charges exactly match the complete ownership walk" {
  for type3 in [false, true] {
    ignore(open_pdf(cache_test_pdf(type3~)))
    let page = current_document.val.unwrap().page(1).unwrap()
    let text = [
        for item in page.items if item is @pdf.PdfPageItem::Text(text) => text
      ][0]
    let shared_point = {
      ..text,
      quad: {
        p0: text.quad.p0,
        p1: text.quad.p0,
        p2: text.quad.p0,
        p3: text.quad.p0,
      },
    }
    let models = [
      page,
      { ..page, items: [..page.items, ..page.items], },
      {
        ..page,
        items: [
          @pdf.PdfPageItem::Text(shared_point),
          @pdf.PdfPageItem::Text(shared_point),
        ],
      },
      { ..page, items: [], },
      { ..page, text: "A".repeat(100000), },
    ]
    for model in models {
      let size = browser_model_cache_size(
        model,
        32 * 1024 * 1024,
        geometry=false,
      )
      for
        budget in [0, 1, 128, 1024, size - 1, size, size + 1, 32 * 1024 * 1024] {
        assert_eq(
          browser_model_cache_size(model, budget),
          browser_model_cache_size(model, budget, geometry=false),
        )
      }
    }
    ignore(close_pdf())
  }
}

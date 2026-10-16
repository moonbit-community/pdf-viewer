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

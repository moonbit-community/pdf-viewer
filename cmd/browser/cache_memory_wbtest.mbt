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

///|
// Keep the previous ownership walker as an independent byte-charge oracle.
extern "js" fn browser_model_cache_legacy_walk(
  counter : BrowserCacheCounter,
  page : @pdf.PdfPageModel,
) -> Int =
  #| (counter, page) => {
  #|   const seen = counter.seen, pending = [page], budget = counter.budget;
  #|   let bytes = counter.bytes;
  #|   const add = value => {
  #|     if (typeof value === 'string') bytes += 64 + value.length * 4;
  #|     else if (value !== null && typeof value === 'object') pending.push(value);
  #|     else if (typeof value === 'function') bytes = budget + 1;
  #|     else bytes += 16;
  #|   };
  #|   while (pending.length && bytes <= budget) {
  #|     const value = pending.pop();
  #|     if (seen.has(value)) continue;
  #|     seen.add(value);
  #|     bytes += 128;
  #|     if (ArrayBuffer.isView(value)) bytes += value.byteLength * 2;
  #|     else if (value instanceof ArrayBuffer) bytes += value.byteLength * 2;
  #|     else if (Array.isArray(value)) {
  #|       bytes += value.length * 16;
  #|       if (bytes > budget) break;
  #|       for (let i = 0; i < value.length && bytes <= budget; i++) add(value[i]);
  #|     } else if (value instanceof WeakMap || value instanceof WeakSet) {
  #|       return budget + 1;
  #|     } else if (value instanceof Map || value instanceof Set) {
  #|       bytes += value.size * 64;
  #|       if (bytes > budget) break;
  #|       if (value instanceof Map) for (const [key, item] of value) { add(key); add(item); }
  #|       else for (const item of value) add(item);
  #|     } else {
  #|       for (const key in value) if (Object.hasOwn(value, key)) {
  #|         bytes += 32;
  #|         add(value[key]);
  #|         if (bytes > budget) break;
  #|       }
  #|     }
  #|     if (pending.length > 131072) return budget + 1;
  #|   }
  #|   return Math.min(bytes, budget + 1);
  #| }

///|
test "own-key cache traversal preserves complete ownership charges" {
  for type3 in [false, true] {
    ignore(open_pdf(cache_test_pdf(type3~)))
    let page = current_document.val.unwrap().page(1).unwrap()
    let models = [
      page,
      { ..page, items: [..page.items, ..page.items], },
      { ..page, items: [], },
      { ..page, text: "A".repeat(100000), },
    ]
    for model in models {
      let budget = 32 * 1024 * 1024
      let size = browser_model_cache_legacy_walk(
        browser_cache_counter(budget),
        model,
      )
      for limit in [0, 1, 128, 1024, size - 1, size, size + 1, budget] {
        assert_eq(
          browser_model_cache_size(model, limit),
          browser_model_cache_legacy_walk(browser_cache_counter(limit), model),
        )
      }
    }
    ignore(close_pdf())
  }
}

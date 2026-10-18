///|
extern "js" fn browser_page_test_json(value : BrowserPageData) -> String =
  #| value => value.json

///|
test "Native page metadata preserves JSON values and special object keys" {
  let fields : Map[String, Json] = Map([
    ("__proto__", { "constructor": "value" }),
    ("control", Json::string("\u0000\n\t\"\\中文😀")),
    ("numbers", [0, -0.0, 1.0e-100, 1.0e100, 9007199254740991.0]),
    ("values", [true, false, null, [], {}]),
  ])
  let value = Json::object(fields)
  let native = browser_page_value(value).unwrap()
  assert_eq(@json.parse(browser_page_stringify(native)), value)
  assert_true(
    browser_page_value(Json::number(1.0, repr="1.0000000000000001")) is None,
  )
  assert_true(browser_page_value(@json.parse("1e1000")) is None)
  let mut deep : Json = null
  for _ in 0..<140 {
    deep = [deep]
  }
  assert_true(browser_page_value(deep) is None)
  assert_eq(@json.parse(deep.stringify()), deep)
}

///|
test "Metadata conversion keeps depth boundaries and local fallback state" {
  let mut boundary : Json = null
  for _ in 0..<127 {
    boundary = [boundary]
  }
  assert_eq(
    @json.parse(browser_page_stringify(browser_page_value(boundary).unwrap())),
    boundary,
  )
  assert_true(browser_page_value(Json::array([boundary])) is None)
  for
    invalid in [
      Json::number(1.0, repr="1.0000000000000001"),
      @json.parse("1e1000"),
      Json::number(0.0 / 0.0),
      Json::number(1.0 / 0.0),
    ] {
    assert_true(
      browser_page_value({ "nested": [null, { "value": invalid }] }) is None,
    )
    let supported : Json = { "nested": [null, { "value": true }], "tail": [] }
    assert_eq(
      @json.parse(
        browser_page_stringify(browser_page_value(supported).unwrap()),
      ),
      supported,
    )
  }
}

///|
extern "js" fn browser_page_test_numbers(packet : BrowserPageData) -> String =
  #| packet => JSON.stringify(Array.from(new Float64Array(packet.buffers[0])))

///|
test "Packed text geometry retains row order styles and fallback ownership" {
  ignore(open_pdf(cache_test_pdf()))
  let layer = current_document.val.unwrap().page(1).unwrap().text_layer()
  let first = {
    ..layer.items[0],
    item_index: 7,
    text: "fi😀",
    separator: "\n",
    quad: {
      p0: { x: 1.0, y: 2.0, },
      p1: { x: 3.0, y: 4.0, },
      p2: { x: 5.0, y: 6.0, },
      p3: { x: 7.0, y: 8.0, },
    },
    matrix: [9.0, 10.0, 11.0, 12.0, 13.0, 14.0],
  }
  let second = { ..first, item_index: 8, text: "B", font_style: "italic", }
  let packed = { ..layer, items: [first, second, first], }
  let buffers = browser_page_buffers()
  let metadata = browser_page_layer(packed, Some(buffers))
  assert_true(
    metadata
    is {
      "version": Number(2, ..),
      "draws": { "__pdf_numbers": Number(0, ..), .. },
      "text": [String("fi😀"), String("B"), String("fi😀")],
      "separators": [String("\n"), String("\n"), String("\n")],
      "styles": [_, { "font_style": String("italic"), .. }],
      ..
    },
  )
  let packet = browser_page_finish(metadata.stringify(), buffers)
  assert_eq(@json.parse(browser_page_test_numbers(packet)), [
    7, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 8, 1, 1, 2, 3, 4, 5, 6,
    7, 8, 9, 10, 11, 12, 13, 14, 7, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13,
    14,
  ])
  for
    invalid in [
      { ..first, matrix: [1.0, 2.0, 3.0], },
      { ..first, matrix: [0.0 / 0.0, 0.0, 0.0, 1.0, 0.0, 0.0], },
    ] {
    let invalid = { ..layer, items: [first, invalid], }
    let buffers = browser_page_buffers()
    assert_eq(
      browser_page_layer(invalid, Some(buffers)),
      ToJson::to_json(invalid),
    )
    let packet = browser_page_finish("null", buffers)
    assert_eq(browser_page_test_numbers(packet), "[]")
  }
  ignore(close_pdf())
}

///|
test "Page packet errors preserve the established bridge result" {
  close_pdf()
  for (scale, rotation) in [(0.0, 0), (1.0, 1), (1.0, 0)] {
    let legacy = @json.parse(
      render_page(
        1,
        scale,
        rotation,
        omit_svg=true,
        compiled_canvas=true,
        text_runs=true,
      ),
    )
    let packet = render_page_data(1, scale, rotation)
    assert_eq(@json.parse(browser_page_test_json(packet)), legacy)
  }
}

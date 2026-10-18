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

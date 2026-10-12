///|
let width_cache : Map[String, Double] = Map([])

///|
let width_order : Array[String] = []

///|
fn measure_width(
  text : String,
  family : String,
  weight : String,
  style : String,
) -> Double {
  let key = "\{family}\n\{weight}\n\{style}\n\{text}"
  if width_cache.get(key) is Some(width) {
    return width
  }
  let width = native_measure(text, family, weight, style)
  width_cache[key] = width
  width_order.push(key)
  if width_cache.length() > 4096 {
    ignore(width_cache.remove(width_order.remove(0)))
  }
  width
}

///|
fn clear_width_cache() -> Unit {
  width_cache.clear()
  width_order.clear()
}

///|
fn make_text_layer(layer : @js.Value) -> @dom.Element {
  let node = make_element("div", class_name="text-layer")
  set_data(node, "page", value_int(layer, "page").to_string())
  for item in value_array(value_field(layer, "items")) {
    let matrix = value_numbers(value_field(item, "matrix"))
    let separator = value_string(item, "separator")
    let index = value_int(item, "item_index")
    if separator != "" {
      let tag = if separator == "\n" { "br" } else { "span" }
      let before = make_element(tag, class_name="separator")
      set_data(before, "beforeItem", index.to_string())
      if separator != "\n" {
        set_text(before, separator)
      }
      set_style(before, "left", "\{matrix[4]}px")
      set_style(before, "top", "\{matrix[5]}px")
      set_style(
        before,
        "transform",
        "matrix(\{matrix[0]},\{matrix[1]},\{matrix[2]},\{matrix[3]},0,0)",
      )
      append_element(node, before)
    }
    let glyph = make_element("span", class_name="glyph")
    set_data(glyph, "item", index.to_string())
    set_data(glyph, "vertical", value_bool(item, "vertical").to_string())
    let (a, b, c, d) = (matrix[0], matrix[1], matrix[2], matrix[3])
    let width = (a * a + b * b).sqrt().max(0.001)
    let height = (c * c + d * d).sqrt().max(0.001)
    set_style(glyph, "left", "\{matrix[4]}px")
    set_style(glyph, "top", "\{matrix[5]}px")
    set_style(glyph, "width", "\{width}px")
    set_style(glyph, "height", "\{height}px")
    set_style(glyph, "fontSize", "\{height}px")
    set_style(glyph, "lineHeight", "\{height}px")
    set_style(
      glyph,
      "transform",
      "matrix(\{a / width},\{b / width},\{c / height},\{d / height},0,0)",
    )
    let family = value_string(item, "font_family")
    let weight = value_string(item, "font_weight")
    let font_style = value_string(item, "font_style")
    set_style(glyph, "fontFamily", family)
    set_style(glyph, "fontWeight", weight)
    set_style(glyph, "fontStyle", font_style)
    let text = value_string(item, "text")
    let content = make_element("span", class_name="glyph-text")
    set_text(content, text)
    let measured = measure_width(text, family, weight, font_style) * height
    set_style(content, "height", "\{height}px")
    set_style(content, "lineHeight", "\{height}px")
    set_style(content, "width", "\{measured}px")
    set_style(content, "transform", "scaleX(\{width / measured})")
    append_element(glyph, content)
    append_element(node, glyph)
  }
  node
}

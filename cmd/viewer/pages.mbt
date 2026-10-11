///|
let width_cache : Map[String, Double] = Map([])

///|
let width_order : Array[String] = []

///|
fn make_element(tag : String, class_name? : String = "") -> @dom.Element {
  let node = @dom.document().create_element(tag)
  if class_name != "" {
    node.set_attribute("class", class_name)
  }
  node
}

///|
fn page_element(number : Int) -> @dom.Element? {
  element("pages").query_selector("[data-page=\"\{number}\"]")
}

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

///|
async fn mount_page(result : @js.Value, current : () -> Bool) -> @dom.Element {
  let page = make_element("section", class_name="page")
  let number = value_int(result, "page")
  set_data(page, "page", number.to_string())
  page.set_attribute("aria-label", "第 \{number} 页")
  let viewport = value_field(value_field(result, "layer"), "viewport")
  set_style(page, "width", "\{value_number(viewport, "width")}px")
  set_style(page, "height", "\{value_number(viewport, "height")}px")
  if value_bool(result, "xfa") {
    append_element(page, create_xfa(result, "display").wait())
    set_data(page, "xfa", "true")
    return page
  }
  let paint = make_element("div", class_name="paint-layer")
  paint.set_attribute("aria-hidden", "true")
  paint.set_property("inert", @js.Value::cast_from(true))
  let canvas = make_element("canvas")
  let rendered = paint_canvas(canvas, result, output_scale()).wait()
  if current() {
    report_diagnostics(value_field(rendered, "diagnostics"))
  }
  append_element(paint, canvas)
  let text = make_text_layer(value_field(result, "layer"))
  let annotations = annotation_layer(state.annotations.unwrap(), result)
  let accessibility = accessibility_layer(result, annotations).to_option()
  if accessibility is Some(_) {
    text.set_attribute("aria-hidden", "true")
  }
  append_element(page, paint)
  append_element(page, text)
  append_element(page, annotations)
  append_element(page, editor_layer(result))
  if accessibility is Some(layer) {
    append_element(page, layer)
  }
  page
}

///|
async fn page_mounted(page : @dom.Element, current : () -> Bool) -> Unit {
  annotations_bind(state.annotations.unwrap(), page)
  native_fonts_ready().wait()
  if !current() {
    return
  }
  clear_width_cache()
  for glyph in page.query_selector_all(".glyph").iter() {
    let actual = measure_width(
        element_text(glyph),
        get_style(glyph, "fontFamily"),
        get_style(glyph, "fontWeight"),
        get_style(glyph, "fontStyle"),
      ) *
      parse_float(get_style(glyph, "fontSize"))
    if glyph.query_selector(".glyph-text") is Some(text) {
      set_style(text, "width", "\{actual}px")
      set_style(
        text,
        "transform",
        "scaleX(\{parse_float(get_style(glyph, "width")) / actual})",
      )
    }
  }
  highlight_search()
  if state.selection_range is Some(range) {
    restore_selection(range)
  }
}

///|
extern "js" fn parse_float(text : String) -> Double =
  #| text => parseFloat(text) || 0

///|
fn pinned_pages() -> FixedArray[Int] {
  let pins : Array[Int] = []
  if state.selection_range is Some(range) {
    for number in [range.start.page, range.end.page] {
      for page in (number - 1)..<=(number + 1) {
        if page >= 1 && page <= state.count {
          pins.push(page)
        }
      }
    }
  }
  FixedArray::from_array(pins[:])
}

///|
extern "js" fn create_scheduler(
  render : (Int, Double, Int, @js.Value) -> @js_async.Promise[@js.Value],
  mount : (@js.Value, () -> Bool) -> @js_async.Promise[@dom.Element],
  mounted : (@dom.Element, () -> Bool) -> @js_async.Promise[Unit],
  unload : (@dom.Element) -> Unit,
  error : (@js.Value) -> Unit,
  pinned : () -> FixedArray[Int],
  single : () -> Bool,
) -> @js.Value =
  #| (render,mount,onMount,onUnload,onError,pinned,singlePage) => globalThis.pdfViewerHost.createScheduler({viewer:document.getElementById("viewer"),pages:document.getElementById("pages"),render,mount,onMount,onUnload,onError,pinned,singlePage})

///|
extern "js" fn render_scheduled(
  number : Int,
  scale : Double,
  rotation : Int,
  options : @js.Value,
) -> @js_async.Promise[String] =
  #| (number,scale,rotation,options) => globalThis.pdfViewerHost.pdf.call("render_page",[number,scale,rotation],options)

///|
extern "js" fn scheduler_document(
  scheduler : @js.Value,
  layouts : @js.Value,
) -> Unit =
  #| (scheduler,layouts) => scheduler.setDocument(layouts)

///|
extern "js" fn scheduler_layout(
  scheduler : @js.Value,
  number : Int,
  scale : Double,
  rotation : Int,
) -> Unit =
  #| (scheduler,number,scale,rotation) => { scheduler.current=number; scheduler.layout(scale,rotation); }

///|
extern "js" fn scheduler_update(scheduler : @js.Value, number : Int) -> Unit =
  #| (scheduler,number) => scheduler.update(number)

///|
extern "js" fn scheduler_ensure(
  scheduler : @js.Value,
  number : Int,
) -> @js_async.Promise[@dom.Element] =
  #| (scheduler,number) => scheduler.ensure(number)

///|
extern "js" fn scheduler_clear(scheduler : @js.Value) -> Unit =
  #| scheduler => scheduler.clear()

///|
extern "js" fn scheduler_cancel(scheduler : @js.Value) -> Unit =
  #| scheduler => scheduler.cancel()

///|
fn show_native_error(error : @js.Value) -> Unit {
  if value_string(error, "name") == "AbortError" {
    return
  }
  let message = native_error_message(error)
  if message.contains("AbortError") || message.contains("cancelled") {
    return
  }
  state.error = message
  state.status = "未能完成操作"
  notify()
}

///|
extern "js" fn native_error_message(error : @js.Value) -> String =
  #| error => error?.message || String(error)

///|
fn initialize_pages() -> Unit {
  state.annotations = Some(
    create_annotations(
      element("viewer"),
      link => {
        ignore(@js_async.Promise::from_async(() => navigate_annotation(link)))
      },
      () => {
        native_source_url(
          if state.file_path != state.file_name {
            state.file_path
          } else {
            ""
          },
        )
      },
    ),
  )
  state.scheduler = Some(
    create_scheduler(
      (number, scale, rotation, options) => {
        @js_async.Promise::from_async(() => {
          checked(render_scheduled(number, scale, rotation, options).wait())
        })
      },
      (result, current) => {
        @js_async.Promise::from_async(() => mount_page(result, current))
      },
      (page, current) => {
        @js_async.Promise::from_async(() => page_mounted(page, current))
      },
      page => annotations_unmount(state.annotations.unwrap(), page),
      show_native_error,
      pinned_pages,
      () => state.view_mode == "page",
    ),
  )
}

///|
fn apply_view_mode() -> Unit {
  toggle_class(element("viewer"), "page-mode", state.view_mode == "page")
  for page in element("pages").get_children().iter() {
    toggle_class(
      page,
      "current-page",
      state.view_mode == "page" &&
      parse_float(element_data(page, "page")).to_int() == state.current_page,
    )
  }
}

///|
fn location_page() -> Int {
  let number = native_location_page()
  if number >= 1 && number <= state.count {
    number
  } else {
    1
  }
}

///|
fn go_to_page(number : Int, push? : Bool = false) -> Unit {
  if state.count == 0 {
    return
  }
  let number = number.max(1).min(state.count)
  state.current_page = number
  set_input_value("page-number", number.to_string())
  native_location_update(number, push)
  apply_view_mode()
  if state.view_mode != "page" && page_element(number) is Some(page) {
    page.scroll_into_view_with_options(block="start")
  }
  scheduler_update(state.scheduler.unwrap(), number)
  notify()
}

///|
async fn repaint(preserve? : Bool = true) -> Unit {
  if state.count == 0 {
    return
  }
  state.generation += 1
  let generation = state.generation
  let saved = if preserve { state.selection_range } else { None }
  let number = state.current_page
  let viewer = element("viewer")
  let padding = computed_number(viewer, "paddingTop")
  let offset = match page_element(number) {
    Some(page) =>
      (
        viewer.get_bounding_client_rect().get_top() +
        padding -
        page.get_bounding_client_rect().get_top()
      ) /
      offset_height(page).max(1.0)
    None => 0.0
  }
  set_busy(true)
  try {
    let scale = if state.zoom == "fit" {
      let layout = state.layouts[number - 1]
      let width = if state.rotation % 180 != 0 {
        layout.height
      } else {
        layout.width
      }
      ((viewer.get_client_width() - 64.0) / width).max(0.1).min(4.0)
    } else {
      parse_float(state.zoom)
    }
    state.scale = scale
    scheduler_layout(state.scheduler.unwrap(), number, scale, state.rotation)
    apply_view_mode()
    state.status = "正在渲染第 \{number} / \{state.count} 页"
    notify()
    let page = page_element(number).unwrap()
    let top = page.get_bounding_client_rect().get_top() -
      viewer.get_bounding_client_rect().get_top() +
      viewer.get_scroll_top()
    viewer.set_scroll_top(
      (top - padding + offset * offset_height(page)).max(0.0),
    )
    scheduler_update(state.scheduler.unwrap(), number)
    ignore(scheduler_ensure(state.scheduler.unwrap(), number).wait())
    if saved is Some(range) {
      ignore(
        scheduler_ensure(state.scheduler.unwrap(), range.start.page).wait(),
      )
      ignore(scheduler_ensure(state.scheduler.unwrap(), range.end.page).wait())
    }
    if generation != state.generation {
      return
    }
    if saved is Some(range) {
      restore_selection(range)
      if page_element(range.start.page) is Some(page) &&
        page.query_selector("[data-item=\"\{range.start.item}\"]")
        is Some(glyph) {
        glyph.scroll_into_view_with_options(block="nearest", inline="nearest")
      }
    } else {
      clear_selection()
    }
    highlight_search()
    apply_view_mode()
    state.status = "\{state.count} 页 · \{(state.scale * 100.0).round().to_int()}%"
    native_location_update(state.current_page, false)
    notify()
  } catch {
    error => if generation == state.generation { show_error(error) }
  }
  if generation == state.generation {
    set_busy(false)
  }
}

///|
async fn change_scale(factor : Double) -> Unit {
  state.zoom = (state.scale * factor).max(0.1).min(4.0).to_string()
  repaint()
}

///|
extern "js" fn map_point(
  viewport : @js.Value,
  x : Double,
  y : Double,
  inverse : Bool,
) -> FixedArray[Double] =
  #| (viewport,x,y,inverse) => { let matrix=new DOMMatrix(viewport.matrix); if(inverse) matrix=matrix.inverse(); const point=matrix.transformPoint({x,y}); return [point.x,point.y]; }

///|
fn annotation_viewport(page : @dom.Element) -> @js.Value {
  parse_value(
    element_data(page.query_selector(".annotation-layer").unwrap(), "viewport"),
  )
}

///|
async fn navigate_annotation(link : @js.Value) -> Unit {
  try {
    if value_string(link, "kind") == "named-action" {
      match value_string(link, "action") {
        "FirstPage" => go_to_page(1, push=true)
        "LastPage" => go_to_page(state.count, push=true)
        "NextPage" => go_to_page(state.current_page + 1, push=true)
        "PrevPage" => go_to_page(state.current_page - 1, push=true)
        "GoBack" => @dom.window().history_go_back()
        "GoForward" => @dom.window().history_go_forward()
        _ => ()
      }
      return
    }
    let destination = value_field(link, "destination")
    let number = value_int(destination, "page")
    if !value_bool(destination, "resolved") ||
      value_bool(destination, "remote") ||
      number < 1 ||
      number > state.count {
      return
    }
    let generation = state.document_generation
    clear_selection()
    go_to_page(number, push=true)
    let mut page = scheduler_ensure(state.scheduler.unwrap(), number).wait()
    if generation != state.document_generation {
      return
    }
    let mut viewport = annotation_viewport(page)
    let layout = state.layouts[number - 1]
    let width = if state.rotation % 180 != 0 {
      layout.height
    } else {
      layout.width
    }
    let height = if state.rotation % 180 != 0 {
      layout.width
    } else {
      layout.height
    }
    let viewer = element("viewer")
    let fit_width = (viewer.get_client_width() - 64.0).max(1.0)
    let fit_height = (viewer.get_client_height() - 64.0).max(1.0)
    let kind = value_string(destination, "kind")
    let mut scale = state.scale
    match kind {
      "XYZ" =>
        if value_number(destination, "zoom") > 0.0 {
          scale = value_number(destination, "zoom")
        }
      "FitH" | "FitBH" => scale = fit_width / width
      "FitV" | "FitBV" => scale = fit_height / height
      "Fit" | "FitB" => scale = (fit_width / width).min(fit_height / height)
      "FitR" => {
        let first = map_point(
          viewport,
          value_number(destination, "left"),
          value_number(destination, "bottom"),
          false,
        )
        let last = map_point(
          viewport,
          value_number(destination, "right"),
          value_number(destination, "top"),
          false,
        )
        let w = (last[0] - first[0]).abs()
        let h = (last[1] - first[1]).abs()
        if w > 0.0 && h > 0.0 {
          scale *= (fit_width / w).min(fit_height / h)
        }
      }
      _ => ()
    }
    scale = scale.max(0.1).min(4.0)
    if scale != state.scale {
      state.zoom = scale.to_string()
      repaint(preserve=false)
      page = scheduler_ensure(state.scheduler.unwrap(), number).wait()
      if generation != state.document_generation {
        return
      }
      viewport = annotation_viewport(page)
    }
    let origin = map_point(viewport, 0.0, 0.0, true)
    let left = if value_field(destination, "left").is_null() {
      origin[0]
    } else {
      value_number(destination, "left")
    }
    let top = if value_field(destination, "top").is_null() {
      origin[1]
    } else {
      value_number(destination, "top")
    }
    let mut point = map_point(viewport, left, top, false)
    if kind == "FitR" {
      let first = map_point(
        viewport,
        left,
        value_number(destination, "bottom"),
        false,
      )
      let last = map_point(
        viewport,
        value_number(destination, "right"),
        top,
        false,
      )
      point = [first[0].min(last[0]), first[1].min(last[1])]
    }
    if ["XYZ", "FitH", "FitBH", "FitV", "FitBV", "FitR"].contains(kind) &&
      !point[0].is_nan() &&
      !point[0].is_inf() &&
      !point[1].is_nan() &&
      !point[1].is_inf() {
      let box = page.get_bounding_client_rect()
      let view = viewer.get_bounding_client_rect()
      viewer.set_scroll_top(
        viewer.get_scroll_top() +
        box.get_top() -
        view.get_top() -
        computed_number(viewer, "paddingTop") +
        point[1],
      )
      viewer.set_scroll_left(
        viewer.get_scroll_left() +
        box.get_left() -
        view.get_left() -
        computed_number(viewer, "paddingLeft") +
        point[0],
      )
    }
  } catch {
    error => show_error(error)
  }
}

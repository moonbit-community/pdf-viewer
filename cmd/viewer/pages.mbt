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
async fn mount_page(result : @js.Value, current : () -> Bool) -> @dom.Element {
  let page = make_element("section", class_name="page")
  let number = value_int(result, "page")
  set_data(page, "page", number.to_string())
  page.set_attribute("aria-label", "Page \{number}")
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
  append_element(paint, canvas)
  // Publish the output surface before painting. The renderer fills it tile by
  // tile; selection and annotation layers still wait for the completed page.
  if current() && page_element(number) is Some(placeholder) {
    append_element(placeholder, paint)
  }
  let rendered = paint_canvas(
    canvas,
    result,
    output_scale(),
    current=Some(current),
  ).wait() catch {
    error => {
      if paint.get_parent_element() is Some(parent) {
        parent.remove_child(paint.as_node())
      }
      raise error
    }
  }
  if current() {
    report_diagnostics(value_field(rendered, "diagnostics"))
  }
  let text = make_text_layer(value_field(result, "layer"))
  let annotations = annotation_layer(state.annotations.unwrap(), result)
  let accessibility = accessibility_layer(result, annotations).to_option()
  if accessibility is Some(_) {
    text.set_attribute("aria-hidden", "true")
  }
  append_element(page, paint)
  append_element(page, text)
  text.set_property("pdfTextLayer", value_field(result, "layer"))
  append_element(page, annotations)
  append_element(page, editor_layer(result))
  if accessibility is Some(layer) {
    append_element(page, layer)
  }
  page
}

///|
async fn page_mounted(page : @dom.Element, current : () -> Bool) -> Unit {
  if current() && state.xfa {
    editor_refresh_xfa_fields()
  }
  if current() && page.query_selector(".text-layer") is Some(text) {
    cache_selection_page(
      value_field(@js.Value::cast_from(text), "pdfTextLayer"),
    )
  }
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
  if state.selection_range is Some(range) &&
    (state.selection_restore || native_selection_range().to_option() is None) {
    restore_selection(range)
  }
}

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
  #| (number,scale,rotation,options) => globalThis.pdfViewerHost.pdf.call("render_page",[number,scale,rotation,true],options)

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
  invalidate : Bool,
) -> Unit =
  #| (scheduler,number,scale,rotation,invalidate) => { scheduler.current=number; scheduler.layout(scale,rotation,{invalidate}); }

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
  show_error_message(native_error_message(error))
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
      page => {
        ignore(
          selection_pages.remove(
            parse_float(element_data(page, "page")).to_int(),
          ),
        )
        annotations_unmount(state.annotations.unwrap(), page)
      },
      show_native_error,
      pinned_pages,
      () => state.view_mode == "page",
    ),
  )
}

///|
async fn repaint(preserve? : Bool = true, invalidate? : Bool = false) -> Unit {
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
    scheduler_layout(
      state.scheduler.unwrap(),
      number,
      scale,
      state.rotation,
      invalidate,
    )
    apply_view_mode()
    state.status = RenderingPage(number)
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
    state.status = DocumentLoaded
    native_location_update(state.current_page, false)
    notify()
  } catch {
    error => if generation == state.generation { show_error(error) }
  }
  if generation == state.generation {
    if state.status is RenderingPage(_) {
      state.status = DocumentLoaded
    }
    set_busy(false)
  }
}

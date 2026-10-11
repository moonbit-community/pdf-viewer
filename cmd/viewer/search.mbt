///|
fn clear_search() -> Unit {
  abort(state.search_controller)
  state.search_generation += 1
  state.search_query = ""
  state.search_input = ""
  state.search_results = []
  state.search_active = -1
  set_input_value("search-query", "")
  highlight_search()
  dispatch_detail(
    "pdf-search-change",
    @js.Value::cast_from((@js.Nullable::null() : @js.Nullable[Unit])),
  )
  notify()
}

///|
fn highlight_search() -> Unit {
  let matches : Map[String, Bool] = Map([])
  for index, result in state.search_results {
    for item in result.items {
      let key = "\{result.page}:\{item}"
      matches[key] = matches.get(key).unwrap_or(false) ||
        index == state.search_active
    }
  }
  for glyph in element("pages").query_selector_all(".glyph, .xfa-text").iter() {
    let page = glyph.closest(".page").unwrap()
    let key = "\{element_data(page, "page")}:\{element_data(glyph, "item")}"
    toggle_class(glyph, "pdf-search-hit", matches.contains(key))
    toggle_class(glyph, "pdf-search-active", matches.get(key).unwrap_or(false))
  }
}

///|
async fn scroll_search() -> Unit {
  let active = state.search_active
  let generation = state.search_generation
  if state.search_results.get(active) is Some(result) {
    go_to_page(result.page)
    ignore(scheduler_ensure(state.scheduler.unwrap(), result.page).wait()) catch {
      error => {
        if active == state.search_active &&
          generation == state.search_generation {
          show_error(error)
        }
        return
      }
    }
    if active != state.search_active || generation != state.search_generation {
      return
    }
    if result.items.get(0) is Some(item) &&
      page_element(result.page) is Some(page) &&
      page.query_selector("[data-item=\"\{item}\"]") is Some(glyph) {
      glyph.scroll_into_view_with_options(block="center", inline="nearest")
    }
  }
}

///|
async fn jump_search(delta : Int) -> Unit {
  let count = state.search_results.length()
  if count == 0 {
    return
  }
  state.search_active = (state.search_active + delta + count) % count
  highlight_search()
  notify()
  scroll_search()
}

///|
extern "js" fn search_detail(query : String, results : @js.Value) -> @js.Value =
  #| (query,results) => ({query,results})

///|
async fn search_document() -> Unit {
  abort(state.search_controller)
  let controller = @js_async.AbortController::new()
  state.search_controller = Some(controller)
  state.search_generation += 1
  let generation = state.document_generation
  let query = input_value("search-query")
  state.search_case = input_checked("search-case")
  state.search_whole = input_checked("search-whole")
  state.search_diacritic = input_checked("search-diacritic")
  state.search_input = query
  if query == "" {
    clear_search()
    return
  }
  try {
    let response = call(
      "search_pdf",
      args=[
        @js.Value::cast_from(query),
        @js.Value::cast_from(state.search_case),
        @js.Value::cast_from(state.search_whole),
        @js.Value::cast_from(!state.search_diacritic),
      ],
      controller~,
      priority=20,
    )
    if controller_aborted(controller) || generation != state.document_generation {
      return
    }
    let values = value_field(response, "results")
    state.search_query = query
    state.search_results = value_array(values)
      .iter()
      .map(value => {
        page: value_int(value, "page"),
        items: value_array(value_field(value, "item_indices"))
        .iter()
        .map(value => @js.Value::cast(value))
        .collect(),
      })
      .collect()
    state.search_active = if state.search_results.is_empty() { -1 } else { 0 }
    highlight_search()
    notify()
    scroll_search()
    if controller_aborted(controller) || generation != state.document_generation {
      return
    }
    dispatch_detail("pdf-search-change", search_detail(query, values))
  } catch {
    error =>
      if !controller_aborted(controller) &&
        generation == state.document_generation {
        show_error(error)
      }
  }
}

///|
pub fn perform_search() -> @js_async.Promise[Unit] {
  @js_async.Promise::from_async(() => {
    search_document()
    flush_ui()
  })
}

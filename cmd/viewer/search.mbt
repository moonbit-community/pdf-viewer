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
  let ranges : Array[@js.Value] = []
  let active_ranges : Array[@js.Value] = []
  let glyphs = element("pages").query_selector_all(".glyph, .xfa-text")
  for index, result in state.search_results {
    for item in result.items {
      let key = "\{result.page}:\{item}"
      matches[key] = matches.get(key).unwrap_or(false) ||
        index == state.search_active
    }
    guard page_element(result.page) is Some(page) else { continue }
    for item in result.items {
      guard page.query_selector("[data-item=\"\{item}\"]") is Some(glyph) else {
        continue
      }
      let content = glyph.query_selector(".glyph-text").unwrap_or(glyph)
      let start = if result.xfa {
        0
      } else {
        parse_float(element_data(glyph, "sourceStart")).to_int()
      }
      let first = if result.xfa {
        result.start_offset
      } else {
        (result.index - start).max(0)
      }
      let last = if result.xfa {
        result.end_offset
      } else {
        (result.index + result.length - start).min(
          node_length(@js.Value::cast_from(content)),
        )
      }
      if last > first &&
        search_native_range(content, first, last).to_option() is Some(range) {
        ranges.push(range)
        if index == state.search_active {
          active_ranges.push(range)
        }
      }
    }
  }
  set_data(
    element("pages"),
    "searchRanges",
    search_publish_ranges(
      FixedArray::from_array(ranges[:]),
      FixedArray::from_array(active_ranges[:]),
    ).to_string(),
  )
  for glyph in glyphs.iter() {
    let page = glyph.closest(".page").unwrap()
    let key = "\{element_data(page, "page")}:\{element_data(glyph, "item")}"
    toggle_class(glyph, "pdf-search-hit", matches.contains(key))
    toggle_class(glyph, "pdf-search-active", matches.get(key).unwrap_or(false))
  }
}

///|
// Native ranges paint exact UTF-16 intervals without replacing text nodes or
// disturbing a user's selection. Search state and source mapping stay in MoonBit.
extern "js" fn search_native_range(
  content : @dom.Element,
  first : Int,
  last : Int,
) -> @js.Nullable[@js.Value] =
  #| (content,first,last) => {const text=content.firstChild;if(!text||text.nodeType!==3||first<0||last>text.length||last<=first)return null;const range=document.createRange();range.setStart(text,first);range.setEnd(text,last);return range;}

///|
extern "js" fn search_publish_ranges(
  ranges : FixedArray[@js.Value],
  active : FixedArray[@js.Value],
) -> Bool =
  #| (ranges,active) => {if(!globalThis.CSS?.highlights||typeof Highlight!=='function')return false;const hits=new Highlight(),selected=new Highlight();for(const range of ranges)hits.add(range);for(const range of active)selected.add(range);selected.priority=1;CSS.highlights.set('pdf-search-hit',hits);CSS.highlights.set('pdf-search-active',selected);return true;}

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
        index: value_int(value, "index"),
        length: value_int(value, "length"),
        xfa: value_string(value, "source_kind") == "xfa",
        start_offset: value_int(value, "start_offset"),
        end_offset: value_int(value, "end_offset"),
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

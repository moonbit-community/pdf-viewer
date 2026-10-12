///|
fn launch(work : async () -> Unit) -> Unit {
  ignore(
    @js_async.Promise::from_async(() => {
      work() catch {
        error => show_error(error)
      }
    }),
  )
}

///|
extern "js" fn picked_file() -> @js.Nullable[@js.Value] =
  #| () => { const input=document.getElementById("file-input"),file=input.files[0]||null;input.value="";return file; }

///|
extern "js" fn dropped_file(event : @dom.DragEvent) -> @js.Nullable[@js.Value] =
  #| event => event.dataTransfer.files[0]||null

///|
extern "js" fn blur_input(id : String) -> Unit =
  #| id => document.getElementById(id).blur()

///|
async fn viewer_scroll() -> Unit {
  if state.scroll_pending ||
    state.count == 0 ||
    state.layouts.length() != state.count {
    return
  }
  state.scroll_pending = true
  native_frame().wait()
  state.scroll_pending = false
  if state.count == 0 || state.layouts.length() != state.count {
    return
  }
  let top = element("viewer").get_bounding_client_rect().get_top()
  let mut best = 1
  let mut distance = 1.0e300
  for page in element("pages").get_children().iter() {
    let number = parse_float(element_data(page, "page")).to_int()
    if state.view_mode == "page" && number != state.current_page {
      continue
    }
    let delta = (page.get_bounding_client_rect().get_top() - top - 24.0).abs()
    if delta < distance {
      distance = delta
      best = number
    }
  }
  state.current_page = best
  native_location_update(best, false)
  scheduler_update(state.scheduler.unwrap(), best)
  notify()
}

///|
async fn handle(message : Msg) -> Unit {
  match message {
    Publish(_) => ()
    Open => click_element("file-input")
    FileChanged(file) => if editor_can_replace() { load_document(file, "") }
    Navigate(number, push) => go_to_page(number, push~)
    MovePage(delta) => go_to_page(state.current_page + delta, push=true)
    ChangeZoom(zoom) => {
      state.zoom = zoom
      repaint()
    }
    Scale(factor) => change_scale(factor)
    Rotate => {
      state.rotation = (state.rotation + 90) % 360
      repaint()
    }
    ChangeView(mode) => {
      state.view_mode = mode
      apply_view_mode()
      if mode == "page" && page_element(state.current_page) is Some(page) {
        page.scroll_into_view_with_options(block="start")
      }
      scheduler_update(state.scheduler.unwrap(), state.current_page)
      notify()
    }
    ToggleSidebar(sidebar) => toggle_sidebar(sidebar)
    CloseSidebar => close_sidebar()
    LayerVisibility(number, visible) =>
      layers_update("set_optional_content_visibility", [
        @js.Value::cast_from(number),
        @js.Value::cast_from(visible),
      ])
    LayerConfig(index) =>
      layers_update("set_optional_content_config", [@js.Value::cast_from(index)])
    SearchInput(value) => {
      state.search_input = value
      search_document()
    }
    SearchOptions => search_document()
    SearchKey(event) =>
      match event.key() {
        "Enter" =>
          if state.search_query == input_value("search-query") {
            jump_search(1)
          } else {
            search_document()
          }
        "Escape" => {
          clear_search()
          blur_input("search-query")
        }
        _ => ()
      }
    JumpSearch(delta) => jump_search(delta)
    Print => print_document_async()
    Download => editor_save()
    Copy => {
      refresh_copy_selection()
      if state.selection is Some(_) {
        write_clipboard(state.selection_text).wait()
      } else if state.selection_promise is Some(pending) {
        native_copy_pending(pending_selection_text(pending)).wait()
      }
    }
    DownloadAttachment(index, name) => download_attachment(index, name)
    DownloadMetadata => download_metadata()
    DragOver => {
      state.drag_over = true
      notify()
    }
    DragLeave => {
      state.drag_over = false
      notify()
    }
    Drop(file) => {
      state.drag_over = false
      notify()
      if file is Some(file) && editor_can_replace() {
        load_document(file, "")
      }
    }
    PointerDown => if state.selection_restore { clear_selection() }
    Scroll => viewer_scroll()
    ViewerKey(event) => selection_key(event)
    Edit(action) => editor_handle(action)
  }
}

///|
fn initialize_events() -> Unit {
  initialize_editor_events()
  let document = @dom.document()
  let window = @dom.window()
  document.add_event_listener("selectionchange", _ => {
    if state.selection_pending {
      return
    }
    state.selection_pending = true
    launch(() => {
      native_frame().wait()
      state.selection_pending = false
      read_native_selection()
    })
  })
  document.add_event_listener("copy", event => {
    if event.to_clipboard_event() is Some(event) {
      copy_event(event)
    }
  })
  document.add_event_listener("keydown", event => {
    if event.to_keyboard_event() is Some(event) &&
      state.count > 0 &&
      (event.ctrl_key() || event.meta_key()) &&
      event.key().to_lower() == "p" {
      event.prevent_default()
      launch(print_document_async)
    }
  })
  for name in ["popstate", "hashchange"] {
    window.add_event_listener(name, _ => {
      if state.count > 0 {
        go_to_page(location_page())
      }
    })
  }
  window.add_event_listener("resize", _ => {
    if state.resize_timer is Some(timer) {
      window.clear_timeout(timer)
    }
    state.resize_timer = Some(
      window.set_timeout(
        () => if state.zoom == "fit" { launch(() => repaint()) },
        150,
      ),
    )
  })
  window.add_event_listener("afterprint", _ => clear_print())
  window.add_event_listener("pagehide", _ => {
    scheduler_cancel(state.scheduler.unwrap())
    abort(state.search_controller)
    abort(state.selection_controller)
    cancel_thumbnails()
    abort(state.print_controller)
    close_worker()
  })
  window.add_event_listener("pageshow", event => {
    if event_persisted(event) && state.file is Some(file) {
      launch(() => load_document(file, state.file_path))
    }
  })
}

///|
extern "js" fn event_persisted(event : @dom.Event) -> Bool =
  #| event => Boolean(event.persisted)

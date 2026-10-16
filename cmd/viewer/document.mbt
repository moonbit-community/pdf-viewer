///|
pub fn close_document() -> Unit {
  clear_document_state(false)
}

///|
fn clear_document_state(keep_prepared_worker : Bool) -> Unit {
  reset_editor()
  clear_xfa_fonts()
  clear_render_assets()
  state.document_generation += 1
  state.generation += 1
  close_worker(keep_prepared_worker)
  close_sidebar()
  if state.annotations is Some(ui) {
    annotations_close(ui)
  }
  clear_selection()
  clear_search()
  clear_print()
  if state.scheduler is Some(scheduler) {
    scheduler_clear(scheduler)
  }
  clear_width_cache()
  state.count = 0
  state.current_page = 1
  state.xfa = false
  state.file = None
  state.file_name = ""
  state.file_path = ""
  state.document_info = Json::null()
  state.layers = Json::null()
  state.layers_busy = false
  state.labels = []
  state.layouts = []
  element("viewer").set_scroll_top(0.0)
  element("viewer").set_scroll_left(0.0)
  state.status = Ready
  set_busy(false)
}

///|
async fn load_document(file : @js.Value, path : String) -> Unit {
  state.document_generation += 1
  let requested_generation = state.document_generation
  // Native input events can precede the first after-render controller setup.
  // Wait before publishing state or reading the file on every open path.
  while state.scheduler is None {
    native_frame().wait()
  }
  if requested_generation != state.document_generation {
    return
  }
  // Host callers can set the native controls before opening their first file.
  // Capture those preferences before publishing the new reader session.
  let zoom = input_value("zoom")
  let view_mode = input_value("view-mode")
  clear_document_state(true)
  state.zoom = zoom
  state.view_mode = view_mode
  let generation = state.document_generation
  set_busy(true)
  state.error = ""
  state.status = ReadingDocument
  notify()
  try {
    reset_worker()
    let canvas_diagnostics = initialize_graphics().wait()
    if generation != state.document_generation {
      return
    }
    let mut password : String? = None
    let mut opened : @js.Value? = None
    while opened is None {
      let data = if value_string(file, "url") != "" {
        @js.Value::cast_from((@js.Nullable::null() : @js.Nullable[Unit]))
      } else {
        file_bytes(file).wait()
      }
      if generation != state.document_generation {
        return
      }
      try {
        let info = checked(
          open_document(file, data, @js.Nullable::from_option(password)).wait(),
        )
        if generation != state.document_generation {
          return
        }
        opened = Some(info)
      } catch {
        ViewerError(code, message) => {
          if code != "password-required" && code != "password-invalid" {
            raise ViewerError(code, message)
          }
          let prompt = if code == "password-invalid" {
            "Incorrect password. Try again."
          } else {
            "This PDF requires a password"
          }
          password = prompt_password(prompt).to_option()
          if password is None {
            raise ViewerError(code, message)
          }
          continue
        }
        error => raise error
      }
    }
    let info = opened.unwrap()
    report_diagnostics(canvas_diagnostics)
    report_diagnostics(
      value_field(value_field(worker_diagnostics(), "graphics"), "diagnostics"),
    )
    state.file = Some(file)
    let name = value_string(file, "name")
    state.file_name = if name != "" { name } else { "document.pdf" }
    state.file_path = if path != "" { path } else { state.file_name }
    state.count = value_int(info, "pages")
    state.xfa = value_bool(info, "xfa")
    state.labels = value_strings(value_field(info, "labels")).iter().collect()
    let response = call("page_layouts")
    if generation != state.document_generation {
      return
    }
    let layouts = value_field(response, "layouts")
    state.layouts = value_array(layouts)
      .iter()
      .map(value => {
        page: value_int(value, "page"),
        width: value_number(value, "width"),
        height: value_number(value, "height"),
      })
      .collect()
    scheduler_document(state.scheduler.unwrap(), layouts)
    state.rotation = 0
    clear_search()
    state.current_page = location_page()
    close_sidebar()
    flush_ui()
    repaint(preserve=false)
    let info = call("document_info")
    if generation != state.document_generation {
      return
    }
    state.document_info = value_json(info)
    state.layers = json_field(state.document_info, "layers")
    let labels = value_strings(value_field(info, "labels"))
    if labels.length() == state.count {
      state.labels = labels.iter().collect()
    }
    notify()
  } catch {
    error =>
      if generation == state.document_generation {
        close_document()
        show_error(error)
      }
  }
  if generation == state.document_generation {
    set_busy(false)
  }
}

///|
pub fn load_file(file : @js.Value, path : String) -> @js_async.Promise[Unit] {
  @js_async.Promise::from_async(() => {
    load_document(file, path)
    flush_ui()
  })
}

///|
extern "js" fn diagnostic_value(
  count : Int,
  generation : Int,
  file : @js.Nullable[@js.Value],
  cache : @js.Value,
  worker : @js.Value,
  display_cache : @js.Value,
) -> @js.Value =
  #| (pages,documentGeneration,file,cache,worker,display_cache) => ({pages,documentGeneration,mounted:[...document.getElementById("pages").querySelectorAll('[data-rendered="true"]')].map(page=>Number(page.dataset.page)),source_bytes:file?.size||cache.range?.total_bytes||0,worker,cache,display_cache,render_assets:globalThis.pdfViewerHost.renderAssetsDiagnostics()})

///|
extern "js" fn display_cache_diagnostics(scheduler : @js.Value) -> @js.Value =
  #| scheduler => scheduler.diagnostics()

///|
pub fn runtime_diagnostics() -> @js_async.Promise[@js.Value] {
  @js_async.Promise::from_async(() => {
    let cache = call("cache_info")
    diagnostic_value(
      state.count,
      state.document_generation,
      @js.Nullable::from_option(state.file),
      cache,
      worker_diagnostics(),
      display_cache_diagnostics(state.scheduler.unwrap()),
    )
  })
}

///|
extern "js" fn initial_file() -> @js.Nullable[@js.Value] =
  #| () => { const path=new URL(location.href).searchParams.get("file");if(!path)return null;const url=new URL(path,location.href);return {name:decodeURIComponent(url.pathname.split('/').pop())||"document.pdf",url:url.href,path}; }

///|
extern "js" fn has_initial_file() -> Bool =
  #| () => Boolean(new URL(location.href).searchParams.get('file'))

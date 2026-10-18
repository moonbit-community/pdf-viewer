///|
/// Native APIs not currently wrapped by Rabbita and the existing PDF renderer
/// are narrow FFI calls. Navigation, lifecycle and UI state stay in MoonBit.
extern "js" fn value_string(value : @js.Value, key : String) -> String =
  #| (value, key) => value?.[key] == null ? "" : String(value[key])

///|
extern "js" fn value_int(value : @js.Value, key : String) -> Int =
  #| (value, key) => (value?.[key] || 0) | 0

///|
extern "js" fn value_number(value : @js.Value, key : String) -> Double =
  #| (value, key) => Number(value?.[key] || 0)

///|
extern "js" fn value_bool(value : @js.Value, key : String) -> Bool =
  #| (value, key) => Boolean(value?.[key])

///|
extern "js" fn value_field(value : @js.Value, key : String) -> @js.Value =
  #| (value, key) => value?.[key] ?? null

///|
extern "js" fn value_array(value : @js.Value) -> FixedArray[@js.Value] =
  #| value => Array.isArray(value) ? value : []

///|
extern "js" fn value_numbers(value : @js.Value) -> FixedArray[Double] =
  #| value => value

///|
extern "js" fn value_strings(value : @js.Value) -> FixedArray[String] =
  #| value => value || []

///|
fn value_json(value : @js.Value) -> Json {
  @json.parse(value_json_string(value)) catch {
    _ => Json::null()
  }
}

///|
extern "js" fn value_json_string(value : @js.Value) -> String =
  #| value => JSON.stringify(value ?? null)

///|
extern "js" fn parse_value(text : String) -> @js.Value =
  #| text => JSON.parse(text)

///|
suberror ViewerError {
  ViewerError(String, String)
}

///|
fn checked(raw : String) -> @js.Value raise ViewerError {
  checked_value(parse_value(raw))
}

///|
fn checked_value(value : @js.Value) -> @js.Value raise ViewerError {
  if !value_bool(value, "ok") {
    raise ViewerError(value_string(value, "code"), value_string(value, "error"))
  }
  value
}

///|
extern "js" fn worker_call(
  operation : String,
  args : FixedArray[@js.Value],
  signal : @js.Nullable[@js_async.AbortSignal],
  priority : Int,
) -> @js_async.Promise[String] =
  #| (method, args, signal, priority) => globalThis.pdfViewerHost.pdf.call(method, args, { signal: signal || undefined, priority })

///|
async fn call(
  operation : String,
  args? : FixedArray[@js.Value] = [],
  controller? : @js_async.AbortController,
  priority? : Int = 0,
) -> @js.Value {
  let signal = controller.map(c => c.signal())
  checked(
    worker_call(operation, args, @js.Nullable::from_option(signal), priority).wait(),
  )
}

///|
extern "js" fn reset_worker() -> Unit =
  #| () => globalThis.pdfViewerHost.pdf.resetForDocument()

///|
extern "js" fn close_worker(keep_prepared : Bool) -> Unit =
  #| keep => { const pdf=globalThis.pdfViewerHost.pdf; if(keep)pdf.closeForReplacement(); else pdf.close(); }

///|
extern "js" fn prepare_worker() -> Unit =
  #| () => globalThis.pdfViewerHost.pdf.prepare()

///|
extern "js" fn worker_diagnostics() -> @js.Value =
  #| () => globalThis.pdfViewerHost.pdf.diagnostics()

///|
extern "js" fn initialize_graphics() -> @js_async.Promise[@js.Value] =
  #| () => globalThis.pdfViewerHost.initializeGraphics()

///|
extern "js" fn file_bytes(file : @js.Value) -> @js_async.Promise[@js.Value] =
  #| file => file.arrayBuffer().then(bytes => new Uint8Array(bytes))

///|
extern "js" fn open_document(
  file : @js.Value,
  data : @js.Value,
  password : @js.Nullable[String],
) -> @js_async.Promise[String] =
  #| (file, data, password) => globalThis.pdfViewerHost.openDocument(file, data, password)

///|
extern "js" fn prompt_password(message : String) -> @js.Nullable[String] =
  #| message => window.prompt(message)

///|
extern "js" fn controller_aborted(
  controller : @js_async.AbortController,
) -> Bool =
  #| controller => controller.signal.aborted

///|
fn abort(controller : @js_async.AbortController?) -> Unit {
  if controller is Some(controller) {
    controller.abort()
  }
}

///|
fn element(id : String) -> @dom.Element {
  @dom.document().get_element_by_id(id).unwrap()
}

///|
extern "js" fn element_text(node : @dom.Element) -> String =
  #| node => node.textContent || ""

///|
extern "js" fn set_text(node : @dom.Element, text : String) -> Unit =
  #| (node, text) => { node.textContent = text; }

///|
extern "js" fn set_style(
  node : @dom.Element,
  key : String,
  value : String,
) -> Unit =
  #| (node, key, value) => { node.style[key] = value; }

///|
extern "js" fn get_style(node : @dom.Element, key : String) -> String =
  #| (node, key) => node.style[key] || ""

///|
extern "js" fn clear_children(node : @dom.Element) -> Unit =
  #| node => node.replaceChildren()

///|
extern "js" fn append_element(
  node : @dom.Element,
  child : @dom.Element,
) -> Unit =
  #| (node, child) => node.append(child)

///|
extern "js" fn element_data(node : @dom.Element, key : String) -> String =
  #| (node, key) => node.dataset[key] || ""

///|
extern "js" fn set_data(
  node : @dom.Element,
  key : String,
  value : String,
) -> Unit =
  #| (node, key, value) => { node.dataset[key] = value; }

///|
extern "js" fn toggle_class(
  node : @dom.Element,
  name : String,
  active : Bool,
) -> Unit =
  #| (node, name, active) => node.classList.toggle(name, active)

///|
extern "js" fn input_value(id : String) -> String =
  #| id => document.getElementById(id).value

///|
extern "js" fn set_input_value(id : String, value : String) -> Unit =
  #| (id, value) => { document.getElementById(id).value = value; }

///|
extern "js" fn input_checked(id : String) -> Bool =
  #| id => document.getElementById(id).checked

///|
extern "js" fn click_element(id : String) -> Unit =
  #| id => document.getElementById(id).click()

///|
extern "js" fn offset_height(node : @dom.Element) -> Double =
  #| node => node.offsetHeight

///|
extern "js" fn computed_number(node : @dom.Element, key : String) -> Double =
  #| (node, key) => parseFloat(getComputedStyle(node)[key]) || 0

///|
extern "js" fn native_frame() -> @js_async.Promise[Unit] =
  #| () => new Promise(resolve => requestAnimationFrame(() => resolve()))

///|
async fn flush_ui() -> Unit {
  notify()
  after_render(callback => {
    ui_scheduler.val
    .unwrap()
    .queue_command(@cmd.custom_cmd(_ => callback(), kind=@cmd.after_render))
  }).wait()
}

///|
extern "js" fn after_render(
  schedule : (() -> Unit) -> Unit,
) -> @js_async.Promise[Unit] =
  #| schedule => new Promise(resolve => schedule(() => resolve()))

///|
extern "js" fn dispatch_detail(name : String, value : @js.Value) -> Unit =
  #| (name, value) => document.getElementById("viewer").dispatchEvent(new CustomEvent(name, { detail: value }))

///|
extern "js" fn native_location_page() -> Int =
  #| () => Number(new URL(location.href).hash.match(/^#page=(\d+)$/)?.[1]) || 1

///|
extern "js" fn native_location_update(number : Int, push : Bool) -> Unit =
  #| (number, push) => { const url = new URL(location.href); url.hash = `page=${number}`; history[push ? "pushState" : "replaceState"]({ page: number }, "", url); }

///|
extern "js" fn download_native(file : @js.Value, name : String) -> Unit =
  #| (file, name) => { const url = file.url || URL.createObjectURL(file); const a = document.createElement("a"); a.href = url; a.download = name; a.click(); if (!file.url) setTimeout(() => URL.revokeObjectURL(url), 1000); }

///|
extern "js" fn download_base64(
  data : String,
  name : String,
  mime : String,
) -> Unit =
  #| (data, name, mime) => { const bytes = Uint8Array.from(atob(data), c => c.charCodeAt(0)); const a = document.createElement("a"); a.href = URL.createObjectURL(new Blob([bytes], { type: mime })); a.download = name; a.click(); setTimeout(() => URL.revokeObjectURL(a.href), 1000); }

///|
extern "js" fn write_clipboard(text : String) -> @js_async.Promise[Unit] =
  #| text => navigator.clipboard.writeText(text)

///|
extern "js" fn native_fonts_ready() -> @js_async.Promise[Unit] =
  #| () => document.fonts.ready.then(() => {})

///|
fn paint_canvas(
  node : @dom.Element,
  result : @js.Value,
  output_scale : Double,
  current? : (() -> Bool)? = None,
) -> @js_async.Promise[@js.Value] {
  native_paint_canvas(
    node,
    result,
    output_scale,
    @js.Nullable::from_option(current),
    (c, m, y, k) => {
      FixedArray::from_array(@pdf.process_cmyk_to_rgb(c, m, y, k)[:])
    },
  )
}

///|
extern "js" fn native_paint_canvas(
  node : @dom.Element,
  result : @js.Value,
  output_scale : Double,
  current : @js.Nullable[() -> Bool],
  convert : (Double, Double, Double, Double) -> FixedArray[Double],
) -> @js_async.Promise[@js.Value] =
  #| (node, result, outputScale, current, convert) => globalThis.pdfViewerHost.paintCanvas(node, result, outputScale, current, convert)

///|
extern "js" fn create_xfa(
  result : @js.Value,
  intent : String,
) -> @js_async.Promise[@dom.Element] =
  #| (result, intent) => globalThis.pdfViewerHost.makeXfaLayer(result, intent)

///|
extern "js" fn clear_xfa_fonts() -> Unit =
  #| () => globalThis.pdfViewerHost.clearXfaFonts()

///|
extern "js" fn clear_render_assets() -> Unit =
  #| () => globalThis.pdfViewerHost.clearRenderAssets()

///|
extern "js" fn output_scale() -> Double =
  #| () => Math.max(1, window.devicePixelRatio || 1)

///|
extern "js" fn create_annotations(
  node : @dom.Element,
  navigate : (@js.Value) -> Unit,
  source : () -> String,
) -> @js.Value =
  #| (viewer, navigate, sourceURL) => globalThis.pdfViewerHost.createAnnotations(viewer, navigate, sourceURL)

///|
extern "js" fn annotation_layer(
  ui : @js.Value,
  result : @js.Value,
) -> @dom.Element =
  #| (ui, result) => ui.create(result.annotations || [], result.layer.viewport)

///|
extern "js" fn accessibility_layer(
  result : @js.Value,
  annotations : @dom.Element,
) -> @js.Nullable[@dom.Element] =
  #| (result, annotations) => globalThis.pdfViewerHost.makeAccessibilityLayer(result.accessibility, annotations)

///|
extern "js" fn annotations_bind(ui : @js.Value, page : @dom.Element) -> Unit =
  #| (ui, page) => ui.bind(page)

///|
extern "js" fn annotations_unmount(ui : @js.Value, page : @dom.Element) -> Unit =
  #| (ui, page) => ui.unmount(page)

///|
extern "js" fn annotations_close(ui : @js.Value) -> Unit =
  #| ui => ui.close()

///|
extern "js" fn native_source_url(path : String) -> String =
  #| path => path ? new URL(path, location.href).href : ""

///|
extern "js" fn native_measure(
  text : String,
  family : String,
  weight : String,
  style : String,
) -> Double =
  #| (text, family, weight, style) => globalThis.pdfViewerHost.measure(text, family, weight, style)

///|
fn report_diagnostics(value : @js.Value) -> Unit {
  let values = value_array(value)
  if values.is_empty() {
    return
  }
  let messages : Array[String] = []
  for value in values {
    let message = value_string(value, "message")
    let reason = value_string(value, "reason")
    messages.push(
      if message != "" {
        message
      } else if reason != "" {
        reason
      } else {
        value_string(value, "code")
      },
    )
  }
  state.error = messages.join("; ")
  notify()
}

///|
fn show_error(error : Error) -> Unit {
  let message = match error {
    ViewerError(_, message) => message
    _ => error.to_string()
  }
  show_error_message(message)
}

///|
fn show_error_message(message : String) -> Unit {
  if message.contains("AbortError") || message.contains("cancelled") {
    return
  }
  state.error = message
  state.status = OperationFailed
  notify()
}

///|
extern "js" fn parse_float(text : String) -> Double =
  #| text => parseFloat(text) || 0

///|
fn set_busy(busy : Bool) -> Unit {
  state.busy = busy
  element("viewer").set_attribute("aria-busy", busy.to_string())
  notify()
}

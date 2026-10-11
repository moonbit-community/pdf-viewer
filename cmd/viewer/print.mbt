///|
let print_generation : Ref[Int] = Ref(0)

///|
fn clear_print() -> Unit {
  abort(state.print_controller)
  print_generation.val += 1
  clear_children(element("print-pages"))
  toggle_class(element("app"), "pdf-print-ready", false)
  state.printing = false
  notify()
}

///|
async fn print_document_async() -> Unit {
  if state.count == 0 {
    return
  }
  let document_generation = state.document_generation
  while state.layers_busy {
    native_frame().wait()
    if document_generation != state.document_generation {
      return
    }
  }
  editor_flush_field()
  while editor.applying {
    native_frame().wait()
    if document_generation != state.document_generation {
      return
    }
  }
  clear_print()
  let generation = state.document_generation
  let token = print_generation.val
  let controller = @js_async.AbortController::new()
  state.print_controller = Some(controller)
  state.printing = true
  let root = element("print-pages")
  let style = make_element("style")
  let rules : Array[String] = []
  append_element(root, style)
  try {
    for number in 1..<=state.count {
      state.status = "正在准备打印第 \{number} / \{state.count} 页"
      notify()
      let result = call(
        "render_print_page",
        args=[
          @js.Value::cast_from(number),
          @js.Value::cast_from(1.0),
          @js.Value::cast_from(0),
          @js.Value::cast_from(true),
        ],
        controller~,
        priority=-2,
      )
      if controller_aborted(controller) ||
        generation != state.document_generation {
        return
      }
      let page = make_element("section", class_name="page")
      set_data(page, "page", number.to_string())
      let viewport = value_field(value_field(result, "layer"), "viewport")
      let width = value_number(viewport, "width")
      let height = value_number(viewport, "height")
      let name = "pdf-print-\{number}"
      set_style(page, "width", "\{width}pt")
      set_style(page, "height", "\{height}pt")
      set_style(page, "page", name)
      rules.push("@page \{name} { size: \{width}pt \{height}pt; margin: 0; }")
      let (surface, diagnostics) = if value_bool(result, "xfa") {
        (
          create_xfa(result, "print").wait(),
          @js.Value::cast_from((@js.Nullable::null() : @js.Nullable[Unit])),
        )
      } else {
        let canvas = make_element("canvas")
        let rendered = paint_canvas(
          canvas,
          result,
          150.0 / 72.0,
          current=Some(() => {
            !controller_aborted(controller) &&
            generation == state.document_generation &&
            token == print_generation.val
          }),
        ).wait()
        (canvas, value_field(rendered, "diagnostics"))
      }
      if controller_aborted(controller) ||
        generation != state.document_generation {
        return
      }
      append_element(page, surface)
      append_element(root, page)
      report_diagnostics(diagnostics)
    }
    set_text(style, "@media print { \{rules.join("\n")} }")
    native_fonts_ready().wait()
    if controller_aborted(controller) || generation != state.document_generation {
      return
    }
    toggle_class(element("app"), "pdf-print-ready", true)
    native_print()
  } catch {
    error =>
      if generation == state.document_generation &&
        token == print_generation.val &&
        !controller_aborted(controller) {
        clear_print()
        show_error(error)
      }
  }
  if generation == state.document_generation && token == print_generation.val {
    state.printing = false
    state.status = "\{state.count} 页 · \{(state.scale * 100.0).round().to_int()}%"
    notify()
  }
}

///|
pub fn print_document() -> @js_async.Promise[Unit] {
  @js_async.Promise::from_async(() => {
    print_document_async()
    flush_ui()
  })
}

///|
extern "js" fn native_print() -> Unit =
  #| () => window.print()

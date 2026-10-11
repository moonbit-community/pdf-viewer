///|
fn editor_pointer_down(event : @dom.PointerEvent) -> Unit {
  if !editor.enabled ||
    !editor.annotations ||
    editor.applying ||
    event.get_button() != 0 {
    return
  }
  guard native_edit_target(event).to_option() is Some(target) else { return }
  if target.closest(".editor-field") is Some(_) {
    return
  }
  guard target.closest(".page") is Some(page) &&
    page.query_selector(".editor-layer") is Some(layer) else {
    return
  }
  let mut entry = Json::null()
  let mut mode = editor.tool
  if mode == "select" {
    guard target.closest(".editor-annotation") is Some(control) else { return }
    entry = value_json(parse_value(element_data(control, "entry")))
    mode = if target.closest(".editor-resize") is Some(_) {
      "resize"
    } else {
      "move"
    }
    editor_select(entry)
  }
  if mode == "image" && editor.image == Json::null() {
    editor.status = "先选择签名图片"
    notify()
    return
  }
  if mode == "text" && editor.text.trim().is_empty() {
    editor.status = "先在工具栏输入文字"
    notify()
    return
  }
  let viewport = value_json(parse_value(element_data(layer, "viewport")))
  let matrix = edit_array(json_field(viewport, "matrix")).map(edit_number)
  if matrix.length() != 6 ||
    (matrix[0] * matrix[3] - matrix[1] * matrix[2]).abs() < 1.0e-12 {
    return
  }
  let start = edit_pdf_point(
    page,
    matrix,
    event.get_client_x(),
    event.get_client_y(),
  )
  event.prevent_default()
  event.stop_immediate_propagation()
  page.set_pointer_capture(event.get_pointer_id())
  editor.gesture = Some({
    page,
    number: parse_float(element_data(page, "page")).to_int(),
    pointer: event.get_pointer_id(),
    mode,
    start,
    points: [start],
    matrix,
    entry,
  })
}

///|
fn editor_gesture_bounds(
  gesture : EditGesture,
  end : EditPoint,
) -> Array[Double] {
  if gesture.mode == "move" || gesture.mode == "resize" {
    let old = edit_array(json_field(gesture.entry, "bounds")).map(edit_number)
    let dx = end.x - gesture.start.x
    let dy = end.y - gesture.start.y
    if gesture.mode == "move" {
      [old[0] + dx, old[1] + dy, old[2] + dx, old[3] + dy]
    } else {
      [
        old[0],
        (old[1] + dy).min(old[3] - 2.0),
        (old[2] + dx).max(old[0] + 2.0),
        old[3],
      ]
    }
  } else {
    edit_bounds(gesture.start, end)
  }
}

///|
fn editor_pointer_move(event : @dom.PointerEvent) -> Unit {
  guard editor.gesture is Some(gesture) &&
    gesture.pointer == event.get_pointer_id() else {
    return
  }
  event.prevent_default()
  let point = edit_pdf_point(
    gesture.page,
    gesture.matrix,
    event.get_client_x(),
    event.get_client_y(),
  )
  if gesture.points.length() < 20000 {
    gesture.points.push(point)
  }
  guard gesture.page.query_selector(".editor-preview") is Some(preview) else {
    return
  }
  let rectangle = gesture.mode != "ink" && gesture.mode != "signature"
  let points = if rectangle {
    editor_gesture_bounds(gesture, point)
  } else {
    let coordinates : Array[Double] = []
    for point in gesture.points {
      coordinates.push(point.x)
      coordinates.push(point.y)
    }
    coordinates
  }
  native_preview(
    preview,
    FixedArray::from_array(points),
    FixedArray::from_array(gesture.matrix),
    editor.color,
    if rectangle {
      1.0
    } else {
      editor.size
    },
    rectangle,
  )
}

///|
async fn editor_pointer_up(event : @dom.PointerEvent) -> Unit {
  guard editor.gesture is Some(gesture) &&
    gesture.pointer == event.get_pointer_id() else {
    return
  }
  editor.gesture = None
  gesture.page.release_pointer_capture(gesture.pointer)
  event.prevent_default()
  let end = edit_pdf_point(
    gesture.page,
    gesture.matrix,
    event.get_client_x(),
    event.get_client_y(),
  )
  let mut bounds = editor_gesture_bounds(gesture, end)
  let moving = gesture.mode == "move" || gesture.mode == "resize"
  if moving &&
    (end.x - gesture.start.x).abs() + (end.y - gesture.start.y).abs() < 0.5 {
    return
  }
  let mut patch : Json = if moving {
    {
      "kind": "update",
      "page": gesture.number,
      "id": edit_string(gesture.entry, "id"),
      "bounds": bounds,
    }
  } else {
    {
      "kind": "add",
      "page": gesture.number,
      "id": native_annotation_id(),
      "bounds": bounds,
      "color": edit_rgb(),
      "size": editor.size,
    }
  }
  if gesture.mode == "ink" || gesture.mode == "signature" {
    if gesture.points.length() < 2 {
      gesture.points.push({ x: end.x + 0.01, y: end.y + 0.01, })
    }
    let points = gesture.points.map(point => [point.x, point.y])
    let xs = gesture.points.map(point => point.x)
    let ys = gesture.points.map(point => point.y)
    let padding = editor.size / 2.0 + 0.5
    bounds = [
      xs.fold(init=xs[0], Double::min) - padding,
      ys.fold(init=ys[0], Double::min) - padding,
      xs.fold(init=xs[0], Double::max) + padding,
      ys.fold(init=ys[0], Double::max) + padding,
    ]
    patch = edit_put(patch, "bounds", ToJson::to_json(bounds))
    patch = edit_put(patch, "subtype", Json::string("Ink"))
    patch = edit_put(patch, "paths", ToJson::to_json([points]))
    patch = edit_put(
      patch,
      "contents",
      Json::string(
        if gesture.mode == "signature" {
          "手写签名"
        } else {
          "笔迹"
        },
      ),
    )
    let previous = editor_changes()
      .filter(entry => {
        edit_string(entry, "id") == editor.ink_id &&
        edit_string(entry, "kind") == "add" &&
        edit_number(json_field(entry, "size")) == editor.size &&
        json_field(entry, "color") == ToJson::to_json(edit_rgb())
      })
      .get(0)
    if previous is Some(previous) && editor.ink_page == gesture.number {
      let old = edit_array(json_field(previous, "bounds")).map(edit_number)
      bounds = [
        bounds[0].min(old[0]),
        bounds[1].min(old[1]),
        bounds[2].max(old[2]),
        bounds[3].max(old[3]),
      ]
      patch = edit_put(patch, "bounds", ToJson::to_json(bounds))
      patch = edit_put(patch, "id", json_field(previous, "id"))
      patch = edit_put(
        patch,
        "paths",
        Json::array(
          [..edit_array(json_field(previous, "paths")), ToJson::to_json(points)],
        ),
      )
    }
    editor.ink_id = edit_string(patch, "id")
    editor.ink_page = gesture.number
  } else if gesture.mode == "text" {
    if bounds[2] - bounds[0] < 2.0 || bounds[3] - bounds[1] < 2.0 {
      bounds = [
        gesture.start.x,
        gesture.start.y - 40.0,
        gesture.start.x + 160.0,
        gesture.start.y,
      ]
    }
    patch = edit_put(patch, "bounds", ToJson::to_json(bounds))
    patch = edit_put(patch, "subtype", Json::string("FreeText"))
    patch = edit_put(patch, "contents", Json::string(editor.text))
    if editor.text.iter().any(c => c.to_int() > 255) {
      patch = edit_put(
        patch,
        "image",
        editor_text_image(
          editor.text,
          ToJson::to_json(bounds),
          editor.size,
          editor.color,
          false,
        ),
      )
    }
  } else if gesture.mode == "highlight" {
    if bounds[2] - bounds[0] < 2.0 || bounds[3] - bounds[1] < 2.0 {
      return
    }
    patch = edit_put(patch, "subtype", Json::string("Highlight"))
    patch = edit_put(patch, "contents", Json::string(editor.text))
  } else if gesture.mode == "image" {
    if bounds[2] - bounds[0] < 2.0 || bounds[3] - bounds[1] < 2.0 {
      bounds = [
        gesture.start.x,
        gesture.start.y - 60.0,
        gesture.start.x + 160.0,
        gesture.start.y,
      ]
    }
    let ratio = edit_number(json_field(editor.image, "width")) /
      edit_number(json_field(editor.image, "height"))
    let w = bounds[2] - bounds[0]
    let h = bounds[3] - bounds[1]
    if w / h > ratio {
      bounds[2] = bounds[0] + h * ratio
    } else {
      bounds[1] = bounds[3] - w / ratio
    }
    patch = edit_put(patch, "bounds", ToJson::to_json(bounds))
    patch = edit_put(patch, "subtype", Json::string("Stamp"))
    patch = edit_put(patch, "image", editor.image)
    patch = edit_put(patch, "contents", Json::string("图片签名"))
  } else if moving {
    let previous = editor_changes()
      .filter(entry => {
        edit_string(entry, "id") == edit_string(gesture.entry, "id")
      })
      .get(0)
    if previous is Some(previous) &&
      json_field(previous, "paths") is Array(paths) {
      let old = edit_array(json_field(gesture.entry, "bounds")).map(edit_number)
      let paths = paths.map(path => {
        edit_array(path).map(point => {
          let point = edit_array(point).map(edit_number)
          [
            bounds[0] +
            (point[0] - old[0]) * (bounds[2] - bounds[0]) / (old[2] - old[0]),
            bounds[1] +
            (point[1] - old[1]) * (bounds[3] - bounds[1]) / (old[3] - old[1]),
          ]
        })
      })
      patch = edit_put(patch, "paths", ToJson::to_json(paths))
    }
  }
  editor_commit(patch)
}

///|
fn initialize_editor_events() -> Unit {
  let viewer = element("viewer")
  viewer.add_event_listener_with_options(
    "pointerdown",
    event => {
      if event.to_pointer_event() is Some(event) {
        editor_pointer_down(event)
      }
    },
    capture=true,
  )
  viewer.add_event_listener("pointermove", event => {
    if event.to_pointer_event() is Some(event) {
      editor_pointer_move(event)
    }
  })
  viewer.add_event_listener("pointerup", event => {
    if event.to_pointer_event() is Some(event) {
      launch(() => editor_pointer_up(event))
    }
  })
  viewer.add_event_listener("pointercancel", _ => {
    editor.gesture = None
    editor_refresh_layers()
  })
  @dom.document().add_event_listener("keydown", event => {
    guard editor.enabled && event.to_keyboard_event() is Some(key) else {
      return
    }
    if event_editable(event) {
      return
    }
    let modifier = key.ctrl_key() || key.meta_key()
    if modifier && key.key().to_lower() == "z" {
      key.prevent_default()
      launch(() => editor_history(if key.shift_key() { 1 } else { -1 }))
    } else if modifier && key.key().to_lower() == "y" {
      key.prevent_default()
      launch(() => editor_history(1))
    } else if key.key() == "Delete" || key.key() == "Backspace" {
      if editor.selected != Json::null() {
        key.prevent_default()
        launch(() => editor_handle(Delete))
      }
    } else if key.key() == "Escape" {
      editor.gesture = None
      editor.selected = Json::null()
      editor.tool = "select"
      editor_refresh_layers()
      notify()
    }
  })
  @dom.document().add_event_listener("keydown", event => {
    if event.to_keyboard_event() is Some(key) &&
      (key.ctrl_key() || key.meta_key()) &&
      key.key().to_lower() == "s" &&
      state.count > 0 {
      key.prevent_default()
      launch(editor_save)
    }
  })
  @dom.window().add_event_listener("beforeunload", event => {
    if editor_dirty() || editor.applying {
      native_unsaved_warning(event)
    }
  })
}

///|
extern "js" fn event_editable(event : @dom.Event) -> Bool =
  #| event => Boolean(event.target?.closest?.('input,textarea,select,[contenteditable="true"]'))

///|
extern "js" fn native_annotation_id() -> String =
  #| () => 'new:'+crypto.randomUUID()

///|
extern "js" fn native_unsaved_warning(event : @dom.Event) -> Unit =
  #| event => {event.preventDefault();event.returnValue='';}

///|
fn editor_can_replace() -> Bool {
  !(editor_dirty() || editor.applying) || native_discard_edits()
}

///|
extern "js" fn native_discard_edits() -> Bool =
  #| () => confirm('当前 PDF 有未保存的修改，是否放弃这些修改？')

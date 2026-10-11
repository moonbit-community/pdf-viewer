///|
fn editor_layer(result : @js.Value) -> @dom.Element {
  let layer = make_element("div", class_name="editor-layer")
  set_data(layer, "entries", value_json_string(value_field(result, "editor")))
  set_data(
    layer,
    "viewport",
    value_json_string(value_field(value_field(result, "layer"), "viewport")),
  )
  set_data(layer, "page", value_int(result, "page").to_string())
  editor_fill_layer(layer)
  layer
}

///|
fn editor_refresh_layers() -> Unit {
  for layer in element("pages").query_selector_all(".editor-layer").iter() {
    editor_fill_layer(layer)
  }
  set_data(element("pages"), "editing", editor.enabled.to_string())
  set_data(element("pages"), "editTool", editor.tool)
}

///|
fn editor_position(
  control : @dom.Element,
  entry : Json,
  matrix : Array[Double],
) -> Unit {
  let bounds = edit_array(json_field(entry, "bounds")).map(edit_number)
  let x = bounds[0]
  let y = bounds[3]
  set_style(control, "width", "\{bounds[2]-x}px")
  set_style(control, "height", "\{y-bounds[1]}px")
  set_style(control, "transformOrigin", "0 0")
  set_style(
    control,
    "transform",
    "matrix(\{matrix[0]},\{matrix[1]},\{-matrix[2]},\{-matrix[3]},\{matrix[0]*x+matrix[2]*y+matrix[4]},\{matrix[1]*x+matrix[3]*y+matrix[5]})",
  )
}

///|
fn editor_fill_layer(layer : @dom.Element) -> Unit {
  clear_children(layer)
  if !editor.enabled {
    return
  }
  let entries = edit_array(
    value_json(parse_value(element_data(layer, "entries"))),
  )
  let viewport = value_json(parse_value(element_data(layer, "viewport")))
  let matrix = edit_array(json_field(viewport, "matrix")).map(edit_number)
  if matrix.length() != 6 {
    return
  }
  for entry in entries {
    if edit_string(entry, "subtype") == "widget" {
      if editor_field_control(entry) is Some(control) {
        editor_position(control, entry, matrix)
        append_element(layer, control)
      }
    } else if editor.tool == "select" && edit_bool(entry, "editable") {
      let control = make_element("button", class_name="editor-annotation")
      control.set_attribute("type", "button")
      control.set_attribute(
        "aria-label",
        "编辑批注：" + edit_string(entry, "contents"),
      )
      set_data(control, "entry", entry.stringify())
      if edit_string(entry, "id") == edit_string(editor.selected, "id") {
        control.set_attribute("aria-pressed", "true")
        let resize = make_element("span", class_name="editor-resize")
        resize.set_attribute("aria-hidden", "true")
        append_element(control, resize)
      }
      control.add_event_listener("click", event => {
        event.prevent_default()
        event.stop_propagation()
        editor_select(entry)
      })
      editor_position(control, entry, matrix)
      append_element(layer, control)
    }
  }
  let preview = make_element("canvas", class_name="editor-preview")
  preview.set_attribute("aria-hidden", "true")
  preview.set_property(
    "width",
    @js.Value::cast_from(
      edit_number(json_field(viewport, "width")).ceil().to_int(),
    ),
  )
  preview.set_property(
    "height",
    @js.Value::cast_from(
      edit_number(json_field(viewport, "height")).ceil().to_int(),
    ),
  )
  append_element(layer, preview)
}

///|
fn editor_select(entry : Json) -> Unit {
  editor.selected = entry
  editor.text = edit_string(entry, "contents")
  let color = edit_string(entry, "color")
  if color.has_prefix("#") && color.length() == 7 {
    editor.color = color
  }
  editor.status = "拖动批注可移动；拖动右下角可调整大小"
  editor_refresh_layers()
  notify()
}

///|
fn editor_field_control(entry : Json) -> @dom.Element? {
  let generation = state.document_generation
  let field_type = edit_string(entry, "field_type")
  let flags = edit_number(json_field(entry, "field_flags")).to_int()
  if (field_type != "Tx" && field_type != "Ch" && field_type != "Btn") ||
    (field_type == "Btn" && (flags & 65536) != 0) {
    return None
  }
  let editable = edit_bool(entry, "editable")
  let control = make_element(
    if field_type == "Ch" && (flags & 262144) == 0 {
      "select"
    } else if field_type == "Tx" && (flags & 4096) != 0 {
      "textarea"
    } else {
      "input"
    },
    class_name="editor-field",
  )
  let values = edit_array(json_field(entry, "values")).map(json_string)
  let id = edit_string(entry, "id")
  let label = edit_string(entry, "field_label")
  control.set_attribute(
    "aria-label",
    if label != "" {
      label
    } else {
      "PDF 表单字段 " + id
    },
  )
  set_data(control, "editorId", id)
  set_data(control, "fieldName", edit_string(entry, "field_name"))
  control.set_property("disabled", @js.Value::cast_from(!editable))
  if field_type == "Btn" {
    control.set_attribute(
      "type",
      if (flags & 32768) != 0 {
        "radio"
      } else {
        "checkbox"
      },
    )
    control.set_attribute(
      "name",
      "pdf-field-" + edit_string(entry, "field_name"),
    )
    control.set_property(
      "checked",
      @js.Value::cast_from(edit_bool(entry, "checked")),
    )
  } else if field_type == "Ch" && (flags & 262144) == 0 {
    control.set_property(
      "multiple",
      @js.Value::cast_from((flags & 2097152) != 0),
    )
    if (flags & 131072) == 0 {
      control.set_attribute("size", "4")
    }
    for option in edit_array(json_field(entry, "options")) {
      let item = make_element("option")
      item.set_attribute("value", edit_string(option, "export_value"))
      set_text(item, edit_string(option, "display_value"))
      item.set_property(
        "selected",
        @js.Value::cast_from(edit_bool(option, "selected")),
      )
      append_element(control, item)
    }
  } else {
    control.set_attribute(
      "type",
      if (flags & 8192) != 0 {
        "password"
      } else {
        "text"
      },
    )
    control.set_property(
      "value",
      @js.Value::cast_from(values.get(0).unwrap_or("")),
    )
    let max = edit_number(json_field(entry, "max_length")).to_int()
    if max > 0 {
      control.set_attribute("maxlength", max.to_string())
    }
    control.set_property("spellcheck", @js.Value::cast_from(false))
  }
  fn read_values() -> Array[String] {
    if field_type == "Btn" {
      [
        if native_field_checked(control) {
          edit_string(entry, "on_value")
        } else {
          "Off"
        },
      ]
    } else {
      native_field_values(control).iter().collect()
    }
  }
  control.add_event_listener("input", _ => {
    if generation != state.document_generation {
      return
    }
    editor.pending_input = ToJson::to_json(read_values()) !=
      json_field(entry, "values")
    notify()
  })
  control.add_event_listener("change", _ => {
    let values = read_values()
    let indices = if field_type == "Ch" && (flags & 262144) == 0 {
      ToJson::to_json(native_field_indices(control))
    } else {
      Json::null()
    }
    // Capture native values before an async redraw unmounts the control.
    launch(() => {
      if generation != state.document_generation {
        return
      }
      let mut patch : Json = {
        "kind": "field",
        "id": id,
        "page": json_field(entry, "page"),
        "values": values,
        "field_name": edit_string(entry, "field_name"),
      }
      if indices != Json::null() {
        patch = edit_put(patch, "indices", indices)
      }
      if field_type == "Tx" &&
        values.get(0) is Some(text) &&
        text.iter().any(c => c.to_int() > 255) {
        patch = edit_put(
          patch,
          "image",
          editor_text_image(
            text,
            json_field(entry, "bounds"),
            12.0,
            "#000000",
            (flags & 8192) != 0,
          ),
        )
      }
      editor_commit(patch)
    })
  })
  Some(control)
}

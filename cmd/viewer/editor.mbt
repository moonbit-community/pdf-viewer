///|
async fn editor_apply_snapshot(changes : Array[Json], generation : Int) -> Bool {
  ignore(
    call("apply_edits", args=[
      @js.Value::cast_from(ToJson::to_json(changes).stringify()),
    ]),
  )
  if generation != state.document_generation {
    return false
  }
  editor_flush_field()
  clear_selection()
  clear_search()
  cancel_thumbnails()
  editor.selected = Json::null()
  repaint(invalidate=true)
  if state.sidebar == Some(Thumbnails) {
    for
      preview in element("sidebar-content")
      .query_selector_all(".thumbnail-preview")
      .iter() {
      clear_children(preview)
    }
    start_thumbnails()
  }
  true
}

///|
async fn editor_commit(patch : Json) -> Unit {
  editor_commit_batch([patch])
}

///|
async fn editor_commit_batch(patches : Array[Json]) -> Unit {
  let generation = state.document_generation
  while editor.applying {
    native_frame().wait()
    if generation != state.document_generation {
      return
    }
  }
  if state.count == 0 || patches.is_empty() {
    return
  }
  editor.applying = true
  state.error = ""
  notify()
  try {
    let mut next = editor_changes()
    for patch in patches {
      let id = json_string_field(patch, "id")
      let previous = next
        .filter(entry => json_string_field(entry, "id") == id)
        .get(0)
      let field_name = json_string_field(patch, "field_name")
      next = next.filter(entry => {
        json_string_field(entry, "id") != id &&
        !(json_string_field(patch, "kind") == "field" &&
        field_name != "" &&
        json_string_field(entry, "kind") == "field" &&
        json_string_field(entry, "field_name") == field_name)
      })
      let patch = if previous is Some(previous) &&
        (
          json_string_field(previous, "kind") == "add" ||
          (
            json_string_field(previous, "kind") == "update" &&
            json_string_field(patch, "kind") == "update"
          )
        ) {
        let mut merged = previous
        if patch is Object(fields) {
          for key, value in fields {
            merged = json_put(merged, key, value)
          }
        }
        json_put(merged, "kind", json_field(previous, "kind"))
      } else {
        patch
      }
      if !(json_string_field(patch, "kind") == "add" &&
        json_string_field(patch, "delete") == "true") {
        next.push(patch)
      }
    }
    state.current_page = json_number(json_field(patches[0], "page")).to_int()
    if editor_apply_snapshot(next, generation) {
      editor.history = editor.history[:editor.cursor + 1].to_owned()
      editor.history.push(next)
      editor.cursor += 1
      editor.pending_input = false
      // Keep at most 100 undo steps. Snapshot arrays share immutable JSON
      // values, including image data; edits do not multiply pixel storage.
      if editor.history.length() > 101 {
        ignore(editor.history.remove(0))
        editor.cursor -= 1
      }
      editor.status = "Changes applied. Download to save."
    }
  } catch {
    error => if generation == state.document_generation { show_error(error) }
  }
  if generation == state.document_generation {
    editor.applying = false
    notify()
  }
}

///|
async fn editor_history(delta : Int) -> Unit {
  let generation = state.document_generation
  while editor.applying {
    native_frame().wait()
    if generation != state.document_generation {
      return
    }
  }
  let cursor = editor.cursor + delta
  if cursor < 0 || cursor >= editor.history.length() {
    return
  }
  editor.applying = true
  notify()
  try {
    if editor_apply_snapshot(editor.history[cursor], generation) {
      editor.cursor = cursor
      editor.status = if delta < 0 { "Undone" } else { "Redone" }
    }
  } catch {
    error => if generation == state.document_generation { show_error(error) }
  }
  if generation == state.document_generation {
    editor.applying = false
    notify()
  }
}

///|
async fn editor_save() -> Unit {
  let generation = state.document_generation
  while state.layers_busy {
    native_frame().wait()
    if generation != state.document_generation {
      return
    }
  }
  editor_flush_field()
  while editor.applying {
    native_frame().wait()
    if generation != state.document_generation {
      return
    }
  }
  if editor_changes().is_empty() {
    editor.pending_input = false
    if state.file is Some(file) {
      download_native(file, state.file_name)
      editor.saved = "[]"
      editor.status = "Downloaded PDF"
      notify()
    }
    return
  }
  editor.applying = true
  notify()
  try {
    let result = call("save_pdf")
    if generation == state.document_generation {
      let name = if state.file_name.to_lower().has_suffix(".pdf") {
        state.file_name[:state.file_name.length() - 4].to_owned()
      } else {
        state.file_name
      }
      download_base64(
        value_string(result, "data"),
        name + "-edited.pdf",
        "application/pdf",
      )
      editor.saved = ToJson::to_json(editor_changes()).stringify()
      editor.pending_input = false
      editor.status = "Downloaded edited PDF"
    }
  } catch {
    error => if generation == state.document_generation { show_error(error) }
  }
  if generation == state.document_generation {
    editor.applying = false
    notify()
  }
}

///|
async fn editor_handle(action : EditorAction) -> Unit {
  match action {
    Toggle => {
      if !editor.enabled {
        let generation = state.document_generation
        editor.applying = true
        editor.status = "Preparing document for editing"
        notify()
        let result = call("editor_info") catch {
          error => {
            if generation != state.document_generation {
              return
            }
            editor.applying = false
            notify()
            raise error
          }
        }
        if generation != state.document_generation {
          return
        }
        editor.applying = false
        if !value_bool(result, "editable") {
          raise ViewerError("edit-unavailable", value_string(result, "reason"))
        }
        editor.annotations = value_bool(result, "annotations")
      }
      editor.enabled = !editor.enabled
      editor.selected = Json::null()
      editor.status = if editor.enabled {
        if editor.annotations {
          "Fill forms, or select a tool and drag on the page"
        } else {
          "This PDF allows form filling but prohibits annotation changes"
        }
      } else {
        ""
      }
      editor_refresh_layers()
      notify()
    }
    Tool(tool) => {
      if !editor.annotations && tool != "select" {
        return
      }
      if tool == "highlight-selection" {
        editor_highlight_selection()
        return
      }
      if tool == "ink" || tool == "signature" {
        editor.size = 2.0
      } else if tool == "text" {
        editor.size = 14.0
      }
      editor.tool = tool
      editor.selected = Json::null()
      editor.gesture = None
      editor.ink_id = ""
      editor.ink_page = 0
      editor.status = match tool {
        "text" => "Enter text, then drag a text box on the page"
        "highlight" => "Drag to highlight an area on the page"
        "ink" => "Draw ink on the page"
        "signature" => "Draw your signature on the page"
        "image" =>
          "Select a signature image, then drag its placement area on the page"
        _ =>
          "Select an annotation to edit, move, or resize from its lower-right corner"
      }
      editor_refresh_layers()
      notify()
    }
    Text(text) => {
      editor.text = text
      notify()
    }
    Color(color) => {
      if color.length() == 7 {
        editor.color = color
      }
      notify()
    }
    Size(value) => {
      editor.size = parse_float(value).max(0.5).min(200.0)
      notify()
    }
    Undo => editor_history(-1)
    Redo => editor_history(1)
    Delete => {
      if editor.selected == Json::null() {
        return
      }
      let patch : Json = {
        "kind": "delete",
        "id": json_string_field(editor.selected, "id"),
        "page": json_field(editor.selected, "page"),
      }
      let previous = editor_changes()
        .filter(entry => {
          json_string_field(entry, "id") ==
          json_string_field(editor.selected, "id")
        })
        .get(0)
      editor_commit(
        if previous is Some(previous) &&
          json_string_field(previous, "kind") == "add" {
          json_put(patch, "delete", Json::string("true"))
        } else {
          patch
        },
      )
    }
    ApplyText => {
      if editor.selected == Json::null() {
        return
      }
      let mut patch : Json = {
        "kind": "update",
        "id": json_string_field(editor.selected, "id"),
        "page": json_field(editor.selected, "page"),
        "contents": editor.text,
        "color": edit_rgb(),
        "size": editor.size,
      }
      if json_string_field(editor.selected, "subtype") == "free-text" ||
        json_string_field(editor.selected, "subtype") == "freetext" {
        patch = json_put(
          patch,
          "image",
          if editor.text.iter().any(c => c.to_int() > 255) {
            editor_text_image(
              editor.text,
              json_field(editor.selected, "bounds"),
              editor.size,
              editor.color,
              false,
            )
          } else {
            Json::null()
          },
        )
      }
      editor_commit(patch)
    }
    PickImage(file) => {
      let generation = state.document_generation
      editor.image_generation += 1
      let token = editor.image_generation
      let image = native_signature_image(file).wait() catch {
        error => {
          if generation != state.document_generation ||
            token != editor.image_generation {
            return
          }
          raise error
        }
      }
      if generation != state.document_generation ||
        token != editor.image_generation {
        return
      }
      editor.image = value_json(image)
      editor.tool = "image"
      editor.status = "Drag the image signature placement area on the page"
      editor_refresh_layers()
      notify()
    }
  }
}

///|
fn editor_flush_field() -> Unit {
  native_blur_field()
}

///|
extern "js" fn native_blur_field() -> Unit =
  #| () => {const active=document.activeElement;if(active?.matches('.editor-field, .xfa-editor-field')) active.blur();}

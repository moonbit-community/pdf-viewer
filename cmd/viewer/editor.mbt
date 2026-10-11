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
  repaint()
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
  let generation = state.document_generation
  while editor.applying {
    native_frame().wait()
    if generation != state.document_generation {
      return
    }
  }
  if state.count == 0 {
    return
  }
  editor.applying = true
  state.error = ""
  notify()
  try {
    let id = edit_string(patch, "id")
    let previous = editor_changes()
      .filter(entry => edit_string(entry, "id") == id)
      .get(0)
    let field_name = edit_string(patch, "field_name")
    let next = editor_changes().filter(entry => {
      edit_string(entry, "id") != id &&
      !(edit_string(patch, "kind") == "field" &&
      field_name != "" &&
      edit_string(entry, "kind") == "field" &&
      edit_string(entry, "field_name") == field_name)
    })
    let patch = if previous is Some(previous) &&
      (
        edit_string(previous, "kind") == "add" ||
        (
          edit_string(previous, "kind") == "update" &&
          edit_string(patch, "kind") == "update"
        )
      ) {
      let mut merged = previous
      if patch is Object(fields) {
        for key, value in fields {
          merged = edit_put(merged, key, value)
        }
      }
      edit_put(merged, "kind", json_field(previous, "kind"))
    } else {
      patch
    }
    if !(edit_string(patch, "kind") == "add" &&
      edit_string(patch, "delete") == "true") {
      next.push(patch)
    }
    state.current_page = edit_number(json_field(patch, "page")).to_int()
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
      editor.status = "修改已应用，可下载保存"
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
      editor.status = if delta < 0 { "已撤销" } else { "已重做" }
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
      editor.status = "已下载修改后的 PDF"
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
        if state.xfa {
          raise ViewerError(
            "edit-unavailable", "动态 XFA 文档暂不支持编辑和保存",
          )
        }
        let generation = state.document_generation
        editor.applying = true
        editor.status = "正在准备编辑文档"
        notify()
        let result = call("editor_info") catch {
          error => {
            if generation == state.document_generation {
              editor.applying = false
              notify()
            }
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
      }
      editor.enabled = !editor.enabled
      editor.selected = Json::null()
      editor.status = if editor.enabled {
        "可填写表单；选择工具后在页面拖动"
      } else {
        ""
      }
      editor_refresh_layers()
      notify()
    }
    Tool(tool) => {
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
        "text" => "输入文字后，在页面拖出文本框"
        "highlight" => "在页面拖动标记区域"
        "ink" => "在页面上绘制笔迹"
        "signature" => "在页面上写下签名"
        "image" => "选择签名图片后，在页面拖出放置区域"
        _ => "选择批注可修改、拖动或调整右下角大小"
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
        "id": edit_string(editor.selected, "id"),
        "page": json_field(editor.selected, "page"),
      }
      let previous = editor_changes()
        .filter(entry => {
          edit_string(entry, "id") == edit_string(editor.selected, "id")
        })
        .get(0)
      editor_commit(
        if previous is Some(previous) && edit_string(previous, "kind") == "add" {
          edit_put(patch, "delete", Json::string("true"))
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
        "id": edit_string(editor.selected, "id"),
        "page": json_field(editor.selected, "page"),
        "contents": editor.text,
        "color": edit_rgb(),
        "size": editor.size,
      }
      if edit_string(editor.selected, "subtype") == "free-text" ||
        edit_string(editor.selected, "subtype") == "freetext" {
        patch = edit_put(
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
      let image = native_signature_image(file).wait()
      if generation != state.document_generation ||
        token != editor.image_generation {
        return
      }
      editor.image = value_json(image)
      editor.tool = "image"
      editor.status = "在页面拖出图片签名的放置区域"
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
  #| () => {const active=document.activeElement;if(active?.matches('.editor-field')) active.blur();}

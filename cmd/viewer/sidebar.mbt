///|
let thumbnail_tasks : Map[Int, (@js_async.AbortController, Int)] = Map([])

///|
let thumbnail_generation : Ref[Int] = Ref(0)

///|
fn cancel_thumbnails() -> Unit {
  abort(state.thumbnail_controller)
  if state.thumbnail_observer is Some(observer) {
    observer.disconnect()
  }
  state.thumbnail_observer = None
  for (controller, _) in thumbnail_tasks.values() {
    controller.abort()
  }
  thumbnail_tasks.clear()
  thumbnail_generation.val += 1
}

///|
fn close_sidebar() -> Unit {
  cancel_thumbnails()
  state.sidebar = None
  notify()
}

///|
extern "js" fn thumbnail_observer(
  callback : (FixedArray[@js.Value]) -> Unit,
) -> @dom.IntersectionObserver =
  #| callback => new IntersectionObserver(callback,{root:document.getElementById("sidebar"),rootMargin:"150px 0px"})

///|
extern "js" fn entry_target(entry : @js.Value) -> @dom.Element =
  #| entry => entry.target

///|
fn start_thumbnails() -> Unit {
  cancel_thumbnails()
  let controller = @js_async.AbortController::new()
  state.thumbnail_controller = Some(controller)
  let observer = thumbnail_observer(entries => {
    if controller_aborted(controller) {
      return
    }
    for entry in entries {
      let button = entry_target(entry)
      let number = parse_float(element_data(button, "page")).to_int()
      let preview = button.query_selector(".thumbnail-preview").unwrap()
      if !value_bool(entry, "isIntersecting") {
        if thumbnail_tasks.get(number) is Some((task, _)) {
          task.abort()
        }
        ignore(thumbnail_tasks.remove(number))
        clear_children(preview)
        continue
      }
      if preview.get_children().iter().count() > 0 ||
        thumbnail_tasks.contains(number) {
        continue
      }
      let task = @js_async.AbortController::new()
      thumbnail_generation.val += 1
      let token = thumbnail_generation.val
      thumbnail_tasks[number] = (task, token)
      ignore(
        @js_async.Promise::from_async(() => {
          try {
            let result = call(
              "render_page",
              args=[
                @js.Value::cast_from(number),
                @js.Value::cast_from(0.12),
                @js.Value::cast_from(0),
              ],
              controller=task,
              priority=-5,
            )
            if controller_aborted(task) || controller_aborted(controller) {
              return
            }
            let (surface, diagnostics) = if value_bool(result, "xfa") {
              (
                create_xfa(result, "display").wait(),
                @js.Value::cast_from(
                  (@js.Nullable::null() : @js.Nullable[Unit]),
                ),
              )
            } else {
              let canvas = make_element("canvas")
              let rendered = paint_canvas(canvas, result, 1.0).wait()
              (canvas, value_field(rendered, "diagnostics"))
            }
            if controller_aborted(task) || controller_aborted(controller) {
              return
            }
            clear_children(preview)
            append_element(preview, surface)
            if value_bool(result, "xfa") {
              let viewport = value_field(
                value_field(result, "layer"),
                "viewport",
              )
              set_style(
                preview,
                "width",
                "\{value_number(viewport, "width")}px",
              )
              set_style(
                preview,
                "height",
                "\{value_number(viewport, "height")}px",
              )
            }
            report_diagnostics(diagnostics)
          } catch {
            error =>
              if !controller_aborted(task) && !controller_aborted(controller) {
                show_error(error)
              }
          }
          if thumbnail_tasks.get(number) is Some((_, active)) && active == token {
            ignore(thumbnail_tasks.remove(number))
          }
        }),
      )
    }
  })
  state.thumbnail_observer = Some(observer)
  for
    button in element("sidebar-content")
    .query_selector_all(".thumbnail-item")
    .iter() {
    observer.observe(button)
  }
}

///|
async fn toggle_sidebar(sidebar : Sidebar) -> Unit {
  if state.sidebar == Some(sidebar) {
    close_sidebar()
    return
  }
  cancel_thumbnails()
  state.sidebar = Some(sidebar)
  flush_ui()
  if state.sidebar == Some(Thumbnails) {
    start_thumbnails()
  }
}

///|
fn outline_view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let entries = json_array(json_field(model.document_info, "outline"))
  if entries.is_empty() {
    return @html.p(class="sidebar-empty", "此文档没有目录")
  }
  @html.fragment(
    entries.map(entry => {
      let destination = json_field(entry, "destination")
      let page = json_int(json_field(destination, "page"))
      let title = json_string(json_field(entry, "title"))
      @html.button(
        class="sidebar-item",
        type_="button",
        disabled=page == 0 || json_bool(json_field(destination, "remote")),
        title=if page != 0 {
          "第 \{page} 页"
        } else {
          "此条目没有可定位的本地页面"
        },
        attrs=@html.Attrs::build().style(
          "padding-left",
          "\{12 + json_int(json_field(entry, "level")).min(8) * 16}px",
        ),
        on_click=emit(Navigate(page, true)),
        if title == "" {
          "未命名条目"
        } else {
          title
        },
      )
    }),
  )
}

///|
fn info_view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let info = json_field(model.document_info, "info")
  let rows : Array[@html.Html] = []
  for
    (label, key) in [
      ("标题", "Title"),
      ("作者", "Author"),
      ("主题", "Subject"),
      ("创建者", "Creator"),
      ("生成器", "Producer"),
      ("页数", "Pages"),
      ("版本", "Version"),
    ] {
    let field = json_field(info, key)
    let value = if key == "Pages" && field is Null {
      model.count.to_string()
    } else if key == "Version" && field is Array(values) {
      values.map(json_string).join(".")
    } else {
      json_string(field)
    }
    if value == "" {
      continue
    }
    rows.push(@html.dt(label))
    rows.push(@html.dd(value))
  }
  if rows.is_empty() {
    rows.push(
      @html.dd(class="sidebar-empty", "此文档没有公开的 Info 字段"),
    )
  }
  let metadata = json_field(model.document_info, "metadata")
  let available = json_bool(json_field(metadata, "available"))
  let attachments = json_array(json_field(model.document_info, "attachments"))
  let children : Array[@html.Html] = [
    @html.dl(class="info-list", rows),
    @html.div(class="sidebar-section", [
      @html.span(
        if available {
          "XMP metadata · \{json_int(json_field(metadata, "size"))} bytes"
        } else {
          "没有嵌入 XMP metadata"
        },
      ),
      @html.button(
        class="sidebar-item",
        hidden=!available,
        on_click=emit(DownloadMetadata),
        "下载 XMP",
      ),
    ]),
    @html.h3("附件（\{attachments.length()}）"),
  ]
  if attachments.is_empty() {
    children.push(@html.p(class="sidebar-empty", "此文档没有嵌入附件"))
  }
  for attachment in attachments {
    let name = json_string(json_field(attachment, "name"))
    let description = json_string(json_field(attachment, "description"))
    children.push(
      @html.div(class="attachment-row", [
        @html.span(
          title=if description == "" { name } else { description },
          "\{name} · \{json_int(json_field(attachment, "size"))} bytes",
        ),
        @html.button(
          class="sidebar-item",
          disabled=!json_bool(json_field(attachment, "available")),
          on_click=emit(
            DownloadAttachment(json_int(json_field(attachment, "index")), name),
          ),
          "下载",
        ),
      ]),
    )
  }
  @html.fragment(children)
}

///|
fn thumbnails_view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let children : Array[@html.Html] = []
  let limit = model.count.min(200)
  for number in 1..<=limit {
    let label = model.labels.get(number - 1).unwrap_or(number.to_string())
    children.push(
      @html.button(
        class="sidebar-item thumbnail-item",
        type_="button",
        attrs=@html.Attrs::build()
          .data_set("page", number.to_string())
          .aria_label("第 \{label} 页"),
        on_click=emit(Navigate(number, true)),
        [
          @html.div(class="thumbnail-preview", ([] : Array[@html.Html])),
          @html.span(class="thumbnail-label", label),
        ],
      ),
    )
  }
  if model.count > limit {
    children.push(
      @html.p(class="sidebar-empty", "仅显示前 \{limit} 页缩略图"),
    )
  }
  @html.fragment(children)
}

///|
async fn download_attachment(index : Int, name : String) -> Unit {
  let generation = state.document_generation
  try {
    let result = call("download_attachment", args=[@js.Value::cast_from(index)])
    if generation == state.document_generation {
      download_base64(
        value_string(result, "data"),
        if name == "" {
          "attachment.bin"
        } else {
          name
        },
        "application/octet-stream",
      )
    }
  } catch {
    error => if generation == state.document_generation { show_error(error) }
  }
}

///|
async fn download_metadata() -> Unit {
  let generation = state.document_generation
  try {
    let result = call("download_metadata")
    if generation == state.document_generation {
      download_base64(
        value_string(result, "data"),
        "metadata.xmp",
        "application/rdf+xml",
      )
    }
  } catch {
    error => if generation == state.document_generation { show_error(error) }
  }
}

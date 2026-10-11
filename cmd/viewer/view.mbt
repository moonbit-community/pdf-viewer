///|
fn control(
  id : String,
  label : String,
  caption : String,
  disabled : Bool,
  command : @cmd.Cmd,
) -> @html.Html {
  @html.button(
    id~,
    title=label,
    attrs=@html.Attrs::build().aria_label(label),
    disabled~,
    on_click=command,
    caption,
  )
}

///|
fn checkbox(
  id : String,
  title : String,
  caption : String,
  checked : Bool,
  disabled : Bool,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  @html.label(title~, [
    @html.input(
      id~,
      input_type=Checkbox,
      checked~,
      attrs=@html.Attrs::build().disabled(disabled),
      on_change=@cmd.Emit(_ => emit(SearchOptions)),
    ),
    @html.text(caption),
  ])
}

///|
fn view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let disabled = model.count == 0
  let zoom_options : Array[@html.Html] = []
  let zoom_values = [
    ("fit", "适合宽度"),
    ("0.5", "50%"),
    ("0.75", "75%"),
    ("1", "100%"),
    ("1.25", "125%"),
    ("1.5", "150%"),
    ("2", "200%"),
  ]
  for (value, label) in zoom_values {
    zoom_options.push(@html.option(value~, label))
  }
  if !zoom_values.iter().any(pair => pair.0 == model.zoom) {
    zoom_options.push(
      @html.option(
        value=model.zoom,
        attrs=@html.Attrs::build().data_set("custom", "true"),
        "\{(parse_float(model.zoom) * 100.0).round().to_int()}%",
      ),
    )
  }
  let sidebar_title = match model.sidebar {
    Some(Outline) | None => "目录"
    Some(Thumbnails) => "缩略图"
    Some(Info) => "文档信息"
    Some(Layers) => "图层"
  }
  let sidebar = match model.sidebar {
    Some(Outline) => outline_view(model, emit)
    Some(Thumbnails) => thumbnails_view(model, emit)
    Some(Info) => info_view(model, emit)
    Some(Layers) => layers_view(model, emit)
    None => @html.fragment([])
  }
  let viewer_class = (if model.view_mode == "page" { "page-mode " } else { "" }) +
    (if model.drag_over { "drag-over" } else { "" })
  let page_label = model.labels
    .get(model.page - 1)
    .unwrap_or(model.page.to_string())
  @html.fragment([
    @html.header(
      class="toolbar",
      attrs=@html.Attrs::build().aria_label("文档工具栏"),
      [
        @html.a(class="brand", href="./", [
          @html.text("MoonBit "),
          @html.strong("PDF"),
        ]),
        @html.div(class="file-controls", [
          @html.button(
            id="open-file",
            type_="button",
            on_click=emit(Open),
            "打开 PDF",
          ),
          @html.input(
            id="file-input",
            input_type=File,
            accept="application/pdf,.pdf",
            hidden=true,
            on_change=@cmd.Emit(_ => {
              match picked_file().to_option() {
                Some(file) => emit(FileChanged(file))
                None => @cmd.none
              }
            }),
          ),
          @html.span(
            id="file-name",
            title=model.file_path,
            if model.file_name == "" {
              "未打开文档"
            } else {
              model.file_name
            },
          ),
          @html.button(
            id="outline-toggle",
            type_="button",
            disabled~,
            on_click=emit(ToggleSidebar(Outline)),
            "目录",
          ),
          @html.button(
            id="thumbnail-toggle",
            type_="button",
            disabled~,
            on_click=emit(ToggleSidebar(Thumbnails)),
            "缩略图",
          ),
          @html.button(
            id="info-toggle",
            type_="button",
            disabled~,
            on_click=emit(ToggleSidebar(Info)),
            "信息",
          ),
          @html.button(
            id="layers-toggle",
            type_="button",
            hidden=model.layers is Null,
            disabled~,
            on_click=emit(ToggleSidebar(Layers)),
            "图层",
          ),
        ]),
        @html.div(class="page-controls", [
          control(
            "previous-page",
            "上一页",
            "↑",
            disabled || model.page <= 1,
            emit(MovePage(-1)),
          ),
          @html.input(
            id="page-number",
            input_type=Number,
            min=1,
            max=model.count.max(1),
            value=model.page.to_string(),
            title="第 \{model.page} 页（\{page_label}）",
            attrs=@html.Attrs::build().aria_label("页码").disabled(disabled),
            on_change=@cmd.Emit(value => {
              emit(Navigate(parse_float(value).to_int(), true))
            }),
          ),
          @html.span(id="page-count", "/ \{model.count}"),
          control(
            "next-page",
            "下一页",
            "↓",
            disabled || model.page >= model.count,
            emit(MovePage(1)),
          ),
        ]),
        @html.div(class="zoom-controls", [
          control(
            "zoom-out",
            "缩小",
            "−",
            disabled,
            emit(Scale(1.0 / 1.25)),
          ),
          @html.select(
            id="zoom",
            disabled~,
            attrs=@html.Attrs::build()
              .aria_label("缩放")
              .value_prop(model.zoom),
            on_change=@cmd.Emit(value => emit(ChangeZoom(value))),
            zoom_options,
          ),
          control("zoom-in", "放大", "+", disabled, emit(Scale(1.25))),
          control("rotate", "顺时针旋转", "↻", disabled, emit(Rotate)),
          @html.select(
            id="view-mode",
            disabled~,
            attrs=@html.Attrs::build()
              .aria_label("页面模式")
              .value_prop(model.view_mode),
            on_change=@cmd.Emit(value => emit(ChangeView(value))),
            [
              @html.option(value="scroll", "连续"),
              @html.option(value="page", "单页"),
            ],
          ),
        ]),
        @html.div(
          class="search-controls",
          attrs=@html.Attrs::build().role("search").aria_label("搜索文档"),
          [
            @html.input(
              id="search-query",
              input_type=Search,
              placeholder="搜索文档",
              value=model.search_input,
              on_input=@cmd.Emit(value => emit(SearchInput(value))),
              attrs=@html.Attrs::build()
                .aria_label("搜索文档")
                .disabled(disabled)
                .on_keydown(event => {
                  if event.key() == "Enter" {
                    event.prevent_default()
                  }
                  emit(SearchKey(event))
                }),
            ),
            control(
              "search-previous",
              "上一个结果",
              "↑",
              model.search_count == 0,
              emit(JumpSearch(-1)),
            ),
            control(
              "search-next",
              "下一个结果",
              "↓",
              model.search_count == 0,
              emit(JumpSearch(1)),
            ),
            checkbox(
              "search-case",
              "区分大小写",
              " Aa",
              model.search_case,
              disabled,
              emit,
            ),
            checkbox(
              "search-whole",
              "只匹配完整单词",
              " 词",
              model.search_whole,
              disabled,
              emit,
            ),
            checkbox(
              "search-diacritic",
              "忽略变音符号",
              " é",
              model.search_diacritic,
              disabled,
              emit,
            ),
            @html.span(
              id="search-status",
              attrs=@html.Attrs::build().aria_live("polite"),
              model.search_status,
            ),
          ],
        ),
        control(
          "print",
          "打印",
          "打印",
          disabled || model.printing || model.layers_busy,
          emit(Print),
        ),
        @html.button(
          id="edit-toggle",
          disabled=disabled || model.editor.busy || model.layers_busy,
          on_click=emit(Edit(Toggle)),
          if model.editor.enabled {
            "结束编辑"
          } else {
            "编辑 / 填写"
          },
        ),
        @html.button(
          id="download",
          disabled=disabled || model.editor.busy || model.layers_busy,
          on_click=emit(Download),
          "下载",
        ),
      ],
    ),
    editor_view(model.editor, emit),
    @html.main_(
      id="viewer",
      class=viewer_class,
      attrs=@html.Attrs::build()
        .tabindex(0)
        .aria_label("PDF 文档")
        .aria_busy(model.busy.to_string())
        .on_dragover(event => {
          event.prevent_default()
          emit(DragOver)
        })
        .on_dragleave(_ => emit(DragLeave))
        .on_drop(event => {
          event.prevent_default()
          emit(Drop(dropped_file(event).to_option()))
        })
        .on_pointerdown(_ => emit(PointerDown))
        .on_scroll(_ => emit(Scroll))
        .on_keydown(event => {
          if !key_from_control(event) &&
            (
              (
                (event.ctrl_key() || event.meta_key()) &&
                event.key().to_lower() == "a"
              ) ||
              (
                event.shift_key() &&
                ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].contains(
                  event.key(),
                )
              )
            ) {
            event.prevent_default()
          }
          emit(ViewerKey(event))
        }),
      [
        @html.section(id="empty-state", hidden=!disabled, [
          @html.div(
            class="document-symbol",
            attrs=@html.Attrs::build().aria_hidden("true"),
            "PDF",
          ),
          @html.h1("打开一份文档"),
          @html.p("将 PDF 拖到这里，或选择本地文件。"),
          @html.p(
            "阅读、搜索、填写表单，或添加批注和签名。",
          ),
          @html.button(
            id="open-empty",
            type_="button",
            on_click=emit(Open),
            "选择 PDF 文件",
          ),
          @html.p(class="hint", "文档在浏览器中读取和渲染。"),
        ]),
        @html.div(id="pages", ([] : Array[@html.Html])),
      ],
    ),
    @html.div(
      id="print-pages",
      attrs=@html.Attrs::build().aria_hidden("true").inert(true),
      ([] : Array[@html.Html]),
    ),
    @html.aside(
      id="sidebar",
      hidden=model.sidebar is None,
      attrs=@html.Attrs::build().aria_label("文档导航"),
      [
        @html.div(class="sidebar-header", [
          @html.strong(id="sidebar-title", sidebar_title),
          control(
            "sidebar-close",
            "关闭面板",
            "×",
            false,
            emit(CloseSidebar),
          ),
        ]),
        @html.div(id="sidebar-content", sidebar),
      ],
    ),
    @html.footer(class="status-bar", [
      @html.span(
        id="status",
        attrs=@html.Attrs::build().role("status").aria_live("polite"),
        model.status,
      ),
      @html.span(id="selection-status", model.selection_status),
      @html.button(
        id="copy-selection",
        disabled=!model.can_copy,
        on_click=emit(Copy),
        "复制选中文字",
      ),
    ]),
    @html.div(
      id="error",
      hidden=model.error == "",
      attrs=@html.Attrs::build().role("alert"),
      model.error,
    ),
  ])
}

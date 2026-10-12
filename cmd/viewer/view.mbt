///|
fn view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let disabled = model.count == 0
  let sidebar_title = match model.sidebar {
    Some(Outline) | None => "Outline"
    Some(Thumbnails) => "Thumbnails"
    Some(Info) => "Document information"
    Some(Layers) => "Layers"
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
  @html.fragment([
    toolbar_view(model, emit),
    editor_view(model.editor, emit),
    @html.main_(
      id="viewer",
      class=viewer_class,
      attrs=@html.Attrs::build()
        .tabindex(0)
        .aria_label("PDF document")
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
          @html.h1("Open a document"),
          @html.p("Drop a PDF here or choose a local file."),
          @html.p(
            "Read, search, fill forms, and add annotations and signatures.",
          ),
          @html.button(
            id="open-empty",
            type_="button",
            on_click=emit(Open),
            "Choose a PDF file",
          ),
          @html.p(
            class="hint",
            "Documents are read and rendered in your browser.",
          ),
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
      attrs=@html.Attrs::build().aria_label("Document navigation"),
      [
        @html.div(class="sidebar-header", [
          @html.strong(id="sidebar-title", sidebar_title),
          control(
            "sidebar-close",
            "Close panel",
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
        "Copy selected text",
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

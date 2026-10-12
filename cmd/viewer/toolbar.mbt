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
fn zoom_options(zoom : String) -> Array[@html.Html] {
  let zoom_options : Array[@html.Html] = []
  let zoom_values = [
    ("fit", "Fit width"),
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
  if !zoom_values.iter().any(pair => pair.0 == zoom) {
    zoom_options.push(
      @html.option(
        value=zoom,
        attrs=@html.Attrs::build().data_set("custom", "true"),
        "\{(parse_float(zoom) * 100.0).round().to_int()}%",
      ),
    )
  }
  zoom_options
}

///|
fn toolbar_view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let disabled = model.count == 0
  let page_label = model.labels
    .get(model.page - 1)
    .unwrap_or(model.page.to_string())
  @html.header(
    class="toolbar",
    attrs=@html.Attrs::build().aria_label("Document toolbar"),
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
          "Open PDF",
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
            "No document open"
          } else {
            model.file_name
          },
        ),
        @html.button(
          id="outline-toggle",
          type_="button",
          disabled~,
          on_click=emit(ToggleSidebar(Outline)),
          "Outline",
        ),
        @html.button(
          id="thumbnail-toggle",
          type_="button",
          disabled~,
          on_click=emit(ToggleSidebar(Thumbnails)),
          "Thumbnails",
        ),
        @html.button(
          id="info-toggle",
          type_="button",
          disabled~,
          on_click=emit(ToggleSidebar(Info)),
          "Info",
        ),
        @html.button(
          id="layers-toggle",
          type_="button",
          hidden=model.layers is Null,
          disabled~,
          on_click=emit(ToggleSidebar(Layers)),
          "Layers",
        ),
      ]),
      @html.div(class="page-controls", [
        control(
          "previous-page",
          "Previous page",
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
          title="Page \{model.page} (\{page_label})",
          attrs=@html.Attrs::build()
            .aria_label("Page number")
            .disabled(disabled),
          on_change=@cmd.Emit(value => {
            emit(Navigate(parse_float(value).to_int(), true))
          }),
        ),
        @html.span(id="page-count", "/ \{model.count}"),
        control(
          "next-page",
          "Next page",
          "↓",
          disabled || model.page >= model.count,
          emit(MovePage(1)),
        ),
      ]),
      @html.div(class="zoom-controls", [
        control(
          "zoom-out",
          "Zoom out",
          "−",
          disabled,
          emit(Scale(1.0 / 1.25)),
        ),
        @html.select(
          id="zoom",
          disabled~,
          attrs=@html.Attrs::build().aria_label("Zoom").value_prop(model.zoom),
          on_change=@cmd.Emit(value => emit(ChangeZoom(value))),
          zoom_options(model.zoom),
        ),
        control("zoom-in", "Zoom in", "+", disabled, emit(Scale(1.25))),
        control("rotate", "Rotate clockwise", "↻", disabled, emit(Rotate)),
        @html.select(
          id="view-mode",
          disabled~,
          attrs=@html.Attrs::build()
            .aria_label("Page mode")
            .value_prop(model.view_mode),
          on_change=@cmd.Emit(value => emit(ChangeView(value))),
          [
            @html.option(value="scroll", "Continuous"),
            @html.option(value="page", "Single page"),
          ],
        ),
      ]),
      @html.div(
        class="search-controls",
        attrs=@html.Attrs::build().role("search").aria_label("Search document"),
        [
          @html.input(
            id="search-query",
            input_type=Search,
            placeholder="Search document",
            value=model.search_input,
            on_input=@cmd.Emit(value => emit(SearchInput(value))),
            attrs=@html.Attrs::build()
              .aria_label("Search document")
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
            "Previous result",
            "↑",
            model.search_count == 0,
            emit(JumpSearch(-1)),
          ),
          control(
            "search-next",
            "Next result",
            "↓",
            model.search_count == 0,
            emit(JumpSearch(1)),
          ),
          checkbox(
            "search-case",
            "Match case",
            " Aa",
            model.search_case,
            disabled,
            emit,
          ),
          checkbox(
            "search-whole",
            "Whole words only",
            " Word",
            model.search_whole,
            disabled,
            emit,
          ),
          checkbox(
            "search-diacritic",
            "Ignore diacritics",
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
        "Print",
        "Print",
        disabled || model.printing || model.layers_busy,
        emit(Print),
      ),
      @html.button(
        id="edit-toggle",
        disabled=disabled || model.editor.busy || model.layers_busy,
        on_click=emit(Edit(Toggle)),
        if model.editor.enabled {
          "Finish editing"
        } else {
          "Edit / Fill"
        },
      ),
      @html.button(
        id="download",
        disabled=disabled || model.editor.busy || model.layers_busy,
        on_click=emit(Download),
        "Download",
      ),
    ],
  )
}

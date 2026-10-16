///|
async fn layers_update(
  operation : String,
  args : FixedArray[@js.Value],
) -> Unit {
  if state.count == 0 || state.layers_busy {
    return
  }
  let generation = state.document_generation
  state.layers_busy = true
  state.error = ""
  notify()
  editor_flush_field()
  while editor.applying {
    native_frame().wait()
    if generation != state.document_generation {
      return
    }
  }
  cancel_thumbnails()
  clear_print()
  try {
    let result = call(operation, args~)
    if generation != state.document_generation {
      return
    }
    state.layers = value_json(value_field(result, "layers"))
    clear_selection()
    clear_search()
    repaint(preserve=false, invalidate=true)
    if generation != state.document_generation {
      return
    }
    if state.sidebar == Some(Thumbnails) {
      for
        preview in element("sidebar-content")
        .query_selector_all(".thumbnail-preview")
        .iter() {
        clear_children(preview)
      }
      start_thumbnails()
    }
  } catch {
    error => if generation == state.document_generation { show_error(error) }
  }
  if generation == state.document_generation {
    state.layers_busy = false
    flush_ui()
    if generation == state.document_generation {
      layers_restore_controls()
    }
  }
}

///|
fn layers_restore_controls() -> Unit {
  // The VDOM compares old/new properties. A rejected toggle leaves the model
  // unchanged, so explicitly reconcile native checked/value state after paint.
  for entry in json_array(json_field(state.layers, "groups")) {
    let number = json_int(json_field(entry, "id"))
    if @dom.document().get_element_by_id("layer-\{number}").to_option()
      is Some(control) {
      control.set_property(
        "checked",
        @js.Value::cast_from(json_bool(json_field(entry, "visible"))),
      )
    }
  }
  if @dom.document().get_element_by_id("layers-config").to_option()
    is Some(control) {
    let index = json_field(state.layers, "config_index")
    let selected = if index is Null { -1 } else { json_int(index) }
    control.set_property("value", @js.Value::cast_from(selected.to_string()))
  }
}

///|
fn layers_controls_busy(model : Model) -> Bool {
  // Layer updates wait for field commits. Disabling on field blur would eat
  // the pending pointer click, including while that commit repaints the page.
  model.layers_busy || (model.busy && !model.editor.busy) || model.printing
}

///|
fn layer_rows_view(
  rows : Array[Json],
  groups : Map[Int, Json],
  model : Model,
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  let children : Array[@html.Html] = []
  for row in rows {
    let id = json_field(row, "id")
    if id is Number(_, ..) && groups.get(json_int(id)) is Some(entry) {
      let number = json_int(id)
      let control = "layer-\{number}"
      let name = json_string(json_field(entry, "name"))
      let visible = json_bool(json_field(entry, "visible"))
      let locked = json_bool(json_field(entry, "locked"))
      let print_visible = json_bool(json_field(entry, "print_visible"))
      children.push(
        @html.label(
          class="layer-item",
          title=if locked {
            "Layer locked by the document"
          } else if visible != print_visible {
            "This layer has different display and print visibility"
          } else {
            name
          },
          [
            @html.input(
              id=control,
              input_type=Checkbox,
              checked=visible,
              attrs=@html.Attrs::build()
                .data_set("layer-id", number.to_string())
                .disabled(locked || layers_controls_busy(model)),
              on_change=@cmd.Emit(_ => {
                // Keep the native checkbox controlled until the Worker accepts
                // the toggle, including a rejected locked radio peer.
                element(control).set_property(
                  "checked",
                  @js.Value::cast_from(visible),
                )
                emit(LayerVisibility(number, !visible))
              }),
            ),
            @html.span(if name == "" { "Unnamed layer" } else { name }),
            @html.span(
              class="layer-hint",
              if locked {
                "Locked"
              } else if visible != print_visible {
                if print_visible {
                  "Visible in print"
                } else {
                  "Hidden in print"
                }
              } else {
                ""
              },
            ),
          ],
        ),
      )
    } else {
      let name = json_string(json_field(row, "name"))
      children.push(
        @html.div(class="layer-group", [
          @html.h3(
            class="layer-group-name",
            if name == "" {
              "Other layers"
            } else {
              name
            },
          ),
          layer_rows_view(
            json_array(json_field(row, "children")),
            groups,
            model,
            emit,
          ),
        ]),
      )
    }
  }
  @html.fragment(children)
}

///|
fn layers_view(model : Model, emit : @cmd.Emit[Msg]) -> @html.Html {
  let entries = json_array(json_field(model.layers, "groups"))
  if entries.is_empty() {
    return @html.p(class="sidebar-empty", "This document has no layers")
  }
  let index = json_field(model.layers, "config_index")
  let selected = if index is Null { -1 } else { json_int(index) }
  let options : Array[@html.Html] = []
  for entry in json_array(json_field(model.layers, "configs")) {
    let index = json_field(entry, "index")
    let value = if index is Null { -1 } else { json_int(index) }
    let name = json_string(json_field(entry, "name"))
    options.push(
      @html.option(
        value=value.to_string(),
        if name != "" {
          name
        } else if value == -1 {
          "Default configuration"
        } else {
          "Configuration \{value + 1}"
        },
      ),
    )
  }
  let groups : Map[Int, Json] = Map([])
  for entry in entries {
    groups[json_int(json_field(entry, "id"))] = entry
  }
  let busy = layers_controls_busy(model)
  @html.div(
    class="layers-panel",
    attrs=@html.Attrs::build()
      .aria_busy(model.layers_busy.to_string())
      .data_set("config-index", selected.to_string()),
    [
      @html.label(class="layer-config-label", [
        @html.text("Layer configuration"),
        @html.select(
          id="layers-config",
          disabled=busy,
          attrs=@html.Attrs::build()
            .aria_label("Layer configuration")
            .value_prop(selected.to_string()),
          on_change=@cmd.Emit(value => {
            emit(LayerConfig(parse_float(value).to_int()))
          }),
          options,
        ),
      ]),
      @html.button(
        id="layers-reset",
        disabled=busy,
        on_click=emit(LayerConfig(selected)),
        "Reset this configuration",
      ),
      layer_rows_view(
        json_array(json_field(model.layers, "order")),
        groups,
        model,
        emit,
      ),
    ],
  )
}

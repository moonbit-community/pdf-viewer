///|
fn editor_view(model : EditorModel, emit : @cmd.Emit[Msg]) -> @html.Html {
  @html.div(
    id="editor-toolbar",
    class="editor-toolbar",
    hidden=!model.enabled,
    attrs=@html.Attrs::build().aria_label("Annotation and form editing"),
    [
      @html.div(
        class="editor-tools",
        [
          for
            (value, label) in [
              ("select", "Select"),
              ("text", "Text"),
              ("highlight", "Highlight"),
              ("ink", "Ink"),
              ("signature", "Handwritten signature"),
              ("image", "Image signature"),
            ] => {
            @html.button(
              id="edit-" + value,
              type_="button",
              disabled=model.busy || (!model.annotations && value != "select"),
              attrs=@html.Attrs::build().aria_pressed(
                (model.tool == value).to_string(),
              ),
              on_click=emit(Edit(Tool(value))),
              label,
            )
          }
        ],
      ),
      @html.input(
        id="editor-text",
        input_type=Text,
        value=model.text,
        placeholder="Annotation text",
        attrs=@html.Attrs::build()
          .aria_label("Annotation text")
          .disabled(!model.annotations),
        on_input=@cmd.Emit(text => emit(Edit(Text(text)))),
      ),
      @html.input(
        id="editor-color",
        input_type=Color,
        value=model.color,
        attrs=@html.Attrs::build().disabled(!model.annotations),
        title="Annotation color",
        on_input=@cmd.Emit(color => emit(Edit(Color(color)))),
      ),
      @html.input(
        id="editor-size",
        input_type=Number,
        min=1,
        max=200,
        value=model.size.to_string(),
        attrs=@html.Attrs::build().disabled(!model.annotations),
        title="Font size / line width",
        on_input=@cmd.Emit(size => emit(Edit(Size(size)))),
      ),
      @html.label(class="editor-image-picker", [
        @html.text(
          if model.image_ready {
            "Replace signature image"
          } else {
            "Select signature image"
          },
        ),
        @html.input(
          id="signature-image",
          input_type=File,
          accept="image/png,image/jpeg,image/webp",
          attrs=@html.Attrs::build().disabled(!model.annotations),
          on_change=@cmd.Emit(_ => {
            match picked_image().to_option() {
              Some(file) => emit(Edit(PickImage(file)))
              None => @cmd.none
            }
          }),
        ),
      ]),
      @html.button(
        id="edit-apply-text",
        disabled=model.busy || model.selected == Json::null(),
        on_click=emit(Edit(ApplyText)),
        "Apply text / style",
      ),
      @html.button(
        id="edit-delete",
        disabled=model.busy || model.selected == Json::null(),
        on_click=emit(Edit(Delete)),
        "Delete",
      ),
      @html.button(
        id="edit-undo",
        disabled=model.busy || !model.undo,
        on_click=emit(Edit(Undo)),
        "Undo",
      ),
      @html.button(
        id="edit-redo",
        disabled=model.busy || !model.redo,
        on_click=emit(Edit(Redo)),
        "Redo",
      ),
      @html.span(
        id="editor-status",
        attrs=@html.Attrs::build().aria_live("polite"),
        model.status,
      ),
      @html.span(id="editor-dirty", if model.dirty { "Unsaved" } else { "" }),
    ],
  )
}

///|
extern "js" fn picked_image() -> @js.Nullable[@js.Value] =
  #| () => {const input=document.getElementById('signature-image'),file=input.files[0]||null;input.value='';return file;}

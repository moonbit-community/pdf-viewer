///|
fn editor_view(model : EditorModel, emit : @cmd.Emit[Msg]) -> @html.Html {
  @html.div(
    id="editor-toolbar",
    class="editor-toolbar",
    hidden=!model.enabled,
    attrs=@html.Attrs::build().aria_label("批注和表单编辑"),
    [
      @html.div(
        class="editor-tools",
        [
          for
            (value, label) in [
              ("select", "选择"),
              ("text", "文字"),
              ("highlight", "标记"),
              ("ink", "画笔"),
              ("signature", "手写签名"),
              ("image", "图片签名"),
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
        placeholder="批注文字",
        attrs=@html.Attrs::build()
          .aria_label("批注文字")
          .disabled(!model.annotations),
        on_input=@cmd.Emit(text => emit(Edit(Text(text)))),
      ),
      @html.input(
        id="editor-color",
        input_type=Color,
        value=model.color,
        attrs=@html.Attrs::build().disabled(!model.annotations),
        title="批注颜色",
        on_input=@cmd.Emit(color => emit(Edit(Color(color)))),
      ),
      @html.input(
        id="editor-size",
        input_type=Number,
        min=1,
        max=200,
        value=model.size.to_string(),
        attrs=@html.Attrs::build().disabled(!model.annotations),
        title="字号／线宽",
        on_input=@cmd.Emit(size => emit(Edit(Size(size)))),
      ),
      @html.label(class="editor-image-picker", [
        @html.text(
          if model.image_ready {
            "更换签名图片"
          } else {
            "选择签名图片"
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
        "应用文字/样式",
      ),
      @html.button(
        id="edit-delete",
        disabled=model.busy || model.selected == Json::null(),
        on_click=emit(Edit(Delete)),
        "删除",
      ),
      @html.button(
        id="edit-undo",
        disabled=model.busy || !model.undo,
        on_click=emit(Edit(Undo)),
        "撤销",
      ),
      @html.button(
        id="edit-redo",
        disabled=model.busy || !model.redo,
        on_click=emit(Edit(Redo)),
        "重做",
      ),
      @html.span(
        id="editor-status",
        attrs=@html.Attrs::build().aria_live("polite"),
        model.status,
      ),
      @html.span(id="editor-dirty", if model.dirty { "未保存" } else { "" }),
    ],
  )
}

///|
extern "js" fn picked_image() -> @js.Nullable[@js.Value] =
  #| () => {const input=document.getElementById('signature-image'),file=input.files[0]||null;input.value='';return file;}

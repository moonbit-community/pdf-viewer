///|
fn main {
  @rabbita.new(() => {
    let (model, emit) = @rabbita.create_state_with_init(
      init=emit => {
        ui_emit.val = Some(emit)
        (
          snapshot(),
          @cmd.custom_cmd(
            scheduler => {
              ui_scheduler.val = Some(scheduler)
              initialize_pages()
              initialize_events()
              if state.document_generation == 0 && !has_initial_file() {
                prepare_worker()
              }
              launch(() => {
                if initial_file().to_option() is Some(file) {
                  load_document(file, value_string(file, "path"))
                }
              })
            },
            kind=@cmd.after_render,
          ),
        )
      },
      update=(model, message, _) => {
        match message {
          Publish(model) => (model, @cmd.none)
          _ =>
            (
              model,
              @cmd.effect(() => {
                handle(message) catch {
                  error => show_error(error)
                }
              }),
            )
        }
      },
    )
    model.view(model => view(model, emit))
  }).mount("app")
}

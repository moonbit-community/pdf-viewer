///|
extern "js" fn native_xfa_editable(
  control : @dom.Element,
  enabled : Bool,
) -> Unit =
  #| (control,enabled) => {const readonly=control.dataset.xfaReadonly==='true'||!enabled;control.classList.add('xfa-editor-field');if(control.matches('textarea,input:not([type=checkbox]):not([type=radio])'))control.readOnly=readonly;else control.disabled=readonly;control.setAttribute('aria-readonly',String(readonly));}

///|
extern "js" fn native_xfa_value(control : @dom.Element) -> String =
  #| control => control.matches('input[type=checkbox],input[type=radio]')?(control.getAttribute(control.checked?'xfaOn':'xfaOff')||''):control.value

///|
fn editor_refresh_xfa_fields() -> Unit {
  if !state.xfa {
    return
  }
  let generation = state.document_generation
  for control in element("pages").query_selector_all("[data-xfa-id]").iter() {
    native_xfa_editable(control, editor.enabled)
    if element_data(control, "xfaEditorBound") == "true" {
      continue
    }
    set_data(control, "xfaEditorBound", "true")
    let id = element_data(control, "xfaId")
    let page = control.closest(".page").unwrap()
    let number = parse_float(element_data(page, "page")).to_int()
    let baseline = native_xfa_value(control)
    control.add_event_listener("input", _ => {
      if generation == state.document_generation && editor.enabled {
        editor.pending_input = native_xfa_value(control) != baseline
        notify()
      }
    })
    control.add_event_listener("change", _ => {
      let value = native_xfa_value(control)
      if value == baseline {
        return
      }
      launch(() => {
        if generation != state.document_generation || !editor.enabled {
          return
        }
        editor_commit({
          "kind": "xfa",
          "id": "xfa:" + id,
          "data_id": id,
          "page": number,
          "value": value,
        })
      })
    })
  }
}

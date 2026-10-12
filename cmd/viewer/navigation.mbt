///|
fn apply_view_mode() -> Unit {
  toggle_class(element("viewer"), "page-mode", state.view_mode == "page")
  for page in element("pages").get_children().iter() {
    toggle_class(
      page,
      "current-page",
      state.view_mode == "page" &&
      parse_float(element_data(page, "page")).to_int() == state.current_page,
    )
  }
}

///|
fn location_page() -> Int {
  let number = native_location_page()
  if number >= 1 && number <= state.count {
    number
  } else {
    1
  }
}

///|
fn go_to_page(number : Int, push? : Bool = false) -> Unit {
  if state.count == 0 {
    return
  }
  let number = number.max(1).min(state.count)
  state.current_page = number
  set_input_value("page-number", number.to_string())
  native_location_update(number, push)
  apply_view_mode()
  if state.view_mode != "page" && page_element(number) is Some(page) {
    page.scroll_into_view_with_options(block="start")
  }
  scheduler_update(state.scheduler.unwrap(), number)
  notify()
}

///|
async fn change_scale(factor : Double) -> Unit {
  state.zoom = (state.scale * factor).max(0.1).min(4.0).to_string()
  repaint()
}

///|
extern "js" fn map_point(
  viewport : @js.Value,
  x : Double,
  y : Double,
  inverse : Bool,
) -> FixedArray[Double] =
  #| (viewport,x,y,inverse) => { let matrix=new DOMMatrix(viewport.matrix); if(inverse) matrix=matrix.inverse(); const point=matrix.transformPoint({x,y}); return [point.x,point.y]; }

///|
fn annotation_viewport(page : @dom.Element) -> @js.Value {
  parse_value(
    element_data(page.query_selector(".annotation-layer").unwrap(), "viewport"),
  )
}

///|
async fn navigate_annotation(link : @js.Value) -> Unit {
  try {
    if value_string(link, "kind") == "named-action" {
      match value_string(link, "action") {
        "FirstPage" => go_to_page(1, push=true)
        "LastPage" => go_to_page(state.count, push=true)
        "NextPage" => go_to_page(state.current_page + 1, push=true)
        "PrevPage" => go_to_page(state.current_page - 1, push=true)
        "GoBack" => @dom.window().history_go_back()
        "GoForward" => @dom.window().history_go_forward()
        _ => ()
      }
      return
    }
    let destination = value_field(link, "destination")
    let number = value_int(destination, "page")
    if !value_bool(destination, "resolved") ||
      value_bool(destination, "remote") ||
      number < 1 ||
      number > state.count {
      return
    }
    let generation = state.document_generation
    clear_selection()
    go_to_page(number, push=true)
    let mut page = scheduler_ensure(state.scheduler.unwrap(), number).wait()
    if generation != state.document_generation {
      return
    }
    let mut viewport = annotation_viewport(page)
    let layout = state.layouts[number - 1]
    let width = if state.rotation % 180 != 0 {
      layout.height
    } else {
      layout.width
    }
    let height = if state.rotation % 180 != 0 {
      layout.width
    } else {
      layout.height
    }
    let viewer = element("viewer")
    let fit_width = (viewer.get_client_width() - 64.0).max(1.0)
    let fit_height = (viewer.get_client_height() - 64.0).max(1.0)
    let kind = value_string(destination, "kind")
    let mut scale = state.scale
    match kind {
      "XYZ" =>
        if value_number(destination, "zoom") > 0.0 {
          scale = value_number(destination, "zoom")
        }
      "FitH" | "FitBH" => scale = fit_width / width
      "FitV" | "FitBV" => scale = fit_height / height
      "Fit" | "FitB" => scale = (fit_width / width).min(fit_height / height)
      "FitR" => {
        let first = map_point(
          viewport,
          value_number(destination, "left"),
          value_number(destination, "bottom"),
          false,
        )
        let last = map_point(
          viewport,
          value_number(destination, "right"),
          value_number(destination, "top"),
          false,
        )
        let w = (last[0] - first[0]).abs()
        let h = (last[1] - first[1]).abs()
        if w > 0.0 && h > 0.0 {
          scale *= (fit_width / w).min(fit_height / h)
        }
      }
      _ => ()
    }
    scale = scale.max(0.1).min(4.0)
    if scale != state.scale {
      state.zoom = scale.to_string()
      repaint(preserve=false)
      page = scheduler_ensure(state.scheduler.unwrap(), number).wait()
      if generation != state.document_generation {
        return
      }
      viewport = annotation_viewport(page)
    }
    let origin = map_point(viewport, 0.0, 0.0, true)
    let left = if value_field(destination, "left").is_null() {
      origin[0]
    } else {
      value_number(destination, "left")
    }
    let top = if value_field(destination, "top").is_null() {
      origin[1]
    } else {
      value_number(destination, "top")
    }
    let mut point = map_point(viewport, left, top, false)
    if kind == "FitR" {
      let first = map_point(
        viewport,
        left,
        value_number(destination, "bottom"),
        false,
      )
      let last = map_point(
        viewport,
        value_number(destination, "right"),
        top,
        false,
      )
      point = [first[0].min(last[0]), first[1].min(last[1])]
    }
    if ["XYZ", "FitH", "FitBH", "FitV", "FitBV", "FitR"].contains(kind) &&
      !point[0].is_nan() &&
      !point[0].is_inf() &&
      !point[1].is_nan() &&
      !point[1].is_inf() {
      let box = page.get_bounding_client_rect()
      let view = viewer.get_bounding_client_rect()
      viewer.set_scroll_top(
        viewer.get_scroll_top() +
        box.get_top() -
        view.get_top() -
        computed_number(viewer, "paddingTop") +
        point[1],
      )
      viewer.set_scroll_left(
        viewer.get_scroll_left() +
        box.get_left() -
        view.get_left() -
        computed_number(viewer, "paddingLeft") +
        point[0],
      )
    }
  } catch {
    error => show_error(error)
  }
}

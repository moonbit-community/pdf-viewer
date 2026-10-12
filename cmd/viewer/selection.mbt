///|
// Only mounted pages retain a selection index. The Worker owns unloaded pages.
let selection_pages : Map[Int, @pdf.PdfTextLayer] = Map([])

///|
fn selection_point(value : @js.Value) -> @pdf.PdfPoint {
  { x: value_number(value, "x"), y: value_number(value, "y"), }
}

///|
fn cache_selection_page(layer : @js.Value) -> Unit {
  if layer.is_null() {
    return
  }
  let viewport = value_field(layer, "viewport")
  let items : Array[@pdf.PdfTextLayerItem] = []
  for item in value_array(value_field(layer, "items")) {
    let quad = value_field(item, "quad")
    // Older host-built layers can continue resolving ranges through the Worker.
    if quad.is_null() {
      return
    }
    items.push({
      item_index: value_int(item, "item_index"),
      text: value_string(item, "text"),
      separator: value_string(item, "separator"),
      quad: {
        p0: selection_point(value_field(quad, "p0")),
        p1: selection_point(value_field(quad, "p1")),
        p2: selection_point(value_field(quad, "p2")),
        p3: selection_point(value_field(quad, "p3")),
      },
      matrix: [
        for value in value_numbers(value_field(item, "matrix")) => value
      ],
      font_family: value_string(item, "font_family"),
      font_weight: value_string(item, "font_weight"),
      font_style: value_string(item, "font_style"),
      vertical: value_bool(item, "vertical"),
    })
  }
  let page = value_int(layer, "page")
  selection_pages[page] = {
    page,
    items,
    viewport: {
      width: value_number(viewport, "width"),
      height: value_number(viewport, "height"),
      scale: value_number(viewport, "scale"),
      user_unit: value_number(viewport, "user_unit"),
      rotation: value_int(viewport, "rotation"),
      matrix: [
        for value in value_numbers(value_field(viewport, "matrix")) => value
      ],
      transform: value_string(viewport, "transform"),
    },
  }
}

///|
fn local_selection(
  number : Int,
  start : TextPoint,
  end : TextPoint,
) -> @js.Value? {
  guard selection_pages.get(number) is Some(layer) else { return None }
  guard !layer.items.is_empty() else {
    return Some(parse_value("{\"ok\":true,\"selection\":null}"))
  }
  let first = layer.items[0]
  let last = layer.items[layer.items.length() - 1]
  let start_item = if start.item < 0 { first.item_index } else { start.item }
  let start_offset = if start.offset < 0 && start_item == first.item_index {
    0
  } else {
    start.offset
  }
  let end_item = if end.item < 0 { last.item_index } else { end.item }
  let end_offset = if end.offset < 0 && end_item == last.item_index {
    last.text.length()
  } else {
    end.offset
  }
  guard layer.select_text(start_item, start_offset, end_item, end_offset)
    is Some(selection) else {
    return None
  }
  let result : Json = {
    "ok": true,
    "selection": if selection.text == "" &&
      start_item == end_item &&
      start_offset == end_offset {
      Json::null()
    } else {
      ToJson::to_json(selection)
    },
    "start": {
      "page": number,
      "item": selection.start_item,
      "offset": selection.start_offset,
    },
    "end": {
      "page": number,
      "item": selection.end_item,
      "offset": selection.end_offset,
    },
  }
  Some(parse_value(result.stringify()))
}

///|
extern "js" fn native_selection_range() -> @js.Nullable[@js.Value] =
  #| () => { const s=getSelection(); return s&&!s.isCollapsed&&s.rangeCount?s.getRangeAt(0):null; }

///|
extern "js" fn node_is_text(node : @js.Value) -> Bool =
  #| node => node.nodeType===Node.TEXT_NODE

///|
extern "js" fn node_owner(node : @js.Value) -> @js.Nullable[@dom.Element] =
  #| node => node.nodeType===Node.TEXT_NODE?node.parentElement:node.nodeType===Node.ELEMENT_NODE?node:null

///|
extern "js" fn node_first(node : @js.Value) -> @js.Value =
  #| node => node.firstChild

///|
extern "js" fn same_node(first : @js.Value, last : @js.Value) -> Bool =
  #| (first,last) => first===last

///|
extern "js" fn node_length(node : @js.Value) -> Int =
  #| node => (node.textContent||"").length

///|
extern "js" fn native_clear_selection() -> Unit =
  #| () => getSelection()?.removeAllRanges()

///|
extern "js" fn native_restore_selection(
  first : @js.Value,
  first_offset : Int,
  last : @js.Value,
  last_offset : Int,
) -> Unit =
  #| (first,firstOffset,last,lastOffset) => { const r=new Range();r.setStart(first,firstOffset);r.setEnd(last,lastOffset);const s=getSelection();s.removeAllRanges();s.addRange(r); }

///|
fn boundary(node : @js.Value, offset : Int, end? : Bool = false) -> TextPoint? {
  let owner = match node_owner(node).to_option() {
    Some(owner) => owner
    None => return None
  }
  if owner.closest(".xfa-text") is Some(text) {
    return Some({
      page: parse_float(element_data(text.closest(".page").unwrap(), "page")).to_int(),
      item: parse_float(element_data(text, "item")).to_int(),
      offset: if node_is_text(node) {
        offset
      } else if offset != 0 {
        node_length(@js.Value::cast_from(text))
      } else {
        0
      },
    })
  }
  if owner.closest(".glyph") is Some(glyph) {
    let wrapper = node_first(@js.Value::cast_from(glyph))
    let text = node_first(wrapper)
    let actual = if same_node(node, text) {
      offset
    } else if same_node(node, @js.Value::cast_from(glyph)) ||
      same_node(node, wrapper) {
      if offset == 0 {
        0
      } else {
        node_length(text)
      }
    } else {
      return None
    }
    return Some({
      page: parse_float(element_data(glyph.closest(".page").unwrap(), "page")).to_int(),
      item: parse_float(element_data(glyph, "item")).to_int(),
      offset: actual,
    })
  }
  if owner.closest(".text-layer") is Some(layer) {
    let children = layer.get_children().iter().collect()
    let mut position = -1
    if same_node(node, @js.Value::cast_from(layer)) {
      position = offset
    } else {
      for index, child in children {
        if same_node(@js.Value::cast_from(owner), @js.Value::cast_from(child)) {
          position = index
          break
        }
      }
    }
    if position < 0 {
      return None
    }
    if end {
      for index = (position - 1).min(children.length() - 1)
          index >= 0
          index = index - 1 {
        let child = children[index]
        if child.matches(".glyph") {
          let text = node_first(node_first(@js.Value::cast_from(child)))
          return boundary(text, node_length(text), end=true)
        }
      }
    } else {
      for index in position..<children.length() {
        let child = children[index]
        if child.matches(".glyph") {
          return boundary(
            node_first(node_first(@js.Value::cast_from(child))),
            0,
          )
        }
      }
    }
  }
  None
}

///|
fn clear_selection() -> Unit {
  if state.selection_range is None &&
    state.selection is None &&
    state.selection_promise is None {
    return
  }
  abort(state.selection_controller)
  state.selection_generation += 1
  state.selection_restore = false
  state.selection_promise = None
  state.selection = None
  state.selection_range = None
  state.selection_text = ""
  state.selection_status = ""
  dispatch_detail(
    "pdf-selection-change",
    @js.Value::cast_from((@js.Nullable::null() : @js.Nullable[Unit])),
  )
  notify()
}

///|
fn native_text_range() -> TextRange? {
  guard native_selection_range().to_option() is Some(range) else { return None }
  guard boundary(
      value_field(range, "startContainer"),
      value_int(range, "startOffset"),
    )
    is Some(start) else {
    return None
  }
  guard boundary(
      value_field(range, "endContainer"),
      value_int(range, "endOffset"),
      end=true,
    )
    is Some(end) else {
    return None
  }
  Some({ start, end, })
}

///|
fn publish_selection(
  range : TextRange,
  ranges : Array[@js.Value],
  chunks : Array[String],
) -> Unit {
  let changed_pages = match state.selection_range {
    Some(old) =>
      old.start.page != range.start.page || old.end.page != range.end.page
    None => true
  }
  state.selection_range = Some(range)
  state.selection_text = chunks.join("\n")
  state.selection = Some(
    selection_detail(
      state.file_name,
      state.file_path,
      state.selection_text,
      FixedArray::from_array(ranges[:]),
    ),
  )
  state.selection_status = "已选 \{state.selection_text.iter().count()} 个字符"
  if changed_pages {
    scheduler_update(state.scheduler.unwrap(), state.current_page)
  }
  dispatch_detail("pdf-selection-change", state.selection.unwrap())
  notify()
}

///|
fn collect_local_selection(range : TextRange) -> Bool {
  let ranges : Array[@js.Value] = []
  let chunks : Array[String] = []
  let mut start : TextPoint? = None
  let mut end : TextPoint? = None
  for number in range.start.page..<=range.end.page {
    let first = if number == range.start.page {
      range.start
    } else {
      { page: number, item: -1, offset: -1, }
    }
    let last = if number == range.end.page {
      range.end
    } else {
      { page: number, item: -1, offset: -1, }
    }
    guard local_selection(number, first, last) is Some(result) else {
      return false
    }
    let selection = value_field(result, "selection")
    if selection.is_null() {
      continue
    }
    if start is None {
      start = Some(json_point(value_json(value_field(result, "start"))))
    }
    end = Some(json_point(value_json(value_field(result, "end"))))
    ranges.push(selection)
    chunks.push(value_string(selection, "text"))
  }
  if ranges.is_empty() {
    clear_selection()
    return true
  }
  abort(state.selection_controller)
  state.selection_controller = None
  state.selection_generation += 1
  state.selection_restore = false
  state.selection_promise = None
  publish_selection(
    { start: start.unwrap(), end: end.unwrap(), },
    ranges,
    chunks,
  )
  true
}

///|
fn restore_selection(range : TextRange) -> Unit {
  if page_element(range.start.page) is Some(first) &&
    page_element(range.end.page) is Some(last) &&
    first.query_selector("[data-item=\"\{range.start.item}\"]") is Some(first) &&
    last.query_selector("[data-item=\"\{range.end.item}\"]") is Some(last) {
    let first = node_first(@js.Value::cast_from(first))
    let last = node_first(@js.Value::cast_from(last))
    native_restore_selection(
      if state.xfa {
        first
      } else {
        node_first(first)
      },
      range.start.offset,
      if state.xfa {
        last
      } else {
        node_first(last)
      },
      range.end.offset,
    )
  }
}

///|
extern "js" fn selection_detail(
  name : String,
  path : String,
  text : String,
  ranges : FixedArray[@js.Value],
) -> @js.Value =
  #| (name,path,text,ranges) => ({file:{name,path},text,ranges})

///|
async fn collect_selection(
  start : TextPoint,
  end : TextPoint,
  restore? : Bool = false,
) -> Unit {
  abort(state.selection_controller)
  let controller = @js_async.AbortController::new()
  state.selection_controller = Some(controller)
  state.selection_generation += 1
  let token = state.selection_generation
  state.selection_restore = restore
  if restore {
    native_clear_selection()
  }
  let generation = state.document_generation
  state.selection_range = Some({ start, end, })
  state.selection = None
  state.selection_text = ""
  state.selection_status = "正在准备选中文字"
  scheduler_update(state.scheduler.unwrap(), state.current_page)
  notify()
  let ranges : Array[@js.Value] = []
  let chunks : Array[String] = []
  let mut actual_start : TextPoint? = None
  let mut actual_end : TextPoint? = None
  try {
    for number in start.page..<=end.page {
      let first = if number == start.page {
        start
      } else {
        { page: number, item: -1, offset: -1, }
      }
      let last = if number == end.page {
        end
      } else {
        { page: number, item: -1, offset: -1, }
      }
      let result = match local_selection(number, first, last) {
        Some(result) => result
        None =>
          call(
            "select_page_text",
            args=[
              @js.Value::cast_from(number),
              @js.Value::cast_from(first.item),
              @js.Value::cast_from(first.offset),
              @js.Value::cast_from(last.item),
              @js.Value::cast_from(last.offset),
            ],
            controller~,
            priority=20,
          )
      }
      if controller_aborted(controller) ||
        generation != state.document_generation {
        return
      }
      let selection = value_field(result, "selection")
      if selection.is_null() {
        continue
      }
      if actual_start is None {
        actual_start = Some(
          json_point(value_json(value_field(result, "start"))),
        )
      }
      actual_end = Some(json_point(value_json(value_field(result, "end"))))
      ranges.push(selection)
      chunks.push(value_string(selection, "text"))
    }
    if ranges.is_empty() {
      clear_selection()
      return
    }
    let range = { start: actual_start.unwrap(), end: actual_end.unwrap(), }
    state.selection_range = Some(range)
    if restore {
      ignore(
        scheduler_ensure(state.scheduler.unwrap(), range.start.page).wait(),
      )
      ignore(scheduler_ensure(state.scheduler.unwrap(), range.end.page).wait())
      if controller_aborted(controller) ||
        generation != state.document_generation {
        return
      }
      restore_selection(range)
    }
    publish_selection(range, ranges, chunks)
  } catch {
    error =>
      if !controller_aborted(controller) &&
        generation == state.document_generation {
        show_error(error)
      }
  }
  if token == state.selection_generation {
    state.selection_restore = false
  }
}

///|
async fn read_native_selection() -> Unit {
  if state.busy {
    return
  }
  let range = match native_selection_range().to_option() {
    Some(range) => range
    None => {
      if state.selection_restore {
        return
      }
      clear_selection()
      return
    }
  }
  let start = boundary(
    value_field(range, "startContainer"),
    value_int(range, "startOffset"),
  )
  let end = boundary(
    value_field(range, "endContainer"),
    value_int(range, "endOffset"),
    end=true,
  )
  if start is Some(start) && end is Some(end) {
    if state.selection_range == Some({ start, end, }) {
      if state.selection is Some(value) {
        dispatch_detail("pdf-selection-change", value)
        return
      }
      if state.selection_controller is Some(controller) &&
        !controller_aborted(controller) &&
        state.selection_promise is Some(pending) {
        pending.wait()
        return
      }
    }
    if collect_local_selection({ start, end, }) {
      return
    }
    let pending = @js_async.Promise::from_async(() => {
      collect_selection(start, end)
    })
    state.selection_promise = Some(pending)
    pending.wait()
  } else {
    clear_selection()
  }
}

///|
async fn select_all_text_async() -> Unit {
  if state.count == 0 {
    return
  }
  let start = { page: 1, item: -1, offset: -1, }
  let end = { page: state.count, item: -1, offset: -1, }
  let pending = @js_async.Promise::from_async(() => {
    collect_selection(start, end, restore=true)
  })
  state.selection_promise = Some(pending)
  pending.wait()
}

///|
pub fn read_selection() -> @js_async.Promise[Unit] {
  @js_async.Promise::from_async(() => {
    read_native_selection()
    flush_ui()
  })
}

///|
pub fn select_all_text() -> @js_async.Promise[Unit] {
  @js_async.Promise::from_async(() => {
    select_all_text_async()
    flush_ui()
  })
}

///|
extern "js" fn native_copy(event : @dom.ClipboardEvent, text : String) -> Unit =
  #| (event,text) => { event.clipboardData.setData("text/plain",text); event.preventDefault(); }

///|
extern "js" fn native_copy_pending(
  text : @js_async.Promise[String],
) -> @js_async.Promise[Unit] =
  #| text => navigator.clipboard.write&&window.ClipboardItem ? navigator.clipboard.write([new ClipboardItem({"text/plain":text.then(value=>new Blob([value],{type:"text/plain"}))})]) : text.then(value=>navigator.clipboard.writeText(value))

///|
fn refresh_copy_selection() -> Unit {
  if native_text_range() is Some(range) && state.selection_range != Some(range) {
    if !collect_local_selection(range) {
      let pending = @js_async.Promise::from_async(() => {
        collect_selection(range.start, range.end)
      })
      state.selection_promise = Some(pending)
    }
  }
}

///|
fn pending_selection_text(
  pending : @js_async.Promise[Unit],
) -> @js_async.Promise[String] {
  let generation = state.document_generation
  let token = state.selection_generation
  @js_async.Promise::from_async(() => {
    pending.wait()
    if generation != state.document_generation ||
      token != state.selection_generation ||
      state.selection is None {
      raise ViewerError("AbortError", "Selection cancelled")
    }
    state.selection_text
  })
}

///|
fn copy_event(event : @dom.ClipboardEvent) -> Unit {
  if native_input_focused() {
    return
  }
  refresh_copy_selection()
  if state.selection is Some(_) && native_text_range() == state.selection_range {
    native_copy(event, state.selection_text)
  } else if state.selection_range is Some(_) &&
    state.selection_promise is Some(pending) {
    event.prevent_default()
    ignore(
      @js_async.Promise::from_async(() => {
        native_copy_pending(pending_selection_text(pending)).wait() catch {
          error => show_error(error)
        }
      }),
    )
  }
}

///|
extern "js" fn native_input_focused() -> Bool =
  #| () => Boolean(document.activeElement?.matches('input,textarea,select,[contenteditable="true"]'))

///|
extern "js" fn selection_can_modify() -> Bool =
  #| () => Boolean(getSelection()?.modify)

///|
extern "js" fn selection_inside(viewer : @dom.Element) -> Bool =
  #| viewer => viewer.contains(getSelection()?.focusNode)

///|
extern "js" fn selection_start(node : @js.Value) -> Unit =
  #| node => { const s=getSelection(),r=new Range();r.setStart(node,0);r.collapse(true);s.removeAllRanges();s.addRange(r); }

///|
extern "js" fn selection_extend(
  direction : String,
  granularity : String,
) -> Unit =
  #| (direction,granularity) => { const s=getSelection();s.setBaseAndExtent(s.anchorNode,s.anchorOffset,s.focusNode,s.focusOffset);s.modify("extend",direction,granularity); }

///|
extern "js" fn key_from_control(event : @dom.KeyboardEvent) -> Bool =
  #| event => event.target.matches("input, textarea, select, button")

///|
async fn selection_key(event : @dom.KeyboardEvent) -> Unit {
  if key_from_control(event) || !selection_can_modify() {
    return
  }
  let key = event.key()
  let modifier = event.ctrl_key() || event.meta_key()
  if modifier && key.to_lower() == "a" {
    event.prevent_default()
    select_all_text_async()
    return
  }
  let direction = match key {
    "ArrowLeft" | "ArrowUp" => "backward"
    "ArrowRight" | "ArrowDown" => "forward"
    _ => return
  }
  if !event.shift_key() {
    return
  }
  event.prevent_default()
  if !selection_inside(element("viewer")) {
    if page_element(state.current_page) is Some(page) &&
      page.query_selector(".glyph-text") is Some(first) {
      selection_start(node_first(@js.Value::cast_from(first)))
    } else {
      return
    }
  }
  let granularity = if key == "ArrowUp" || key == "ArrowDown" {
    "line"
  } else if modifier {
    "word"
  } else {
    "character"
  }
  selection_extend(direction, granularity)
  read_native_selection()
}

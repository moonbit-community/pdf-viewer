///|
extern "js" fn native_selection_range() -> @js.Nullable[@js.Value] =
  #| () => { const s=getSelection(); return s&&!s.isCollapsed&&s.rangeCount?s.getRangeAt(0):null; }

///|
extern "js" fn node_is_text(node : @js.Value) -> Bool =
  #| node => node.nodeType===Node.TEXT_NODE

///|
extern "js" fn node_owner(node : @js.Value) -> @js.Nullable[@dom.Element] =
  #| node => node.nodeType===Node.TEXT_NODE?node.parentElement:node

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
      let result = call(
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
    dispatch_detail("pdf-selection-change", state.selection.unwrap())
    notify()
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
fn copy_event(event : @dom.ClipboardEvent) -> Unit {
  if state.selection is Some(_) &&
    native_selection_range().to_option() is Some(_) {
    native_copy(event, state.selection_text)
  } else if state.selection_range is Some(_) &&
    state.selection_promise is Some(pending) {
    event.prevent_default()
    let generation = state.document_generation
    let token = state.selection_generation
    let text = @js_async.Promise::from_async(() => {
      pending.wait()
      if generation != state.document_generation ||
        token != state.selection_generation ||
        state.selection is None {
        raise ViewerError("AbortError", "Selection cancelled")
      }
      state.selection_text
    })
    ignore(
      @js_async.Promise::from_async(() => {
        native_copy_pending(text).wait() catch {
          error => show_error(error)
        }
      }),
    )
  }
}

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

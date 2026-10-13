///|
/// Each page receives one annotation containing its original PDF-space quads.
/// A cross-page gesture is committed as one undo step.
async fn editor_highlight_selection() -> Unit {
  read_native_selection()
  guard state.selection is Some(selection) else {
    editor.status = "Select text on the page first"
    notify()
    return
  }
  let patches : Array[Json] = []
  for range in value_array(value_field(selection, "ranges")) {
    let quads = value_array(value_field(range, "quads"))
    if quads.is_empty() {
      continue
    }
    let first = value_field(quads[0], "p0")
    let mut min_x = value_number(first, "x")
    let mut min_y = value_number(first, "y")
    let mut max_x = min_x
    let mut max_y = min_y
    for quad in quads {
      for key in ["p0", "p1", "p2", "p3"] {
        let point = value_field(quad, key)
        let x = value_number(point, "x")
        let y = value_number(point, "y")
        min_x = min_x.min(x)
        min_y = min_y.min(y)
        max_x = max_x.max(x)
        max_y = max_y.max(y)
      }
    }
    if max_x <= min_x || max_y <= min_y {
      continue
    }
    patches.push({
      "kind": "add",
      "id": native_annotation_id(),
      "page": value_int(range, "page"),
      "subtype": "Highlight",
      "contents": value_string(range, "text"),
      "bounds": [min_x, min_y, max_x, max_y],
      "quads": value_json(value_field(range, "quads")),
      "color": edit_rgb(),
    })
  }
  if patches.is_empty() {
    editor.status = "Select PDF text on the page first"
    notify()
    return
  }
  editor_commit_batch(patches)
}

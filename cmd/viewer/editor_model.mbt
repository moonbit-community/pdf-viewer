///|
struct EditorModel {
  enabled : Bool
  annotations : Bool
  tool : String
  color : String
  text : String
  size : Double
  selected : Json
  dirty : Bool
  busy : Bool
  undo : Bool
  redo : Bool
  image_ready : Bool
  status : String
} derive(Eq)

///|
enum EditorAction {
  Toggle
  Tool(String)
  Text(String)
  Color(String)
  Size(String)
  Undo
  Redo
  Delete
  ApplyText
  PickImage(@js.Value)
}

///|
struct EditPoint {
  x : Double
  y : Double
}

///|
struct EditGesture {
  page : @dom.Element
  number : Int
  pointer : Int
  mode : String
  start : EditPoint
  points : Array[EditPoint]
  matrix : Array[Double]
  entry : Json
}

///|
struct EditorRuntime {
  mut enabled : Bool
  mut annotations : Bool
  mut tool : String
  mut color : String
  mut text : String
  mut size : Double
  mut selected : Json
  mut history : Array[Array[Json]]
  mut cursor : Int
  mut saved : String
  mut applying : Bool
  mut pending_input : Bool
  mut image : Json
  mut status : String
  mut gesture : EditGesture?
  mut ink_id : String
  mut ink_page : Int
  mut image_generation : Int
}

///|
let editor : EditorRuntime = {
  enabled: false,
  annotations: true,
  tool: "select",
  color: "#254fa4",
  text: "",
  size: 14.0,
  selected: Json::null(),
  history: [[]],
  cursor: 0,
  saved: "[]",
  applying: false,
  pending_input: false,
  image: Json::null(),
  status: "",
  gesture: None,
  ink_id: "",
  ink_page: 0,
  image_generation: 0,
}

///|
fn editor_changes() -> Array[Json] {
  editor.history[editor.cursor]
}

///|
fn editor_dirty() -> Bool {
  editor.pending_input ||
  ToJson::to_json(editor_changes()).stringify() != editor.saved
}

///|
fn editor_snapshot() -> EditorModel {
  {
    enabled: editor.enabled,
    annotations: editor.annotations,
    tool: editor.tool,
    color: editor.color,
    text: editor.text,
    size: editor.size,
    selected: editor.selected,
    dirty: editor_dirty(),
    busy: editor.applying,
    undo: editor.cursor > 0,
    redo: editor.cursor + 1 < editor.history.length(),
    image_ready: editor.image != Json::null(),
    status: editor.status,
  }
}

///|
fn reset_editor() -> Unit {
  editor.enabled = false
  editor.selected = Json::null()
  editor.history = [[]]
  editor.cursor = 0
  editor.annotations = true
  editor.saved = "[]"
  editor.applying = false
  editor.pending_input = false
  editor.gesture = None
  editor.status = ""
  editor.image = Json::null()
  editor.tool = "select"
  editor.ink_id = ""
  editor.ink_page = 0
  editor.image_generation += 1
}

///|
enum Sidebar {
  Outline
  Thumbnails
  Info
} derive(Eq)

///|
struct PageLayout {
  page : Int
  width : Double
  height : Double
} derive(Eq)

///|
struct TextPoint {
  page : Int
  item : Int
  offset : Int
} derive(Eq, ToJson)

///|
struct TextRange {
  start : TextPoint
  end : TextPoint
} derive(Eq, ToJson)

///|
struct SearchHit {
  page : Int
  items : Array[Int]
}

///|
/// Rabbita owns the application DOM. Native page surfaces are mounted inside
/// stable empty containers so UI updates preserve Canvas and native selections.
struct Model {
  count : Int
  page : Int
  file_name : String
  file_path : String
  labels : Array[String]
  zoom : String
  view_mode : String
  sidebar : Sidebar?
  document_info : Json
  busy : Bool
  status : String
  error : String
  search_input : String
  search_status : String
  search_count : Int
  search_case : Bool
  search_whole : Bool
  search_diacritic : Bool
  selection_status : String
  can_copy : Bool
  printing : Bool
  drag_over : Bool
} derive(Eq)

///|
enum Msg {
  Publish(Model)
  Open
  FileChanged(@js.Value)
  Navigate(Int, Bool)
  MovePage(Int)
  ChangeZoom(String)
  Scale(Double)
  Rotate
  ChangeView(String)
  ToggleSidebar(Sidebar)
  CloseSidebar
  SearchInput(String)
  SearchOptions
  SearchKey(@dom.KeyboardEvent)
  JumpSearch(Int)
  Print
  Download
  Copy
  DownloadAttachment(Int, String)
  DownloadMetadata
  DragOver
  DragLeave
  Drop(@js.Value?)
  PointerDown
  Scroll
  ViewerKey(@dom.KeyboardEvent)
}

///|
struct Runtime {
  mut file : @js.Value?
  mut file_name : String
  mut file_path : String
  mut count : Int
  mut current_page : Int
  mut xfa : Bool
  mut labels : Array[String]
  mut layouts : Array[PageLayout]
  mut document_info : Json
  mut sidebar : Sidebar?
  mut zoom : String
  mut view_mode : String
  mut scale : Double
  mut rotation : Int
  mut generation : Int
  mut document_generation : Int
  mut busy : Bool
  mut status : String
  mut error : String
  mut search_input : String
  mut search_case : Bool
  mut search_whole : Bool
  mut search_diacritic : Bool
  mut search_query : String
  mut search_results : Array[SearchHit]
  mut search_active : Int
  mut search_controller : @js_async.AbortController?
  mut search_generation : Int
  mut selection : @js.Value?
  mut selection_text : String
  mut selection_range : TextRange?
  mut selection_controller : @js_async.AbortController?
  mut selection_restore : Bool
  mut selection_generation : Int
  mut selection_promise : @js_async.Promise[Unit]?
  mut selection_status : String
  mut selection_pending : Bool
  mut thumbnail_controller : @js_async.AbortController?
  mut thumbnail_observer : @dom.IntersectionObserver?
  mut print_controller : @js_async.AbortController?
  mut printing : Bool
  mut scheduler : @js.Value?
  mut annotations : @js.Value?
  mut scroll_pending : Bool
  mut resize_timer : Int?
  mut drag_over : Bool
}

///|
let state : Runtime = {
  file: None,
  file_name: "",
  file_path: "",
  count: 0,
  current_page: 1,
  xfa: false,
  labels: [],
  layouts: [],
  document_info: Json::null(),
  sidebar: None,
  zoom: "fit",
  view_mode: "scroll",
  scale: 1.0,
  rotation: 0,
  generation: 0,
  document_generation: 0,
  busy: false,
  status: "就绪",
  error: "",
  search_input: "",
  search_case: false,
  search_whole: false,
  search_diacritic: true,
  search_query: "",
  search_results: [],
  search_active: -1,
  search_controller: None,
  search_generation: 0,
  selection: None,
  selection_text: "",
  selection_range: None,
  selection_controller: None,
  selection_restore: false,
  selection_generation: 0,
  selection_promise: None,
  selection_status: "",
  selection_pending: false,
  thumbnail_controller: None,
  thumbnail_observer: None,
  print_controller: None,
  printing: false,
  scheduler: None,
  annotations: None,
  scroll_pending: false,
  resize_timer: None,
  drag_over: false,
}

///|
let ui_emit : Ref[@cmd.Emit[Msg]?] = Ref(None)

///|
let ui_scheduler : Ref[&@cmd.Scheduler?] = Ref(None)

///|
fn snapshot() -> Model {
  let search_count = state.search_results.length()
  let search_status = if search_count > 0 {
    "\{state.search_active + 1} / \{search_count}"
  } else if state.search_query != "" {
    "无结果"
  } else {
    ""
  }
  {
    count: state.count,
    page: state.current_page,
    file_name: state.file_name,
    file_path: state.file_path,
    labels: state.labels,
    zoom: state.zoom,
    view_mode: state.view_mode,
    sidebar: state.sidebar,
    document_info: state.document_info,
    busy: state.busy,
    status: state.status,
    error: state.error,
    search_input: state.search_input,
    search_status,
    search_count,
    search_case: state.search_case,
    search_whole: state.search_whole,
    search_diacritic: state.search_diacritic,
    selection_status: state.selection_status,
    can_copy: state.selection_text != "",
    printing: state.printing,
    drag_over: state.drag_over,
  }
}

///|
fn notify() -> Unit {
  if ui_emit.val is Some(emit) && ui_scheduler.val is Some(scheduler) {
    scheduler.queue_command(emit(Publish(snapshot())))
  }
}

///|
fn json_field(value : Json, name : String) -> Json {
  match value {
    Object(fields) => fields.get(name).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn json_string(value : Json) -> String {
  match value {
    String(value) => value
    Null => ""
    _ => value.stringify()
  }
}

///|
fn json_int(value : Json) -> Int {
  match value {
    Number(value, ..) => value.to_int()
    _ => 0
  }
}

///|
fn json_bool(value : Json) -> Bool {
  match value {
    True => true
    _ => false
  }
}

///|
fn json_array(value : Json) -> Array[Json] {
  match value {
    Array(values) => values
    _ => []
  }
}

///|
fn json_point(value : Json) -> TextPoint {
  {
    page: json_int(json_field(value, "page")),
    item: json_int(json_field(value, "item")),
    offset: json_int(json_field(value, "offset")),
  }
}

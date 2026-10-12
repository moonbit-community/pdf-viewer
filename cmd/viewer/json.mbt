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
fn json_number(value : Json) -> Double {
  match value {
    Number(n, ..) => n
    _ => 0.0
  }
}

///|
fn json_string_field(value : Json, key : String) -> String {
  json_string(json_field(value, key))
}

///|
fn json_bool_field(value : Json, key : String) -> Bool {
  json_bool(json_field(value, key))
}

///|
fn json_put(value : Json, key : String, entry : Json) -> Json {
  let fields : Map[String, Json] = match value {
    Object(fields) => fields.copy()
    _ => Map([])
  }
  fields[key] = entry
  Json::object(fields)
}

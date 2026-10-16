///|
/// A content-stream text operation owns its graphics state once. Individual
/// glyphs carry only source identity, geometry and a font-resource invocation.
priv struct PdfCanvasTextRun {
  scope : Int
  state : Int
  draws : Array[Double]
  text : Array[String]
}

///|
priv enum PdfCanvasCommand {
  Paint(Json)
  TextRun(PdfCanvasTextRun)
}

///|
fn pdf_canvas_text_row(
  value : PdfTextItem,
  call : PdfCanvasGlyphCall,
) -> Array[Double]? {
  guard value.glyph_transform is Some(transform) && transform.length() == 6 else {
    return None
  }
  let b = value.bounds
  let q = value.quad
  let row = [
    value.index.to_double(),
    value.charcode.to_double(),
    value.advance_x,
    value.advance_y,
    b.min_x,
    b.min_y,
    b.max_x,
    b.max_y,
    q.p0.x,
    q.p0.y,
    q.p1.x,
    q.p1.y,
    q.p2.x,
    q.p2.y,
    q.p3.x,
    q.p3.y,
    ..transform,
    call.resource.id.to_double(),
    ..call.matrix,
  ]
  if row.length() == 29 && row.all(v => !v.is_nan() && !v.is_inf()) {
    Some(row)
  } else {
    None
  }
}

///|
fn pdf_canvas_text_state(command : Json) -> Json {
  guard command is Object(fields) && fields.get("paint") is Some(Object(paint)) else {
    return command
  }
  let shared : Map[String, Json] = Map([])
  for name, value in paint {
    match name {
      "index"
      | "text"
      | "charcode"
      | "advance_x"
      | "advance_y"
      | "bounds"
      | "quad"
      | "glyph_transform" => ()
      _ => shared[name] = value
    }
  }
  pdf_canvas_object_with(command, "paint", Json::object(shared))
}

///|
fn pdf_canvas_commands_json(commands : Array[PdfCanvasCommand]) -> Json {
  let result : Array[Json] = commands.map(command => {
    match command {
      Paint(value) => value
      TextRun(run) =>
        {
          "kind": "text_run".to_json(),
          "state": run.state.to_json(),
          "draws": run.draws.to_json(),
          "text": run.text.to_json(),
        }
    }
  })
  result.to_json()
}

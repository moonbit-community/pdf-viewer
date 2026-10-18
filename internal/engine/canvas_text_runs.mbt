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
fn pdf_canvas_append_text_row(
  draws : Array[Double],
  value : PdfTextItem,
  call : PdfCanvasGlyphCall,
) -> Bool {
  guard value.glyph_transform is Some(transform) &&
    transform.length() == 6 &&
    call.matrix.length() == 6 else {
    return false
  }
  let b = value.bounds
  let q = value.quad
  // Validate before touching an existing run. A malformed public model must
  // keep its individual-paint fallback without changing earlier glyph rows.
  guard pdf_canvas_text_number(value.advance_x) &&
    pdf_canvas_text_number(value.advance_y) &&
    pdf_canvas_text_number(b.min_x) &&
    pdf_canvas_text_number(b.min_y) &&
    pdf_canvas_text_number(b.max_x) &&
    pdf_canvas_text_number(b.max_y) &&
    pdf_canvas_text_number(q.p0.x) &&
    pdf_canvas_text_number(q.p0.y) &&
    pdf_canvas_text_number(q.p1.x) &&
    pdf_canvas_text_number(q.p1.y) &&
    pdf_canvas_text_number(q.p2.x) &&
    pdf_canvas_text_number(q.p2.y) &&
    pdf_canvas_text_number(q.p3.x) &&
    pdf_canvas_text_number(q.p3.y) else {
    return false
  }
  for number in transform {
    guard pdf_canvas_text_number(number) else { return false }
  }
  for number in call.matrix {
    guard pdf_canvas_text_number(number) else { return false }
  }
  draws.push(value.index.to_double())
  draws.push(value.charcode.to_double())
  draws.push(value.advance_x)
  draws.push(value.advance_y)
  draws.push(b.min_x)
  draws.push(b.min_y)
  draws.push(b.max_x)
  draws.push(b.max_y)
  draws.push(q.p0.x)
  draws.push(q.p0.y)
  draws.push(q.p1.x)
  draws.push(q.p1.y)
  draws.push(q.p2.x)
  draws.push(q.p2.y)
  draws.push(q.p3.x)
  draws.push(q.p3.y)
  for number in transform {
    draws.push(number)
  }
  draws.push(call.resource.id.to_double())
  for number in call.matrix {
    draws.push(number)
  }
  true
}

///|
fn pdf_canvas_text_number(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
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
fn pdf_canvas_commands_json(
  commands : Array[PdfCanvasCommand],
  number_data? : (Array[Double]) -> Json = values => values.to_json(),
) -> Json {
  let result : Array[Json] = commands.map(command => {
    match command {
      Paint(value) => value
      TextRun(run) =>
        {
          "kind": "text_run".to_json(),
          "state": run.state.to_json(),
          "draws": number_data(run.draws),
          "text": run.text.to_json(),
        }
    }
  })
  result.to_json()
}

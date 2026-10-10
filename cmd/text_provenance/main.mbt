///|
fn main {
  @sys.exit(run())
}

///|
/// Check public API relationships, not a second PDF parser. Byte gaps are
/// permitted because empty copied glyphs are absent from logical text.
fn inspect(
  page : @pdf.PdfPageModel,
  provenance : Array[@pdf.PdfTextProvenance],
) -> Json {
  let errors : Array[String] = []
  let text = page.text_content().text
  if [ for item in provenance => item.source ] != page.text_sources() {
    errors.push("provenance does not match logical text sources")
  }
  let fonts : Array[Int] = []
  let programs : Array[Int] = []
  let mut captured = 0
  let mut invalid = 0
  let mut cids = 0
  let mut gids = 0
  let mut names = 0
  let mut byte_count = 0
  let ordered = provenance.copy()
  ordered.sort_by((a, b) => a.source.item_index.compare(b.source.item_index))
  let ends : Map[String, Int] = Map([])
  for item in ordered {
    let source = item.source
    if source.start < 0 ||
      source.end < source.start ||
      source.end > text.length() {
      errors.push("invalid UTF-16 range for item \{source.item_index}")
    }
    if item.font_object_number is Some(number) && !fonts.contains(number) {
      fonts.push(number)
    }
    if item.font_program_object_number is Some(number) &&
      !programs.contains(number) {
      programs.push(number)
    }
    if item.cid is Some(_) {
      cids += 1
    }
    if item.gid is Some(_) {
      gids += 1
    }
    if item.glyph_name is Some(_) {
      names += 1
    }
    guard item.string_source is Some(origin) else { continue }
    captured += 1
    byte_count += origin.bytes.length()
    if origin.byte_start < 0 ||
      origin.byte_end - origin.byte_start != origin.bytes.length() ||
      origin.bytes.is_empty() ||
      origin.bytes.length() > 4 {
      errors.push("invalid operand byte range for item \{source.item_index}")
    }
    if origin.operator_index < 0 || origin.operand_index < 0 {
      errors.push(
        "invalid operation/operand index for item \{source.item_index}",
      )
    }
    let key : Json = {
      "streams": ToJson::to_json(origin.content_streams),
      "forms": ToJson::to_json(origin.form_path),
      "operator": origin.operator_index,
      "operand": origin.operand_index,
    }
    let key = key.stringify()
    if origin.byte_start < ends.get(key).unwrap_or(0) {
      errors.push(
        "overlapping operand byte ranges for item \{source.item_index}",
      )
    }
    ends[key] = origin.byte_end
    if origin.charcode_valid {
      let mut code = 0U
      for byte in origin.bytes {
        code = (code << 8) | byte.to_int().reinterpret_as_uint()
      }
      if code.reinterpret_as_int() != source.charcode {
        errors.push(
          "operand bytes disagree with charcode for item \{source.item_index}",
        )
      }
    } else {
      invalid += 1
      if item.cid is Some(_) ||
        item.gid is Some(_) ||
        item.glyph_name is Some(_) {
        errors.push("invalid character code has a font glyph mapping")
      }
    }
  }
  if captured != provenance.length() {
    errors.push("some logical text glyphs have no decoded string source")
  }
  {
    "passed": errors.is_empty(),
    "logical_glyphs": provenance.length(),
    "captured_glyphs": captured,
    "captured_bytes": byte_count,
    "invalid_codes": invalid,
    "cid_mappings": cids,
    "gid_mappings": gids,
    "glyph_names": names,
    "font_objects": ToJson::to_json(fonts),
    "font_program_objects": ToJson::to_json(programs),
    "errors": ToJson::to_json(errors),
  }
}

///|
fn run() -> Int {
  let args = @env.args()
  if args.length() < 3 || args.length() > 4 {
    println("usage: text_provenance <input.pdf> <output.json> [page]")
    return 2
  }
  try {
    let number = if args.length() == 4 { @string.parse_int(args[3]) } else { 1 }
    let viewer = @pdf.open_document(@fs.read_file_to_bytes(args[1]))
    guard viewer.page(number) is Some(page) else {
      println("text_provenance: page \{number} does not exist")
      return 1
    }
    let provenance = viewer.text_provenance(number).unwrap()
    let checks = inspect(page, provenance)
    let report : Json = {
      "file": args[1],
      "page": number,
      "offset_unit": "decoded PDF string operand bytes",
      "text": page.text_content().text,
      "checks": checks,
      "provenance": ToJson::to_json(provenance),
    }
    @fs.write_string_to_file(args[2], report.stringify(indent=2))
    println(checks.stringify())
    if checks is { "passed": True, .. } {
      0
    } else {
      1
    }
  } catch {
    error => {
      println("text_provenance: " + @debug.to_string(error))
      1
    }
  }
}

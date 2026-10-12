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
  lexical : Array[@pdf.PdfTextLexicalSource],
  diagnostics : Array[@pdf.PdfTextRecoveryDiagnostic],
  source_length : Int,
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
  let mut located = 0
  let mut file_spans = 0
  let mut empty_copies = 0
  let by_item : Map[Int, @pdf.PdfTextProvenance] = Map([])
  for item in provenance {
    by_item[item.source.item_index] = item
  }
  for item in lexical {
    if item.failure is Some(reason) {
      errors.push(
        "unverified lexical source for item \{item.item_index}: " + reason,
      )
      continue
    }
    located += 1
    match item.logical_source {
      Some(source) =>
        match by_item.get(item.item_index) {
          Some(origin) if origin.source == source &&
            origin.string_source == item.string_source => ()
          _ =>
            errors.push(
              "lexical and logical source disagree for item \{item.item_index}",
            )
        }
      None => empty_copies += 1
    }
    for span in item.spans {
      let decoded = span.decoded_stream_span
      if decoded.start < 0 || decoded.end <= decoded.start {
        errors.push("invalid decoded-stream lexical span")
      }
      if span.encoded_stream_span is Some(encoded) &&
        (
          encoded.start < 0 ||
          encoded.end < encoded.start ||
          encoded.end > source_length
        ) {
        errors.push("encoded-stream span exceeds the input file")
      }
      if span.file_span is Some(file) {
        file_spans += 1
        match span.encoded_stream_span {
          Some(encoded) if file.start == encoded.start + decoded.start &&
            file.end == encoded.start + decoded.end &&
            file.end <= encoded.end => ()
          _ =>
            errors.push(
              "file lexical span does not belong to its original stream",
            )
        }
      }
    }
  }
  let structure = page.text_structure()
  let structured_sources : Array[@pdf.PdfTextSourceRange] = []
  let mut run_count = 0
  for paragraph in structure.paragraphs {
    for run in paragraph.runs {
      run_count += 1
      if run.start < paragraph.start || run.end > paragraph.end {
        errors.push("run exceeds its paragraph")
      }
      for source in run.sources {
        if source.start < run.start || source.end > run.end {
          errors.push("glyph exceeds its run")
        }
        structured_sources.push(source)
      }
    }
  }
  if structure.text != text || structured_sources != page.text_sources() {
    errors.push("structured runs do not preserve logical source order")
  }
  let origins : Map[Int, @pdf.PdfTextLexicalSource] = Map([])
  for origin in lexical {
    origins[origin.item_index] = origin
  }
  let kinds : Map[String, Int] = Map([])
  for observation in diagnostics {
    let key = ToJson::to_json(observation.kind).stringify()
    kinds[key] = kinds.get(key).unwrap_or(0) + 1
    match origins.get(observation.item_index) {
      Some(origin) if origin.logical_source == observation.source &&
        origin.string_source == observation.string_source => ()
      _ => errors.push("recovery observation disagrees with its glyph origin")
    }
    match page.items.get(observation.item_index) {
      Some(@pdf.PdfPageItem::Text(item)) if observation.page == page.number &&
        observation.charcode == item.charcode &&
        observation.font == item.font => ()
      _ =>
        errors.push("recovery observation does not identify its painted glyph")
    }
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
    "located_glyphs": located,
    "empty_copied_glyphs": empty_copies,
    "file_lexical_spans": file_spans,
    "text_runs": run_count,
    "paragraphs": structure.paragraphs.length(),
    "recovery_observations": diagnostics.length(),
    "diagnostic_kinds": kinds.to_json(),
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
    let bytes = @fs.read_file_to_bytes(args[1])
    let viewer = @pdf.open_document(bytes)
    guard viewer.page(number) is Some(page) else {
      println("text_provenance: page \{number} does not exist")
      return 1
    }
    let provenance = viewer.text_provenance(number).unwrap()
    let lexical = viewer.text_lexical_sources(number).unwrap()
    let diagnostics = viewer.text_recovery_diagnostics(number).unwrap()
    let checks = inspect(page, provenance, lexical, diagnostics, bytes.length())
    let report : Json = {
      "file": args[1],
      "page": number,
      "offset_unit": "decoded PDF string operand bytes",
      "text": page.text_content().text,
      "checks": checks,
      "provenance": ToJson::to_json(provenance),
      "lexical_sources": ToJson::to_json(lexical),
      "text_structure": ToJson::to_json(page.text_structure()),
      "text_recovery_diagnostics": diagnostics.to_json(),
      "reader_diagnostics": viewer.reader_diagnostics().to_json(),
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

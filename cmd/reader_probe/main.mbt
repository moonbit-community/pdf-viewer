///|
fn main {
  @sys.exit(run())
}

///|
fn run() -> Int {
  let args = @env.args()
  guard args.length() == 3 || args.length() == 4 else {
    println("usage: reader_probe input.pdf output.json [--text|--cmaps]")
    return 2
  }
  let bytes = @fs.read_file_to_bytes(args[1]) catch { _ => return 2 }
  let startxref = try @reader.pdf_read_startxref_position(bytes) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
  let streams : Map[String, Int] = Map([])
  let original = try @pdflite.pdf_read_document_from_bytes(bytes) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
  if original is Some(document) {
    for number in document.object_numbers() {
      if document.lookup_object_or_null(number)
        is @syntax.PdfStreamObject(stream) {
        if stream.dictionary.lookup_immediate(@core.pdf_name_of_bytes(b"/Type"))
          is Some(@syntax.PdfNameObject(name)) {
          let kind = @utf8.decode_lossy(name.bytes())
          streams[kind] = streams.get(kind).unwrap_or(0) + 1
        }
      }
    }
  }
  let report : Json = try {
    let document = @pdf.open_document(bytes)
    let text : Json = if args.length() == 4 && args[3] == "--text" {
      match document.page(1) {
        Some(page) =>
          {
            "glyphs": page.text_content().items.length(),
            "text": page.text_content().text,
            "diagnostics": document
            .text_recovery_diagnostics(1)
            .unwrap_or([])
            .to_json(),
          }
        None => Json::null()
      }
    } else {
      Json::null()
    }
    let inspect_cmaps = args.length() == 4 && args[3] == "--cmaps"
    // The original page tree has been validated by open_document. Recovered
    // trees cannot be walked raw; their skipped branches are reported instead.
    let skipped = inspect_cmaps && !document.reader_diagnostics().is_empty()
    let maps = if inspect_cmaps && !skipped && original is Some(original) {
      cmap_samples(original, args[1]).to_json()
    } else {
      Json::array([])
    }
    {
      "file": args[1],
      "passed": true,
      "pages": document.page_count(),
      "bytes": bytes.length(),
      "startxref": startxref.to_json(),
      "stream_types": streams.to_json(),
      "text": text,
      "reader_diagnostics": document.reader_diagnostics().to_json(),
      "cmaps": maps,
      "cmap_page_tree_skipped": skipped,
    }
  } catch {
    error =>
      {
        "file": args[1],
        "passed": false,
        "error": @debug.to_string(error),
        "bytes": bytes.length(),
        "startxref": startxref.to_json(),
        "stream_types": streams.to_json(),
      }
  }
  @fs.write_string_to_file(args[2], report.stringify(indent=2)) catch {
    _ => return 2
  }
  println(report.stringify())
  if report is { "passed": True, .. } {
    0
  } else {
    1
  }
}

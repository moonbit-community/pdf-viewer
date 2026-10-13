///|
pub fn apply_xfa_packets(changes : String) -> String {
  guard current_document.val is Some(document) else {
    return browser_error_with_code("document-closed", "No document open")
  }
  try {
    let original = editor_original.val.unwrap_or(document)
    guard @json.parse(changes) is Array(packets) else {
      return browser_error("Expected XFA packet replacements")
    }
    let replacements = packets.map(packet => {
      guard packet is Object(fields) &&
        fields.get("name") is Some(String(name)) &&
        fields.get("data_base64") is Some(String(encoded)) else {
        raise @core.SoftError("Invalid XFA data packet")
      }
      ({ name, data: @base64.decode(encoded), } : @pdf.PdfXfaPacket)
    })
    current_document.val = Some(original.with_xfa_packets(replacements))
    editor_original.val = Some(original)
    browser_clear_pages()
    ({ "ok": true } : Json).stringify()
  } catch {
    error => browser_error_with_code("edit-error", @debug.to_string(error))
  }
}

///|
pub fn xfa_data() -> String {
  try {
    guard current_document.val is Some(document) else {
      return browser_error("No document open")
    }
    let packets = document.xfa_packets()
    let value : Json = {
      "ok": true,
      "needs_rendering": document.xfa_needs_rendering(),
      "packets": packets
      .map(packet => {
        (
          {
            "name": packet.name.to_json(),
            "data_base64": @base64.encode(packet.data).to_json(),
          } : Json)
      })
      .to_json(),
      "fonts": if packets.is_empty() {
        [].to_json()
      } else {
        document.xfa_fonts_json()
      },
    }
    value.stringify()
  } catch {
    error => browser_error(@debug.to_string(error))
  }
}

///|
pub fn xfa_font_glyphs(id : String, text : String) -> String {
  try {
    guard current_document.val is Some(document) else {
      return browser_error("No document open")
    }
    let result : Json = {
      "ok": true,
      "glyphs": document.xfa_font_glyphs_json(id, text),
    }
    result.stringify()
  } catch {
    error => browser_error(@debug.to_string(error))
  }
}

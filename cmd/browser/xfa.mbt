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

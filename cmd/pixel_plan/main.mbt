///|
/// Small headless validation bridge. Browser hosts use cmd/browser instead.
pub fn render_plan(
  bytes : Bytes,
  number : Int,
  scale : Double,
  rotation : Int,
) -> String {
  try {
    let document = @pdf.open_document(bytes)
    guard document.page(number) is Some(page) else {
      return ({ "ok": false, "error": "Page does not exist" } : Json).stringify()
    }
    (
      {
        "ok": true,
        "count": document.page_count(),
        "canvas": page.canvas_plan(scale~, rotation=page.rotation + rotation),
        "svg": page.render_svg(scale~, rotation=page.rotation + rotation),
      } : Json).stringify()
  } catch {
    error =>
      ({ "ok": false, "error": @debug.to_string(error) } : Json).stringify()
  }
}

///|
pub fn process_cmyk_to_rgb(
  cyan : Double,
  magenta : Double,
  yellow : Double,
  black : Double,
) -> Array[Double] {
  @pdf.process_cmyk_to_rgb(cyan, magenta, yellow, black)
}

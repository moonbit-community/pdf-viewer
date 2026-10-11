///|
/// Use the same body renderer with independently selected print appearances.
pub fn render_print_page(
  number : Int,
  scale : Double,
  rotation : Int,
) -> String {
  browser_render_page(number, scale, rotation, true)
}

///|
/// Render the first page of a PDF to a self-contained SVG file.
///
/// Usage:
///
///   moon run cmd/main --target native -- input.pdf [output.svg]
///
/// The command is intentionally small: document parsing, page modelling,
/// viewport calculation, and SVG serialization all live in the library so the
/// same pipeline can later be called from a browser host.
async fn main {
  let args = @env.args()
  if args.length() < 2 {
    println(
      "usage: moon run cmd/main --target native -- input.pdf [output.svg]",
    )
  } else {
    let input_path = args[1]
    let output_path = if args.length() >= 3 { args[2] } else { "page-1.svg" }
    let source = @fs.read_file(input_path).binary()
    let viewer = @viewer.open_document(source) catch {
      _ => {
        println("failed to parse PDF: " + input_path)
        return
      }
    }
    let rendered = viewer.render_svg(1, scale=1.0) catch { _ => None }
    match rendered {
      Some(svg) => {
        @fs.write_file(
          output_path,
          @utf8.encode(svg),
          create_mode=CreateOrTruncate,
          permission=0o644,
        )
        println(
          "rendered page 1/" +
          viewer.page_count().to_string() +
          " to " +
          output_path,
        )
      }
      None => println("PDF does not contain page 1")
    }
  }
}

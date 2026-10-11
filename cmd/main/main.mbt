///|
fn main {
  @sys.exit(run())
}

///|
fn run() -> Int {
  let args = @env.args()
  if args.length() < 2 || args.length() > 4 {
    println(
      "usage: pdf-viewer <input.pdf> [output.svg|output.canvas.json] [page]",
    )
    return 2
  }
  let input = args[1]
  let page_number = if args.length() >= 4 {
    @string.parse_int(args[3]) catch {
      _ => {
        println("pdf-viewer: page must be an integer")
        return 2
      }
    }
  } else {
    1
  }
  if page_number < 1 {
    println("pdf-viewer: page must be positive")
    return 2
  }
  let output = if args.length() >= 3 {
    args[2]
  } else {
    input + ".page-\{page_number}.svg"
  }
  try {
    let bytes = @fs.read_file_to_bytes(input)
    let viewer = @pdf.open_document(bytes)
    let page = match viewer.page(page_number) {
      Some(page) => page
      None => {
        println("pdf-viewer: page \{page_number} does not exist")
        return 1
      }
    }
    let canvas = output.has_suffix(".canvas.json")
    for
      diagnostic in page.graphics_diagnostics(
        renderer=if canvas { "canvas" } else { "svg" },
      ) {
      println(
        "pdf-viewer: \{diagnostic.code} (item \{diagnostic.item}): \{diagnostic.message}",
      )
    }
    let rendered = if canvas {
      page.canvas_plan().stringify()
    } else {
      page.render_svg(scale=1.0)
    }
    @fs.write_string_to_file(output, rendered)
    println("wrote page \{page_number} of \{viewer.page_count()} to \{output}")
    0
  } catch {
    err => {
      println("pdf-viewer: \{@debug.to_string(err)}")
      1
    }
  }
}

///|
fn main {
  @sys.exit(run())
}

///|
fn run() -> Int {
  let args = @env.args()
  if args.length() < 2 || args.length() > 4 {
    println("usage: pdf-viewer <input.pdf> [output.svg] [page]")
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
    let svg = viewer.render_svg(page_number, scale=1.0) catch {
      err => {
        println("pdf-viewer: failed to render page: \{@debug.to_string(err)}")
        return 1
      }
    }
    match svg {
      Some(svg) => {
        @fs.write_string_to_file(output, svg)
        println(
          "wrote page \{page_number} of \{viewer.page_count()} to \{output}",
        )
        0
      }
      None => {
        println("pdf-viewer: page \{page_number} does not exist")
        1
      }
    }
  } catch {
    err => {
      println("pdf-viewer: \{@debug.to_string(err)}")
      1
    }
  }
}

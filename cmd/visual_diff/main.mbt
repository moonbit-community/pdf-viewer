///|
fn main {
  @sys.exit(run())
}

///|
fn run() -> Int {
  let args = @env.args()
  if args.length() != 8 {
    println(
      "usage: visual_diff <reference.rgba> <width> <height> <viewer.rgba> <width> <height> <heatmap.rgba>",
    )
    return 2
  }
  try {
    let reference = @pixels.Raster::from_rgba(
      @fs.read_file_to_bytes(args[1]),
      @string.parse_int(args[2]),
      @string.parse_int(args[3]),
    )
    let viewer = @pixels.Raster::from_rgba(
      @fs.read_file_to_bytes(args[4]),
      @string.parse_int(args[5]),
      @string.parse_int(args[6]),
    )
    guard reference is Some(reference) && viewer is Some(viewer) else {
      println("visual_diff: invalid RGBA buffer or raster dimensions")
      return 1
    }
    let result = @pixels.compare(reference, viewer)
    @fs.write_bytes_to_file(args[7], result.heatmap)
    println(ToJson::to_json(result.stats).stringify())
    0
  } catch {
    error => {
      println("visual_diff: " + @debug.to_string(error))
      1
    }
  }
}

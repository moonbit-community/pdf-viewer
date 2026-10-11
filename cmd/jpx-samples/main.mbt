///|

///|
async fn main {
  let args = @env.args()
  guard args.length() >= 3 else {
    fail("usage: jpx_samples.mbtx input.jp2 output.raw [SMaskInData]")
  }
  let bytes = @fs.read_file(args[1]).binary()
  let smask = if args.length() > 3 {
    if args[3] == "2" {
      2
    } else if args[3] == "1" {
      1
    } else {
      0
    }
  } else {
    0
  }
  match @jpx.decode(bytes, smask_in_data=smask) {
    Err(error) => println("ERROR: \{error}")
    Ok(samples) => {
      @fs.write_file(args[2], samples.bytes)
      if samples.embedded_alpha is Some(alpha) {
        @fs.write_file(args[2] + ".alpha", alpha)
      }
      println(
        "\{samples.width} \{samples.height} \{samples.components} \{samples.bits} \{samples.colour_hint}",
      )
    }
  }
}

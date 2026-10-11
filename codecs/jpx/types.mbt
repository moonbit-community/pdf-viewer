///|
/// Interleaved, row-major, unsigned 8/16-bit big-endian PDF colour samples.
/// Embedded opacity is separate, unmodified and never applied twice. No PDF
/// /Decode, colour-key, external mask or Matte has been applied here.
pub(all) struct Samples {
  bytes : Bytes
  width : Int
  height : Int
  bits : Int
  components : Int
  row_bytes : Int
  embedded_alpha : Bytes?
  embedded_alpha_bits : Int
  embedded_alpha_row_bytes : Int
  embedded_alpha_associated : Bool
  embedded_icc_profile : Bytes?
  colour_hint : String
} derive(Debug)

///|
pub(all) struct Limits {
  max_input_bytes : Int
  max_pixels : Int
  max_samples : Int
  max_tiles : Int
  max_layers : Int
}

///|
/// Bounds are checked before invoking the reused entropy/wavelet decoder.
/// `max_samples` also bounds per-component intermediate coefficient arrays.
pub fn default_limits() -> Limits {
  {
    max_input_bytes: 33554432,
    max_pixels: 4194304,
    max_samples: 8388608,
    max_tiles: 1024,
    max_layers: 128,
  }
}

///|
priv suberror Invalid {
  Invalid(String)
}

///|
priv struct Channel {
  index : Int
  kind : Int
  association : Int
}

///|
priv struct Header {
  codestream : Bytes
  hint : String
  icc_profile : Bytes?
  channels : Array[Channel]
  palette : Palette?
  mappings : Array[(Int, Int, Int)]
}

///|
priv struct Geometry {
  width : Int
  height : Int
  components : Int
  bits : Array[Int]
  signed : Array[Bool]
  dx : Array[Int]
  dy : Array[Int]
  x0 : Int
  y0 : Int
}

///|
priv struct Palette {
  entries : Int
  bits : Array[Int]
  signed : Array[Bool]
  values : Array[Array[Int]]
}

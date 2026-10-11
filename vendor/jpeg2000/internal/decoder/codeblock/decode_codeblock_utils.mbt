///|
// Local utility functions used by codeblock decoding.
// These are copies of functions defined in the decoder root package,
// duplicated here to avoid circular dependency.

///|
fn clamp_sample_for_signedness(
  v : Int,
  signed_samples : Bool,
  precision_bits? : Int = 8,
) -> Int {
  if signed_samples {
    let half = 1 << (precision_bits - 1)
    if v < -half {
      return -half
    }
    if v >= half {
      return half - 1
    }
    return v
  }
  let max_val = (1 << precision_bits) - 1
  if v < 0 {
    return 0
  }
  if v > max_val {
    return max_val
  }
  v
}

///|
fn print_audit_cblk_stats(
  kind : String,
  audit_label : String,
  comp : Int,
  res : Int,
  sb : Int,
  cbx : Int,
  cby : Int,
  samples : Array[Int],
) -> Unit {
  let mut min_v = 0
  let mut max_v = 0
  let preview : Array[Int] = []
  if samples.length() > 0 {
    min_v = samples[0]
    max_v = samples[0]
  }
  for i in 0..<samples.length() {
    let v = samples[i]
    if v < min_v {
      min_v = v
    }
    if v > max_v {
      max_v = v
    }
    if i < 64 {
      preview.push(v)
    }
  }
  println(
    "\{kind}:label=\{audit_label} c=\{comp} r=\{res} sb=\{sb} cbx=\{cbx} cby=\{cby} len=\{samples.length()} min=\{min_v} max=\{max_v} first=\{preview}",
  )
}

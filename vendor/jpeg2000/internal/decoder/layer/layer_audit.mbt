///|
fn print_audit_sample_stats(
  kind : String,
  audit_label : String,
  comp : Int,
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
    "\{kind}:label=\{audit_label} c=\{comp} len=\{samples.length()} min=\{min_v} max=\{max_v} first=\{preview}",
  )
}

///|
fn print_audit_sample_stats_float(
  kind : String,
  audit_label : String,
  comp : Int,
  samples : Array[Double],
) -> Unit {
  let rounded : Array[Int] = []
  for v in samples {
    rounded.push(@math.round_ties_even_f32(v))
  }
  print_audit_sample_stats(kind, audit_label, comp, rounded)
}

///|
fn print_audit_sample_stats_float_exact(
  kind : String,
  audit_label : String,
  comp : Int,
  samples : Array[Double],
) -> Unit {
  let mut min_v = 0.0
  let mut max_v = 0.0
  let preview : Array[String] = []
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
    if i < 16384 {
      preview.push("\{v}")
    }
  }
  println(
    "\{kind}:label=\{audit_label} c=\{comp} len=\{samples.length()} min=\{min_v} max=\{max_v} first=\{preview}",
  )
}

///|
fn print_audit_sample_stats_float_f32bits(
  kind : String,
  audit_label : String,
  comp : Int,
  samples : Array[Double],
) -> Unit {
  let mut min_v = ""
  let mut max_v = ""
  let preview : Array[String] = []
  if samples.length() > 0 {
    min_v = @math.f32bits_hex(samples[0])
    max_v = min_v
  }
  for i in 0..<samples.length() {
    let v = @math.f32bits_hex(samples[i])
    if min_v == "" || v < min_v {
      min_v = v
    }
    if max_v == "" || v > max_v {
      max_v = v
    }
    if i < 16384 {
      preview.push(v)
    }
  }
  println(
    "\{kind}:label=\{audit_label} c=\{comp} len=\{samples.length()} min=\{min_v} max=\{max_v} first=\{preview}",
  )
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

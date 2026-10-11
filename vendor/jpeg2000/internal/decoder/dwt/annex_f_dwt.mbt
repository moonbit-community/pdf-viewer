///|
// Spec grouping:
// - Annex F: Discrete Wavelet Transformation
// - F.3: 5/3 Reversible Filter (lossless)

///|
// T.800-2015 F.3.5, F.3.7, F.3.8.1:
// 1D inverse 5/3 DWT with PSEO boundary extension (spec-compliant).
// cas=0: signal starts at even absolute position (standard case)
// cas=1: signal starts at odd absolute position (non-zero tile offset)
//
// Uses PSEO (Periodic Symmetric Extension Operation) per F.3.7 Eq. F-4
// for boundary extension, as required by the T.800-2015 specification.
pub fn idwt_53_1d(
  low : Array[Int],
  high : Array[Int],
  cas? : Int = 0,
) -> Array[Int] {
  // Delegate to spec-compliant PSEO implementation
  idwt_53_1d_spec(low, high, cas)
}

///|
// Spec basis (T.800-2015 F.3):
// 2D inverse 5/3 DWT for single decomposition level.
// Input: coefficients in subband layout (LL, HL, LH, HH quadrants)
// Output: reconstructed samples
fn idwt_53_2d_single_level(
  coeffs : Array[Int],
  width : Int,
  height : Int,
  half_w? : Int = -1,
  half_h? : Int = -1,
  cas_h? : Int = -1,
  cas_v? : Int = -1,
) -> Result[Array[Int], String] {
  if width <= 0 || height <= 0 {
    return Err("invalid dimensions for idwt")
  }
  if coeffs.length() != width * height {
    return Err("coefficient count mismatch")
  }
  // T.800-2015 B.5: LL/detail split depends on absolute coordinates.
  // half_w/half_h specify the LL subband size; -1 = use default ceil(width/2).
  let half_w = if half_w >= 0 { half_w } else { (width + 1) / 2 }
  let half_h = if half_h >= 0 { half_h } else { (height + 1) / 2 }
  // T.800-2015 F.3.5: cas from absolute coordinate parity (passed by caller).
  // Fallback: infer from half_w/width when cas not explicitly provided.
  let cas_h = if cas_h >= 0 {
    cas_h
  } else if 2 * half_w < width {
    1
  } else {
    0
  }
  let cas_v = if cas_v >= 0 {
    cas_v
  } else if 2 * half_h < height {
    1
  } else {
    0
  }
  // Step 1: Horizontal inverse DWT on each row
  let horiz : Array[Int] = []
  for _ in 0..<(width * height) {
    horiz.push(0)
  }
  for y in 0..<height {
    let low : Array[Int] = []
    let high : Array[Int] = []
    if y < half_h {
      // Top half: LL (left) + HL (right)
      for x in 0..<half_w {
        low.push(coeffs[y * width + x])
      }
      for x in half_w..<width {
        high.push(coeffs[y * width + x])
      }
    } else {
      // Bottom half: LH (left) + HH (right)
      for x in 0..<half_w {
        low.push(coeffs[y * width + x])
      }
      for x in half_w..<width {
        high.push(coeffs[y * width + x])
      }
    }
    let row = idwt_53_1d(low, high, cas=cas_h)
    for x in 0..<row.length() {
      if x < width {
        horiz[y * width + x] = row[x]
      }
    }
  }
  // Step 2: Vertical inverse DWT on each column
  let result : Array[Int] = []
  for _ in 0..<(width * height) {
    result.push(0)
  }
  for x in 0..<width {
    let low : Array[Int] = []
    let high : Array[Int] = []
    for y in 0..<half_h {
      low.push(horiz[y * width + x])
    }
    for y in half_h..<height {
      high.push(horiz[y * width + x])
    }
    let col = idwt_53_1d(low, high, cas=cas_v)
    for y in 0..<col.length() {
      if y < height {
        result[y * width + x] = col[y]
      }
    }
  }
  Ok(result)
}

///|
// Spec basis (T.800-2015 F.3):
// 1D inverse 5/3 DWT on Double coefficients (for lossy mode with 5/3 filter).
// Same algorithm as integer version but operates on floating-point values.
pub fn idwt_53_1d_float(
  low : Array[Double],
  high : Array[Double],
  cas? : Int = 0,
) -> Array[Double] {
  let sn = low.length()
  let dn = high.length()
  if sn == 0 && dn == 0 {
    return []
  }
  if sn == 0 {
    // T.800-2015 F.3.6: For length-1 signals with odd origin, divide by 2
    // When sn=0 and dn=1 and cas=1, output X(i0) = Y(i0)/2
    if dn == 1 && cas == 1 {
      return [high[0] / 2.0]
    }
    // For longer signals or even origin, return high-pass directly
    // (proper extension/filtering would apply for dn > 1, but this edge case
    // is rare in valid JPEG 2000 streams and needs more complex handling)
    return high
  }
  if dn == 0 {
    return low
  }
  // Step 1: Update low-pass (undo forward update)
  let s : Array[Double] = []
  for i in 0..<sn {
    let (d_left, d_right) = if cas == 0 {
      let dl = if i > 0 { high[i - 1] } else { high[0] }
      let dr = if i < dn { high[i] } else { high[dn - 1] }
      (dl, dr)
    } else {
      let dl = if i < dn { high[i] } else { high[dn - 1] }
      let dr = if i + 1 < dn { high[i + 1] } else { high[dn - 1] }
      (dl, dr)
    }
    // s[i] -= floor((d_left + d_right + 2) / 4)
    s.push(low[i] - ((d_left + d_right + 2.0) / 4.0).floor())
  }
  // Step 2: Predict high-pass (undo forward predict)
  let d : Array[Double] = []
  for i in 0..<dn {
    let (x_left, x_right) = if cas == 0 {
      let xl = if i < sn { s[i] } else { s[sn - 1] }
      let xr = if i + 1 < sn { s[i + 1] } else { s[sn - 1] }
      (xl, xr)
    } else {
      let xl = if i > 0 && i - 1 < sn { s[i - 1] } else { s[0] }
      let xr = if i < sn { s[i] } else { s[sn - 1] }
      (xl, xr)
    }
    // d[i] += floor((x_left + x_right) / 2)
    d.push(high[i] + ((x_left + x_right) / 2.0).floor())
  }
  // Step 3: Interleave
  let out : Array[Double] = []
  let n = sn + dn
  for i in 0..<n {
    if cas == 0 {
      if i % 2 == 0 {
        out.push(s[i / 2])
      } else {
        out.push(d[i / 2])
      }
    } else if i % 2 == 0 {
      out.push(d[i / 2])
    } else {
      out.push(s[i / 2])
    }
  }
  out
}

///|
// Spec basis (T.800-2015 F.3):
// 2D inverse 5/3 DWT on Double coefficients for single decomposition level.
fn idwt_53_2d_single_level_float(
  coeffs : Array[Double],
  width : Int,
  height : Int,
  half_w? : Int = -1,
  half_h? : Int = -1,
  cas_h? : Int = -1,
  cas_v? : Int = -1,
) -> Result[Array[Double], String] {
  if width <= 0 || height <= 0 {
    return Err("invalid dimensions for 5/3 float idwt")
  }
  if coeffs.length() != width * height {
    return Err("coefficient count mismatch for 5/3 float idwt")
  }
  let half_w = if half_w >= 0 { half_w } else { (width + 1) / 2 }
  let half_h = if half_h >= 0 { half_h } else { (height + 1) / 2 }
  let cas_h = if cas_h >= 0 {
    cas_h
  } else if 2 * half_w < width {
    1
  } else {
    0
  }
  let cas_v = if cas_v >= 0 {
    cas_v
  } else if 2 * half_h < height {
    1
  } else {
    0
  }
  // Step 1: Horizontal inverse DWT on each row
  let horiz : Array[Double] = []
  for _ in 0..<(width * height) {
    horiz.push(0.0)
  }
  for y in 0..<height {
    let low : Array[Double] = []
    let high : Array[Double] = []
    for x in 0..<half_w {
      low.push(coeffs[y * width + x])
    }
    for x in half_w..<width {
      high.push(coeffs[y * width + x])
    }
    let row = idwt_53_1d_float(low, high, cas=cas_h)
    for x in 0..<row.length() {
      if x < width {
        horiz[y * width + x] = row[x]
      }
    }
  }
  // Step 2: Vertical inverse DWT on each column
  let result : Array[Double] = []
  for _ in 0..<(width * height) {
    result.push(0.0)
  }
  for x in 0..<width {
    let low : Array[Double] = []
    let high : Array[Double] = []
    for y in 0..<half_h {
      low.push(horiz[y * width + x])
    }
    for y in half_h..<height {
      high.push(horiz[y * width + x])
    }
    let col = idwt_53_1d_float(low, high, cas=cas_v)
    for y in 0..<col.length() {
      if y < height {
        result[y * width + x] = col[y]
      }
    }
  }
  Ok(result)
}

///|
// Spec basis (T.800-2015 F.3):
// Apply inverse 5/3 DWT on Double coefficients for multiple decomposition levels.
// Used when qstyle≠0 (quantization) combined with transformation=1 (5/3 filter).
fn apply_inverse_dwt_53_float(
  coeffs : Array[Double],
  width : Int,
  height : Int,
  decomposition_levels : Int,
  tcx0? : Int = 0,
  tcy0? : Int = 0,
) -> Result[Array[Double], String] {
  if decomposition_levels <= 0 {
    return Ok(coeffs)
  }
  if width <= 0 || height <= 0 {
    return Err("invalid dimensions for 5/3 float idwt")
  }
  if coeffs.length() != width * height {
    return Err("coefficient count mismatch for 5/3 float idwt")
  }
  // T.800-2015 B.5: Pre-compute resolution dimensions using absolute coordinates
  let res_dims : Array[(Int, Int)] = []
  for r in 0..<=decomposition_levels {
    let level = decomposition_levels - r
    let (rw, rh) = @subband.subband_ll_dims(width, height, level, tcx0~, tcy0~)
    res_dims.push((rw, rh))
  }
  // T.800-2015 F.3.5: Pre-compute absolute origins for cas determination
  let origins = @subband.resolution_origins(tcx0, tcy0, decomposition_levels)
  if decomposition_levels == 1 {
    let (ll_w, ll_h) = res_dims[0]
    let (ox, oy) = origins[1]
    return idwt_53_2d_single_level_float(
      coeffs,
      width,
      height,
      half_w=ll_w,
      half_h=ll_h,
      cas_h=ox % 2,
      cas_v=oy % 2,
    )
  }
  let current : Array[Double] = []
  for c in coeffs {
    current.push(c)
  }
  for level in 0..<decomposition_levels {
    let (ll_w, ll_h) = res_dims[level]
    let (next_w, next_h) = res_dims[level + 1]
    // T.800-2015 B.5: skip only when OUTPUT resolution has zero extent
    // When LL has zero extent but output is non-zero, the 1D_SR procedure
    // handles this per F.3.6 (single-sample scaling for odd origins)
    if next_w <= 0 || next_h <= 0 {
      continue
    }
    let (ox, oy) = origins[level + 1]
    let subband : Array[Double] = []
    for y in 0..<next_h {
      for x in 0..<next_w {
        if y < height && x < width && y * width + x < current.length() {
          subband.push(current[y * width + x])
        } else {
          subband.push(0.0)
        }
      }
    }
    let result_v = idwt_53_2d_single_level_float(
      subband,
      next_w,
      next_h,
      half_w=ll_w,
      half_h=ll_h,
      cas_h=ox % 2,
      cas_v=oy % 2,
    )
    guard result_v is Ok(result) else {
      return Err("5/3 float idwt level \{level} failed")
    }
    for y in 0..<next_h {
      for x in 0..<next_w {
        if y < height && x < width {
          current[y * width + x] = result[y * next_w + x]
        }
      }
    }
  }
  Ok(current)
}

///|
// Spec grouping:
// - F.3.6: 9/7 Irreversible Filter (lossy)
// - Table F.4: lifting coefficients

// T.800-2015 Table F.4: 9/7 irreversible lifting coefficients.
// T.800-2015 Table F.4: float32 precision for 9/7 lifting coefficients.
let idwt97_alpha : Double = @math.round_to_f32(-1.586134342)

///|
let idwt97_beta : Double = @math.round_to_f32(-0.052980118)

///|
let idwt97_gamma : Double = @math.round_to_f32(0.882911075)

///|
let idwt97_delta : Double = @math.round_to_f32(0.443506852)

///|
let idwt97_k : Double = @math.round_to_f32(1.230174105)

///|
// T.800-2015 F.3.8.2: high-pass unscale constant for 9/7 IDWT (≈ 2/K).
// This is approximately 2 * (1 / K), not just 1 / K.
let idwt97_two_invk : Double = @math.round_to_f32(1.625732422)

///|
fn print_dwt_level_trace(
  kind : String,
  audit_label : String,
  comp : Int,
  level : Int,
  width : Int,
  height : Int,
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
    "\{kind}:label=\{audit_label} c=\{comp} level=\{level} w=\{width} h=\{height} len=\{samples.length()} min=\{min_v} max=\{max_v} first=\{preview}",
  )
}

///|
fn print_dwt_level_trace_f32bits(
  kind : String,
  audit_label : String,
  comp : Int,
  level : Int,
  width : Int,
  height : Int,
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
    "\{kind}:label=\{audit_label} c=\{comp} level=\{level} w=\{width} h=\{height} len=\{samples.length()} min=\{min_v} max=\{max_v} first=\{preview}",
  )
}

///|
fn print_dwt_1d_trace_f32bits(
  kind : String,
  audit_label : String,
  comp : Int,
  level : Int,
  dir : String,
  vec : Int,
  stage : String,
  samples : Array[Double],
) -> Unit {
  let preview : Array[String] = []
  for i in 0..<samples.length() {
    if i < 16384 {
      preview.push(@math.f32bits_hex(samples[i]))
    }
  }
  println(
    "\{kind}:label=\{audit_label} c=\{comp} level=\{level} dir=\{dir} vec=\{vec} stage=\{stage} len=\{samples.length()} first=\{preview}",
  )
}

///|
fn step2_contract_update(
  prev : Double,
  left : Double,
  right : Double,
  c : Double,
) -> Double {
  let pair_sum = @math.round_to_f32(left + right)
  @math.round_to_f32(prev + pair_sum * c)
}

///|
fn step2_contract_edge_update(
  prev : Double,
  left : Double,
  c : Double,
) -> Double {
  let edge_scale = @math.round_to_f32(c + c)
  @math.round_to_f32(prev + left * edge_scale)
}

///|
// Spec basis (T.800-2015 F.3.6):
// 1D inverse 9/7 DWT using lifting steps (reverse of forward transform).
// Steps: unscale → undo δ → undo γ → undo β → undo α → interleave
fn idwt_97_1d(
  low : Array[Double],
  high : Array[Double],
  cas? : Int = 0,
  trace_enabled? : Bool = false,
  trace_label? : String = "",
  trace_comp? : Int = -1,
  trace_level? : Int = -1,
  trace_dir? : String = "",
  trace_vec? : Int = -1,
) -> Array[Double] {
  fn to_f32(v : Double) -> Double {
    @math.round_to_f32(v)
  }
  fn trace_stage(
    enabled : Bool,
    label : String,
    comp : Int,
    level : Int,
    dir : String,
    vec : Int,
    stage : String,
    wavelet : Array[Double],
  ) -> Unit {
    if enabled {
      print_dwt_1d_trace_f32bits(
        "recon-audit:dwt-1d-stage-f32bits", label, comp, level, dir, vec, stage,
        wavelet,
      )
    }
  }
  let sn = low.length()
  let dn = high.length()
  let total = sn + dn
  if total == 0 {
    return []
  }
  let wavelet : Array[Double] = []
  for _ in 0..<total {
    wavelet.push(0.0)
  }
  if cas == 0 {
    for i in 0..<sn {
      let idx = i * 2
      if idx < total {
        wavelet[idx] = low[i]
      }
    }
    for i in 0..<dn {
      let idx = i * 2 + 1
      if idx < total {
        wavelet[idx] = high[i]
      }
    }
  } else {
    for i in 0..<dn {
      let idx = i * 2
      if idx < total {
        wavelet[idx] = high[i]
      }
    }
    for i in 0..<sn {
      let idx = i * 2 + 1
      if idx < total {
        wavelet[idx] = low[i]
      }
    }
  }
  let (a, b, can_decode) = if cas == 0 {
    if dn > 0 || sn > 1 {
      (0, 1, true)
    } else {
      (0, 1, false)
    }
  } else if sn > 0 || dn > 1 {
    (1, 0, true)
  } else {
    (1, 0, false)
  }
  if !can_decode {
    return wavelet
  }
  for i in 0..<sn {
    let idx = i * 2 + a
    if idx >= 0 && idx < total {
      wavelet[idx] = to_f32(wavelet[idx] * idwt97_k)
    }
  }
  for i in 0..<dn {
    let idx = i * 2 + b
    if idx >= 0 && idx < total {
      wavelet[idx] = to_f32(wavelet[idx] * idwt97_two_invk)
    }
  }
  trace_stage(
    trace_enabled, trace_label, trace_comp, trace_level, trace_dir, trace_vec, "scale",
    wavelet,
  )
  fn step2(
    wavelet : Array[Double],
    l_start : Int,
    w_start : Int,
    end : Int,
    m_raw : Int,
    c : Double,
    total : Int,
  ) -> Unit {
    if end <= 0 {
      return
    }
    let imax = if m_raw < 0 { end } else if m_raw < end { m_raw } else { end }
    let mut fl = l_start
    let mut fw = w_start
    for _ in 0..<imax {
      if fw - 1 >= 0 && fw < total && fl >= 0 && fl < total {
        // Keep pair_sum in f32 for contracted lifting step precision
        // but defer the mul+add rounding to the final store.
        wavelet[fw - 1] = step2_contract_update(
          wavelet[fw - 1],
          wavelet[fl],
          wavelet[fw],
          c,
        )
      }
      fl = fw
      fw += 2
    }
    if m_raw >= 0 &&
      m_raw < end &&
      fw - 1 >= 0 &&
      fw - 1 < total &&
      fl >= 0 &&
      fl < total {
      wavelet[fw - 1] = step2_contract_edge_update(
        wavelet[fw - 1],
        wavelet[fl],
        c,
      )
    }
  }
  let m0 = if sn < dn - a { sn } else { dn - a }
  let m1 = if dn < sn - b { dn } else { sn - b }
  step2(wavelet, b, a + 1, sn, m0, -idwt97_delta, total)
  trace_stage(
    trace_enabled, trace_label, trace_comp, trace_level, trace_dir, trace_vec, "delta",
    wavelet,
  )
  step2(wavelet, a, b + 1, dn, m1, -idwt97_gamma, total)
  trace_stage(
    trace_enabled, trace_label, trace_comp, trace_level, trace_dir, trace_vec, "gamma",
    wavelet,
  )
  step2(wavelet, b, a + 1, sn, m0, -idwt97_beta, total)
  trace_stage(
    trace_enabled, trace_label, trace_comp, trace_level, trace_dir, trace_vec, "beta",
    wavelet,
  )
  step2(wavelet, a, b + 1, dn, m1, -idwt97_alpha, total)
  trace_stage(
    trace_enabled, trace_label, trace_comp, trace_level, trace_dir, trace_vec, "alpha",
    wavelet,
  )
  wavelet
}

///|
// Spec basis (T.800-2015 F.3.6):
// 2D inverse 9/7 DWT for single decomposition level on Double coefficients.
fn idwt_97_2d_single_level(
  coeffs : Array[Double],
  width : Int,
  height : Int,
  half_w? : Int = -1,
  half_h? : Int = -1,
  cas_h? : Int = -1,
  cas_v? : Int = -1,
  packet_audit? : Bool = false,
  audit_label? : String = "",
  audit_comp? : Int = -1,
  audit_level? : Int = -1,
) -> Result[Array[Double], String] {
  if width <= 0 || height <= 0 {
    return Err("invalid dimensions for 9/7 idwt")
  }
  if coeffs.length() != width * height {
    return Err("coefficient count mismatch for 9/7 idwt")
  }
  let half_w = if half_w >= 0 { half_w } else { (width + 1) / 2 }
  let half_h = if half_h >= 0 { half_h } else { (height + 1) / 2 }
  let cas_h = if cas_h >= 0 {
    cas_h
  } else if 2 * half_w < width {
    1
  } else {
    0
  }
  let cas_v = if cas_v >= 0 {
    cas_v
  } else if 2 * half_h < height {
    1
  } else {
    0
  }
  // Step 1: Horizontal inverse DWT on each row
  let horiz : Array[Double] = []
  for _ in 0..<(width * height) {
    horiz.push(0.0)
  }
  for y in 0..<height {
    let low : Array[Double] = []
    let high : Array[Double] = []
    for x in 0..<half_w {
      low.push(coeffs[y * width + x])
    }
    for x in half_w..<width {
      high.push(coeffs[y * width + x])
    }
    let trace_row = packet_audit && audit_level >= 0 && y < 8
    let row = idwt_97_1d(
      low,
      high,
      cas=cas_h,
      trace_enabled=trace_row,
      trace_label=audit_label,
      trace_comp=audit_comp,
      trace_level=audit_level,
      trace_dir="h",
      trace_vec=y,
    )
    for x in 0..<row.length() {
      if x < width {
        horiz[y * width + x] = row[x]
      }
    }
  }
  if packet_audit {
    print_dwt_level_trace(
      "recon-audit:dwt-level-horiz-float", audit_label, audit_comp, audit_level,
      width, height, horiz,
    )
    print_dwt_level_trace_f32bits(
      "recon-audit:dwt-level-horiz-f32bits", audit_label, audit_comp, audit_level,
      width, height, horiz,
    )
  }
  // Step 2: Vertical inverse DWT on each column
  let result : Array[Double] = []
  for _ in 0..<(width * height) {
    result.push(0.0)
  }
  for x in 0..<width {
    let low : Array[Double] = []
    let high : Array[Double] = []
    for y in 0..<half_h {
      low.push(horiz[y * width + x])
    }
    for y in half_h..<height {
      high.push(horiz[y * width + x])
    }
    let trace_col = packet_audit && audit_level >= 0 && x < 16
    let col = idwt_97_1d(
      low,
      high,
      cas=cas_v,
      trace_enabled=trace_col,
      trace_label=audit_label,
      trace_comp=audit_comp,
      trace_level=audit_level,
      trace_dir="v",
      trace_vec=x,
    )
    for y in 0..<col.length() {
      if y < height {
        result[y * width + x] = col[y]
      }
    }
  }
  if packet_audit {
    print_dwt_level_trace(
      "recon-audit:dwt-level-post-float", audit_label, audit_comp, audit_level, width,
      height, result,
    )
    print_dwt_level_trace_f32bits(
      "recon-audit:dwt-level-post-f32bits", audit_label, audit_comp, audit_level,
      width, height, result,
    )
  }
  Ok(result)
}

///|
// Spec basis (T.800-2015 F.3.6):
// Apply inverse 9/7 DWT for specified number of decomposition levels.
// Input/output are Double arrays (dequantized coefficients).
fn apply_inverse_dwt_97(
  coeffs : Array[Double],
  width : Int,
  height : Int,
  decomposition_levels : Int,
  tcx0? : Int = 0,
  tcy0? : Int = 0,
  packet_audit? : Bool = false,
  audit_label? : String = "",
  audit_comp? : Int = -1,
) -> Result[Array[Double], String] {
  if decomposition_levels <= 0 {
    return Ok(coeffs)
  }
  if width <= 0 || height <= 0 {
    return Err("invalid dimensions for 9/7 idwt")
  }
  if coeffs.length() != width * height {
    return Err("coefficient count mismatch for 9/7 idwt")
  }
  // T.800-2015 B.5: Pre-compute resolution dimensions using absolute coordinates
  let res_dims : Array[(Int, Int)] = []
  for r in 0..<=decomposition_levels {
    let level = decomposition_levels - r
    let (rw, rh) = @subband.subband_ll_dims(width, height, level, tcx0~, tcy0~)
    res_dims.push((rw, rh))
  }
  // T.800-2015 F.3.5: Pre-compute absolute origins for cas determination
  let origins = @subband.resolution_origins(tcx0, tcy0, decomposition_levels)
  if decomposition_levels == 1 {
    let (ll_w, ll_h) = res_dims[0]
    let (ox, oy) = origins[1]
    return idwt_97_2d_single_level(
      coeffs,
      width,
      height,
      half_w=ll_w,
      half_h=ll_h,
      cas_h=ox % 2,
      cas_v=oy % 2,
      packet_audit~,
      audit_label~,
      audit_comp~,
      audit_level=0,
    )
  }
  let current : Array[Double] = []
  for c in coeffs {
    current.push(c)
  }
  for level in 0..<decomposition_levels {
    let (ll_w, ll_h) = res_dims[level]
    let (next_w, next_h) = res_dims[level + 1]
    // T.800-2015 B.5: skip only when OUTPUT resolution has zero extent
    // When LL has zero extent but output is non-zero, the 1D_SR procedure
    // handles this per F.3.6 (single-sample scaling for odd origins)
    if next_w <= 0 || next_h <= 0 {
      continue
    }
    let (ox, oy) = origins[level + 1]
    let subband : Array[Double] = []
    for y in 0..<next_h {
      for x in 0..<next_w {
        if y < height && x < width && y * width + x < current.length() {
          subband.push(current[y * width + x])
        } else {
          subband.push(0.0)
        }
      }
    }
    let result_v = idwt_97_2d_single_level(
      subband,
      next_w,
      next_h,
      half_w=ll_w,
      half_h=ll_h,
      cas_h=ox % 2,
      cas_v=oy % 2,
      packet_audit~,
      audit_label~,
      audit_comp~,
      audit_level=level,
    )
    guard result_v is Ok(result) else {
      return Err("9/7 idwt level \{level} failed")
    }
    for y in 0..<next_h {
      for x in 0..<next_w {
        if y < height && x < width {
          current[y * width + x] = result[y * next_w + x]
        }
      }
    }
  }
  Ok(current)
}

///|
test "idwt_97_1d_basic" {
  let low : Array[Double] = [100.0]
  let high : Array[Double] = [0.0]
  let result = idwt_97_1d(low, high)
  inspect(result.length(), content="2")
  // Both values should be approximately equal (DC only, gain ≈ 0.66)
  let diff = (result[0] - result[1]).abs()
  assert_true(diff < 0.01)
}

///|
test "idwt_97_step2_contract_rounding_precision" {
  let c = -idwt97_delta
  let out0 = step2_contract_update(
    @math.round_to_f32(-541.276611328125),
    @math.round_to_f32(-1108.089111328125),
    @math.round_to_f32(130.36341857910156),
    c,
  )
  assert_eq(@math.f32bits_hex(out0), "0xc2d74c0e")

  let out1 = step2_contract_update(
    @math.round_to_f32(-98.41392517089844),
    0.0,
    @math.round_to_f32(195.54513549804688),
    c,
  )
  assert_eq(@math.f32bits_hex(out1), "0xc33923b9")
}

///|
test "idwt_97_2d_zero_detail" {
  // 4x4 with constant LL, all detail=0 → output should be uniform
  let coeffs : Array[Double] = Array::make(16, 0.0)
  // Set all LL coefficients (top-left 2x2) to 1.0
  coeffs[0 * 4 + 0] = 1.0
  coeffs[0 * 4 + 1] = 1.0
  coeffs[1 * 4 + 0] = 1.0
  coeffs[1 * 4 + 1] = 1.0
  let result = idwt_97_2d_single_level(coeffs, 4, 4)
  guard result is Ok(r) else { return }
  // All output pixels should be the same value (uniform DC input → uniform output)
  let ref_val = r[0]
  for i in 1..<16 {
    let err = (r[i] - ref_val).abs()
    assert_true(err < 0.01)
  }
}

///|
// Spec basis (T.800-2015 F.3 + E.1):
// Unified inverse DWT dispatch: selects 5/3 or 9/7 based on COD transformation.
// T.800-2015 A.6.1: transformation=0 → 9/7 irreversible, transformation=1 → 5/3 reversible.
// For qstyle=0: integer 5/3 IDWT (truly reversible, no dequantization).
// For qstyle≠0 + transformation=1: dequantize → 5/3 float IDWT → round (lossy 5/3).
// For qstyle≠0 + transformation=0: dequantize → 9/7 IDWT → round (lossy 9/7).
pub fn apply_inverse_dwt(
  coeffs : Array[Int],
  width : Int,
  height : Int,
  decomposition_levels : Int,
  qcd : @core.QcdMetadata,
  precision_bits : Int,
  transformation? : Int = -1,
  tcx0? : Int = 0,
  tcy0? : Int = 0,
) -> Result[Array[Int], String] {
  // T.800-2015 E.1: qstyle=0 means no quantization (truly reversible encoding).
  // For qstyle≠0, dequantization is required regardless of DWT filter type.
  let needs_dequantization = qcd.quantization_style != 0
  // Determine DWT filter type: 5/3 (reversible) or 9/7 (irreversible)
  let use_53_filter = if transformation >= 0 {
    transformation == 1
  } else {
    qcd.quantization_style == 0
  }
  // Fast path: qstyle=0 with 5/3 filter → pure integer IDWT
  if not(needs_dequantization) && use_53_filter {
    return apply_inverse_dwt_53(
      coeffs,
      width,
      height,
      decomposition_levels,
      tcx0~,
      tcy0~,
    )
  }
  // All other paths require dequantization
  if decomposition_levels <= 0 {
    return Ok(coeffs)
  }
  if width <= 0 || height <= 0 {
    return Err("invalid dimensions")
  }
  if coeffs.length() != width * height {
    return Err("coefficient count mismatch")
  }
  let dequantized = @quant.dequantize_coefficients(
    coeffs,
    width,
    height,
    decomposition_levels,
    qcd,
    precision_bits,
    tcx0~,
    tcy0~,
    use_53_filter~,
  )
  // Select IDWT based on filter type
  let dwt_v = if use_53_filter {
    // Lossy encoding with 5/3 filter (qstyle≠0 + transformation=1)
    apply_inverse_dwt_53_float(
      dequantized,
      width,
      height,
      decomposition_levels,
      tcx0~,
      tcy0~,
    )
  } else {
    // Standard 9/7 irreversible path
    apply_inverse_dwt_97(
      dequantized,
      width,
      height,
      decomposition_levels,
      tcx0~,
      tcy0~,
    )
  }
  let filter_name = if use_53_filter { "5/3 float" } else { "9/7" }
  guard dwt_v is Ok(float_result) else {
    return Err("\{filter_name} IDWT failed")
  }
  // Round to nearest integer with ties-to-even (matches lrintf default mode).
  let int_result : Array[Int] = []
  for v in float_result {
    int_result.push(@math.round_ties_even_f32(v))
  }
  Ok(int_result)
}

///|
// Spec basis (T.800-2015 F.3 + E.1):
// Float-output variant of inverse DWT used for irreversible pipelines where
// rounding is deferred to later stages (e.g. inverse ICT + DC level shift).
pub fn apply_inverse_dwt_float(
  coeffs : Array[Int],
  width : Int,
  height : Int,
  decomposition_levels : Int,
  qcd : @core.QcdMetadata,
  precision_bits : Int,
  transformation? : Int = -1,
  tcx0? : Int = 0,
  tcy0? : Int = 0,
  packet_audit? : Bool = false,
  audit_label? : String = "",
  audit_comp? : Int = -1,
) -> Result[Array[Double], String] {
  // T.800-2015 E.1: qstyle=0 means no dequantization (reversible coding path).
  let needs_dequantization = qcd.quantization_style != 0
  let use_53_filter = if transformation >= 0 {
    transformation == 1
  } else {
    qcd.quantization_style == 0
  }
  if decomposition_levels <= 0 {
    if needs_dequantization {
      return Ok(
        @quant.dequantize_coefficients(
          coeffs,
          width,
          height,
          decomposition_levels,
          qcd,
          precision_bits,
          tcx0~,
          tcy0~,
          use_53_filter~,
        ),
      )
    }
    let out : Array[Double] = []
    for v in coeffs {
      out.push(v.to_double())
    }
    return Ok(out)
  }
  if width <= 0 || height <= 0 {
    return Err("invalid dimensions")
  }
  if coeffs.length() != width * height {
    return Err("coefficient count mismatch")
  }
  if not(needs_dequantization) && use_53_filter {
    let int_v = apply_inverse_dwt_53(
      coeffs,
      width,
      height,
      decomposition_levels,
      tcx0~,
      tcy0~,
    )
    guard int_v is Ok(int_result) else { return Err("5/3 IDWT failed") }
    let out : Array[Double] = []
    for v in int_result {
      out.push(v.to_double())
    }
    return Ok(out)
  }
  let dequantized = if needs_dequantization {
    @quant.dequantize_coefficients(
      coeffs,
      width,
      height,
      decomposition_levels,
      qcd,
      precision_bits,
      tcx0~,
      tcy0~,
      use_53_filter~,
    )
  } else {
    let out : Array[Double] = []
    for v in coeffs {
      out.push(v.to_double())
    }
    out
  }
  if use_53_filter {
    return apply_inverse_dwt_53_float(
      dequantized,
      width,
      height,
      decomposition_levels,
      tcx0~,
      tcy0~,
    )
  }
  apply_inverse_dwt_97(
    dequantized,
    width,
    height,
    decomposition_levels,
    tcx0~,
    tcy0~,
    packet_audit~,
    audit_label~,
    audit_comp~,
  )
}

///|
// Spec basis (T.800-2015 F.3, B.5):
// Apply inverse DWT for specified number of decomposition levels.
// tcx0/tcy0: absolute tile-component coordinates for correct subband splits.
pub fn apply_inverse_dwt_53(
  coeffs : Array[Int],
  width : Int,
  height : Int,
  decomposition_levels : Int,
  tcx0? : Int = 0,
  tcy0? : Int = 0,
) -> Result[Array[Int], String] {
  if decomposition_levels <= 0 {
    return Ok(coeffs)
  }
  if width <= 0 || height <= 0 {
    return Err("invalid dimensions")
  }
  if coeffs.length() != width * height {
    return Err("coefficient count mismatch")
  }
  // T.800-2015 B.5: Pre-compute resolution dimensions using absolute coordinates
  let res_dims : Array[(Int, Int)] = []
  for r in 0..<=decomposition_levels {
    let level = decomposition_levels - r
    let (rw, rh) = @subband.subband_ll_dims(width, height, level, tcx0~, tcy0~)
    res_dims.push((rw, rh))
  }
  // T.800-2015 F.3.5: Pre-compute absolute origins for cas determination
  let origins = @subband.resolution_origins(tcx0, tcy0, decomposition_levels)
  // For single level, apply directly with correct split
  if decomposition_levels == 1 {
    let (ll_w, ll_h) = res_dims[0]
    let (ox, oy) = origins[1]
    return idwt_53_2d_single_level(
      coeffs,
      width,
      height,
      half_w=ll_w,
      half_h=ll_h,
      cas_h=ox % 2,
      cas_v=oy % 2,
    )
  }
  // For multiple levels, apply recursively from lowest resolution
  let current : Array[Int] = []
  for c in coeffs {
    current.push(c)
  }
  for level in 0..<decomposition_levels {
    let (ll_w, ll_h) = res_dims[level]
    let (next_w, next_h) = res_dims[level + 1]
    // T.800-2015 B.5: skip only when OUTPUT resolution has zero extent
    // When LL has zero extent but output is non-zero, the 1D_SR procedure
    // handles this per F.3.6 (single-sample scaling for odd origins)
    if next_w <= 0 || next_h <= 0 {
      continue
    }
    // T.800-2015 F.3.5: cas from absolute coordinate parity at this resolution
    let (ox, oy) = origins[level + 1]
    // Extract subband for this level
    let subband : Array[Int] = []
    for y in 0..<next_h {
      for x in 0..<next_w {
        if y < height && x < width && y * width + x < current.length() {
          subband.push(current[y * width + x])
        } else {
          subband.push(0)
        }
      }
    }
    // Apply single-level inverse DWT with correct LL/detail split and cas
    let result_v = idwt_53_2d_single_level(
      subband,
      next_w,
      next_h,
      half_w=ll_w,
      half_h=ll_h,
      cas_h=ox % 2,
      cas_v=oy % 2,
    )
    guard result_v is Ok(result) else {
      return Err("idwt level \{level} failed (ll_w=\{ll_w}, ll_h=\{ll_h})")
    }
    // Copy result back
    for y in 0..<next_h {
      for x in 0..<next_w {
        if y < height && x < width {
          current[y * width + x] = result[y * next_w + x]
        }
      }
    }
  }
  Ok(current)
}

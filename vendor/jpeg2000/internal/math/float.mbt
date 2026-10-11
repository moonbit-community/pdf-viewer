///|
// Floating-point math utilities

///|
/// Compute 2^n as Double for any integer n (positive or negative).
pub fn pow2_double(n : Int) -> Double {
  if n >= 0 {
    let mut result = 1.0
    for _ in 0..<n {
      result *= 2.0
    }
    result
  } else {
    let mut result = 1.0
    for _ in 0..<-n {
      result *= 0.5
    }
    result
  }
}

///|
fn round_ties_even_int(v : Double) -> Int {
  let base_f = v.floor()
  let frac = v - base_f
  let base_i = base_f.to_int()
  let eps = 0.000000000001
  if frac < 0.5 - eps {
    return base_i
  }
  if frac > 0.5 + eps {
    return base_i + 1
  }
  if base_i % 2 == 0 {
    return base_i
  }
  base_i + 1
}

///|
// Mirror lrintf() behavior by rounding on float32 domain
// with ties-to-even. Snaps to float32 first, then applies exact ties-to-even.
pub fn round_ties_even_f32(v : Double) -> Int {
  let vf = round_to_f32(v)
  let base_f = vf.floor()
  let frac = vf - base_f
  let base_i = base_f.to_int()
  if frac < 0.5 {
    return base_i
  }
  if frac > 0.5 {
    return base_i + 1
  }
  if base_i % 2 == 0 {
    return base_i
  }
  base_i + 1
}

///|
// Convert a Double to its IEEE 32-bit floating-point hex representation.
pub fn f32bits_hex(v : Double) -> String {
  let bits = Float::from_double(v).reinterpret_as_uint()
  "0x" +
  @bytes.bytes_to_hex([
    (bits >> 24).reinterpret_as_int() & 0xFF,
    (bits >> 16).reinterpret_as_int() & 0xFF,
    (bits >> 8).reinterpret_as_int() & 0xFF,
    bits.reinterpret_as_int() & 0xFF,
  ])
}

///|
// Round a Double to nearest IEEE754 float32 value (ties-to-even).
// Used for float32 arithmetic precision in irreversible (9/7) paths.
pub fn round_to_f32(v : Double) -> Double {
  if v == 0.0 {
    return 0.0
  }
  let sign = if v < 0.0 { -1.0 } else { 1.0 }
  let abs_v = if v < 0.0 { -v } else { v }

  // Handle extremely small values as zero.
  if abs_v < pow2_double(-149) {
    return 0.0
  }

  // Find binary exponent: abs_v in [2^exp, 2^(exp+1)).
  let mut exp = 0
  let mut t = abs_v
  if t >= 1.0 {
    while t >= 2.0 {
      t *= 0.5
      exp += 1
    }
  } else {
    while t < 1.0 {
      t *= 2.0
      exp -= 1
    }
  }

  // Clamp overflow to float32 max finite.
  if exp > 127 {
    return sign * 3.4028234663852886e38
  }

  // Normal: 24-bit significand; subnormal: fixed ulp 2^-149.
  let step = if exp >= -126 { pow2_double(exp - 23) } else { pow2_double(-149) }
  let q = round_ties_even_int(abs_v / step).to_double() * step
  sign * q
}

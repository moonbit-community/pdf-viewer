///|
// Spec grouping:
// - T.800-2015 F.3.7: 1D_EXTR procedure
// - Equation F-4: PSEO (Periodic Symmetric Extension Operation)

///|
// T.800-2015 F.3.7 Eq. F-4:
// PSEO(i, i0, i1) = i0 + min(mod(i - i0, 2*(i1 - i0) - 1),
//                           2*(i1 - i0) - 1 - mod(i - i0, 2*(i1 - i0) - 1))
//
// This computes the reflected index for periodic symmetric extension.
// For a signal with indices [i0, i1), it reflects at both boundaries.
pub fn pseo(i : Int, i0 : Int, i1 : Int) -> Int {
  let n = i1 - i0 // signal length
  if n <= 0 {
    return i0
  }
  if n == 1 {
    return i0
  }
  // T.800-2015 Eq. F-4:
  // period = 2*n - 1 (one complete reflection cycle)
  // For positions [0, n-1]: direct mapping
  // For positions [n, 2n-2]: reflection at n-1
  let period = 2 * n - 1
  // mod with proper handling for negative values
  let offset = i - i0
  let mod_val = if offset >= 0 {
    offset % period
  } else {
    let abs_mod = -offset % period
    if abs_mod == 0 {
      0
    } else {
      period - abs_mod
    }
  }
  // T.800-2015 F.3.7 Eq. F-4: Use min(mod_val, period - mod_val)
  // This creates whole-sample symmetric extension
  let alt = period - mod_val
  let reflected = if mod_val < alt { mod_val } else { alt }
  i0 + reflected
}

///|
// T.800-2015 F.3.7 Table F.2: Extension to the left for 5-3 filter
// i0 even: ileft = 1
// i0 odd: ileft = 2
pub fn ileft_53(i0 : Int) -> Int {
  if i0 % 2 == 0 {
    1
  } else {
    2
  }
}

///|
// T.800-2015 F.3.7 Table F.3: Extension to the right for 5-3 filter
// i1 odd: iright = 1
// i1 even: iright = 2
pub fn iright_53(i1 : Int) -> Int {
  if i1 % 2 == 1 {
    1
  } else {
    2
  }
}

///|
// T.800-2015 F.3.7: Get extended signal value using PSEO
// For index i outside [i0, i1), use PSEO to compute the reflected index
pub fn extend_signal(signal : Array[Int], i : Int, i0 : Int, i1 : Int) -> Int {
  if i >= i0 && i < i1 {
    signal[i - i0]
  } else {
    let reflected_idx = pseo(i, i0, i1)
    signal[reflected_idx - i0]
  }
}

///|
// T.800-2015 F.3.7: Get extended signal value (Double version)
pub fn extend_signal_double(
  signal : Array[Double],
  i : Int,
  i0 : Int,
  i1 : Int,
) -> Double {
  if i >= i0 && i < i1 {
    signal[i - i0]
  } else {
    let reflected_idx = pseo(i, i0, i1)
    signal[reflected_idx - i0]
  }
}

///|
// T.800-2015 F.3.7 Table F.2: Extension to the left for 9-7 filter
// i0 even: ileft = 3
// i0 odd: ileft = 4
pub fn ileft_97(i0 : Int) -> Int {
  if i0 % 2 == 0 {
    3
  } else {
    4
  }
}

///|
// T.800-2015 F.3.7 Table F.3: Extension to the right for 9-7 filter
// i1 odd: iright = 3
// i1 even: iright = 4
pub fn iright_97(i1 : Int) -> Int {
  if i1 % 2 == 1 {
    3
  } else {
    4
  }
}

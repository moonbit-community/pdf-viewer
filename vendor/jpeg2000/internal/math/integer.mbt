///|
/// Ceiling division for positive integers.
/// Returns ceil(n / d) for positive n and d.
/// Returns 0 if n <= 0 or d <= 0.
pub fn ceil_div(n : Int, d : Int) -> Int {
  if n <= 0 {
    return 0
  }
  if d <= 0 {
    return 0
  }
  (n + d - 1) / d
}

///|
/// Ceiling division with error checking.
/// Returns Err if d <= 0, returns Ok(0) if n <= 0.
pub fn ceil_div_checked(n : Int, d : Int) -> Result[Int, String] {
  if d <= 0 {
    return Err("invalid divisor")
  }
  if n <= 0 {
    return Ok(0)
  }
  Ok((n + d - 1) / d)
}

///|
/// Floor of log2 for positive integers.
/// Returns the largest k such that 2^k <= n.
/// Returns 0 for n <= 1.
pub fn floor_log2(n : Int) -> Int {
  if n <= 1 {
    return 0
  }
  let mut k = 0
  let mut v = n
  while v > 1 {
    v = v >> 1
    k += 1
  }
  k
}

///|
/// 2D grid index calculation.
/// Returns y * width + x for row-major layout.
pub fn grid_index_2d(width : Int, x : Int, y : Int) -> Int {
  y * width + x
}

///|
/// Sum all integers in an array.
pub fn sum_ints(values : Array[Int]) -> Int {
  let mut total = 0
  for v in values {
    total += v
  }
  total
}

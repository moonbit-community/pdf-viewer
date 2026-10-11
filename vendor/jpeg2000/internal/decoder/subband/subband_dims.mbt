///|
// Spec grouping:
// - T.800-2015 Annex B.5: Resolution levels and Subbands
// - Equations B-15 to B-18: Subband dimension calculations
// Common code used by both quantization (Annex E) and DWT (Annex F)

///|
// T.800-2015 B.5 Eq. B-15 to B-18:
// Compute LL subband dimensions at a given DWT level.
// level=0 returns original dimensions; level=decomposition_levels returns
// smallest LL subband.
// tcx0, tcy0 = absolute tile-component origin for proper boundary handling.
pub fn subband_ll_dims(
  img_w : Int,
  img_h : Int,
  level : Int,
  tcx0? : Int = 0,
  tcy0? : Int = 0,
) -> (Int, Int) {
  let mut w = img_w
  let mut h = img_h
  let mut cx = tcx0
  let mut cy = tcy0
  for _ in 0..<level {
    // T.800-2015 B.5: LL width = ceil(tcx1/2) - ceil(tcx0/2)
    // where tcx1 = cx + w
    let new_w = (cx + w + 1) / 2 - (cx + 1) / 2
    let new_h = (cy + h + 1) / 2 - (cy + 1) / 2
    cx = (cx + 1) / 2
    cy = (cy + 1) / 2
    w = new_w
    h = new_h
  }
  (w, h)
}

///|
// T.800-2015 B.5 Eq. B-15 to B-18:
// Compute detail subband dimensions (HL, LH, HH) at a given DWT level.
// parent_w, parent_h = dimensions of the resolution at this level.
// tcx0, tcy0 = absolute coordinates of this resolution's origin.
pub fn subband_detail_dims(
  parent_w : Int,
  parent_h : Int,
  tcx0? : Int = 0,
  tcy0? : Int = 0,
) -> (Int, Int, Int, Int, Int, Int) {
  // T.800-2015 B.5: LL width = ceil(tcx1/2) - ceil(tcx0/2)
  let ll_w = (tcx0 + parent_w + 1) / 2 - (tcx0 + 1) / 2
  let ll_h = (tcy0 + parent_h + 1) / 2 - (tcy0 + 1) / 2
  let hl_w = parent_w - ll_w
  let lh_h = parent_h - ll_h
  // HL: hl_w × ll_h, LH: ll_w × lh_h, HH: hl_w × lh_h
  (hl_w, ll_h, ll_w, lh_h, hl_w, lh_h)
}

///|
// T.800-2015 B.5:
// Compute absolute tile-component origins at each resolution level.
// Returns Array[(cx, cy)] indexed by resolution (matching res_dims):
//   result[0] = deepest LL origin (after decomposition_levels halvings)
//   result[decomposition_levels] = full resolution origin (tcx0, tcy0)
pub fn resolution_origins(
  tcx0 : Int,
  tcy0 : Int,
  decomposition_levels : Int,
) -> Array[(Int, Int)] {
  let from_full : Array[(Int, Int)] = []
  let mut cx = tcx0
  let mut cy = tcy0
  from_full.push((cx, cy))
  for _ in 0..<decomposition_levels {
    cx = (cx + 1) / 2
    cy = (cy + 1) / 2
    from_full.push((cx, cy))
  }
  let result : Array[(Int, Int)] = []
  for i in 0..<from_full.length() {
    result.push(from_full[from_full.length() - 1 - i])
  }
  result
}

///|
// T.800-2015 B.5 Eq. B-15:
// Compute absolute tile-component resolution bounds (trx0, try0, trx1, try1)
// for each resolution level.
// Returns Array[(trx0, try0, trx1, try1)] indexed by resolution:
//   result[0] = deepest LL bounds
//   result[decomposition_levels] = full resolution bounds
pub fn resolution_bounds(
  img_w : Int,
  img_h : Int,
  tcx0 : Int,
  tcy0 : Int,
  decomposition_levels : Int,
) -> Array[(Int, Int, Int, Int)] {
  let from_full : Array[(Int, Int, Int, Int)] = []
  let mut x0 = tcx0
  let mut y0 = tcy0
  let mut x1 = tcx0 + img_w
  let mut y1 = tcy0 + img_h
  from_full.push((x0, y0, x1, y1))
  for _ in 0..<decomposition_levels {
    // T.800-2015 B.5: LL bounds at next level
    x0 = (x0 + 1) / 2
    y0 = (y0 + 1) / 2
    x1 = (x1 + 1) / 2
    y1 = (y1 + 1) / 2
    from_full.push((x0, y0, x1, y1))
  }
  let result : Array[(Int, Int, Int, Int)] = []
  for i in 0..<from_full.length() {
    result.push(from_full[from_full.length() - 1 - i])
  }
  result
}

///|
// T.800-2015 B.5 Eq. B-15 and Table B.1:
// Compute absolute subband bounds (tbx0, tby0, tbx1, tby1) for a given subband.
// tcx0, tcy0, tcx1, tcy1 = absolute tile-component coordinates
// nb = decomposition level (1 = highest detail, NL = lowest detail)
// subband_type: 0=LL, 1=HL, 2=LH, 3=HH (using xob/yob from Table B.1)
// Returns (tbx0, tby0, tbx1, tby1) in absolute coordinates.
pub fn subband_bounds(
  tcx0 : Int,
  tcy0 : Int,
  tcx1 : Int,
  tcy1 : Int,
  nb : Int,
  subband_type : Int,
) -> (Int, Int, Int, Int) {
  // T.800-2015 Table B.1: xob/yob offsets
  let (xob, yob) = match subband_type {
    0 => (0, 0) // LL
    1 => (1, 0) // HL
    2 => (0, 1) // LH
    _ => (1, 1) // HH
  }
  // T.800-2015 B.5 Eq. B-15:
  // tbx0 = ceil((tcx0 - 2^(nb-1) * xob) / 2^nb)
  let pow2_nb = 1 << nb
  let pow2_nb_1 = if nb >= 1 { 1 << (nb - 1) } else { 0 }
  let offset_x = pow2_nb_1 * xob
  let offset_y = pow2_nb_1 * yob
  fn ceil_div(num : Int, den : Int) -> Int {
    if num <= 0 {
      num / den
    } else {
      (num + den - 1) / den
    }
  }
  let tbx0 = ceil_div(tcx0 - offset_x, pow2_nb)
  let tby0 = ceil_div(tcy0 - offset_y, pow2_nb)
  let tbx1 = ceil_div(tcx1 - offset_x, pow2_nb)
  let tby1 = ceil_div(tcy1 - offset_y, pow2_nb)
  (tbx0, tby0, tbx1, tby1)
}

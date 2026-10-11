///|
// Spec grouping:
// - T.800-2015 B.6 (precinct partitioning)
// - T.800-2015 B.7 (code-block geometry within precincts)

///|
// T.800-2015 B.6: Extract precinct size exponents from precinct_size_bytes.
// Each byte encodes (PPy << 4) | PPx for one resolution level.
// Returns (ppx_exp, ppy_exp) exponents (precinct size = 2^pp).
// Default for resolution 0 when no precincts: whole tile (effectively 15, 15).
pub fn get_precinct_exponents(
  precinct_size_bytes : Array[Int],
  res : Int,
) -> (Int, Int) {
  if precinct_size_bytes.length() == 0 {
    // No precincts defined - single precinct covering entire resolution
    (15, 15)
  } else if res < precinct_size_bytes.length() {
    let byte = precinct_size_bytes[res]
    let ppx = byte & 0x0F
    let ppy = (byte >> 4) & 0x0F
    (ppx, ppy)
  } else {
    // Use last defined precinct size for higher resolutions
    let byte = precinct_size_bytes[precinct_size_bytes.length() - 1]
    let ppx = byte & 0x0F
    let ppy = (byte >> 4) & 0x0F
    (ppx, ppy)
  }
}

///|
// Resolve precinct exponents for a component, with COD precinct bytes as fallback.
pub fn get_component_precinct_exponents(
  default_precinct_size_bytes : Array[Int],
  comp_precinct_size_bytes : Array[Array[Int]],
  component : Int,
  res : Int,
) -> (Int, Int) {
  if component < comp_precinct_size_bytes.length() {
    return get_precinct_exponents(comp_precinct_size_bytes[component], res)
  }
  get_precinct_exponents(default_precinct_size_bytes, res)
}

///|
// T.800-2015 B.6:
// cblkwidthexpn/cblkheightexpn are clamped by precinct group exponents.
// res=0  -> cbg exp = PPx/PPy
// res>0  -> cbg exp = PPx-1/PPy-1
pub fn effective_cb_dim_for_res(cb_dim : Int, pp_exp : Int, res : Int) -> Int {
  let mut cb_exp = 0
  let mut v = cb_dim
  while v > 1 {
    v = v >> 1
    cb_exp += 1
  }
  let cbg_exp = if res == 0 {
    pp_exp
  } else if pp_exp > 0 {
    pp_exp - 1
  } else {
    0
  }
  let eff_exp = if cb_exp < cbg_exp { cb_exp } else { cbg_exp }
  1 << eff_exp
}

///|
// T.800-2015 B.6 Equation B-16/B-17: Compute number of precincts for a resolution.
// numPrecinctsWide = ceil(trx1 / ppx) - floor(trx0 / ppx)
// numPrecinctsTall = ceil(try1 / ppy) - floor(try0 / ppy)
// where (trx0, try0) and (trx1, try1) are tile-component resolution bounds.
// ppx = 2^PPx, ppy = 2^PPy
pub fn compute_num_precincts_with_origin(
  trx0 : Int,
  try0 : Int,
  trx1 : Int,
  try1 : Int,
  ppx_exp : Int,
  ppy_exp : Int,
) -> (Int, Int) {
  if trx1 <= trx0 || try1 <= try0 {
    return (0, 0)
  }
  let ppx = 1 << ppx_exp
  let ppy = 1 << ppy_exp
  // T.800-2015 B.6 Eq. B-16: ceil(trx1/ppx) - floor(trx0/ppx)
  let npx = (trx1 + ppx - 1) / ppx - trx0 / ppx
  let npy = (try1 + ppy - 1) / ppy - try0 / ppy
  (npx, npy)
}

///|
// Backward-compatible wrapper assuming origin at (0,0).
pub fn compute_num_precincts(
  res_width : Int,
  res_height : Int,
  ppx_exp : Int,
  ppy_exp : Int,
) -> (Int, Int) {
  compute_num_precincts_with_origin(
    0, 0, res_width, res_height, ppx_exp, ppy_exp,
  )
}

///|
// T.800-2015 B.7: Compute code-block range within a subband for a given precinct.
// Uses absolute tile-component-subband coordinates (tbx0, tby0, tbx1, tby1).
// Returns (ncbx, ncby, cb_x_start, cb_y_start, pixel_width, pixel_height)
// where pixel_width/height are the actual pixel dimensions of CBs in this precinct.
// cb_x_start/cb_y_start are relative to the subband origin (0-indexed).
pub fn compute_precinct_codeblock_range_abs(
  trx0 : Int,
  try0 : Int,
  tbx0 : Int,
  tby0 : Int,
  tbx1 : Int,
  tby1 : Int,
  cb_width : Int,
  cb_height : Int,
  px : Int,
  py : Int,
  ppx_exp : Int,
  ppy_exp : Int,
  res : Int,
) -> (Int, Int, Int, Int, Int, Int) {
  let sb_width = tbx1 - tbx0
  let sb_height = tby1 - tby0
  if sb_width <= 0 || sb_height <= 0 {
    return (0, 0, 0, 0, 0, 0)
  }
  let (x0, y0, x1, y1) = compute_precinct_bounds_abs(
    trx0, try0, tbx0, tby0, tbx1, tby1, px, py, ppx_exp, ppy_exp, res,
  )
  if x1 <= x0 || y1 <= y0 {
    return (0, 0, 0, 0, 0, 0)
  }
  // T.800-2015 B.7:
  // code-block partition is aligned on the subband absolute coordinate system,
  // not on the clipped subband-relative origin.
  let tlcblkxstart = x0 / cb_width * cb_width
  let tlcblkystart = y0 / cb_height * cb_height
  let brcblkxend = (x1 + cb_width - 1) / cb_width * cb_width
  let brcblkyend = (y1 + cb_height - 1) / cb_height * cb_height
  let cb_x_start = tlcblkxstart / cb_width - tbx0 / cb_width
  let cb_y_start = tlcblkystart / cb_height - tby0 / cb_height
  let cb_x_end = brcblkxend / cb_width - tbx0 / cb_width
  let cb_y_end = brcblkyend / cb_height - tby0 / cb_height
  let ncbx = cb_x_end - cb_x_start
  let ncby = cb_y_end - cb_y_start
  // Return actual pixel dimensions within this precinct
  let pixel_width = x1 - x0
  let pixel_height = y1 - y0
  (ncbx, ncby, cb_x_start, cb_y_start, pixel_width, pixel_height)
}

///|
// T.800-2015 B.7: Compute absolute precinct bounds in one subband.
// Returns clamped absolute coordinates (x0, y0, x1, y1) in the subband grid.
pub fn compute_precinct_bounds_abs(
  trx0 : Int,
  try0 : Int,
  tbx0 : Int,
  tby0 : Int,
  tbx1 : Int,
  tby1 : Int,
  px : Int,
  py : Int,
  ppx_exp : Int,
  ppy_exp : Int,
  res : Int,
) -> (Int, Int, Int, Int) {
  fn floor_div(num : Int, den : Int) -> Int {
    if den <= 0 {
      return 0
    }
    if num >= 0 {
      return num / den
    }
    -((-num + den - 1) / den)
  }
  fn ceil_div(num : Int, den : Int) -> Int {
    if den <= 0 {
      return 0
    }
    if num >= 0 {
      return (num + den - 1) / den
    }
    -(-num / den)
  }
  let sb_width = tbx1 - tbx0
  let sb_height = tby1 - tby0
  if sb_width <= 0 || sb_height <= 0 {
    return (tbx0, tby0, tbx0, tby0)
  }
  // T.800-2015 B.6/B.7: precinct anchoring:
  // precinct grid for subbands is derived from resolution-level tl_prc start,
  // not from each subband origin. This avoids false-positive subband coverage
  // at tile borders.
  let ppx = 1 << ppx_exp
  let ppy = 1 << ppy_exp
  let tl_prc_x_start = floor_div(trx0, ppx) * ppx
  let tl_prc_y_start = floor_div(try0, ppy) * ppy
  let (cbgwidthexpn, cbgheightexpn, tlcbgxstart, tlcbgystart) = if res == 0 {
    (ppx_exp, ppy_exp, tl_prc_x_start, tl_prc_y_start)
  } else {
    let cbgw = if ppx_exp > 0 { ppx_exp - 1 } else { 0 }
    let cbgh = if ppy_exp > 0 { ppy_exp - 1 } else { 0 }
    (cbgw, cbgh, ceil_div(tl_prc_x_start, 2), ceil_div(tl_prc_y_start, 2))
  }
  let cbgw = 1 << cbgwidthexpn
  let cbgh = 1 << cbgheightexpn
  let abs_x0 = tlcbgxstart + px * cbgw
  let abs_y0 = tlcbgystart + py * cbgh
  let abs_x1 = abs_x0 + cbgw
  let abs_y1 = abs_y0 + cbgh
  // Clamp to subband bounds
  let x0 = if abs_x0 > tbx0 { abs_x0 } else { tbx0 }
  let y0 = if abs_y0 > tby0 { abs_y0 } else { tby0 }
  let x1 = if abs_x1 < tbx1 { abs_x1 } else { tbx1 }
  let y1 = if abs_y1 < tby1 { abs_y1 } else { tby1 }
  (x0, y0, x1, y1)
}

///|
// Backward-compatible wrapper assuming subband origin at (0,0).
pub fn compute_precinct_codeblock_range(
  sb_width : Int,
  sb_height : Int,
  cb_width : Int,
  cb_height : Int,
  px : Int,
  py : Int,
  ppx_exp : Int,
  ppy_exp : Int,
  res : Int,
) -> (Int, Int, Int, Int, Int, Int) {
  compute_precinct_codeblock_range_abs(
    0, 0, 0, 0, sb_width, sb_height, cb_width, cb_height, px, py, ppx_exp, ppy_exp,
    res,
  )
}

///|
// T.800-2015 B.7 Eq. B-22: Compute code-block count using absolute subband bounds.
// Returns (ncbx, ncby) based on reference grid alignment.
// ncbx = ceil(tbx1/xcb) - floor(tbx0/xcb)
// ncby = ceil(tby1/ycb) - floor(tby0/ycb)
pub fn compute_cb_count_from_bounds(
  tbx0 : Int,
  tby0 : Int,
  tbx1 : Int,
  tby1 : Int,
  cb_width : Int,
  cb_height : Int,
) -> (Int, Int) {
  if tbx1 <= tbx0 || tby1 <= tby0 {
    return (0, 0)
  }
  // T.800-2015 B.7: m = floor(tbx0/xcb) to ceil(tbx1/xcb) - 1
  let cb_x_start = tbx0 / cb_width
  let cb_x_end = (tbx1 + cb_width - 1) / cb_width
  let cb_y_start = tby0 / cb_height
  let cb_y_end = (tby1 + cb_height - 1) / cb_height
  (cb_x_end - cb_x_start, cb_y_end - cb_y_start)
}

///|
// T.800-2015 B.7: Compute correct CB geometry using absolute subband bounds.
// global_cbx/cby: relative CB index within subband (0-indexed)
// Returns (pixel_offset_x, pixel_offset_y, actual_width, actual_height)
pub fn compute_cb_geometry_from_bounds(
  tbx0 : Int,
  tby0 : Int,
  tbx1 : Int,
  tby1 : Int,
  cb_width : Int,
  cb_height : Int,
  global_cbx : Int,
  global_cby : Int,
) -> (Int, Int, Int, Int) {
  // Convert relative CB index to reference grid CB index
  let ref_cbx_first = tbx0 / cb_width
  let ref_cby_first = tby0 / cb_height
  let ref_cbx = ref_cbx_first + global_cbx
  let ref_cby = ref_cby_first + global_cby
  // T.800-2015 B.7: CB covers reference [ref_cbx*xcb, (ref_cbx+1)*xcb)
  // Clamped to subband bounds [tbx0, tbx1)
  let cb_ref_x0 = ref_cbx * cb_width
  let cb_ref_x1 = (ref_cbx + 1) * cb_width
  let cb_ref_y0 = ref_cby * cb_height
  let cb_ref_y1 = (ref_cby + 1) * cb_height
  // Clamp to subband bounds
  let x0 = if cb_ref_x0 > tbx0 { cb_ref_x0 } else { tbx0 }
  let x1 = if cb_ref_x1 < tbx1 { cb_ref_x1 } else { tbx1 }
  let y0 = if cb_ref_y0 > tby0 { cb_ref_y0 } else { tby0 }
  let y1 = if cb_ref_y1 < tby1 { cb_ref_y1 } else { tby1 }
  // Pixel offset within subband (relative to subband origin)
  let offset_x = x0 - tbx0
  let offset_y = y0 - tby0
  // Actual CB dimensions
  let actual_w = x1 - x0
  let actual_h = y1 - y0
  (offset_x, offset_y, actual_w, actual_h)
}

///|
// T.800-2015 B.7: Compute code-block geometry for a precinct-local CB index.
// Returns geometry relative to the parent subband origin.
pub fn compute_precinct_local_cb_geometry(
  sb_tbx0 : Int,
  sb_tby0 : Int,
  prec_x0 : Int,
  prec_y0 : Int,
  prec_x1 : Int,
  prec_y1 : Int,
  cb_width : Int,
  cb_height : Int,
  local_cbx : Int,
  local_cby : Int,
) -> (Int, Int, Int, Int) {
  if prec_x1 <= prec_x0 || prec_y1 <= prec_y0 {
    return (0, 0, 0, 0)
  }
  fn floor_div(num : Int, den : Int) -> Int {
    if den <= 0 {
      return 0
    }
    if num >= 0 {
      return num / den
    }
    -((-num + den - 1) / den)
  }
  let tlcblkxstart = floor_div(prec_x0, cb_width) * cb_width
  let tlcblkystart = floor_div(prec_y0, cb_height) * cb_height
  let cblkx0 = tlcblkxstart + local_cbx * cb_width
  let cblky0 = tlcblkystart + local_cby * cb_height
  let cblkx1 = cblkx0 + cb_width
  let cblky1 = cblky0 + cb_height
  let x0 = if cblkx0 > prec_x0 { cblkx0 } else { prec_x0 }
  let y0 = if cblky0 > prec_y0 { cblky0 } else { prec_y0 }
  let x1 = if cblkx1 < prec_x1 { cblkx1 } else { prec_x1 }
  let y1 = if cblky1 < prec_y1 { cblky1 } else { prec_y1 }
  if x1 <= x0 || y1 <= y0 {
    return (0, 0, 0, 0)
  }
  let offset_x = x0 - sb_tbx0
  let offset_y = y0 - sb_tby0
  let actual_w = x1 - x0
  let actual_h = y1 - y0
  (offset_x, offset_y, actual_w, actual_h)
}

///|
// Spec grouping:
// - Annex G (inverse multiple component transformation primitives)

///|
// Spec basis (T.800-2015 Annex G.2):
// - "Reversible multiple component transformation (RCT)".
// - Inverse relation uses component triplet mapping:
//   Y, Db, Dr -> G = Y - floor((Db + Dr)/4), R = Dr + G, B = Db + G.
pub fn tier1_annex_g_inverse_rct_triplet(
  y : Int,
  db : Int,
  dr : Int,
) -> (Int, Int, Int) {
  let g = y - ((db + dr) >> 2)
  let r = dr + g
  let b = db + g
  (r, g, b)
}

///|
// Spec basis (T.800-2015 Annex G.3):
// - "Irreversible multiple component transformation (ICT)".
// - Inverse relation:
//   R = Y + 1.402 Cr, G = Y - 0.34413 Cb - 0.71414 Cr, B = Y + 1.772 Cb.
// Implementation:
// - Floating-point for single-precision accuracy.
// - Uses lrintf-style rounding (round to nearest, ties away from zero).
pub fn tier1_annex_g_inverse_ict_triplet(
  y : Int,
  cb : Int,
  cr : Int,
) -> (Int, Int, Int) {
  let y_f = y.to_double()
  let cb_f = cb.to_double()
  let cr_f = cr.to_double()
  // T.800-2015 G.3 inverse ICT coefficients
  let r_f = y_f + 1.402 * cr_f
  let g_f = y_f - 0.34413 * cb_f - 0.71414 * cr_f
  let b_f = y_f + 1.772 * cb_f
  // Round to nearest integer (matching lrintf behavior)
  fn round_to_int(v : Double) -> Int {
    if v >= 0.0 {
      (v + 0.5).floor().to_int()
    } else {
      (v - 0.5).ceil().to_int()
    }
  }
  (round_to_int(r_f), round_to_int(g_f), round_to_int(b_f))
}

///|
// Internal helper for component-wise triplet transformation.
fn apply_triplet_transform(
  c0 : Array[Int],
  c1 : Array[Int],
  c2 : Array[Int],
  transform : (Int, Int, Int) -> (Int, Int, Int),
  error_msg : String,
) -> Result[(Array[Int], Array[Int], Array[Int]), String] {
  if c0.length() != c1.length() || c0.length() != c2.length() {
    return Err(error_msg)
  }
  let out0 : Array[Int] = []
  let out1 : Array[Int] = []
  let out2 : Array[Int] = []
  for i in 0..<c0.length() {
    let (v0, v1, v2) = transform(c0[i], c1[i], c2[i])
    out0.push(v0)
    out1.push(v1)
    out2.push(v2)
  }
  Ok((out0, out1, out2))
}

///|
// Spec basis (T.800-2015 Annex G.2):
// - inverse RCT is applied component-wise on aligned component sample tuples.
pub fn tier1_annex_g_inverse_rct_components(
  y : Array[Int],
  db : Array[Int],
  dr : Array[Int],
) -> Result[(Array[Int], Array[Int], Array[Int]), String] {
  apply_triplet_transform(
    y, db, dr, tier1_annex_g_inverse_rct_triplet, "inverse RCT requires equal component lengths",
  )
}

///|
// Spec basis (T.800-2015 Annex G.3):
// - inverse ICT is applied component-wise on aligned component sample tuples.
pub fn tier1_annex_g_inverse_ict_components(
  y : Array[Int],
  cb : Array[Int],
  cr : Array[Int],
) -> Result[(Array[Int], Array[Int], Array[Int]), String] {
  apply_triplet_transform(
    y, cb, cr, tier1_annex_g_inverse_ict_triplet, "inverse ICT requires equal component lengths",
  )
}

///|
let inverse_ict_r_cr_coeff : Double = @math.round_to_f32(1.402)

///|
let inverse_ict_g_cb_coeff : Double = @math.round_to_f32(0.34413)

///|
let inverse_ict_g_cr_coeff : Double = @math.round_to_f32(0.71414)

///|
let inverse_ict_b_cb_coeff : Double = @math.round_to_f32(1.772)

///|
fn tier1_annex_g_inverse_ict_triplet_float(
  y : Double,
  cb : Double,
  cr : Double,
) -> (Double, Double, Double) {
  // T.800-2015 G.3: float32 precision pipeline for inverse ICT.
  fn f32(v : Double) -> Double {
    @math.round_to_f32(v)
  }
  let y_f = f32(y)
  let cb_f = f32(cb)
  let cr_f = f32(cr)
  let r = f32(y_f + f32(cr_f * inverse_ict_r_cr_coeff))
  let g = f32(
    y_f -
    f32(cb_f * inverse_ict_g_cb_coeff) -
    f32(cr_f * inverse_ict_g_cr_coeff),
  )
  let b = f32(y_f + f32(cb_f * inverse_ict_b_cb_coeff))
  (r, g, b)
}

///|
fn apply_triplet_transform_float(
  c0 : Array[Double],
  c1 : Array[Double],
  c2 : Array[Double],
  transform : (Double, Double, Double) -> (Double, Double, Double),
  error_msg : String,
) -> Result[(Array[Double], Array[Double], Array[Double]), String] {
  if c0.length() != c1.length() || c0.length() != c2.length() {
    return Err(error_msg)
  }
  let out0 : Array[Double] = []
  let out1 : Array[Double] = []
  let out2 : Array[Double] = []
  for i in 0..<c0.length() {
    let (v0, v1, v2) = transform(c0[i], c1[i], c2[i])
    out0.push(v0)
    out1.push(v1)
    out2.push(v2)
  }
  Ok((out0, out1, out2))
}

///|
// Spec basis (T.800-2015 Annex G.3):
// Float-output inverse ICT variant for irreversible decode paths where
// final rounding is deferred until after DC level shift.
pub fn tier1_annex_g_inverse_ict_components_float(
  y : Array[Double],
  cb : Array[Double],
  cr : Array[Double],
) -> Result[(Array[Double], Array[Double], Array[Double]), String] {
  apply_triplet_transform_float(
    y, cb, cr, tier1_annex_g_inverse_ict_triplet_float, "inverse ICT requires equal component lengths",
  )
}

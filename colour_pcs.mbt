///|
/// Calibrated PDF components to D50 XYZ for a mature CMM's PCS input. The
/// matrix/gamma describe actual source XYZ. Adapt white points in Bradford
/// cone-response coordinates; the legacy display approximation is not a PCS.
/// The same affine black-point policy is retained. No display RGB is inverted.
fn pdf_colour_calibrated_pcs(
  space : @pdflite.PdfColourSpace,
  values : ArrayView[Double],
) -> Array[Double]? {
  let (x, y, z) = match space {
    @pdflite.PdfCalGray(white, black, gamma) => {
      let gray = @math.pow(
        pdf_colour_clamp_unit(pdf_colour_value_or(values, 0, 0.0)),
        if gamma > 0.0 && !gamma.is_inf() {
          gamma
        } else {
          1.0
        },
      )
      pdf_colour_cal_xyz_pcs(
        white,
        black,
        white.x * gray,
        white.y * gray,
        white.z * gray,
      )
    }
    @pdflite.PdfCalRGB(white, black, gamma, matrix) => {
      let valid = gamma.length() >= 3 && gamma.all(g => g >= 0.0 && !g.is_inf())
      let linear = [
        for i in 0..<3 => {
          @math.pow(
            pdf_colour_clamp_unit(pdf_colour_value_or(values, i, 0.0)),
            if valid {
              gamma[i]
            } else {
              1.0
            },
          )
        }
      ]
      let m = pdf_colour_matrix_or_identity(matrix)
      pdf_colour_cal_xyz_pcs(
        white,
        black,
        m[0] * linear[0] + m[3] * linear[1] + m[6] * linear[2],
        m[1] * linear[0] + m[4] * linear[1] + m[7] * linear[2],
        m[2] * linear[0] + m[5] * linear[1] + m[8] * linear[2],
      )
    }
    _ => return None
  }
  let pcs = [x, y, z]
  if pcs.any(v => v.is_nan() || v.is_inf()) {
    None
  } else {
    Some(pcs)
  }
}

///|
/// True Bradford adaptation: white XYZ must itself be transformed to LMS.
/// Keep this separate from the historical PDF.js-compatible display policy.
fn pdf_colour_pcs_adapt(
  source : @pdflite.PdfTristimulusPoint,
  target : @pdflite.PdfTristimulusPoint,
  x : Double,
  y : Double,
  z : Double,
) -> (Double, Double, Double) {
  if source == target {
    return (x, y, z)
  }
  let (sl, sm, ss) = pdf_colour_bradford(source.x, source.y, source.z)
  let (dl, dm, ds) = pdf_colour_bradford(target.x, target.y, target.z)
  let (l, m, s) = pdf_colour_bradford(x, y, z)
  let l = l * dl / sl
  let m = m * dm / sm
  let s = s * ds / ss
  (
    0.9869929 * l - 0.1470543 * m + 0.1599627 * s,
    0.4323053 * l + 0.5183603 * m + 0.0492912 * s,
    -0.0085287 * l + 0.0400428 * m + 0.9684867 * s,
  )
}

///|
fn pdf_colour_cal_xyz_pcs(
  white : @pdflite.PdfTristimulusPoint,
  black : @pdflite.PdfTristimulusPoint,
  x : Double,
  y : Double,
  z : Double,
) -> (Double, Double, Double) {
  let d50 : @pdflite.PdfTristimulusPoint = { x: 0.9642, y: 1.0, z: 0.8249, }
  if black.x == 0.0 && black.y == 0.0 && black.z == 0.0 {
    return pdf_colour_pcs_adapt(white, d50, x, y, z)
  }
  let flat : @pdflite.PdfTristimulusPoint = { x: 1.0, y: 1.0, z: 1.0, }
  let (x, y, z) = pdf_colour_pcs_adapt(white, flat, x, y, z)
  let (x, y, z) = if black.x >= 0.0 && black.y >= 0.0 && black.z >= 0.0 {
    (
      pdf_colour_compensate_black(x, black.x),
      pdf_colour_compensate_black(y, black.y),
      pdf_colour_compensate_black(z, black.z),
    )
  } else {
    (x, y, z)
  }
  pdf_colour_pcs_adapt(flat, d50, x, y, z)
}

///|
/// Gamma is monotone and all subsequent stages are affine. Cube corners
/// therefore bound every calibrated PCS component, including negative XYZ.
fn pdf_colour_calibrated_pcs_ranges(
  space : @pdflite.PdfColourSpace,
) -> Array[(Double, Double)]? {
  let n = match space {
    @pdflite.PdfCalGray(_, _, _) => 1
    @pdflite.PdfCalRGB(_, _, _, _) => 3
    _ => return None
  }
  guard pdf_colour_calibrated_pcs(space, Array::make(n, 0.0)) is Some(initial) else {
    return None
  }
  let low = initial.map(v => v)
  let high = initial.map(v => v)
  for corner in 0..<(1 << n) {
    let values = [
      for i in 0..<n => if (corner & (1 << i)) == 0 { 0.0 } else { 1.0 }
    ]
    guard pdf_colour_calibrated_pcs(space, values) is Some(pcs) else {
      return None
    }
    for i in 0..<3 {
      low[i] = low[i].min(pcs[i])
      high[i] = high[i].max(pcs[i])
    }
  }
  Some([ for i in 0..<3 => (low[i], high[i]) ])
}

///|
/// Exact parametric calibrated blending domain: PCS = M * component^gamma +
/// offset. Matrix columns are XYZ. This descriptor never contains a sampled
/// RGB inverse and remains tiny regardless of page or image size.
pub(all) struct PdfColourCalibration {
  components : Int
  gamma : Array[Double]
  pcs_matrix : Array[Double]
  pcs_offset : Array[Double]
} derive(Debug, Eq, ToJson)

///|
fn pdf_colour_calibration(
  space : @pdflite.PdfColourSpace,
  require_invertible? : Bool = true,
) -> PdfColourCalibration? {
  let gamma = match space {
    @pdflite.PdfCalGray(_, _, gamma) => {
      if gamma <= 0.0 || gamma.is_nan() || gamma.is_inf() {
        return None
      }
      [gamma]
    }
    @pdflite.PdfCalRGB(_, _, gamma, _) =>
      if gamma.is_empty() {
        [1.0, 1.0, 1.0]
      } else if gamma.length() == 3 && gamma.all(g => g > 0.0 && !g.is_inf()) {
        gamma
      } else {
        return None
      }
    _ => return None
  }
  let n = gamma.length()
  guard pdf_colour_calibrated_pcs(space, Array::make(n, 0.0)) is Some(offset) else {
    return None
  }
  let matrix : Array[Double] = []
  for axis in 0..<n {
    let sample = Array::make(n, 0.0)
    sample[axis] = 1.0
    guard pdf_colour_calibrated_pcs(space, sample) is Some(pcs) else {
      return None
    }
    for i in 0..<3 {
      matrix.push(pcs[i] - offset[i])
    }
  }
  // A degenerate calibration cannot be the destination of a colour transform.
  // Source-only forward conversion does not invert its matrix and is valid.
  if n == 1 {
    if require_invertible && matrix[1].abs() < 0.000000000001 {
      return None
    }
  } else {
    let determinant = matrix[0] *
      (matrix[4] * matrix[8] - matrix[7] * matrix[5]) -
      matrix[3] * (matrix[1] * matrix[8] - matrix[7] * matrix[2]) +
      matrix[6] * (matrix[1] * matrix[5] - matrix[4] * matrix[2])
    let scale = matrix.fold(init=0.0, (a, b) => a.max(b.abs())).max(1.0)
    if require_invertible &&
      determinant.abs() <= 0.000000000001 * scale * scale * scale {
      return None
    }
  }
  Some({ components: n, gamma, pcs_matrix: matrix, pcs_offset: offset, })
}

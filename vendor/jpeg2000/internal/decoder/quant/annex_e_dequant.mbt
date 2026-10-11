///|
// Spec grouping:
// - Annex E: Quantization
// - E.1.1: Scalar quantization (dequantization for reconstruction)

///|
// Spec basis (T.800-2015 E.1.1, Table E.1, Table E.2, Equation E-5, Table F.1):
// Extract quantization step size Δ_b for a given subband from QCD metadata.
// Δ_b = (1 + μ_b / 2048) × 2^(R_b − ε_b)
// where R_b = precision + gain_b (Equation E-4, Table E.1/E.2).
// Gains differ by filter type:
//   9/7 (Table E.1): LL=0, HL=1, LH=1, HH=2
//   5/3 (Table E.2): LL=0, HL=0, LH=1, HH=1
// For qstyle=1 (scalar derived), ε_b is derived from base ε_o using Equation E-5:
//   ε_b = ε_o - (N_L - n_b)
// where n_b is the decomposition level at which subband b was generated (Table F.1).
fn qcd_subband_step_size(
  qcd : @core.QcdMetadata,
  subband_index : Int,
  precision_bits : Int,
  decomposition_levels? : Int = 5,
  use_53_filter? : Bool = false,
) -> Double {
  let qstyle = qcd.quantization_style
  if qstyle == 0 {
    // Reversible: no dequantization needed (step size = 1.0)
    return 1.0
  }
  // T.800-2015 Table E.1 (9/7) and Table E.2 (5/3): subband gains for R_b
  // subband_index 0 = LL, then groups of 3: (HL, LH, HH) per resolution
  let gain = if subband_index == 0 {
    0
  } else if use_53_filter {
    // T.800-2015 Table E.2: 5/3 filter gains
    // HL=0, LH=1, HH=1
    match (subband_index - 1) % 3 {
      0 => 0 // HL
      1 => 1 // LH
      _ => 1 // HH
    }
  } else {
    // T.800-2015 E.1.1:
    // For 9/7 decode, log2_gain is treated as 0 for all bands to compensate
    // the two_invK scaling in inverse DWT.
    0
  }
  let r_b = precision_bits + gain
  // Extract (ε, μ) from QCD parameters
  let (epsilon, mu) = if qstyle == 2 {
    // Scalar expounded: 2 bytes per subband
    let byte_index = subband_index * 2
    if byte_index + 1 < qcd.parameters.length() {
      let word = (qcd.parameters[byte_index] << 8) |
        qcd.parameters[byte_index + 1]
      ((word >> 11) & 0x1F, word & 0x7FF)
    } else if qcd.parameters.length() >= 2 {
      let last = qcd.parameters.length() - 2
      let word = (qcd.parameters[last] << 8) | qcd.parameters[last + 1]
      ((word >> 11) & 0x1F, word & 0x7FF)
    } else {
      (precision_bits, 0)
    }
    // qstyle == 1: scalar derived (single base step size for all subbands)
  } else if qcd.parameters.length() >= 2 {
    let word = (qcd.parameters[0] << 8) | qcd.parameters[1]
    let base_epsilon = (word >> 11) & 0x1F
    // T.800-2015 Equation E-5, Table F.1:
    // ε_b = ε_o - (N_L - n_b)
    // n_b = decomposition level at which subband b was generated:
    //   - NL_LL, NL_HL, NL_LH, NL_HH: n_b = N_L
    //   - (NL-1)_HL, (NL-1)_LH, (NL-1)_HH: n_b = N_L - 1
    //   - ...
    //   - 1_HL, 1_LH, 1_HH: n_b = 1
    let n_b = if subband_index == 0 {
      decomposition_levels // NL_LL
    } else {
      // subband 1,2,3 → res_group=0, n_b=NL
      // subband 4,5,6 → res_group=1, n_b=NL-1
      // ...
      let res_group = (subband_index - 1) / 3
      decomposition_levels - res_group
    }
    let derived_epsilon = base_epsilon - (decomposition_levels - n_b)
    (derived_epsilon, word & 0x7FF)
  } else {
    (precision_bits, 0)
  }
  // Δ_b = (1 + μ / 2048) × 2^(R_b − ε)
  let step = (1.0 + mu.to_double() / 2048.0) * @math.pow2_double(r_b - epsilon)
  if use_53_filter {
    step
  } else {
    @math.round_to_f32(step)
  }
}

///|
// Spec basis (T.800-2015 E.1.1):
// Dequantize integer coefficients to Double using per-subband step sizes.
// Operates on the full coefficient array in subband layout (before IDWT).
// Returns floating-point coefficients for irreversible path.
// use_53_filter: true for 5/3 filter, false for 9/7 filter (affects gains)
pub fn dequantize_coefficients(
  coeffs : Array[Int],
  width : Int,
  height : Int,
  decomposition_levels : Int,
  qcd : @core.QcdMetadata,
  precision_bits : Int,
  tcx0? : Int = 0,
  tcy0? : Int = 0,
  use_53_filter? : Bool = false,
) -> Array[Double] {
  let result : Array[Double] = []
  for _ in 0..<coeffs.length() {
    result.push(0.0)
  }
  fn dequantize_value(coeff : Int, step : Double) -> Double {
    if use_53_filter {
      coeff.to_double() * step
    } else {
      // Irreversible (9/7) path: multiply integer coefficients by float32
      // half-step (0.5 × Δ_b) for inverse DWT input.
      let coeff_f = @math.round_to_f32(coeff.to_double())
      let scaled_step = @math.round_to_f32(step * 0.5)
      @math.round_to_f32(coeff_f * scaled_step)
    }
  }
  // Lossy path stores Tier-1 coefficients in x2 fixed-point to preserve
  // 0.5 LSB at shift==0. Convert back during dequantization.
  // T.800-2015 B.5: Pre-compute resolution dimensions using absolute coordinates
  let res_dims : Array[(Int, Int)] = []
  for r in 0..<=decomposition_levels {
    let level = decomposition_levels - r
    let (rw, rh) = @subband.subband_ll_dims(width, height, level, tcx0~, tcy0~)
    res_dims.push((rw, rh))
  }
  // LL subband at coarsest level (subband_index = 0)
  let (ll_w, ll_h) = res_dims[0]
  let ll_step = qcd_subband_step_size(
    qcd,
    0,
    precision_bits,
    decomposition_levels~,
    use_53_filter~,
  )
  for y in 0..<ll_h {
    for x in 0..<ll_w {
      let idx = y * width + x
      if idx < coeffs.length() {
        result[idx] = dequantize_value(coeffs[idx], ll_step)
      }
    }
  }
  // Detail subbands for each resolution level
  for res in 1..<=decomposition_levels {
    let (prev_w, prev_h) = res_dims[res - 1]
    let (parent_w, parent_h) = res_dims[res]
    let qcd_base = 1 + (res - 1) * 3
    // HL subband (top-right): subband_index = qcd_base + 0
    let hl_step = qcd_subband_step_size(
      qcd,
      qcd_base,
      precision_bits,
      decomposition_levels~,
      use_53_filter~,
    )
    for y in 0..<prev_h {
      for x in prev_w..<parent_w {
        let idx = y * width + x
        if idx < coeffs.length() {
          result[idx] = dequantize_value(coeffs[idx], hl_step)
        }
      }
    }
    // LH subband (bottom-left): subband_index = qcd_base + 1
    let lh_step = qcd_subband_step_size(
      qcd,
      qcd_base + 1,
      precision_bits,
      decomposition_levels~,
      use_53_filter~,
    )
    for y in prev_h..<parent_h {
      for x in 0..<prev_w {
        let idx = y * width + x
        if idx < coeffs.length() {
          result[idx] = dequantize_value(coeffs[idx], lh_step)
        }
      }
    }
    // HH subband (bottom-right): subband_index = qcd_base + 2
    let hh_step = qcd_subband_step_size(
      qcd,
      qcd_base + 2,
      precision_bits,
      decomposition_levels~,
      use_53_filter~,
    )
    for y in prev_h..<parent_h {
      for x in prev_w..<parent_w {
        let idx = y * width + x
        if idx < coeffs.length() {
          result[idx] = dequantize_value(coeffs[idx], hh_step)
        }
      }
    }
  }
  result
}

///|
/// Spec basis (T.800-2015 E.1.1, Equation E-5, Table F.1):
/// Compute K_max (total magnitude bit-planes) for a subband from QCD.
/// K_max = ε_b + guard_bits - 1
/// For qstyle=1 (scalar derived), ε_b is derived using Equation E-5:
///   ε_b = ε_o - (N_L - n_b)
/// subband_index: 0=LL, then 1=HL,2=LH,3=HH per resolution from deepest
pub fn qcd_subband_max_bit_planes(
  qcd : @core.QcdMetadata,
  subband_index : Int,
  precision_bits? : Int = 8,
  transformation? : Int = -1,
  decomposition_levels? : Int = 5,
) -> Int {
  let gbits = qcd.guard_bits
  let qstyle = qcd.quantization_style
  let _ = transformation // preserve for future use
  if qstyle == 0 {
    // T.800-2015 Table A.22: qstyle=0 means SPqcd has 1 byte per subband
    let epsilon = if subband_index < qcd.parameters.length() {
      qcd.parameters[subband_index] >> 3
    } else if qcd.parameters.length() > 0 {
      qcd.parameters[qcd.parameters.length() - 1] >> 3
    } else {
      precision_bits
    }
    // T.800-2015 E.1.1: K = ε + g - 1 for reversible path
    epsilon + gbits - 1
  } else if qstyle == 2 {
    // T.800-2015 Table E.1: qstyle=2 (scalar expounded), 2 bytes per subband
    // SPqcd 16-bit word: bits 15-11 = ε, bits 10-0 = μ
    let byte_index = subband_index * 2
    if byte_index + 1 < qcd.parameters.length() {
      let word = (qcd.parameters[byte_index] << 8) |
        qcd.parameters[byte_index + 1]
      let epsilon = (word >> 11) & 0x1F
      epsilon + gbits - 1
    } else if qcd.parameters.length() >= 2 {
      // Fallback: use last 2-byte entry
      let last = qcd.parameters.length() - 2
      let word = (qcd.parameters[last] << 8) | qcd.parameters[last + 1]
      let epsilon = (word >> 11) & 0x1F
      epsilon + gbits - 1
    } else {
      8
    }
    // qstyle == 1: scalar derived (single base step size)
    // T.800-2015 Equation E-5: ε_b = ε_o - (N_L - n_b)
    // K_max = ε_b + guard_bits - 1
  } else if qcd.parameters.length() >= 2 {
    let word = (qcd.parameters[0] << 8) | qcd.parameters[1]
    let base_epsilon = (word >> 11) & 0x1F
    // Compute n_b from subband_index (Table F.1)
    let n_b = if subband_index == 0 {
      decomposition_levels
    } else {
      let res_group = (subband_index - 1) / 3
      decomposition_levels - res_group
    }
    let derived_epsilon = base_epsilon - (decomposition_levels - n_b)
    derived_epsilon + gbits - 1
  } else {
    8
  }
}

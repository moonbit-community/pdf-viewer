///|
// Spec grouping:
// - Annex D.3 decoding passes
// - Step 1-b.2.3 bootstrap for pass integration

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
pub fn tier1_staged_pass_trace(
  coding_passes : Int,
  zero_bit_planes : Int,
) -> Result[String, String] {
  if coding_passes <= 0 {
    return Err("coding_passes must be positive")
  }
  if zero_bit_planes < 0 {
    return Err("zero_bit_planes must be non-negative")
  }
  let seq : Array[String] = []
  let mut bitplane = zero_bit_planes
  for i in 0..<coding_passes {
    if i > 0 && i % 3 == 0 {
      bitplane += 1
    }
    let kind = if i % 3 == 0 {
      "cleanup"
    } else if i % 3 == 1 {
      "sigprop"
    } else {
      "magref"
    }
    seq.push("\{kind}@bp\{bitplane}")
  }
  Ok("tier1-pass-trace:n=\{coding_passes},seq=\{seq}")
}

///|
pub struct Tier1StagedPassState {
  significant : Bool
  sign : Int
  magnitude : Int
  consumed_bits : Int
}

///|
pub fn Tier1StagedPassState::new(
  significant : Bool,
  sign : Int,
  magnitude : Int,
  consumed_bits : Int,
) -> Tier1StagedPassState {
  { significant, sign, magnitude, consumed_bits, }
}

///|
pub struct Tier1StagedBitCursor {
  decisions : Array[Int]
  index : Int
}

///|
pub fn Tier1StagedBitCursor::new(
  decisions : Array[Int],
  index : Int,
) -> Tier1StagedBitCursor {
  { decisions, index, }
}

///|
fn tier1_decision_context_at(
  contexts : Array[Int],
  cursor : Tier1StagedBitCursor,
) -> Int {
  if cursor.index < contexts.length() {
    contexts[cursor.index]
  } else {
    -1
  }
}

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
fn tier1_next_decision_bit(
  cursor : Tier1StagedBitCursor,
) -> Result[(Int, Tier1StagedBitCursor), String] {
  if cursor.decisions.length() <= 0 {
    return Err("decisions are empty")
  }
  let bit = cursor.decisions[cursor.index % cursor.decisions.length()]
  if bit != 0 && bit != 1 {
    return Err("decision bit must be 0 or 1")
  }
  Ok((bit, { decisions: cursor.decisions, index: cursor.index + 1, }))
}

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
pub fn tier1_apply_cleanup_pass_single(
  state : Tier1StagedPassState,
  cursor : Tier1StagedBitCursor,
) -> Result[(Tier1StagedPassState, Tier1StagedBitCursor), String] {
  let bit_v = tier1_next_decision_bit(cursor)
  guard bit_v is Ok((bit, c1)) else { return Err("failed to read cleanup bit") }
  if state.significant || bit == 0 {
    return Ok(
      (
        {
          significant: state.significant,
          sign: state.sign,
          magnitude: state.magnitude,
          consumed_bits: state.consumed_bits + 1,
        },
        c1,
      ),
    )
  }
  let sbit_v = tier1_next_decision_bit(c1)
  guard sbit_v is Ok((sbit, c2)) else { return Err("failed to read sign bit") }
  let sign = if sbit == 0 { 1 } else { -1 }
  Ok(
    (
      {
        significant: true,
        sign,
        magnitude: 1,
        consumed_bits: state.consumed_bits + 2,
      },
      c2,
    ),
  )
}

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
pub fn tier1_apply_magref_pass_single(
  state : Tier1StagedPassState,
  cursor : Tier1StagedBitCursor,
) -> Result[(Tier1StagedPassState, Tier1StagedBitCursor), String] {
  let bit_v = tier1_next_decision_bit(cursor)
  guard bit_v is Ok((bit, c1)) else { return Err("failed to read magref bit") }
  let magnitude = if state.significant && bit == 1 {
    state.magnitude + 1
  } else {
    state.magnitude
  }
  Ok(
    (
      {
        significant: state.significant,
        sign: state.sign,
        magnitude,
        consumed_bits: state.consumed_bits + 1,
      },
      c1,
    ),
  )
}

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
pub fn tier1_apply_passes_single_coeff_with_sigprop_policy(
  coding_passes : Int,
  zero_bit_planes : Int,
  decisions : Array[Int],
  sigprop_discovery_enabled : Bool,
) -> Result[Tier1StagedPassState, String] {
  if coding_passes <= 0 {
    return Err("coding_passes must be positive")
  }
  if zero_bit_planes < 0 {
    return Err("zero_bit_planes must be non-negative")
  }
  let mut state : Tier1StagedPassState = {
    significant: false,
    sign: 1,
    magnitude: 0,
    consumed_bits: 0,
  }
  let mut cursor : Tier1StagedBitCursor = { decisions, index: 0, }
  for i in 0..<coding_passes {
    let kind = i % 3
    if kind == 0 {
      let v = tier1_apply_cleanup_pass_single(state, cursor)
      guard v is Ok((next_state, next_cursor)) else {
        return Err("cleanup pass failed")
      }
      state = next_state
      cursor = next_cursor
      continue
    }
    if kind == 1 {
      let v = if sigprop_discovery_enabled {
        tier1_apply_cleanup_pass_single(state, cursor)
      } else {
        Ok((state, cursor))
      }
      guard v is Ok((next_state, next_cursor)) else {
        return Err("sigprop pass failed")
      }
      state = next_state
      cursor = next_cursor
      continue
    }
    let v = tier1_apply_magref_pass_single(state, cursor)
    guard v is Ok((next_state, next_cursor)) else {
      return Err("magref pass failed")
    }
    state = next_state
    cursor = next_cursor
  }
  Ok(state)
}

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
pub fn tier1_staged_apply_passes(
  coding_passes : Int,
  zero_bit_planes : Int,
  decisions : Array[Int],
) -> Result[Tier1StagedPassState, String] {
  // staged profile always enables sigprop discovery for single-coeff bootstrap.
  tier1_apply_passes_single_coeff_with_sigprop_policy(
    coding_passes, zero_bit_planes, decisions, true,
  )
}

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
pub fn tier1_staged_pass_state_debug(state : Tier1StagedPassState) -> String {
  "tier1-pass-state:sig=\{state.significant},sign=\{state.sign},mag=\{state.magnitude},consumed=\{state.consumed_bits}"
}

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
fn tier1_single_coeff_has_sig_neighbor(_state : Tier1StagedPassState) -> Bool {
  // Single-coefficient bootstrap profile has no neighbors.
  false
}

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
pub fn tier1_apply_passes_normative_preview_single_coeff(
  coding_passes : Int,
  zero_bit_planes : Int,
  decisions : Array[Int],
) -> Result[Tier1StagedPassState, String] {
  // normative single-coeff bootstrap has no significant neighbors in sigprop.
  let has_neighbor = tier1_single_coeff_has_sig_neighbor({
    significant: false,
    sign: 1,
    magnitude: 0,
    consumed_bits: 0,
  })
  tier1_apply_passes_single_coeff_with_sigprop_policy(
    coding_passes, zero_bit_planes, decisions, has_neighbor,
  )
}

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
pub fn tier1_normative_preview_state_debug(
  state : Tier1StagedPassState,
) -> String {
  "tier1-pass-norm-preview:sig=\{state.significant},sign=\{state.sign},mag=\{state.magnitude},consumed=\{state.consumed_bits}"
}

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
pub fn tier1_normative_pass_state_debug(state : Tier1StagedPassState) -> String {
  "tier1-pass-state:sig=\{state.significant},sign=\{state.sign},mag=\{state.magnitude},consumed=\{state.consumed_bits}"
}

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
pub fn tier1_normative_single_coeff_value(state : Tier1StagedPassState) -> Int {
  if !state.significant {
    return 0
  }
  state.sign * state.magnitude
}

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
pub fn tier1_normative_single_coeff_debug(
  state : Tier1StagedPassState,
) -> String {
  "tier1-pass-coeff:value=\{tier1_normative_single_coeff_value(state)}"
}

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
pub fn tier1_normative_preview_sample_values(
  sample_count : Int,
  coeff_state : Tier1StagedPassState,
  decisions : Array[Int],
) -> Result[Array[Int], String] {
  if sample_count <= 0 {
    return Err("sample_count must be positive")
  }
  if decisions.length() <= 0 {
    return Err("decisions are empty")
  }
  let coeff = tier1_normative_single_coeff_value(coeff_state)
  let out : Array[Int] = []
  out.push(coeff)
  for i in 1..<sample_count {
    let bit = decisions[(i - 1) % decisions.length()]
    if bit == 1 {
      out.push(coeff)
    } else {
      out.push(0)
    }
  }
  Ok(out)
}

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
pub fn tier1_normative_preview_sample_values_debug(
  values : Array[Int],
) -> String {
  "tier1-pass-samples:\{values}"
}

///|
pub struct Tier1MiniCoeffState {
  significant : Bool
  sign : Int
  magnitude : Int
}

///|
pub struct Tier1MiniBlockState {
  width : Int
  height : Int
  coeffs : Array[Tier1MiniCoeffState]
  consumed_bits : Int
}

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
fn tier1_mini_block_has_sig_neighbor(
  state : Tier1MiniBlockState,
  x : Int,
  y : Int,
) -> Bool {
  tier1_mini_block_has_sig_neighbor_at(
    state.coeffs,
    state.width,
    state.height,
    x,
    y,
  )
}

///|
fn tier1_mini_block_has_sig_neighbor_at(
  coeffs : Array[Tier1MiniCoeffState],
  w : Int,
  h : Int,
  x : Int,
  y : Int,
  mask_south? : Bool = false,
) -> Bool {
  for dy in -1..<2 {
    for dx in -1..<2 {
      if dx == 0 && dy == 0 {
        continue
      }
      if mask_south && dy == 1 {
        continue
      }
      let nx = x + dx
      let ny = y + dy
      if nx < 0 || ny < 0 || nx >= w || ny >= h {
        continue
      }
      let ni = ny * w + nx
      if coeffs[ni].significant {
        return true
      }
    }
  }
  false
}

///|
fn tier1_mini_block_has_sig_neighbor_flags(
  significant : Array[Bool],
  w : Int,
  h : Int,
  x : Int,
  y : Int,
  mask_south? : Bool = false,
) -> Bool {
  for dy in -1..<2 {
    for dx in -1..<2 {
      if dx == 0 && dy == 0 {
        continue
      }
      if mask_south && dy == 1 {
        continue
      }
      let nx = x + dx
      let ny = y + dy
      if nx < 0 || ny < 0 || nx >= w || ny >= h {
        continue
      }
      let ni = ny * w + nx
      if significant[ni] {
        return true
      }
    }
  }
  false
}

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
fn tier1_mini_block_bump_consumed(
  state : Tier1MiniBlockState,
  delta : Int,
) -> Tier1MiniBlockState {
  {
    width: state.width,
    height: state.height,
    coeffs: state.coeffs,
    consumed_bits: state.consumed_bits + delta,
  }
}

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
fn tier1_mini_block_set_coeff(
  state : Tier1MiniBlockState,
  index : Int,
  coeff : Tier1MiniCoeffState,
) -> Tier1MiniBlockState {
  let coeffs = state.coeffs
  coeffs[index] = coeff
  {
    width: state.width,
    height: state.height,
    coeffs,
    consumed_bits: state.consumed_bits,
  }
}

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
fn tier1_apply_cleanup_pass_2x2(
  state : Tier1MiniBlockState,
  cursor : Tier1StagedBitCursor,
) -> Result[(Tier1MiniBlockState, Tier1StagedBitCursor), String] {
  let mut next = state
  let mut c = cursor
  for y in 0..<next.height {
    for x in 0..<next.width {
      let i = @math.grid_index_2d(next.width, x, y)
      if next.coeffs[i].significant {
        continue
      }
      let sig_v = tier1_next_decision_bit(c)
      guard sig_v is Ok((sig, c1)) else {
        return Err("failed to read cleanup significance bit")
      }
      next = tier1_mini_block_bump_consumed(next, 1)
      c = c1
      if sig == 0 {
        continue
      }
      let sign_v = tier1_next_decision_bit(c)
      guard sign_v is Ok((sbit, c2)) else {
        return Err("failed to read cleanup sign bit")
      }
      next = tier1_mini_block_bump_consumed(next, 1)
      c = c2
      next = tier1_mini_block_set_coeff(next, i, {
        significant: true,
        sign: if sbit == 0 {
          1
        } else {
          -1
        },
        magnitude: 1,
      })
    }
  }
  Ok((next, c))
}

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
fn tier1_apply_sigprop_pass_2x2_normative(
  state : Tier1MiniBlockState,
  cursor : Tier1StagedBitCursor,
) -> Result[(Tier1MiniBlockState, Tier1StagedBitCursor), String] {
  let mut next = state
  let mut c = cursor
  for y in 0..<next.height {
    for x in 0..<next.width {
      let i = @math.grid_index_2d(next.width, x, y)
      if next.coeffs[i].significant {
        continue
      }
      if !tier1_mini_block_has_sig_neighbor(next, x, y) {
        continue
      }
      let sig_v = tier1_next_decision_bit(c)
      guard sig_v is Ok((sig, c1)) else {
        return Err("failed to read sigprop significance bit")
      }
      next = tier1_mini_block_bump_consumed(next, 1)
      c = c1
      if sig == 0 {
        continue
      }
      let sign_v = tier1_next_decision_bit(c)
      guard sign_v is Ok((sbit, c2)) else {
        return Err("failed to read sigprop sign bit")
      }
      next = tier1_mini_block_bump_consumed(next, 1)
      c = c2
      next = tier1_mini_block_set_coeff(next, i, {
        significant: true,
        sign: if sbit == 0 {
          1
        } else {
          -1
        },
        magnitude: 1,
      })
    }
  }
  Ok((next, c))
}

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
fn tier1_apply_magref_pass_2x2(
  state : Tier1MiniBlockState,
  cursor : Tier1StagedBitCursor,
) -> Result[(Tier1MiniBlockState, Tier1StagedBitCursor), String] {
  let mut next = state
  let mut c = cursor
  for i in 0..<next.coeffs.length() {
    if !next.coeffs[i].significant {
      continue
    }
    let bit_v = tier1_next_decision_bit(c)
    guard bit_v is Ok((bit, c1)) else {
      return Err("failed to read magref bit")
    }
    next = tier1_mini_block_bump_consumed(next, 1)
    c = c1
    // Spec basis (T.800-2015 D.3.4):
    // Magnitude refinement shifts existing magnitude left and adds new bit as LSB.
    let old = next.coeffs[i]
    next = tier1_mini_block_set_coeff(next, i, {
      significant: old.significant,
      sign: old.sign,
      magnitude: (old.magnitude << 1) | bit,
    })
  }
  Ok((next, c))
}

///|
// Spec basis (T.800-2015 Annex D.3):
// - "decoded in three coding passes" (significance propagation,
//   magnitude refinement, cleanup).
pub fn tier1_normative_preview_sample_values_mini_block(
  width : Int,
  height : Int,
  coding_passes : Int,
  zero_bit_planes : Int,
  decisions : Array[Int],
  code_block_style? : Int = 0,
) -> Result[(Array[Int], Int), String] {
  if width <= 0 || height <= 0 {
    return Err("mini block dimensions must be positive")
  }
  if coding_passes <= 0 {
    return Err("coding_passes must be positive")
  }
  if zero_bit_planes < 0 {
    return Err("zero_bit_planes must be non-negative")
  }
  // Spec basis (T.800-2015 Annex D.3):
  // Coefficient reconstruction from MQ decisions. Must match the exact scan
  // order and eligibility rules used by the MQ decoder in
  // @mq.tier1_annex_c_decode_all_passes_mini_block.
  let n = width * height
  let coeffs : Array[Tier1MiniCoeffState] = []
  let sigprop_member : Array[Bool] = []
  let sig_before_bp : Array[Bool] = []
  for _ in 0..<n {
    coeffs.push({ significant: false, sign: 1, magnitude: 0, })
    sigprop_member.push(false)
    sig_before_bp.push(false)
  }
  let mut cursor : Tier1StagedBitCursor = { decisions, index: 0, }
  for i in 0..<coding_passes {
    let pass_kind = i % 3
    if pass_kind == 0 {
      // Cleanup pass (D.3.4) — stripe-based scan, skip sig and sigprop_member.
      // The MQ decoder handles run-length internally and emits synthetic
      // per-sample decisions (0=not significant, 1=significant + sign).
      // This reconstruction simply consumes those per-sample decisions.
      // T.800-2015 D.3: PI flags cleared after cleanup pass; sigprop_member must not
      // leak into the next bit-plane cleanup pass.
      let mut stripe_top = 0
      while stripe_top < height {
        let stripe_h = if stripe_top + 4 <= height {
          4
        } else {
          height - stripe_top
        }
        for x in 0..<width {
          for j in 0..<stripe_h {
            let y = stripe_top + j
            if y >= height {
              continue
            }
            let idx = y * width + x
            if coeffs[idx].significant || sigprop_member[idx] {
              continue
            }
            // Consume significance decision
            let sig_v = tier1_next_decision_bit(cursor)
            guard sig_v is Ok((sig_bit, c1)) else {
              return Err("recon: cleanup sig failed")
            }
            cursor = c1
            if sig_bit == 0 {
              continue
            }
            // Became significant — consume sign decision
            let sign_v = tier1_next_decision_bit(cursor)
            guard sign_v is Ok((sbit, c2)) else {
              return Err("recon: cleanup sign failed")
            }
            cursor = c2
            coeffs[idx] = {
              significant: true,
              sign: if sbit == 0 {
                1
              } else {
                -1
              },
              magnitude: 1,
            }
          }
        }
        stripe_top += 4
      }
      for k in 0..<n {
        sigprop_member[k] = false
      }
    } else if pass_kind == 1 {
      // Significance propagation pass (D.3.2) — snapshot sig for magref
      for k in 0..<n {
        sigprop_member[k] = false
        sig_before_bp[k] = coeffs[k].significant
      }
      let mut stripe_top = 0
      while stripe_top < height {
        let stripe_h = if stripe_top + 4 <= height {
          4
        } else {
          height - stripe_top
        }
        for x in 0..<width {
          for j in 0..<stripe_h {
            let y = stripe_top + j
            let idx = y * width + x
            if coeffs[idx].significant {
              continue
            }
            let vsc = (code_block_style & 0x08) != 0 && y % 4 == 3
            if !tier1_mini_block_has_sig_neighbor_at(
                coeffs,
                width,
                height,
                x,
                y,
                mask_south=vsc,
              ) {
              continue
            }
            sigprop_member[idx] = true
            // Consume significance decision
            let sig_v = tier1_next_decision_bit(cursor)
            guard sig_v is Ok((sig_bit, c1)) else {
              return Err("recon: sigprop sig failed")
            }
            cursor = c1
            if sig_bit == 0 {
              continue
            }
            // Became significant — consume sign decision
            let sign_v = tier1_next_decision_bit(cursor)
            guard sign_v is Ok((sbit, c2)) else {
              return Err("recon: sigprop sign failed")
            }
            cursor = c2
            coeffs[idx] = {
              significant: true,
              sign: if sbit == 0 {
                1
              } else {
                -1
              },
              magnitude: 1,
            }
          }
        }
        stripe_top += 4
      }
    } else {
      // Magnitude refinement pass (D.3.3) — use sig_before_bp for eligibility
      let mut stripe_top = 0
      while stripe_top < height {
        let stripe_h = if stripe_top + 4 <= height {
          4
        } else {
          height - stripe_top
        }
        for x in 0..<width {
          for j in 0..<stripe_h {
            let y = stripe_top + j
            let idx = y * width + x
            if !sig_before_bp[idx] {
              continue
            }
            // Consume magref decision
            let bit_v = tier1_next_decision_bit(cursor)
            guard bit_v is Ok((bit, c1)) else {
              return Err("recon: magref failed")
            }
            cursor = c1
            let old = coeffs[idx]
            coeffs[idx] = {
              significant: old.significant,
              sign: old.sign,
              magnitude: (old.magnitude << 1) | bit,
            }
          }
        }
        stripe_top += 4
      }
    }
  }
  let out : Array[Int] = []
  for c in coeffs {
    if !c.significant {
      out.push(0)
    } else {
      out.push(c.sign * c.magnitude)
    }
  }
  Ok((out, cursor.index))
}

///|
// T.800-2015 D.3: Fixed-point reconstruction for coefficient positioning.
// Replays decoded decisions with the same value updates used by T1 decode:
// - significance: +/- (one | half)
// - magref: +/- half depending on sign and decoded bit
// where one = 1 << bp and bp follows the JPEG 2000 pass schedule.
pub fn tier1_fixedpoint_sample_values_mini_block(
  width : Int,
  height : Int,
  coding_passes : Int,
  initial_bpno_plus_one : Int,
  decisions : Array[Int],
  code_block_style? : Int = 0,
) -> Result[(Array[Int], Int), String] {
  if width <= 0 || height <= 0 {
    return Err("mini block dimensions must be positive")
  }
  if coding_passes <= 0 {
    return Err("coding_passes must be positive")
  }
  if initial_bpno_plus_one < 0 {
    return Err("initial_bpno_plus_one must be non-negative")
  }
  let n = width * height
  let significant : Array[Bool] = []
  let sigprop_member : Array[Bool] = []
  let sig_before_bp : Array[Bool] = []
  let values : Array[Int] = []
  for _ in 0..<n {
    significant.push(false)
    sigprop_member.push(false)
    sig_before_bp.push(false)
    values.push(0)
  }
  let mut cursor : Tier1StagedBitCursor = { decisions, index: 0, }
  for i in 0..<coding_passes {
    let pass_kind = i % 3
    // T.800-2015 D.3: bit-plane pass schedule:
    // pass 0: cleanup at bp=initial
    // pass 1,2,3: sigprop/magref/cleanup at bp=initial-1
    // pass 4,5,6: sigprop/magref/cleanup at bp=initial-2
    let bp = initial_bpno_plus_one - (i + 2) / 3
    // Decode loop executes while bpno_plus_one >= 1.
    if bp < 1 {
      continue
    }
    let one = if bp < 30 { 1 << bp } else { 0 }
    let half = one >> 1
    let oneplushalf = one | half
    if pass_kind == 0 {
      // Cleanup pass: skip already significant and prior sigprop members.
      // T.800-2015 D.3: PI flags cleared after cleanup pass; sigprop_member must not
      // leak into the next bit-plane cleanup pass.
      let mut stripe_top = 0
      while stripe_top < height {
        let stripe_h = if stripe_top + 4 <= height {
          4
        } else {
          height - stripe_top
        }
        for x in 0..<width {
          for j in 0..<stripe_h {
            let y = stripe_top + j
            if y >= height {
              continue
            }
            let idx = y * width + x
            if significant[idx] || sigprop_member[idx] {
              continue
            }
            let sig_v = tier1_next_decision_bit(cursor)
            guard sig_v is Ok((sig_bit, c1)) else {
              return Err("t1-recon: cleanup sig failed")
            }
            cursor = c1
            if sig_bit == 0 {
              continue
            }
            let sign_v = tier1_next_decision_bit(cursor)
            guard sign_v is Ok((sbit, c2)) else {
              return Err("t1-recon: cleanup sign failed")
            }
            cursor = c2
            significant[idx] = true
            values[idx] = if sbit == 0 { oneplushalf } else { -oneplushalf }
          }
        }
        stripe_top += 4
      }
      for k in 0..<n {
        sigprop_member[k] = false
      }
    } else if pass_kind == 1 {
      // SigProp pass: refresh membership for this bit-plane.
      for k in 0..<n {
        sigprop_member[k] = false
        sig_before_bp[k] = significant[k]
      }
      let mut stripe_top = 0
      while stripe_top < height {
        let stripe_h = if stripe_top + 4 <= height {
          4
        } else {
          height - stripe_top
        }
        for x in 0..<width {
          for j in 0..<stripe_h {
            let y = stripe_top + j
            let idx = y * width + x
            if significant[idx] {
              continue
            }
            let vsc = (code_block_style & 0x08) != 0 && y % 4 == 3
            if !tier1_mini_block_has_sig_neighbor_flags(
                significant,
                width,
                height,
                x,
                y,
                mask_south=vsc,
              ) {
              continue
            }
            sigprop_member[idx] = true
            let sig_v = tier1_next_decision_bit(cursor)
            guard sig_v is Ok((sig_bit, c1)) else {
              return Err("t1-recon: sigprop sig failed")
            }
            cursor = c1
            if sig_bit == 0 {
              continue
            }
            let sign_v = tier1_next_decision_bit(cursor)
            guard sign_v is Ok((sbit, c2)) else {
              return Err("t1-recon: sigprop sign failed")
            }
            cursor = c2
            significant[idx] = true
            values[idx] = if sbit == 0 { oneplushalf } else { -oneplushalf }
          }
        }
        stripe_top += 4
      }
    } else {
      // MagRef pass: only coefficients significant before this bit-plane.
      let mut stripe_top = 0
      while stripe_top < height {
        let stripe_h = if stripe_top + 4 <= height {
          4
        } else {
          height - stripe_top
        }
        for x in 0..<width {
          for j in 0..<stripe_h {
            let y = stripe_top + j
            let idx = y * width + x
            if !sig_before_bp[idx] {
              continue
            }
            let bit_v = tier1_next_decision_bit(cursor)
            guard bit_v is Ok((bit, c1)) else {
              return Err("t1-recon: magref failed")
            }
            cursor = c1
            let v = values[idx]
            let delta = if (bit == 1) != (v < 0) { half } else { -half }
            values[idx] = v + delta
          }
        }
        stripe_top += 4
      }
    }
  }
  Ok((values, cursor.index))
}

///|
pub fn tier1_fixedpoint_sample_values_mini_block_pass_snapshots(
  width : Int,
  height : Int,
  coding_passes : Int,
  initial_bpno_plus_one : Int,
  decisions : Array[Int],
  code_block_style? : Int = 0,
) -> Result[(Array[Array[Int]], Int), String] {
  if width <= 0 || height <= 0 {
    return Err("mini block dimensions must be positive")
  }
  if coding_passes <= 0 {
    return Err("coding_passes must be positive")
  }
  if initial_bpno_plus_one < 0 {
    return Err("initial_bpno_plus_one must be non-negative")
  }
  let n = width * height
  let significant : Array[Bool] = []
  let sigprop_member : Array[Bool] = []
  let sig_before_bp : Array[Bool] = []
  let values : Array[Int] = []
  for _ in 0..<n {
    significant.push(false)
    sigprop_member.push(false)
    sig_before_bp.push(false)
    values.push(0)
  }
  let snapshots : Array[Array[Int]] = []
  let mut cursor : Tier1StagedBitCursor = { decisions, index: 0, }
  for i in 0..<coding_passes {
    let pass_kind = i % 3
    let bp = initial_bpno_plus_one - (i + 2) / 3
    if bp < 1 {
      continue
    }
    let one = if bp < 30 { 1 << bp } else { 0 }
    let half = one >> 1
    let oneplushalf = one | half
    if pass_kind == 0 {
      let mut stripe_top = 0
      while stripe_top < height {
        let stripe_h = if stripe_top + 4 <= height {
          4
        } else {
          height - stripe_top
        }
        for x in 0..<width {
          for j in 0..<stripe_h {
            let y = stripe_top + j
            if y >= height {
              continue
            }
            let idx = y * width + x
            if significant[idx] || sigprop_member[idx] {
              continue
            }
            let sig_v = tier1_next_decision_bit(cursor)
            guard sig_v is Ok((sig_bit, c1)) else {
              return Err("t1-recon-pass: cleanup sig failed")
            }
            cursor = c1
            if sig_bit == 0 {
              continue
            }
            let sign_v = tier1_next_decision_bit(cursor)
            guard sign_v is Ok((sbit, c2)) else {
              return Err("t1-recon-pass: cleanup sign failed")
            }
            cursor = c2
            significant[idx] = true
            values[idx] = if sbit == 0 { oneplushalf } else { -oneplushalf }
          }
        }
        stripe_top += 4
      }
      for k in 0..<n {
        sigprop_member[k] = false
      }
    } else if pass_kind == 1 {
      for k in 0..<n {
        sigprop_member[k] = false
        sig_before_bp[k] = significant[k]
      }
      let mut stripe_top = 0
      while stripe_top < height {
        let stripe_h = if stripe_top + 4 <= height {
          4
        } else {
          height - stripe_top
        }
        for x in 0..<width {
          for j in 0..<stripe_h {
            let y = stripe_top + j
            let idx = y * width + x
            if significant[idx] {
              continue
            }
            let vsc = (code_block_style & 0x08) != 0 && y % 4 == 3
            if !tier1_mini_block_has_sig_neighbor_flags(
                significant,
                width,
                height,
                x,
                y,
                mask_south=vsc,
              ) {
              continue
            }
            sigprop_member[idx] = true
            let sig_v = tier1_next_decision_bit(cursor)
            guard sig_v is Ok((sig_bit, c1)) else {
              return Err("t1-recon-pass: sigprop sig failed")
            }
            cursor = c1
            if sig_bit == 0 {
              continue
            }
            let sign_v = tier1_next_decision_bit(cursor)
            guard sign_v is Ok((sbit, c2)) else {
              return Err("t1-recon-pass: sigprop sign failed")
            }
            cursor = c2
            significant[idx] = true
            values[idx] = if sbit == 0 { oneplushalf } else { -oneplushalf }
          }
        }
        stripe_top += 4
      }
    } else {
      let mut stripe_top = 0
      while stripe_top < height {
        let stripe_h = if stripe_top + 4 <= height {
          4
        } else {
          height - stripe_top
        }
        for x in 0..<width {
          for j in 0..<stripe_h {
            let y = stripe_top + j
            let idx = y * width + x
            if !sig_before_bp[idx] {
              continue
            }
            let bit_v = tier1_next_decision_bit(cursor)
            guard bit_v is Ok((bit, c1)) else {
              return Err("t1-recon-pass: magref failed")
            }
            cursor = c1
            let v = values[idx]
            let delta = if (bit == 1) != (v < 0) { half } else { -half }
            values[idx] = v + delta
          }
        }
        stripe_top += 4
      }
    }
    let snapshot : Array[Int] = []
    for v in values {
      snapshot.push(v)
    }
    snapshots.push(snapshot)
  }
  Ok((snapshots, cursor.index))
}

///|
pub fn tier1_fixedpoint_sample_values_mini_block_target_pass_events(
  width : Int,
  height : Int,
  coding_passes : Int,
  initial_bpno_plus_one : Int,
  decisions : Array[Int],
  contexts : Array[Int],
  target_pass : Int,
  max_events? : Int = 256,
  code_block_style? : Int = 0,
) -> Result[(Array[String], Array[Int], Int), String] {
  if width <= 0 || height <= 0 {
    return Err("mini block dimensions must be positive")
  }
  if coding_passes <= 0 {
    return Err("coding_passes must be positive")
  }
  if initial_bpno_plus_one < 0 {
    return Err("initial_bpno_plus_one must be non-negative")
  }
  let n = width * height
  let significant : Array[Bool] = []
  let sigprop_member : Array[Bool] = []
  let sig_before_bp : Array[Bool] = []
  let values : Array[Int] = []
  for _ in 0..<n {
    significant.push(false)
    sigprop_member.push(false)
    sig_before_bp.push(false)
    values.push(0)
  }
  let events : Array[String] = []
  let event_indices : Array[Int] = []
  let mut cursor : Tier1StagedBitCursor = { decisions, index: 0, }
  for i in 0..<coding_passes {
    let pass_kind = i % 3
    let bp = initial_bpno_plus_one - (i + 2) / 3
    if bp < 1 {
      continue
    }
    let one = if bp < 30 { 1 << bp } else { 0 }
    let half = one >> 1
    let oneplushalf = one | half
    if pass_kind == 0 {
      let mut stripe_top = 0
      while stripe_top < height {
        let stripe_h = if stripe_top + 4 <= height {
          4
        } else {
          height - stripe_top
        }
        for x in 0..<width {
          for j in 0..<stripe_h {
            let y = stripe_top + j
            if y >= height {
              continue
            }
            let idx = y * width + x
            if significant[idx] || sigprop_member[idx] {
              continue
            }
            let sig_ctx = tier1_decision_context_at(contexts, cursor)
            let decision_index = cursor.index
            let sig_v = tier1_next_decision_bit(cursor)
            guard sig_v is Ok((sig_bit, c1)) else {
              return Err("t1-recon-events: cleanup sig failed")
            }
            cursor = c1
            if i == target_pass && events.length() < max_events {
              event_indices.push(decision_index)
              events.push(
                "pass=\{i} decision_index=\{decision_index} kind=cleanup-sig x=\{x} y=\{y} idx=\{idx} ctx=\{sig_ctx} bit=\{sig_bit}",
              )
            }
            if sig_bit == 0 {
              continue
            }
            let sign_ctx = tier1_decision_context_at(contexts, cursor)
            let sign_index = cursor.index
            let sign_v = tier1_next_decision_bit(cursor)
            guard sign_v is Ok((sbit, c2)) else {
              return Err("t1-recon-events: cleanup sign failed")
            }
            cursor = c2
            significant[idx] = true
            values[idx] = if sbit == 0 { oneplushalf } else { -oneplushalf }
            if i == target_pass && events.length() < max_events {
              event_indices.push(sign_index)
              events.push(
                "pass=\{i} decision_index=\{sign_index} kind=cleanup-sign x=\{x} y=\{y} idx=\{idx} ctx=\{sign_ctx} bit=\{sbit} after=\{values[idx]}",
              )
            }
          }
        }
        stripe_top += 4
      }
      for k in 0..<n {
        sigprop_member[k] = false
      }
    } else if pass_kind == 1 {
      for k in 0..<n {
        sigprop_member[k] = false
        sig_before_bp[k] = significant[k]
      }
      let mut stripe_top = 0
      while stripe_top < height {
        let stripe_h = if stripe_top + 4 <= height {
          4
        } else {
          height - stripe_top
        }
        for x in 0..<width {
          for j in 0..<stripe_h {
            let y = stripe_top + j
            let idx = y * width + x
            if significant[idx] {
              continue
            }
            let vsc = (code_block_style & 0x08) != 0 && y % 4 == 3
            if !tier1_mini_block_has_sig_neighbor_flags(
                significant,
                width,
                height,
                x,
                y,
                mask_south=vsc,
              ) {
              continue
            }
            sigprop_member[idx] = true
            let sig_ctx = tier1_decision_context_at(contexts, cursor)
            let decision_index = cursor.index
            let sig_v = tier1_next_decision_bit(cursor)
            guard sig_v is Ok((sig_bit, c1)) else {
              return Err("t1-recon-events: sigprop sig failed")
            }
            cursor = c1
            if i == target_pass && events.length() < max_events {
              event_indices.push(decision_index)
              events.push(
                "pass=\{i} decision_index=\{decision_index} kind=sigprop-sig x=\{x} y=\{y} idx=\{idx} ctx=\{sig_ctx} bit=\{sig_bit}",
              )
            }
            if sig_bit == 0 {
              continue
            }
            let sign_ctx = tier1_decision_context_at(contexts, cursor)
            let sign_index = cursor.index
            let sign_v = tier1_next_decision_bit(cursor)
            guard sign_v is Ok((sbit, c2)) else {
              return Err("t1-recon-events: sigprop sign failed")
            }
            cursor = c2
            significant[idx] = true
            values[idx] = if sbit == 0 { oneplushalf } else { -oneplushalf }
            if i == target_pass && events.length() < max_events {
              event_indices.push(sign_index)
              events.push(
                "pass=\{i} decision_index=\{sign_index} kind=sigprop-sign x=\{x} y=\{y} idx=\{idx} ctx=\{sign_ctx} bit=\{sbit} after=\{values[idx]}",
              )
            }
          }
        }
        stripe_top += 4
      }
    } else {
      let mut stripe_top = 0
      while stripe_top < height {
        let stripe_h = if stripe_top + 4 <= height {
          4
        } else {
          height - stripe_top
        }
        for x in 0..<width {
          for j in 0..<stripe_h {
            let y = stripe_top + j
            let idx = y * width + x
            if !sig_before_bp[idx] {
              continue
            }
            let mag_ctx = tier1_decision_context_at(contexts, cursor)
            let before = values[idx]
            let decision_index = cursor.index
            let bit_v = tier1_next_decision_bit(cursor)
            guard bit_v is Ok((bit, c1)) else {
              return Err("t1-recon-events: magref failed")
            }
            cursor = c1
            let delta = if (bit == 1) != (before < 0) { half } else { -half }
            values[idx] = before + delta
            if i == target_pass && events.length() < max_events {
              event_indices.push(decision_index)
              events.push(
                "pass=\{i} decision_index=\{decision_index} kind=magref x=\{x} y=\{y} idx=\{idx} ctx=\{mag_ctx} bit=\{bit} before=\{before} after=\{values[idx]}",
              )
            }
          }
        }
        stripe_top += 4
      }
    }
  }
  Ok((events, event_indices, cursor.index))
}

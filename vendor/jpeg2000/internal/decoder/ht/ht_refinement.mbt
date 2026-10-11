///|
// Spec grouping:
// - T.814 HT refinement segment decoding (passes=2/3)

///|
priv struct HtSigPropReader {
  source : Bytes
  mut pos : Int
  mut bits : Int
  mut tmp : Int
  mut last : Int
}

///|
priv struct HtMagRefReader {
  source : Bytes
  mut pos : Int
  mut bits : Int
  mut tmp : Int
  mut last : Int
}

///|
fn ht_sigprop_init(source : Bytes) -> HtSigPropReader {
  { source, pos: 0, bits: 0, tmp: 0, last: 0, }
}

///|
fn ht_sigprop_import_bit(reader : HtSigPropReader) -> Result[Int, String] {
  if reader.bits == 0 {
    let next = if reader.pos < reader.source.length() {
      let v = reader.source[reader.pos].to_int()
      reader.pos += 1
      v
    } else {
      0
    }
    reader.bits = if reader.last == 0xFF { 7 } else { 8 }
    if (next & (1 << reader.bits)) != 0 {
      return Err("ht refinement: invalid SigProp stuffing bit")
    }
    reader.tmp = next
    reader.last = next
  }
  let bit = reader.tmp & 1
  reader.tmp = reader.tmp >> 1
  reader.bits -= 1
  Ok(bit)
}

///|
fn ht_magref_init(source : Bytes) -> HtMagRefReader {
  { source, pos: source.length() - 1, bits: 0, tmp: 0, last: 0xFF, }
}

///|
fn ht_magref_import_bit(reader : HtMagRefReader) -> Int {
  if reader.bits == 0 {
    let next = if reader.pos >= 0 && reader.pos < reader.source.length() {
      let v = reader.source[reader.pos].to_int()
      reader.pos -= 1
      v
    } else {
      0
    }
    reader.bits = 8
    if reader.last > 0x8F && (next & 0x7F) == 0x7F {
      reader.bits = 7
    }
    reader.tmp = next
    reader.last = next
  }
  let bit = reader.tmp & 1
  reader.tmp = reader.tmp >> 1
  reader.bits -= 1
  bit
}

///|
fn ht_sigprop_has_cleanup_neighbor_flags(
  significant : Array[Bool],
  width : Int,
  height : Int,
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
      if nx < 0 || ny < 0 || nx >= width || ny >= height {
        continue
      }
      if significant[ny * width + nx] {
        return true
      }
    }
  }
  false
}

///|
fn htj2k_refinement_half_step(bitplanes_plus_one : Int) -> Result[Int, String] {
  if bitplanes_plus_one < 2 {
    return Err("ht refinement: no lower bit-plane available")
  }
  Ok(1 << (bitplanes_plus_one - 2))
}

///|
fn htj2k_sigprop_new_significant_value(
  bitplanes_plus_one : Int,
) -> Result[Int, String] {
  let half_step_v = htj2k_refinement_half_step(bitplanes_plus_one)
  guard half_step_v is Ok(half_step) else {
    return Err("ht refinement: invalid sigprop sample value")
  }
  Ok(half_step * 3)
}

///|
fn htj2k_apply_magref_bit(value : Int, half_step : Int, bit : Int) -> Int {
  let mag = if value < 0 { -value } else { value }
  let next_mag = if bit == 0 { mag - half_step } else { mag + half_step }
  if value < 0 {
    -next_mag
  } else {
    next_mag
  }
}

///|
fn ht_slice_bytes(
  source : Bytes,
  offset : Int,
  size : Int,
) -> Result[Bytes, String] {
  if offset < 0 || size < 0 || offset + size > source.length() {
    return Err("ht refinement: invalid segment bounds")
  }
  let out : Array[Byte] = []
  for i in offset..<(offset + size) {
    out.push(source[i])
  }
  Ok(Bytes::from_iter(out.iter()))
}

///|
pub struct HtSelectedSet {
  pub cleanup_segment : Bytes
  pub refinement_segment : Bytes
  pub z_blk : Int
  pub skipped_ht_sets : Int
}

///|
pub fn htj2k_select_active_set(
  codeword : Bytes,
  segment_lengths : Array[Int],
  per_segment_passes : Array[Int],
  passes : Int,
) -> Result[HtSelectedSet, String] {
  if passes <= 0 {
    return Err("ht refinement: coding passes must be positive")
  }
  if segment_lengths.length() == 0 || per_segment_passes.length() == 0 {
    if passes > 1 {
      return Err("ht refinement: missing HT segment lengths")
    }
    return Ok({
      cleanup_segment: codeword,
      refinement_segment: Bytes::new(0),
      z_blk: 1,
      skipped_ht_sets: 0,
    })
  }
  let count = if segment_lengths.length() < per_segment_passes.length() {
    segment_lengths.length()
  } else {
    per_segment_passes.length()
  }
  if count == 0 {
    return Err("ht refinement: missing HT segment lengths")
  }
  let mut signaled_passes = 0
  let mut signaled_length = 0
  for i in 0..<count {
    let seg_passes = per_segment_passes[i]
    if seg_passes > 0 {
      signaled_passes += seg_passes
      signaled_length += segment_lengths[i]
    }
  }
  if signaled_passes > passes {
    return Err("ht refinement: segment passes do not match coding passes")
  }
  if signaled_length != codeword.length() {
    return Err("ht refinement: segment lengths do not cover codeword")
  }
  let placeholder_passes = passes - signaled_passes
  if placeholder_passes % 3 != 0 {
    return Err("ht refinement: unsupported HT placeholder pass layout")
  }
  let mut completed_sets = placeholder_passes / 3
  let mut byte_offset = 0
  let mut slot_index = 0
  let mut have_current = false
  let mut current_cleanup = Bytes::new(0)
  let mut current_refinement = Bytes::new(0)
  let mut current_z_blk = 0
  let mut current_skipped_ht_sets = 0
  let mut have_selected = false
  let mut selected_cleanup = Bytes::new(0)
  let mut selected_refinement = Bytes::new(0)
  let mut selected_z_blk = 0
  let mut selected_skipped_ht_sets = 0
  for i in 0..<count {
    let seg_passes = per_segment_passes[i]
    if seg_passes <= 0 {
      continue
    }
    let seg_len = segment_lengths[i]
    let seg_v = ht_slice_bytes(codeword, byte_offset, seg_len)
    guard seg_v is Ok(segment) else {
      return Err("ht refinement: failed to slice HT segment")
    }
    byte_offset += seg_len
    if slot_index % 2 == 0 {
      if seg_passes != 1 {
        return Err("ht refinement: invalid HT cleanup segment pass count")
      }
      if have_current {
        if current_z_blk > 0 {
          have_selected = true
          selected_cleanup = current_cleanup
          selected_refinement = current_refinement
          selected_z_blk = current_z_blk
          selected_skipped_ht_sets = current_skipped_ht_sets
        }
        completed_sets += 1
      }
      have_current = true
      current_cleanup = segment
      current_refinement = Bytes::new(0)
      current_z_blk = if seg_len == 0 { 0 } else { 1 }
      current_skipped_ht_sets = completed_sets
    } else {
      if !have_current {
        return Err("ht refinement: refinement segment without cleanup segment")
      }
      if seg_passes <= 0 || seg_passes > 2 {
        return Err("ht refinement: invalid HT refinement segment pass count")
      }
      current_refinement = segment
      if current_z_blk == 0 {
        if seg_len > 0 {
          return Err(
            "ht refinement: refinement segment without cleanup segment",
          )
        }
      } else if seg_len > 0 {
        current_z_blk = 1 + seg_passes
      }
    }
    slot_index += 1
  }
  if have_current && current_z_blk > 0 {
    have_selected = true
    selected_cleanup = current_cleanup
    selected_refinement = current_refinement
    selected_z_blk = current_z_blk
    selected_skipped_ht_sets = current_skipped_ht_sets
  }
  if !have_selected {
    return Err("ht refinement: no non-empty HT set found")
  }
  Ok({
    cleanup_segment: selected_cleanup,
    refinement_segment: selected_refinement,
    z_blk: selected_z_blk,
    skipped_ht_sets: selected_skipped_ht_sets,
  })
}

///|
pub fn htj2k_apply_refinement_segment(
  base_values : Array[Int],
  cleanup_significant : Array[Bool],
  refinement_segment : Bytes,
  cb_w : Int,
  cb_h : Int,
  bitplanes_plus_one : Int,
  z_blk : Int,
  code_block_style : Int,
) -> Result[Array[Int], String] {
  if z_blk <= 1 || refinement_segment.length() == 0 {
    return Ok(base_values)
  }
  let half_step_v = htj2k_refinement_half_step(bitplanes_plus_one)
  guard half_step_v is Ok(refinement_half_step) else {
    return Err("ht refinement: invalid refinement half-step")
  }
  let sigprop_value_v = htj2k_sigprop_new_significant_value(bitplanes_plus_one)
  guard sigprop_value_v is Ok(sigprop_value) else {
    return Err("ht refinement: invalid SigProp sample value")
  }
  let values = base_values.copy()
  let n = cb_w * cb_h
  if cleanup_significant.length() != n || values.length() != n {
    return Err("ht refinement: code-block state size mismatch")
  }
  let significant = cleanup_significant.copy()
  let sigprop_refined : Array[Bool] = Array::make(n, false)
  let sigprop = ht_sigprop_init(refinement_segment)
  let mut stripe_top = 0
  while stripe_top < cb_h {
    let stripe_h = if stripe_top + 4 <= cb_h { 4 } else { cb_h - stripe_top }
    let mut group_x = 0
    while group_x < cb_w {
      let group_end = if group_x + 4 <= cb_w { group_x + 4 } else { cb_w }
      for x in group_x..<group_end {
        for j in 0..<stripe_h {
          let y = stripe_top + j
          let idx = y * cb_w + x
          if significant[idx] {
            continue
          }
          let vsc = (code_block_style & 0x08) != 0 && y % 4 == 3
          let has_sig = ht_sigprop_has_cleanup_neighbor_flags(
            significant,
            cb_w,
            cb_h,
            x,
            y,
            mask_south=vsc,
          )
          if !has_sig {
            continue
          }
          let bit_v = ht_sigprop_import_bit(sigprop)
          guard bit_v is Ok(bit) else {
            return Err("ht refinement: failed to read SigProp magnitude bit")
          }
          if bit == 1 {
            significant[idx] = true
            sigprop_refined[idx] = true
          }
        }
      }
      for x in group_x..<group_end {
        for j in 0..<stripe_h {
          let y = stripe_top + j
          let idx = y * cb_w + x
          if !sigprop_refined[idx] {
            continue
          }
          let sign_v = ht_sigprop_import_bit(sigprop)
          guard sign_v is Ok(sign_bit) else {
            return Err("ht refinement: failed to read SigProp sign bit")
          }
          values[idx] = if sign_bit == 0 {
            sigprop_value
          } else {
            -sigprop_value
          }
        }
      }
      group_x += 4
    }
    stripe_top += 4
  }
  if z_blk == 3 {
    let magref = ht_magref_init(refinement_segment)
    let mut mr_stripe_top = 0
    while mr_stripe_top < cb_h {
      let stripe_h = if mr_stripe_top + 4 <= cb_h {
        4
      } else {
        cb_h - mr_stripe_top
      }
      for x in 0..<cb_w {
        for j in 0..<stripe_h {
          let y = mr_stripe_top + j
          let idx = y * cb_w + x
          if !cleanup_significant[idx] {
            continue
          }
          let bit = ht_magref_import_bit(magref)
          values[idx] = htj2k_apply_magref_bit(
            values[idx],
            refinement_half_step,
            bit,
          )
        }
      }
      mr_stripe_top += 4
    }
  }
  Ok(values)
}

///|
fn htj2k_fix_cleanup_sign_magnitude(value : Int) -> Int {
  let raw = value.reinterpret_as_uint()
  let mag = (raw & 0x7FFF_FFFFU).reinterpret_as_int()
  if (raw & 0x8000_0000U) != 0U {
    -mag
  } else {
    mag
  }
}

///|
pub fn htj2k_decode_single_set_fixedpoint(
  codeword : Bytes,
  passes : Int,
  segment_lengths : Array[Int],
  per_segment_passes : Array[Int],
  cb_w : Int,
  cb_h : Int,
  bitplanes_plus_one : Int,
  zero_bit_planes : Int,
  code_block_style : Int,
) -> Result[Array[Int], String] {
  let seg_v = htj2k_select_active_set(
    codeword, segment_lengths, per_segment_passes, passes,
  )
  guard seg_v is Ok(selected) else {
    return Err("ht refinement: failed to select active HT set")
  }
  let set_bitplanes_plus_one = bitplanes_plus_one - selected.skipped_ht_sets
  let set_zero_bit_planes = zero_bit_planes + selected.skipped_ht_sets
  if set_bitplanes_plus_one <= 0 {
    return Err("ht refinement: exhausted HT bit-planes")
  }
  let cleanup_v = htj2k_decode_cleanup_only_fixedpoint(
    selected.cleanup_segment,
    cb_w,
    cb_h,
    set_bitplanes_plus_one,
    set_zero_bit_planes,
  )
  guard cleanup_v is Ok(cleanup_values) else {
    return Err("ht refinement: cleanup decode failed")
  }
  let cleanup_significant : Array[Bool] = []
  let fixed_values : Array[Int] = []
  for raw_value in cleanup_values {
    let fixed = htj2k_fix_cleanup_sign_magnitude(raw_value)
    cleanup_significant.push(fixed != 0)
    fixed_values.push(fixed)
  }
  htj2k_apply_refinement_segment(
    fixed_values,
    cleanup_significant,
    selected.refinement_segment,
    cb_w,
    cb_h,
    set_bitplanes_plus_one,
    selected.z_blk,
    code_block_style,
  )
}

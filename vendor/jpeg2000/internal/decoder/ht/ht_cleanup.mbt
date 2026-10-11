///|
// Spec grouping:
// - T.814 cleanup-only HT block decoding (passes=1)

///|
priv struct HtMelReader {
  source : Bytes
  mut data_pos : Int
  mut size : Int
  mut tmp : UInt64
  mut bits : Int
  mut unstuff : Bool
  mut k : Int
  mut num_runs : Int
  mut runs : UInt64
}

///|
priv struct HtRevReader {
  source : Bytes
  mut data_pos : Int
  mut size : Int
  mut tmp : UInt64
  mut bits : Int
  mut unstuff : Bool
}

///|
priv struct HtForwardReader {
  source : Bytes
  mut data_pos : Int
  mut size : Int
  mut tmp : UInt64
  mut bits : Int
  mut unstuff : Bool
  fill_byte : Int
}

///|
fn ht_low_mask(bits : Int) -> UInt {
  if bits <= 0 {
    return 0U
  }
  if bits >= 32 {
    return 0xFFFF_FFFFU
  }
  (1U << bits) - 1U
}

///|
fn ht_count_leading_zeros(v : UInt) -> Int {
  if v == 0U {
    return 32
  }
  let mut n = 0
  let mut bit = 31
  while bit >= 0 {
    if ((v >> bit) & 1U) != 0U {
      break
    }
    n += 1
    bit -= 1
  }
  n
}

///|
fn ht_mel_init(source : Bytes, lcup : Int, scup : Int) -> HtMelReader {
  let reader = {
    source,
    data_pos: lcup - scup,
    size: scup - 1,
    tmp: 0,
    bits: 0,
    unstuff: false,
    k: 0,
    num_runs: 0,
    runs: 0,
  }
  let preload = if reader.size < 4 { reader.size } else { 4 }
  let mut count = 0
  while count < preload {
    let mut d = 0xFF
    if reader.size > 0 && reader.data_pos < reader.source.length() {
      d = reader.source[reader.data_pos].to_int()
      if reader.size == 1 {
        d = d | 0x0F
      }
      reader.data_pos += 1
      reader.size -= 1
    }
    let d_bits = 8 - (if reader.unstuff { 1 } else { 0 })
    reader.tmp = (reader.tmp << d_bits) | d.to_uint64()
    reader.bits += d_bits
    reader.unstuff = d == 0xFF
    count += 1
  }
  if reader.bits > 0 {
    reader.tmp = reader.tmp << (64 - reader.bits)
  }
  reader
}

///|
fn ht_mel_read(reader : HtMelReader) -> Result[Unit, String] {
  if reader.bits > 32 {
    return Ok(())
  }
  let mut t : UInt64 = 0
  let mut added_bits = 0
  let mut read_count = 0
  while reader.bits <= 32 && read_count < 4 {
    let mut d = 0xFF
    if reader.size > 0 && reader.data_pos < reader.source.length() {
      d = reader.source[reader.data_pos].to_int()
      if reader.size == 1 {
        d = d | 0x0F
      }
      reader.data_pos += 1
      reader.size -= 1
    }
    let d_bits = 8 - (if reader.unstuff { 1 } else { 0 })
    t = (t << d_bits) | d.to_uint64()
    added_bits += d_bits
    reader.bits += d_bits
    reader.unstuff = d == 0xFF
    read_count += 1
  }
  if added_bits > 0 {
    reader.tmp = reader.tmp | (t << (64 - reader.bits))
  }
  Ok(())
}

///|
fn ht_mel_decode(reader : HtMelReader) -> Result[Unit, String] {
  let mel_exp = [0, 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 4, 5]
  if reader.bits < 6 {
    let fill_v = ht_mel_read(reader)
    guard fill_v is Ok(_) else { return Err("ht cleanup: MEL fill failed") }
  }
  while reader.bits >= 6 && reader.num_runs < 8 {
    let eval = mel_exp[reader.k]
    let mut run = 0
    if (reader.tmp & (1UL << 63)) != 0 {
      run = (1 << eval) - 1
      reader.k = if reader.k + 1 < 12 { reader.k + 1 } else { 12 }
      reader.tmp = reader.tmp << 1
      reader.bits -= 1
      run = run << 1
    } else {
      run = ((reader.tmp >> (63 - eval)) & ht_low_mask(eval).to_uint64()).to_int()
      reader.k = if reader.k - 1 > 0 { reader.k - 1 } else { 0 }
      reader.tmp = reader.tmp << (eval + 1)
      reader.bits -= eval + 1
      run = (run << 1) + 1
    }
    let at = reader.num_runs * 7
    let clear_mask = 0xFFFF_FFFF_FFFF_FFFFUL ^ (0x7FUL << at)
    reader.runs = reader.runs & clear_mask
    reader.runs = reader.runs | (run.to_uint64() << at)
    reader.num_runs += 1
  }
  Ok(())
}

///|
fn ht_mel_get_run(reader : HtMelReader) -> Result[Int, String] {
  if reader.num_runs == 0 {
    let decode_v = ht_mel_decode(reader)
    guard decode_v is Ok(_) else { return Err("ht cleanup: MEL decode failed") }
  }
  if reader.num_runs == 0 {
    return Err("ht cleanup: MEL run queue empty")
  }
  let t = (reader.runs & 0x7FUL).to_int()
  reader.runs = reader.runs >> 7
  reader.num_runs -= 1
  Ok(t)
}

///|
fn ht_rev_init(
  source : Bytes,
  lcup : Int,
  scup : Int,
) -> Result[HtRevReader, String] {
  if lcup < 2 || scup < 2 {
    return Err("ht cleanup: invalid VLC segment length")
  }
  let d = source[lcup - 2].to_int()
  let reader = {
    source,
    data_pos: lcup - 3,
    size: scup - 2,
    tmp: (d >> 4).to_uint64(),
    bits: 4 - (if ((d >> 4) & 0x7) == 0x7 { 1 } else { 0 }),
    unstuff: (d | 0x0F) > 0x8F,
  }
  ht_rev_read(reader)
  Ok(reader)
}

///|
fn ht_rev_read(reader : HtRevReader, min_bits? : Int = 48) -> Unit {
  while reader.bits < min_bits {
    let d = if reader.size > 0 &&
      reader.data_pos >= 0 &&
      reader.data_pos < reader.source.length() {
      let v = reader.source[reader.data_pos].to_uint64()
      reader.data_pos -= 1
      reader.size -= 1
      v
    } else {
      0UL
    }
    let d_bits = 8 -
      (if reader.unstuff && (d & 0x7FUL) == 0x7FUL { 1 } else { 0 })
    reader.tmp = reader.tmp | (d << reader.bits)
    reader.bits += d_bits
    reader.unstuff = d > 0x8FUL
  }
}

///|
fn ht_rev_fetch(reader : HtRevReader) -> UInt {
  if reader.bits < 32 {
    ht_rev_read(reader)
    if reader.bits < 32 {
      ht_rev_read(reader)
    }
  }
  reader.tmp.to_uint()
}

///|
fn ht_rev_advance(reader : HtRevReader, num_bits : Int) -> UInt {
  reader.tmp = reader.tmp >> num_bits
  reader.bits -= num_bits
  reader.tmp.to_uint()
}

///|
fn ht_frwd_init(
  source : Bytes,
  data_pos : Int,
  size : Int,
  fill_byte : Int,
) -> HtForwardReader {
  { source, data_pos, size, tmp: 0, bits: 0, unstuff: false, fill_byte, }
}

///|
fn ht_frwd_read(reader : HtForwardReader) -> Unit {
  if reader.bits > 32 {
    return
  }
  let mut read_count = 0
  while reader.bits <= 32 && read_count < 4 {
    let d = if reader.size > 0 && reader.data_pos < reader.source.length() {
      let v = reader.source[reader.data_pos].to_int()
      reader.data_pos += 1
      reader.size -= 1
      v
    } else {
      reader.fill_byte
    }
    let d_bits = 8 - (if reader.unstuff { 1 } else { 0 })
    reader.tmp = reader.tmp | (d.to_uint64() << reader.bits)
    reader.bits += d_bits
    reader.unstuff = d == 0xFF
    read_count += 1
  }
}

///|
fn ht_frwd_advance(reader : HtForwardReader, num_bits : Int) -> Unit {
  reader.tmp = reader.tmp >> num_bits
  reader.bits -= num_bits
}

///|
fn ht_frwd_fetch(reader : HtForwardReader) -> UInt {
  if reader.bits < 32 {
    ht_frwd_read(reader)
    if reader.bits < 32 {
      ht_frwd_read(reader)
    }
  }
  reader.tmp.to_uint()
}

///|
fn ht_decode_init_uvlc(vlc : UInt, mode : Int) -> (UInt, UInt, Int) {
  let dec = [
    3 | (5 << 2) | (5 << 5),
    1 | (0 << 2) | (1 << 5),
    2 | (0 << 2) | (2 << 5),
    1 | (0 << 2) | (1 << 5),
    3 | (1 << 2) | (3 << 5),
    1 | (0 << 2) | (1 << 5),
    2 | (0 << 2) | (2 << 5),
    1 | (0 << 2) | (1 << 5),
  ]
  let mut cwd = vlc
  let mut consumed = 0
  let mut u0 = 1U
  let mut u1 = 1U
  if mode == 0 {
    return (u0, u1, consumed)
  }
  if mode <= 2 {
    let d = dec[(cwd & 0x7U).reinterpret_as_int()]
    cwd = cwd >> (d & 0x3)
    consumed += d & 0x3
    let suffix_len = (d >> 2) & 0x7
    consumed += suffix_len
    let u = (d >> 5) + (cwd & ht_low_mask(suffix_len)).reinterpret_as_int()
    if mode == 1 {
      u0 = (u + 1).reinterpret_as_uint()
    } else {
      u1 = (u + 1).reinterpret_as_uint()
    }
    return (u0, u1, consumed)
  }
  if mode == 3 {
    let mut d1 = dec[(cwd & 0x7U).reinterpret_as_int()]
    cwd = cwd >> (d1 & 0x3)
    consumed += d1 & 0x3
    if (d1 & 0x3) > 2 {
      u1 = ((cwd & 1U).reinterpret_as_int() + 2).reinterpret_as_uint()
      consumed += 1
      cwd = cwd >> 1
      let suffix_len = (d1 >> 2) & 0x7
      consumed += suffix_len
      d1 = (d1 >> 5) + (cwd & ht_low_mask(suffix_len)).reinterpret_as_int()
      u0 = (d1 + 1).reinterpret_as_uint()
    } else {
      let mut d2 = dec[(cwd & 0x7U).reinterpret_as_int()]
      cwd = cwd >> (d2 & 0x3)
      consumed += d2 & 0x3
      let mut suffix_len = (d1 >> 2) & 0x7
      consumed += suffix_len
      d1 = (d1 >> 5) + (cwd & ht_low_mask(suffix_len)).reinterpret_as_int()
      u0 = (d1 + 1).reinterpret_as_uint()
      cwd = cwd >> suffix_len
      suffix_len = (d2 >> 2) & 0x7
      consumed += suffix_len
      d2 = (d2 >> 5) + (cwd & ht_low_mask(suffix_len)).reinterpret_as_int()
      u1 = (d2 + 1).reinterpret_as_uint()
    }
    return (u0, u1, consumed)
  }
  let mut d1 = dec[(cwd & 0x7U).reinterpret_as_int()]
  cwd = cwd >> (d1 & 0x3)
  consumed += d1 & 0x3
  let mut d2 = dec[(cwd & 0x7U).reinterpret_as_int()]
  cwd = cwd >> (d2 & 0x3)
  consumed += d2 & 0x3
  let mut suffix_len = (d1 >> 2) & 0x7
  consumed += suffix_len
  d1 = (d1 >> 5) + (cwd & ht_low_mask(suffix_len)).reinterpret_as_int()
  u0 = (d1 + 3).reinterpret_as_uint()
  cwd = cwd >> suffix_len
  suffix_len = (d2 >> 2) & 0x7
  consumed += suffix_len
  d2 = (d2 >> 5) + (cwd & ht_low_mask(suffix_len)).reinterpret_as_int()
  u1 = (d2 + 3).reinterpret_as_uint()
  (u0, u1, consumed)
}

///|
fn ht_decode_noninit_uvlc(vlc : UInt, mode : Int) -> (UInt, UInt, Int) {
  let dec = [
    3 | (5 << 2) | (5 << 5),
    1 | (0 << 2) | (1 << 5),
    2 | (0 << 2) | (2 << 5),
    1 | (0 << 2) | (1 << 5),
    3 | (1 << 2) | (3 << 5),
    1 | (0 << 2) | (1 << 5),
    2 | (0 << 2) | (2 << 5),
    1 | (0 << 2) | (1 << 5),
  ]
  let mut cwd = vlc
  let mut consumed = 0
  let mut u0 = 1U
  let mut u1 = 1U
  if mode == 0 {
    return (u0, u1, consumed)
  }
  if mode <= 2 {
    let d = dec[(cwd & 0x7U).reinterpret_as_int()]
    cwd = cwd >> (d & 0x3)
    consumed += d & 0x3
    let suffix_len = (d >> 2) & 0x7
    consumed += suffix_len
    let u = (d >> 5) + (cwd & ht_low_mask(suffix_len)).reinterpret_as_int()
    if mode == 1 {
      u0 = (u + 1).reinterpret_as_uint()
    } else {
      u1 = (u + 1).reinterpret_as_uint()
    }
    return (u0, u1, consumed)
  }
  let mut d1 = dec[(cwd & 0x7U).reinterpret_as_int()]
  cwd = cwd >> (d1 & 0x3)
  consumed += d1 & 0x3
  let mut d2 = dec[(cwd & 0x7U).reinterpret_as_int()]
  cwd = cwd >> (d2 & 0x3)
  consumed += d2 & 0x3
  let mut suffix_len = (d1 >> 2) & 0x7
  consumed += suffix_len
  d1 = (d1 >> 5) + (cwd & ht_low_mask(suffix_len)).reinterpret_as_int()
  u0 = (d1 + 1).reinterpret_as_uint()
  cwd = cwd >> suffix_len
  suffix_len = (d2 >> 2) & 0x7
  consumed += suffix_len
  d2 = (d2 >> 5) + (cwd & ht_low_mask(suffix_len)).reinterpret_as_int()
  u1 = (d2 + 1).reinterpret_as_uint()
  (u0, u1, consumed)
}

///|
fn ht_cleanup_decode_sample(
  magsgn : HtForwardReader,
  qinf : UInt,
  emb_shift : Int,
  u_q : UInt,
  bitplanes_plus_one : Int,
) -> Result[(Int, Int), String] {
  let m_n = u_q.reinterpret_as_int() -
    ((qinf >> emb_shift) & 1U).reinterpret_as_int()
  if m_n < 0 {
    return Err("ht cleanup: negative m_n")
  }
  let ms_val = ht_frwd_fetch(magsgn)
  ht_frwd_advance(magsgn, m_n)
  let mut v_n = ms_val & ht_low_mask(m_n)
  v_n = v_n | (((qinf >> (emb_shift - 4)) & 1U) << m_n)
  v_n = v_n | 1U
  let raw = ((ms_val << 31) | ((v_n + 2U) << (bitplanes_plus_one - 1))).reinterpret_as_int()
  Ok((raw, 32 - ht_count_leading_zeros(v_n)))
}

///|
fn ht_maybe_set_cleanup_sample(
  output : Array[Int],
  idx : Int,
  locs : Int,
  loc_mask : Int,
  qinf : UInt,
  sig_mask : UInt,
  magsgn : HtForwardReader,
  emb_shift : Int,
  u_q : UInt,
  bitplanes_plus_one : Int,
) -> Result[Int, String] {
  if (qinf & sig_mask) != 0U {
    let sample_v = ht_cleanup_decode_sample(
      magsgn, qinf, emb_shift, u_q, bitplanes_plus_one,
    )
    guard sample_v is Ok((sample, exponent)) else {
      return Err("ht cleanup: sample decode failed")
    }
    output[idx] = sample
    return Ok(exponent)
  }
  if (locs & loc_mask) != 0 {
    output[idx] = 0
  }
  Ok(0)
}

///|
fn ht_cleanup_only_decode_raw_values(
  codeword : Bytes,
  cb_w : Int,
  cb_h : Int,
  bitplanes_plus_one : Int,
  zero_bit_planes : Int,
) -> Result[Array[Int], String] {
  if cb_w <= 0 || cb_h <= 0 {
    return Ok([])
  }
  let lcup = codeword.length()
  if lcup < 2 {
    return Err("ht cleanup: invalid cleanup segment length")
  }
  let scup = (codeword[lcup - 1].to_int() << 4) |
    (codeword[lcup - 2].to_int() & 0x0F)
  if scup < 2 || scup > lcup || scup > 4079 {
    return Err("ht cleanup: invalid Scup")
  }
  if bitplanes_plus_one <= 0 {
    return Err("ht cleanup: invalid bit-plane count")
  }
  let zero_bplanes_p1 = zero_bit_planes + 1
  let mel = ht_mel_init(codeword, lcup, scup)
  let vlc_v = ht_rev_init(codeword, lcup, scup)
  guard vlc_v is Ok(vlc0) else { return Err("ht cleanup: VLC init failed") }
  let vlc = vlc0
  let magsgn = ht_frwd_init(codeword, 0, lcup - scup, 0xFF)
  let output : Array[Int] = []
  for _ in 0..<(cb_w * cb_h) {
    output.push(0)
  }
  let quad_count = (cb_w + 1) / 2
  let line_state : Array[Int] = []
  for _ in 0..<(quad_count + 3) {
    line_state.push(0)
  }
  let run_v = ht_mel_get_run(mel)
  guard run_v is Ok(run0) else {
    let preview : Array[Int] = []
    let preview_len = if codeword.length() < 8 { codeword.length() } else { 8 }
    for i in 0..<preview_len {
      preview.push(codeword[i].to_int())
    }
    return Err(
      "ht cleanup: initial MEL run missing (lcup=\{lcup} scup=\{scup} mel_size=\{mel.size} mel_bits=\{mel.bits} preview=\{preview})",
    )
  }
  let mut run = run0
  let mut qinf0 = 0U
  let mut qinf1 = 0U
  let mut c_q = 0
  let stride = cb_w
  let mut lsp_idx = 0
  line_state[0] = 0
  let mut sp_idx = 0
  let mut x = 0
  while x < cb_w {
    let fetch_bits = ht_rev_fetch(vlc)
    let mut vlc_val = fetch_bits
    qinf0 = ht_vlc_tbl0[(c_q << 7) | (vlc_val & 0x7FU).reinterpret_as_int()].reinterpret_as_uint()
    if c_q == 0 {
      run -= 2
      qinf0 = if run == -1 { qinf0 } else { 0U }
      if run < 0 {
        let next_run_v = ht_mel_get_run(mel)
        guard next_run_v is Ok(next_run) else {
          return Err("ht cleanup: MEL run underflow")
        }
        run = next_run
      }
    }
    c_q = (((qinf0 & 0x10U) >> 4) | ((qinf0 & 0xE0U) >> 5)).reinterpret_as_int()
    vlc_val = ht_rev_advance(vlc, (qinf0 & 0x7U).reinterpret_as_int())
    qinf1 = 0U
    if x + 2 < cb_w {
      qinf1 = ht_vlc_tbl0[(c_q << 7) | (vlc_val & 0x7FU).reinterpret_as_int()].reinterpret_as_uint()
      if c_q == 0 {
        run -= 2
        qinf1 = if run == -1 { qinf1 } else { 0U }
        if run < 0 {
          let next_run_v = ht_mel_get_run(mel)
          guard next_run_v is Ok(next_run) else {
            return Err("ht cleanup: MEL run underflow")
          }
          run = next_run
        }
      }
      c_q = (((qinf1 & 0x10U) >> 4) | ((qinf1 & 0xE0U) >> 5)).reinterpret_as_int()
      vlc_val = ht_rev_advance(vlc, (qinf1 & 0x7U).reinterpret_as_int())
    }
    let mut uvlc_mode = (((qinf0 & 0x8U) >> 3) | ((qinf1 & 0x8U) >> 2)).reinterpret_as_int()
    if uvlc_mode == 3 {
      run -= 2
      uvlc_mode = uvlc_mode + (if run == -1 { 1 } else { 0 })
      if run < 0 {
        let next_run_v = ht_mel_get_run(mel)
        guard next_run_v is Ok(next_run) else {
          return Err("ht cleanup: MEL run underflow")
        }
        run = next_run
      }
    }
    let (u0, u1, consumed_bits) = ht_decode_init_uvlc(vlc_val, uvlc_mode)
    if u0.reinterpret_as_int() > zero_bplanes_p1 ||
      u1.reinterpret_as_int() > zero_bplanes_p1 {
      return Err("ht cleanup: U_q exceeds zero bit-planes + 1")
    }
    let _ = ht_rev_advance(vlc, consumed_bits)
    let mut locs = 0xFF
    if x + 4 > cb_w {
      locs = locs >> ((x + 4 - cb_w) << 1)
    }
    locs = if cb_h > 1 { locs } else { locs & 0x55 }
    if (
        (((qinf0 & 0xF0U) >> 4) | (qinf1 & 0xF0U)).reinterpret_as_int() &
        (0xFF ^ locs)
      ) !=
      0 {
      return Err("ht cleanup: significant samples outside code-block area")
    }
    let _ = ht_maybe_set_cleanup_sample(
      output, sp_idx, locs, 0x1, qinf0, 0x10U, magsgn, 12, u0, bitplanes_plus_one,
    )
    let e_n0_v = ht_maybe_set_cleanup_sample(
      output,
      sp_idx + stride,
      locs,
      0x2,
      qinf0,
      0x20U,
      magsgn,
      13,
      u0,
      bitplanes_plus_one,
    )
    guard e_n0_v is Ok(e_n0) else {
      return Err("ht cleanup: row0 sample decode failed")
    }
    if e_n0 > 0 {
      let t = line_state[lsp_idx] & 0x7F
      line_state[lsp_idx] = 0x80 | (if t > e_n0 { t } else { e_n0 })
    }
    lsp_idx += 1
    sp_idx += 1
    let _ = ht_maybe_set_cleanup_sample(
      output, sp_idx, locs, 0x4, qinf0, 0x40U, magsgn, 14, u0, bitplanes_plus_one,
    )
    let e_nw0_v = ht_maybe_set_cleanup_sample(
      output,
      sp_idx + stride,
      locs,
      0x8,
      qinf0,
      0x80U,
      magsgn,
      15,
      u0,
      bitplanes_plus_one,
    )
    guard e_nw0_v is Ok(e_nw0) else {
      return Err("ht cleanup: row1 sample decode failed")
    }
    line_state[lsp_idx] = if e_nw0 > 0 { 0x80 | e_nw0 } else { 0 }
    sp_idx += 1
    let _ = ht_maybe_set_cleanup_sample(
      output, sp_idx, locs, 0x10, qinf1, 0x10U, magsgn, 12, u1, bitplanes_plus_one,
    )
    let e_n1_v = ht_maybe_set_cleanup_sample(
      output,
      sp_idx + stride,
      locs,
      0x20,
      qinf1,
      0x20U,
      magsgn,
      13,
      u1,
      bitplanes_plus_one,
    )
    guard e_n1_v is Ok(e_n1) else {
      return Err("ht cleanup: row0 second-quad decode failed")
    }
    if e_n1 > 0 {
      let t = line_state[lsp_idx] & 0x7F
      line_state[lsp_idx] = 0x80 | (if t > e_n1 { t } else { e_n1 })
    }
    lsp_idx += 1
    sp_idx += 1
    let _ = ht_maybe_set_cleanup_sample(
      output, sp_idx, locs, 0x40, qinf1, 0x40U, magsgn, 14, u1, bitplanes_plus_one,
    )
    let e_nw1_v = ht_maybe_set_cleanup_sample(
      output,
      sp_idx + stride,
      locs,
      0x80,
      qinf1,
      0x80U,
      magsgn,
      15,
      u1,
      bitplanes_plus_one,
    )
    guard e_nw1_v is Ok(e_nw1) else {
      return Err("ht cleanup: row1 second-quad decode failed")
    }
    line_state[lsp_idx] = if e_nw1 > 0 { 0x80 | e_nw1 } else { 0 }
    sp_idx += 1
    x = x + 4
  }
  let mut y = 2
  while y < cb_h {
    let mut ls0 = line_state[0]
    line_state[0] = 0
    lsp_idx = 0
    sp_idx = y * stride
    c_q = 0
    x = 0
    while x < cb_w {
      c_q = c_q | (ls0 >> 7)
      c_q = c_q | ((line_state[lsp_idx + 1] >> 5) & 0x4)
      let fetch_bits = ht_rev_fetch(vlc)
      let mut vlc_val = fetch_bits
      qinf0 = ht_vlc_tbl1[(c_q << 7) | (vlc_val & 0x7FU).reinterpret_as_int()].reinterpret_as_uint()
      if c_q == 0 {
        run -= 2
        qinf0 = if run == -1 { qinf0 } else { 0U }
        if run < 0 {
          let next_run_v = ht_mel_get_run(mel)
          guard next_run_v is Ok(next_run) else {
            return Err("ht cleanup: MEL run underflow")
          }
          run = next_run
        }
      }
      c_q = (((qinf0 & 0x40U) >> 5) | ((qinf0 & 0x80U) >> 6)).reinterpret_as_int()
      vlc_val = ht_rev_advance(vlc, (qinf0 & 0x7U).reinterpret_as_int())
      qinf1 = 0U
      if x + 2 < cb_w {
        c_q = c_q | (line_state[lsp_idx + 1] >> 7)
        c_q = c_q | ((line_state[lsp_idx + 2] >> 5) & 0x4)
        qinf1 = ht_vlc_tbl1[(c_q << 7) | (vlc_val & 0x7FU).reinterpret_as_int()].reinterpret_as_uint()
        if c_q == 0 {
          run -= 2
          qinf1 = if run == -1 { qinf1 } else { 0U }
          if run < 0 {
            let next_run_v = ht_mel_get_run(mel)
            guard next_run_v is Ok(next_run) else {
              return Err("ht cleanup: MEL run underflow")
            }
            run = next_run
          }
        }
        c_q = (((qinf1 & 0x40U) >> 5) | ((qinf1 & 0x80U) >> 6)).reinterpret_as_int()
        vlc_val = ht_rev_advance(vlc, (qinf1 & 0x7U).reinterpret_as_int())
      }
      let uvlc_mode = (((qinf0 & 0x8U) >> 3) | ((qinf1 & 0x8U) >> 2)).reinterpret_as_int()
      let (u0_v, u1_v, consumed_bits) = ht_decode_noninit_uvlc(
        vlc_val, uvlc_mode,
      )
      let mut u0 = u0_v
      let mut u1 = u1_v
      let _ = ht_rev_advance(vlc, consumed_bits)
      if (qinf0 & 0xF0U & ((qinf0 & 0xF0U) - 1U)) != 0U {
        let mut e = ls0 & 0x7F
        let e1 = line_state[lsp_idx + 1] & 0x7F
        e = if e > e1 { e } else { e1 }
        u0 = u0 + (if e > 2 { (e - 2).reinterpret_as_uint() } else { 0U })
      }
      if (qinf1 & 0xF0U & ((qinf1 & 0xF0U) - 1U)) != 0U {
        let mut e = line_state[lsp_idx + 1] & 0x7F
        let e1 = line_state[lsp_idx + 2] & 0x7F
        e = if e > e1 { e } else { e1 }
        u1 = u1 + (if e > 2 { (e - 2).reinterpret_as_uint() } else { 0U })
      }
      if u0.reinterpret_as_int() > zero_bplanes_p1 ||
        u1.reinterpret_as_int() > zero_bplanes_p1 {
        return Err("ht cleanup: U_q exceeds zero bit-planes + 1")
      }
      ls0 = line_state[lsp_idx + 2]
      line_state[lsp_idx + 1] = 0
      line_state[lsp_idx + 2] = 0
      let mut locs = 0xFF
      if x + 4 > cb_w {
        locs = locs >> ((x + 4 - cb_w) << 1)
      }
      locs = if y + 2 <= cb_h { locs } else { locs & 0x55 }
      if (
          (((qinf0 & 0xF0U) >> 4) | (qinf1 & 0xF0U)).reinterpret_as_int() &
          (0xFF ^ locs)
        ) !=
        0 {
        return Err("ht cleanup: significant samples outside code-block area")
      }
      let _ = ht_maybe_set_cleanup_sample(
        output, sp_idx, locs, 0x1, qinf0, 0x10U, magsgn, 12, u0, bitplanes_plus_one,
      )
      let e_n0_v = ht_maybe_set_cleanup_sample(
        output,
        sp_idx + stride,
        locs,
        0x2,
        qinf0,
        0x20U,
        magsgn,
        13,
        u0,
        bitplanes_plus_one,
      )
      guard e_n0_v is Ok(e_n0) else {
        return Err("ht cleanup: lower stripe sample decode failed")
      }
      if e_n0 > 0 {
        let t = line_state[lsp_idx] & 0x7F
        line_state[lsp_idx] = 0x80 | (if t > e_n0 { t } else { e_n0 })
      }
      lsp_idx += 1
      sp_idx += 1
      let _ = ht_maybe_set_cleanup_sample(
        output, sp_idx, locs, 0x4, qinf0, 0x40U, magsgn, 14, u0, bitplanes_plus_one,
      )
      let e_nw0_v = ht_maybe_set_cleanup_sample(
        output,
        sp_idx + stride,
        locs,
        0x8,
        qinf0,
        0x80U,
        magsgn,
        15,
        u0,
        bitplanes_plus_one,
      )
      guard e_nw0_v is Ok(e_nw0) else {
        return Err("ht cleanup: lower stripe row1 decode failed")
      }
      if e_nw0 > 0 {
        line_state[lsp_idx] = 0x80 | e_nw0
      }
      sp_idx += 1
      let _ = ht_maybe_set_cleanup_sample(
        output, sp_idx, locs, 0x10, qinf1, 0x10U, magsgn, 12, u1, bitplanes_plus_one,
      )
      let e_n1_v = ht_maybe_set_cleanup_sample(
        output,
        sp_idx + stride,
        locs,
        0x20,
        qinf1,
        0x20U,
        magsgn,
        13,
        u1,
        bitplanes_plus_one,
      )
      guard e_n1_v is Ok(e_n1) else {
        return Err("ht cleanup: lower stripe second-quad decode failed")
      }
      if e_n1 > 0 {
        let t = line_state[lsp_idx] & 0x7F
        line_state[lsp_idx] = 0x80 | (if t > e_n1 { t } else { e_n1 })
      }
      lsp_idx += 1
      sp_idx += 1
      let _ = ht_maybe_set_cleanup_sample(
        output, sp_idx, locs, 0x40, qinf1, 0x40U, magsgn, 14, u1, bitplanes_plus_one,
      )
      let e_nw1_v = ht_maybe_set_cleanup_sample(
        output,
        sp_idx + stride,
        locs,
        0x80,
        qinf1,
        0x80U,
        magsgn,
        15,
        u1,
        bitplanes_plus_one,
      )
      guard e_nw1_v is Ok(e_nw1) else {
        return Err("ht cleanup: lower stripe second-quad row1 decode failed")
      }
      if e_nw1 > 0 {
        line_state[lsp_idx] = 0x80 | e_nw1
      }
      sp_idx += 1
      x = x + 4
    }
    y = y + 2
  }
  Ok(output)
}

///|
fn htj2k_decode_cleanup_only_fixedpoint(
  codeword : Bytes,
  cb_w : Int,
  cb_h : Int,
  bitplanes_plus_one : Int,
  zero_bit_planes : Int,
) -> Result[Array[Int], String] {
  ht_cleanup_only_decode_raw_values(
    codeword, cb_w, cb_h, bitplanes_plus_one, zero_bit_planes,
  )
}

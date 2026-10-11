///|
// Spec grouping:
// - Annex C.3 (arithmetic decoding procedure)
// - Step 1-b bootstrap for Tier-1 MQ path

///|
pub struct Tier1AnnexCBootstrap {
  non_empty_segments : Int
  preview_hex : String
  a_init : Int
  c_init : Int
}

///|
pub struct Tier1AnnexCContextState {
  state_index : Int
  mps : Int
}

///|
pub struct Tier1AnnexCDecisionProbe {
  context_index : Int
  decision : Int
  kind : String
}

///|
pub struct Tier1AnnexCDecoderState {
  a : Int
  c : Int
  ct : Int
  byte_pos : Int
  prev_byte : Int
  source : Bytes
}

///|
// Spec basis (T.800-2015 D.6):
// Raw bit reader for BYPASS mode. Reads packed bits MSB-first.
pub struct Tier1RawBitReader {
  source : Bytes
  mut byte_pos : Int
  mut c : Int // current raw byte (T.800-2015 C.2.7: C register)
  mut ct : Int // remaining bits in c (T.800-2015 C.2.7: CT counter)
}

///|
// Spec basis (T.800-2015 D.6):
// Read one raw bit from the BYPASS bitstream.
fn tier1_raw_read_bit(reader : Tier1RawBitReader) -> Int {
  if reader.ct == 0 {
    // T.800-2015 D.6:
    // treat end-of-segment as artificial 0xFF marker stream.
    if reader.c == 0xFF {
      let peek = if reader.byte_pos < reader.source.length() {
        reader.source[reader.byte_pos].to_int()
      } else {
        0xFF
      }
      if peek > 0x8F {
        reader.c = 0xFF
        reader.ct = 8
      } else {
        reader.c = peek
        reader.byte_pos += 1
        reader.ct = 7
      }
    } else {
      reader.c = if reader.byte_pos < reader.source.length() {
        reader.source[reader.byte_pos].to_int()
      } else {
        0xFF
      }
      reader.byte_pos += 1
      reader.ct = 8
    }
  }
  reader.ct -= 1
  (reader.c >> reader.ct) & 1
}

///|
pub const TIER1_ANNEX_C_DEFAULT_CONTEXT_COUNT : Int = 19

///|
const TIER1_CTX_CLEANUP_SIG : Int = 0

///|
const TIER1_CTX_SIGPROP_SIG : Int = 1

///|
const TIER1_CTX_MAGREF : Int = 2

///|
const TIER1_CTX_CLEANUP_SIGN : Int = 3

///|
const TIER1_CTX_SIGPROP_SIGN : Int = 4

///|
const TIER1_CTX_MB_CLEANUP_SIG_NONE : Int = 5

///|
const TIER1_CTX_MB_CLEANUP_SIG_FEW : Int = 6

///|
const TIER1_CTX_MB_CLEANUP_SIG_MANY : Int = 7

///|
const TIER1_CTX_MB_SIGPROP_SIG_FEW : Int = 9

///|
const TIER1_CTX_MB_SIGPROP_SIG_MANY : Int = 10

///|
const TIER1_CTX_MB_MAGREF : Int = 12

///|
const TIER1_CTX_MB_CLEANUP_SIGN_MIXED : Int = 13

///|
const TIER1_CTX_MB_CLEANUP_SIGN_POS : Int = 14

///|
const TIER1_CTX_MB_CLEANUP_SIGN_NEG : Int = 15

///|
const TIER1_CTX_MB_SIGPROP_SIGN_MIXED : Int = 16

///|
const TIER1_CTX_MB_SIGPROP_SIGN_POS : Int = 17

///|
const TIER1_CTX_MB_SIGPROP_SIGN_NEG : Int = 18

///|
const TIER1_SIGN_W_CLEANUP_ORTH : Int = 2

///|
const TIER1_SIGN_W_CLEANUP_DIAG : Int = 1

///|
const TIER1_SIGN_W_SIGPROP_ORTH : Int = 3

///|
const TIER1_SIGN_W_SIGPROP_DIAG : Int = 1

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
fn tier1_count_non_empty_codewords(codewords : Array[Bytes]) -> Int {
  let mut n = 0
  for cw in codewords {
    if cw.length() > 0 {
      n += 1
    }
  }
  n
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_preview_hex(
  codewords : Array[Bytes],
  preview_bytes : Int,
) -> String {
  let out : Array[Int] = []
  let mut remaining = preview_bytes
  for cw in codewords {
    if remaining <= 0 {
      break
    }
    for b in cw {
      if remaining <= 0 {
        break
      }
      out.push(b.to_int())
      remaining -= 1
    }
  }
  @core.bytes_to_hex(out)
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
fn tier1_first_non_empty_codeword(codewords : Array[Bytes]) -> Bytes? {
  for cw in codewords {
    if cw.length() > 0 {
      return Some(cw)
    }
  }
  None
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_annex_c_bootstrap_from_codewords(
  codewords : Array[Bytes],
) -> Result[Tier1AnnexCBootstrap, String] {
  let non_empty_segments = tier1_count_non_empty_codewords(codewords)
  if non_empty_segments <= 0 {
    return Err("no non-empty codeword segment")
  }
  let preview_hex = tier1_preview_hex(codewords, 8)
  guard tier1_first_non_empty_codeword(codewords) is Some(first) else {
    return Err("failed to locate first non-empty codeword segment")
  }
  let b0 = first[0].to_int()
  let b1 = if first.length() > 1 { first[1].to_int() } else { 0x00 }
  // Annex C initial register bootstrap placeholder:
  // A starts from 0x8000, C is seeded from the first bytes.
  let a_init = 0x8000
  let c_init = (b0 << 16) + (b1 << 8)
  Ok({ non_empty_segments, preview_hex, a_init, c_init, })
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_annex_c_bootstrap_debug(info : Tier1AnnexCBootstrap) -> String {
  "annex-c-bootstrap: segments=\{info.non_empty_segments}, a=\{info.a_init}, c=\{info.c_init}, preview=\{info.preview_hex}"
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_annex_c_probe_one_decision(
  boot : Tier1AnnexCBootstrap,
  codewords : Array[Bytes],
  contexts : Array[Tier1AnnexCContextState],
) -> Result[Tier1AnnexCDecisionProbe, String] {
  if contexts.length() <= 0 {
    return Err("annex-c contexts are empty")
  }
  let init_v = tier1_annex_c_initdec_from_bootstrap(boot, codewords)
  guard init_v is Ok(state) else { return Err("annex-c initdec failed") }
  let decode_v = tier1_annex_c_decode_decision(state, contexts[0])
  guard decode_v is Ok((decision, kind, _, _)) else {
    return Err("annex-c decode decision failed")
  }
  Ok({ context_index: 0, decision, kind, })
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_annex_c_probe_debug(probe : Tier1AnnexCDecisionProbe) -> String {
  "probe:ctx=\{probe.context_index},decision=\{probe.decision},kind=\{probe.kind}"
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_annex_c_context_trace_debug(
  context_sequence : Array[Int],
  decisions : Array[Int],
  kinds : Array[String],
) -> String {
  "trace:contexts=\{context_sequence},bits=\{decisions},kinds=\{kinds}"
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
fn tier1_annex_c_initdec_from_bootstrap(
  _boot : Tier1AnnexCBootstrap,
  codewords : Array[Bytes],
) -> Result[Tier1AnnexCDecoderState, String] {
  guard tier1_first_non_empty_codeword(codewords) is Some(first) else {
    return Err("failed to locate first non-empty codeword segment")
  }
  if first.length() <= 0 {
    return Err("non-empty codeword segment is required")
  }
  // Spec: C.3.5 INITDEC
  // Step 1: BP = BPST, C = B << 16
  let b0 = first[0].to_int()
  let c0 = b0 << 16
  // Step 2: Call BYTEIN to read second byte
  let pre_bytein : Tier1AnnexCDecoderState = {
    a: 0x8000,
    c: c0,
    ct: 0,
    byte_pos: 1,
    prev_byte: b0,
    source: first,
  }
  let bytein_v = tier1_annex_c_bytein(pre_bytein)
  guard bytein_v is Ok(after_bytein) else {
    return Err("annex-c initdec bytein failed")
  }
  // Step 3: C = C << 7, CT = CT - 7
  let c_shifted = after_bytein.c << 7
  let ct_adjusted = after_bytein.ct - 7
  Ok({
    a: 0x8000,
    c: c_shifted,
    ct: ct_adjusted,
    byte_pos: after_bytein.byte_pos,
    prev_byte: after_bytein.prev_byte,
    source: first,
  })
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
fn tier1_annex_c_bytein(
  state : Tier1AnnexCDecoderState,
) -> Result[Tier1AnnexCDecoderState, String] {
  // Spec: C.3.4 BYTEIN - compressed image data input with 0xFF byte stuffing
  if state.prev_byte == 0xFF {
    // Previous byte was 0xFF - check for marker or stuffed bit
    let peek = if state.byte_pos < state.source.length() {
      state.source[state.byte_pos].to_int()
    } else {
      0xFF
    }
    if peek > 0x8F {
      // Marker code detected - feed 1-bits, don't advance pointer
      Ok({
        a: state.a,
        c: state.c + 0xFF00,
        ct: 8,
        byte_pos: state.byte_pos,
        prev_byte: state.prev_byte,
        source: state.source,
      })
    } else {
      // Stuffed bit: shift by 9 (MSB is stuff bit = 0), CT = 7
      Ok({
        a: state.a,
        c: state.c + (peek << 9),
        ct: 7,
        byte_pos: state.byte_pos + 1,
        prev_byte: peek,
        source: state.source,
      })
    }
  } else {
    // Normal byte read - shift by 8, CT = 8
    let new_byte = if state.byte_pos < state.source.length() {
      state.source[state.byte_pos].to_int()
    } else {
      0xFF
    }
    Ok({
      a: state.a,
      c: state.c + (new_byte << 8),
      ct: 8,
      byte_pos: state.byte_pos + 1,
      prev_byte: new_byte,
      source: state.source,
    })
  }
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
fn tier1_annex_c_renormd(
  state : Tier1AnnexCDecoderState,
) -> Result[Tier1AnnexCDecoderState, String] {
  let mut s = state
  while s.a < 0x8000 {
    if s.ct == 0 {
      let bytein_v = tier1_annex_c_bytein(s)
      guard bytein_v is Ok(next_s) else { return Err("annex-c bytein failed") }
      s = next_s
    }
    s = {
      a: s.a << 1,
      c: s.c << 1,
      ct: s.ct - 1,
      byte_pos: s.byte_pos,
      prev_byte: s.prev_byte,
      source: s.source,
    }
  }
  Ok(s)
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
fn tier1_annex_c_decode_decision(
  state : Tier1AnnexCDecoderState,
  context : Tier1AnnexCContextState,
) -> Result[
  (Int, String, Tier1AnnexCDecoderState, Tier1AnnexCContextState),
  String,
] {
  // Spec: C.3.2 DECODE (Figure C.15) with MPS_EXCHANGE (C.16) and LPS_EXCHANGE (C.17)
  let qe_v = tier1_annex_c_qe_value(context.state_index)
  guard qe_v is Ok(qe) else { return Err("annex-c qe lookup failed") }
  // Step 1: A = A - Qe
  let a_reduced = state.a - qe
  // C_HIGH is the upper 16 bits of C (unsigned). Must mask because MoonBit
  // Int is signed 32-bit and arithmetic right shift sign-extends.
  let chigh = (state.c >> 16) & 0xFFFF
  if chigh >= qe {
    // MPS region: CHIGH = CHIGH - Qe
    let c_new = state.c - (qe << 16)
    if a_reduced >= 0x8000 {
      // Fast path: no renormalization needed, D = MPS
      Ok(
        (
          context.mps,
          "MPS",
          {
            a: a_reduced,
            c: c_new,
            ct: state.ct,
            byte_pos: state.byte_pos,
            prev_byte: state.prev_byte,
            source: state.source,
          },
          context,
        ),
      )
    } else {
      // MPS_EXCHANGE (Figure C.16): check if A < Qe for conditional exchange
      let (decision, kind, next_ctx) = if a_reduced < qe {
        // Exchange: decode LPS even though in MPS region
        let nlps_v = tier1_annex_c_nlps_state(context.state_index)
        guard nlps_v is Ok(nlps) else {
          return Err("annex-c nlps transition failed")
        }
        let sw_v = tier1_annex_c_switch_mps_on_lps(context.state_index)
        guard sw_v is Ok(sw) else { return Err("annex-c switch lookup failed") }
        let new_mps = if sw { 1 - context.mps } else { context.mps }
        (1 - context.mps, "LPS-X", { state_index: nlps, mps: new_mps, })
      } else {
        // Normal MPS
        let nmps_v = tier1_annex_c_nmps_state(context.state_index)
        guard nmps_v is Ok(nmps) else {
          return Err("annex-c nmps transition failed")
        }
        (context.mps, "MPS", { state_index: nmps, mps: context.mps, })
      }
      let renorm_v = tier1_annex_c_renormd({
        a: a_reduced,
        c: c_new,
        ct: state.ct,
        byte_pos: state.byte_pos,
        prev_byte: state.prev_byte,
        source: state.source,
      })
      guard renorm_v is Ok(next_state) else {
        return Err("annex-c renormd failed")
      }
      Ok((decision, kind, next_state, next_ctx))
    }
  } else {
    // LPS region: don't subtract Qe from CHIGH
    // LPS_EXCHANGE (Figure C.17): check if A < Qe for conditional exchange
    let (decision, kind, next_ctx) = if a_reduced < qe {
      // Exchange: D = MPS(CX), I(CX) = NMPS(I(CX)) — no MPS flip
      let nmps_v = tier1_annex_c_nmps_state(context.state_index)
      guard nmps_v is Ok(nmps) else {
        return Err("annex-c nmps transition failed")
      }
      (context.mps, "MPS-X", { state_index: nmps, mps: context.mps, })
    } else {
      // Normal LPS: D = 1 - MPS(CX), SWITCH check, I(CX) = NLPS(I(CX))
      let nlps_v = tier1_annex_c_nlps_state(context.state_index)
      guard nlps_v is Ok(nlps) else {
        return Err("annex-c nlps transition failed")
      }
      let sw_v = tier1_annex_c_switch_mps_on_lps(context.state_index)
      guard sw_v is Ok(sw) else { return Err("annex-c switch lookup failed") }
      let new_mps = if sw { 1 - context.mps } else { context.mps }
      (1 - context.mps, "LPS", { state_index: nlps, mps: new_mps, })
    }
    let renorm_v = tier1_annex_c_renormd({
      a: qe,
      c: state.c,
      ct: state.ct,
      byte_pos: state.byte_pos,
      prev_byte: state.prev_byte,
      source: state.source,
    })
    guard renorm_v is Ok(next_state) else {
      return Err("annex-c renormd failed")
    }
    Ok((decision, kind, next_state, next_ctx))
  }
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
fn tier1_annex_c_decode_one_with_context(
  state : Tier1AnnexCDecoderState,
  contexts : Array[Tier1AnnexCContextState],
  context_index : Int,
) -> Result[
  (Int, String, Tier1AnnexCDecoderState, Array[Tier1AnnexCContextState]),
  String,
] {
  if contexts.length() <= 0 {
    return Err("annex-c contexts are empty")
  }
  if context_index < 0 || context_index >= contexts.length() {
    return Err("annex-c context index is out of range")
  }
  let one_v = tier1_annex_c_decode_decision(state, contexts[context_index])
  guard one_v is Ok((decision, kind, next_state, next_ctx)) else {
    return Err("annex-c decode decision failed")
  }
  let next_contexts = contexts
  next_contexts[context_index] = next_ctx
  Ok((decision, kind, next_state, next_contexts))
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_annex_c_decode_single_coeff_passes(
  boot : Tier1AnnexCBootstrap,
  codewords : Array[Bytes],
  contexts : Array[Tier1AnnexCContextState],
  coding_passes : Int,
  sigprop_discovery_enabled : Bool,
) -> Result[(Array[Int], Array[Int], Array[String]), String] {
  if coding_passes <= 0 {
    return Err("coding_passes must be positive")
  }
  if contexts.length() < 5 {
    return Err("annex-c contexts must have at least 5 entries")
  }
  let init_v = tier1_annex_c_initdec_from_bootstrap(boot, codewords)
  guard init_v is Ok(init_state) else { return Err("annex-c initdec failed") }
  let mut state = init_state
  let mut active_contexts = contexts
  let context_trace : Array[Int] = []
  let decisions : Array[Int] = []
  let kinds : Array[String] = []
  let mut significant = false
  for i in 0..<coding_passes {
    let pass_kind = i % 3
    if pass_kind == 0 {
      // cleanup significance decision
      let sig_v = tier1_annex_c_decode_one_with_context(
        state,
        active_contexts,
        TIER1_CTX_CLEANUP_SIG,
      )
      guard sig_v is Ok((sig, sig_kind, next_state, next_contexts)) else {
        return Err("annex-c cleanup significance decode failed")
      }
      context_trace.push(TIER1_CTX_CLEANUP_SIG)
      decisions.push(sig)
      kinds.push(sig_kind)
      state = next_state
      active_contexts = next_contexts
      if significant || sig == 0 {
        continue
      }
      // cleanup sign decision
      let sign_v = tier1_annex_c_decode_one_with_context(
        state,
        active_contexts,
        TIER1_CTX_CLEANUP_SIGN,
      )
      guard sign_v is Ok((sign_bit, sign_kind, sign_state, sign_contexts)) else {
        return Err("annex-c cleanup sign decode failed")
      }
      context_trace.push(TIER1_CTX_CLEANUP_SIGN)
      decisions.push(sign_bit)
      kinds.push(sign_kind)
      state = sign_state
      active_contexts = sign_contexts
      significant = true
      continue
    }
    if pass_kind == 1 {
      if !sigprop_discovery_enabled {
        continue
      }
      // sigprop significance decision
      let sig_v = tier1_annex_c_decode_one_with_context(
        state,
        active_contexts,
        TIER1_CTX_SIGPROP_SIG,
      )
      guard sig_v is Ok((sig, sig_kind, next_state, next_contexts)) else {
        return Err("annex-c sigprop significance decode failed")
      }
      context_trace.push(TIER1_CTX_SIGPROP_SIG)
      decisions.push(sig)
      kinds.push(sig_kind)
      state = next_state
      active_contexts = next_contexts
      if significant || sig == 0 {
        continue
      }
      // sigprop sign decision
      let sign_v = tier1_annex_c_decode_one_with_context(
        state,
        active_contexts,
        TIER1_CTX_SIGPROP_SIGN,
      )
      guard sign_v is Ok((sign_bit, sign_kind, sign_state, sign_contexts)) else {
        return Err("annex-c sigprop sign decode failed")
      }
      context_trace.push(TIER1_CTX_SIGPROP_SIGN)
      decisions.push(sign_bit)
      kinds.push(sign_kind)
      state = sign_state
      active_contexts = sign_contexts
      significant = true
      continue
    }
    // magref decision
    let mag_v = tier1_annex_c_decode_one_with_context(
      state,
      active_contexts,
      TIER1_CTX_MAGREF,
    )
    guard mag_v is Ok((mag_bit, mag_kind, next_state, next_contexts)) else {
      return Err("annex-c magref decode failed")
    }
    context_trace.push(TIER1_CTX_MAGREF)
    decisions.push(mag_bit)
    kinds.push(mag_kind)
    state = next_state
    active_contexts = next_contexts
  }
  Ok((context_trace, decisions, kinds))
}

///|
// Spec basis (T.800-2015 B.10 / Annex C / Annex D):
// - Tier-1 coded data is carried as coding-pass segments (B.10), while the
//   arithmetic decoder consumes a bytestream through pass processing (D.3).
// - This staged helper merges split pass segments into one decode stream for
//   Annex C MQ procedures without changing existing pass decoders.
fn tier1_annex_c_merge_pass_segments_to_codewords(
  pass_segments : Array[Bytes],
) -> Result[Array[Bytes], String] {
  if pass_segments.length() <= 0 {
    return Err("pass_segments must not be empty")
  }
  let merged : Array[Byte] = []
  let mut non_empty_segments = 0
  for segment in pass_segments {
    if segment.length() > 0 {
      non_empty_segments += 1
    }
    for b in segment {
      merged.push(b)
    }
  }
  if non_empty_segments <= 0 {
    return Err("no non-empty pass segment")
  }
  let merged_codeword = Bytes::from_iter(merged.iter())
  Ok([merged_codeword])
}

///|
// Spec basis (T.800-2015 B.10 / Annex C / Annex D):
// - Coding-pass segments (B.10) may be provided already split by pass-segment
//   boundaries; this function accepts that shape.
// - MQ arithmetic decode sequencing remains Annex C + D.3 and is delegated to
//   decode_single_coeff_passes to preserve existing staged behavior.
pub fn tier1_annex_c_decode_single_coeff_pass_segments(
  pass_segments : Array[Bytes],
  contexts : Array[Tier1AnnexCContextState],
  coding_passes : Int,
  sigprop_discovery_enabled : Bool,
) -> Result[(Array[Int], Array[Int], Array[String]), String] {
  let merged_v = tier1_annex_c_merge_pass_segments_to_codewords(pass_segments)
  guard merged_v is Ok(codewords) else {
    return Err("annex-c pass-segment merge failed")
  }
  let boot_v = tier1_annex_c_bootstrap_from_codewords(codewords)
  guard boot_v is Ok(boot) else { return Err("annex-c bootstrap failed") }
  tier1_annex_c_decode_single_coeff_passes(
    boot, codewords, contexts, coding_passes, sigprop_discovery_enabled,
  )
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_mq_mini_block_sig_neighbor_count(
  width : Int,
  height : Int,
  significant : Array[Bool],
  x : Int,
  y : Int,
) -> Int {
  let mut n = 0
  for dy in -1..<2 {
    for dx in -1..<2 {
      if dx == 0 && dy == 0 {
        continue
      }
      let nx = x + dx
      let ny = y + dy
      if nx < 0 || ny < 0 || nx >= width || ny >= height {
        continue
      }
      let ni = @math.grid_index_2d(width, nx, ny)
      if significant[ni] {
        n += 1
      }
    }
  }
  n
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_mq_sig_context_table_cleanup(
  neighbor_bucket : Int,
  bias_bucket : Int,
) -> Int {
  let table : Array[Array[Int]] = [
    [
      TIER1_CTX_MB_CLEANUP_SIG_NONE,
      TIER1_CTX_MB_CLEANUP_SIG_FEW,
      TIER1_CTX_MB_CLEANUP_SIG_FEW,
    ],
    [
      TIER1_CTX_MB_CLEANUP_SIG_FEW,
      TIER1_CTX_MB_CLEANUP_SIG_FEW,
      TIER1_CTX_MB_CLEANUP_SIG_MANY,
    ],
    [
      TIER1_CTX_MB_CLEANUP_SIG_FEW,
      TIER1_CTX_MB_CLEANUP_SIG_MANY,
      TIER1_CTX_MB_CLEANUP_SIG_MANY,
    ],
  ]
  table[neighbor_bucket][bias_bucket]
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_mq_sig_context_table_sigprop(
  neighbor_bucket : Int,
  bias_bucket : Int,
) -> Int {
  let table : Array[Array[Int]] = [
    [
      TIER1_CTX_MB_SIGPROP_SIG_FEW,
      TIER1_CTX_MB_SIGPROP_SIG_FEW,
      TIER1_CTX_MB_SIGPROP_SIG_MANY,
    ],
    [
      TIER1_CTX_MB_SIGPROP_SIG_FEW,
      TIER1_CTX_MB_SIGPROP_SIG_MANY,
      TIER1_CTX_MB_SIGPROP_SIG_MANY,
    ],
    [
      TIER1_CTX_MB_SIGPROP_SIG_MANY,
      TIER1_CTX_MB_SIGPROP_SIG_MANY,
      TIER1_CTX_MB_SIGPROP_SIG_MANY,
    ],
  ]
  table[neighbor_bucket][bias_bucket]
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_mq_mini_block_cleanup_sig_context(
  neighbor_count : Int,
  sign_score : Int,
) -> Int {
  let nb = tier1_mq_mini_block_neighbor_bucket(neighbor_count)
  let bb = tier1_mq_mini_block_bias_bucket(sign_score)
  tier1_mq_sig_context_table_cleanup(nb, bb)
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_mq_mini_block_sigprop_sig_context(
  neighbor_count : Int,
  sign_score : Int,
) -> Int {
  let nb = tier1_mq_mini_block_neighbor_bucket(neighbor_count)
  let bb = tier1_mq_mini_block_bias_bucket(sign_score)
  tier1_mq_sig_context_table_sigprop(nb, bb)
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_mq_mini_block_weighted_sign_score(
  width : Int,
  height : Int,
  signs : Array[Int],
  x : Int,
  y : Int,
  orth_weight : Int,
  diag_weight : Int,
) -> Int {
  if orth_weight <= 0 || diag_weight <= 0 {
    return 0
  }
  let mut score = 0
  for dy in -1..<2 {
    for dx in -1..<2 {
      if dx == 0 && dy == 0 {
        continue
      }
      let nx = x + dx
      let ny = y + dy
      if nx < 0 || ny < 0 || nx >= width || ny >= height {
        continue
      }
      let ni = @math.grid_index_2d(width, nx, ny)
      let s = signs[ni]
      if s == 0 {
        continue
      }
      let weight = if dx == 0 || dy == 0 { orth_weight } else { diag_weight }
      score += s * weight
    }
  }
  score
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_mq_mini_block_neighbor_bucket(neighbor_count : Int) -> Int {
  if neighbor_count <= 1 {
    return 0
  }
  if neighbor_count <= 3 {
    return 1
  }
  2
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_mq_mini_block_bias_bucket(score : Int) -> Int {
  let abs_score = if score < 0 { -score } else { score }
  if abs_score <= 0 {
    return 0
  }
  if abs_score == 1 {
    return 1
  }
  2
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_mq_sign_mode_table_cleanup(
  neighbor_bucket : Int,
  bias_bucket : Int,
) -> Int {
  // mode: 0 => mixed, 1 => sign-sensitive (pos/neg)
  let table : Array[Array[Int]] = [
    [0, 0, 1], // sparse neighbors
    [0, 0, 1], // medium neighbors
    [0, 0, 0],
  ] // dense neighbors
  table[neighbor_bucket][bias_bucket]
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_mq_sign_mode_table_sigprop(
  neighbor_bucket : Int,
  bias_bucket : Int,
) -> Int {
  // mode: 0 => mixed, 1 => sign-sensitive (pos/neg)
  let table : Array[Array[Int]] = [
    [0, 1, 1], // sparse neighbors
    [0, 1, 1], // medium neighbors
    [0, 0, 1],
  ] // dense neighbors
  table[neighbor_bucket][bias_bucket]
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_mq_mini_block_cleanup_sign_context(
  score : Int,
  neighbor_count : Int,
) -> Int {
  let nb = tier1_mq_mini_block_neighbor_bucket(neighbor_count)
  let bb = tier1_mq_mini_block_bias_bucket(score)
  let mode = tier1_mq_sign_mode_table_cleanup(nb, bb)
  if mode == 0 || score == 0 {
    return TIER1_CTX_MB_CLEANUP_SIGN_MIXED
  }
  if score > 0 {
    return TIER1_CTX_MB_CLEANUP_SIGN_POS
  }
  TIER1_CTX_MB_CLEANUP_SIGN_NEG
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_mq_mini_block_cleanup_sign_score(
  width : Int,
  height : Int,
  signs : Array[Int],
  x : Int,
  y : Int,
) -> Int {
  // cleanup: directional influence, but moderate weighting
  tier1_mq_mini_block_weighted_sign_score(
    width,
    height,
    signs,
    x,
    y,
    TIER1_SIGN_W_CLEANUP_ORTH,
    TIER1_SIGN_W_CLEANUP_DIAG,
  )
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_mq_mini_block_sigprop_sign_context(
  score : Int,
  neighbor_count : Int,
) -> Int {
  let nb = tier1_mq_mini_block_neighbor_bucket(neighbor_count)
  let bb = tier1_mq_mini_block_bias_bucket(score)
  let mode = tier1_mq_sign_mode_table_sigprop(nb, bb)
  if mode == 0 || score == 0 {
    return TIER1_CTX_MB_SIGPROP_SIGN_MIXED
  }
  if score > 0 {
    return TIER1_CTX_MB_SIGPROP_SIGN_POS
  }
  TIER1_CTX_MB_SIGPROP_SIGN_NEG
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_mq_mini_block_sigprop_sign_score(
  width : Int,
  height : Int,
  signs : Array[Int],
  x : Int,
  y : Int,
) -> Int {
  // sigprop: stronger orthogonal weighting than cleanup
  tier1_mq_mini_block_weighted_sign_score(
    width,
    height,
    signs,
    x,
    y,
    TIER1_SIGN_W_SIGPROP_ORTH,
    TIER1_SIGN_W_SIGPROP_DIAG,
  )
}

///|
// Spec basis (T.800-2015 Table D.1):
// Significance context for LL and LH sub-bands, based on neighbor counts
// Hi = horizontal significant neighbors (0-2)
// Vi = vertical significant neighbors (0-2)
// Di = diagonal significant neighbors (0-4)
// Returns CX in 0-8.
fn tier1_spec_sig_context_ll_lh(hi : Int, vi : Int, di : Int) -> Int {
  if hi >= 2 {
    return 8
  }
  if hi == 1 && vi >= 1 {
    return 7
  }
  if hi == 1 && vi == 0 && di >= 1 {
    return 6
  }
  if hi == 1 && vi == 0 && di == 0 {
    return 5
  }
  if hi == 0 && vi >= 2 {
    return 4
  }
  if hi == 0 && vi == 1 {
    return 3
  }
  if hi == 0 && vi == 0 && di >= 2 {
    return 2
  }
  if hi == 0 && vi == 0 && di == 1 {
    return 1
  }
  0
}

///|
// Spec basis (T.800-2015 Table D.1):
// Significance context for HL sub-band. Same as LL/LH but with Hi and Vi swapped.
fn tier1_spec_sig_context_hl(hi : Int, vi : Int, di : Int) -> Int {
  tier1_spec_sig_context_ll_lh(vi, hi, di)
}

///|
// Spec basis (T.800-2015 Table D.1):
// Significance context for HH sub-band, based on (Hi+Vi) sum and Di.
fn tier1_spec_sig_context_hh(hi : Int, vi : Int, di : Int) -> Int {
  // T.800-2015 Table D.1 HH subband: Σ_D is the primary discriminator,
  // Σ_HV = (Σ_H + Σ_V) is secondary.
  let hv = hi + vi
  if di >= 3 {
    return 8
  }
  if di == 2 && hv >= 1 {
    return 7
  }
  if di == 2 && hv == 0 {
    return 6
  }
  if di == 1 && hv >= 2 {
    return 5
  }
  if di == 1 && hv == 1 {
    return 4
  }
  if di == 1 && hv == 0 {
    return 3
  }
  if hv >= 2 {
    return 2
  }
  if hv == 1 {
    return 1
  }
  0
}

///|
// Spec basis (T.800-2015 Table D.1):
// Select significance context function based on subband type.
// subband_type: 0=LL, 1=HL, 2=LH, 3=HH
fn tier1_spec_sig_context(
  hi : Int,
  vi : Int,
  di : Int,
  subband_type : Int,
) -> Int {
  if subband_type == 1 {
    tier1_spec_sig_context_hl(hi, vi, di)
  } else if subband_type == 3 {
    tier1_spec_sig_context_hh(hi, vi, di)
  } else {
    tier1_spec_sig_context_ll_lh(hi, vi, di)
  }
}

///|
// Spec basis (T.800-2015 Table D.3):
// Sign context from horizontal and vertical neighbor sign contributions.
// H = sum of sign contributions of horizontal neighbors (-2 to +2)
// V = sum of sign contributions of vertical neighbors (-2 to +2)
// Returns (CX in 9-13, xor_bit: 0 or 1).
// The decoded sign bit must be XORed with xor_bit.
fn tier1_spec_sign_context(h : Int, v : Int) -> (Int, Int) {
  if h > 0 {
    if v > 0 {
      (13, 0)
    } else if v == 0 {
      (12, 0)
    } else {
      (11, 0)
    }
  } else if h == 0 {
    if v > 0 {
      (10, 0)
    } else if v == 0 {
      (9, 0)
    } else {
      (10, 1)
    }
    // h < 0
  } else if v > 0 {
    (11, 1)
  } else if v == 0 {
    (12, 1)
  } else {
    (13, 1)
  }
}

///|
// Spec basis (T.800-2015 Table D.4):
// Magnitude refinement context.
// first_magref: true if this is the first refinement for this coefficient (σ'_i = 0)
// has_sig_neighbor: true if any of the 8 neighbors is significant (κ_σ ≠ 0)
// Returns CX = 14, 15, or 16.
fn tier1_spec_magref_context(
  first_magref : Bool,
  has_sig_neighbor : Bool,
) -> Int {
  if !first_magref {
    // Subsequent refinement (σ'_i ≠ 0): CX=16
    16
  } else if has_sig_neighbor {
    // First refinement, has sig neighbor: CX=15
    15
  } else {
    // First refinement, no sig neighbor: CX=14
    14
  }
}

///|
// Compute (Hi, Vi, Di) neighbor significance counts for context mapping.
// Hi = count of significant horizontal neighbors (H0, H1)
// Vi = count of significant vertical neighbors (V0, V1)
// Di = count of significant diagonal neighbors (D0, D1, D2, D3)
fn tier1_spec_neighbor_sig_counts(
  width : Int,
  height : Int,
  significant : Array[Bool],
  x : Int,
  y : Int,
  mask_south? : Bool = false,
) -> (Int, Int, Int) {
  let mut hi = 0
  let mut vi = 0
  let mut di = 0
  // H0 (left)
  if x > 0 && significant[y * width + (x - 1)] {
    hi += 1
  }
  // H1 (right)
  if x + 1 < width && significant[y * width + (x + 1)] {
    hi += 1
  }
  // V0 (above)
  if y > 0 && significant[(y - 1) * width + x] {
    vi += 1
  }
  // V1 (below) — masked by VSC (D.4.1)
  if not(mask_south) && y + 1 < height && significant[(y + 1) * width + x] {
    vi += 1
  }
  // D0 (top-left)
  if x > 0 && y > 0 && significant[(y - 1) * width + (x - 1)] {
    di += 1
  }
  // D1 (top-right)
  if x + 1 < width && y > 0 && significant[(y - 1) * width + (x + 1)] {
    di += 1
  }
  // D2 (bottom-left) — masked by VSC (D.4.1)
  if not(mask_south) &&
    x > 0 &&
    y + 1 < height &&
    significant[(y + 1) * width + (x - 1)] {
    di += 1
  }
  // D3 (bottom-right) — masked by VSC (D.4.1)
  if not(mask_south) &&
    x + 1 < width &&
    y + 1 < height &&
    significant[(y + 1) * width + (x + 1)] {
    di += 1
  }
  (hi, vi, di)
}

///|
// Compute sign contributions of horizontal and vertical neighbors for Table D.3.
// For each significant neighbor: +1 if positive, -1 if negative.
// Non-significant neighbors contribute 0.
fn tier1_spec_neighbor_sign_contributions(
  width : Int,
  height : Int,
  significant : Array[Bool],
  signs : Array[Int],
  x : Int,
  y : Int,
  mask_south? : Bool = false,
) -> (Int, Int) {
  let mut h = 0
  let mut v = 0
  // H0 (left)
  if x > 0 {
    let idx = y * width + (x - 1)
    if significant[idx] {
      h += signs[idx]
    }
  }
  // H1 (right)
  if x + 1 < width {
    let idx = y * width + (x + 1)
    if significant[idx] {
      h += signs[idx]
    }
  }
  // V0 (above)
  if y > 0 {
    let idx = (y - 1) * width + x
    if significant[idx] {
      v += signs[idx]
    }
  }
  // V1 (below) — masked by VSC (D.4.1)
  if not(mask_south) && y + 1 < height {
    let idx = (y + 1) * width + x
    if significant[idx] {
      v += signs[idx]
    }
  }
  (h, v)
}

///|
fn tier1_trace_target_idx(width : Int, height : Int, idx : Int) -> Bool {
  idx == 0 ||
  (width > 1 && idx == 1) ||
  (height > 1 && idx == width) ||
  (width > 1 && height > 1 && idx == width + 1)
}

///|
fn tier1_trace_target_label(width : Int, height : Int, idx : Int) -> String {
  if idx == 0 {
    "idx0"
  } else if width > 1 && idx == 1 {
    "right"
  } else if height > 1 && idx == width {
    "down"
  } else if width > 1 && height > 1 && idx == width + 1 {
    "diag"
  } else {
    "other"
  }
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// - "The bits of the packet header are entropy decoded" and Tier-1 uses
//   arithmetic decoding over coding passes (D.3).
pub fn tier1_annex_c_decode_mini_block_passes(
  boot : Tier1AnnexCBootstrap,
  codewords : Array[Bytes],
  contexts : Array[Tier1AnnexCContextState],
  width : Int,
  height : Int,
  coding_passes : Int,
  _sigprop_discovery_enabled : Bool,
  code_block_style? : Int = 0,
  pass_segments? : Array[Bytes] = [],
  pass_segment_starts? : Array[Bool] = [],
  subband_type? : Int = 0,
  initial_bpno_plus_one? : Int = 0,
  roishift? : Int = 0,
  trace_target_pass? : Int = -1,
  trace_max_events? : Int = 0,
) -> Result[(Array[Int], Array[Int], Array[String]), String] {
  if width <= 0 || height <= 0 {
    return Err("mini block dimensions must be positive")
  }
  if width * height > 4096 {
    return Err("code block size exceeds maximum (64x64)")
  }
  if coding_passes <= 0 {
    return Err("coding_passes must be positive")
  }
  if contexts.length() < TIER1_ANNEX_C_DEFAULT_CONTEXT_COUNT {
    return Err("annex-c contexts must have at least 19 entries")
  }
  let has_bypass = (code_block_style & 0x01) != 0
  let has_reset = (code_block_style & 0x02) != 0
  let has_causal = (code_block_style & 0x08) != 0
  let init_bp = if initial_bpno_plus_one > 0 {
    initial_bpno_plus_one
  } else {
    1 + (coding_passes + 1) / 3
  }
  // T.800-2015 D.3:
  //   type = ((bpno_plus_one <= cblk->numbps - 4) && ...)
  // where bpno_plus_one includes roishift but cblk->numbps does not.
  // So RAW/BYPASS onset is based on the non-ROI bit-plane budget.
  let raw_bp_threshold = init_bp - roishift - 4
  let mut bpno_plus_one = init_bp
  let init_v = tier1_annex_c_initdec_from_bootstrap(boot, codewords)
  guard init_v is Ok(init_state) else { return Err("annex-c initdec failed") }
  let mut state = init_state
  let mut active_contexts = contexts
  let context_trace : Array[Int] = []
  let decisions : Array[Int] = []
  let kinds : Array[String] = []
  let n = width * height
  let significant : Array[Bool] = []
  let signs : Array[Int] = []
  let first_magref_done : Array[Bool] = []
  let sigprop_member : Array[Bool] = []
  let significant_before_bp : Array[Bool] = []
  for _ in 0..<n {
    significant.push(false)
    signs.push(0)
    first_magref_done.push(false)
    sigprop_member.push(false)
    significant_before_bp.push(false)
  }
  let mut raw_reader : Tier1RawBitReader = {
    source: Bytes::new(0),
    byte_pos: 0,
    c: 0,
    ct: 0,
  }
  // T.800-2015 D.6: mode selection per segment type:
  // RAW/MQ is selected at segment start and then kept for all passes in segment.
  let mut segment_use_raw = false
  let mut trace_ord = 0
  let mut trace_emitted = 0
  for i in 0..<coding_passes {
    let pass_kind = i % 3
    if i == trace_target_pass {
      trace_ord = 0
      trace_emitted = 0
    }
    // T.800-2015 A.6.1 / B.10.7: re-initialize MQ decoder at segment boundaries.
    // TERMALL (0x04): each pass has its own segment.
    // Multi-layer non-TERMALL: each layer contribution is a segment.
    // RESET (0x02): reset all contexts to their initial states after each pass.
    let has_segment_start = if i < pass_segment_starts.length() {
      pass_segment_starts[i]
    } else {
      i < pass_segments.length() && pass_segments[i].length() > 0
    }
    if has_segment_start {
      segment_use_raw = has_bypass &&
        pass_kind != 0 &&
        bpno_plus_one <= raw_bp_threshold
    }
    let use_raw = segment_use_raw
    if trace_target_pass >= 0 {
      let pass_label = if pass_kind == 0 {
        "cleanup"
      } else if pass_kind == 1 {
        "sigprop"
      } else {
        "magref"
      }
      println(
        "recon-audit:mq-pass-begin:pass=\{i} kind=\{pass_label} bpno_plus_one=\{bpno_plus_one} use_raw=\{use_raw} a=\{state.a} c=\{state.c} ct=\{state.ct}",
      )
    }
    if has_segment_start && i < pass_segments.length() {
      let seg = pass_segments[i]
      if use_raw {
        // BYPASS raw segments must reset bit-reader even for zero-length segments.
        raw_reader = { source: seg, byte_pos: 0, c: 0, ct: 0, }
      } else {
        // T.800-2015 C.2.7: empty segment initialization seed 0xFF.
        let b0 = if seg.length() > 0 { seg[0].to_int() } else { 0xFF }
        let pre : Tier1AnnexCDecoderState = {
          a: 0x8000,
          c: b0 << 16,
          ct: 0,
          byte_pos: 1,
          prev_byte: b0,
          source: seg,
        }
        let bi_v = tier1_annex_c_bytein(pre)
        guard bi_v is Ok(after_bi) else {
          return Err("annex-c TERMALL re-init bytein failed at pass \{i}")
        }
        state = {
          a: 0x8000,
          c: after_bi.c << 7,
          ct: after_bi.ct - 7,
          byte_pos: after_bi.byte_pos,
          prev_byte: after_bi.prev_byte,
          source: seg,
        }
      }
    }
    if has_reset && i > 0 {
      let rst_v = tier1_annex_c_reset_contexts(
        TIER1_ANNEX_C_DEFAULT_CONTEXT_COUNT,
      )
      guard rst_v is Ok(fresh) else {
        return Err("annex-c RESET context reset failed at pass \{i}")
      }
      active_contexts = fresh
    }
    if pass_kind == 0 {
      // Cleanup pass (D.3.4) with stripe-based scan and run-length coding
      let mut stripe_top = 0
      while stripe_top < height {
        let stripe_height = if stripe_top + 4 <= height {
          4
        } else {
          height - stripe_top
        }
        for x in 0..<width {
          // Check run-length eligibility (D.3.4): requires exactly 4 rows
          // in the stripe. "If there are fewer than four rows remaining in
          // a code-block, then no run-length coding is used."
          let mut run_eligible = stripe_height == 4
          for j in 0..<stripe_height {
            let y = stripe_top + j
            let idx = y * width + x
            if significant[idx] || sigprop_member[idx] {
              run_eligible = false
              break
            }
            let vsc = has_causal && y % 4 == 3
            let (hi, vi, di) = tier1_spec_neighbor_sig_counts(
              width,
              height,
              significant,
              x,
              y,
              mask_south=vsc,
            )
            if hi + vi + di > 0 {
              run_eligible = false
              break
            }
          }
          let mut first_sig_pos = -1
          if run_eligible {
            // Decode run-length bit (CX=17 UNIFORM) — consumed from MQ
            // but NOT pushed to decisions (internal to encoder format)
            let rl_ctx_before = active_contexts[17]
            let rl_qe_v = tier1_annex_c_qe_value(rl_ctx_before.state_index)
            guard rl_qe_v is Ok(rl_qe_before) else {
              return Err("annex-c cleanup run-length qe lookup failed")
            }
            let rl_a_before = state.a
            let rl_c_before = state.c
            let rl_ct_before = state.ct
            let rl_v = tier1_annex_c_decode_one_with_context(
              state, active_contexts, 17,
            )
            guard rl_v is Ok((rl_bit, _, rl_state, rl_contexts)) else {
              return Err("annex-c cleanup run-length decode failed")
            }
            if trace_target_pass >= 0 && i == 0 && stripe_top == 0 && x < 4 {
              println(
                "recon-audit:mq-cleanup-rl:pass=\{i} x=\{x} stripe_top=\{stripe_top} rl_bit=\{rl_bit} a_before=\{rl_a_before} c_before=\{rl_c_before} ct_before=\{rl_ct_before} qeval_before=\{rl_qe_before} mps_before=\{rl_ctx_before.mps}",
              )
            }
            state = rl_state
            active_contexts = rl_contexts
            if rl_bit == 0 {
              // All samples in column are insignificant — push synthetic
              // "not significant" decisions for each sample in the column
              for j in 0..<stripe_height {
                let y = stripe_top + j
                if y < height {
                  context_trace.push(0)
                  decisions.push(0)
                  kinds.push("RL-skip")
                }
              }
              continue
            }
            // Decode 2-bit position within column (CX=18 UNIFORM) —
            // consumed from MQ but NOT pushed to decisions
            let p0_v = tier1_annex_c_decode_one_with_context(
              state, active_contexts, 18,
            )
            guard p0_v is Ok((p0_bit, _, p0_state, p0_contexts)) else {
              return Err("annex-c cleanup run-length position decode failed")
            }
            state = p0_state
            active_contexts = p0_contexts
            let p1_v = tier1_annex_c_decode_one_with_context(
              state, active_contexts, 18,
            )
            guard p1_v is Ok((p1_bit, _, p1_state, p1_contexts)) else {
              return Err("annex-c cleanup run-length position decode failed")
            }
            state = p1_state
            active_contexts = p1_contexts
            first_sig_pos = (p0_bit << 1) | p1_bit
            if trace_target_pass >= 0 && i == 0 && stripe_top == 0 && x < 4 {
              println(
                "recon-audit:mq-cleanup-runlen:pass=\{i} x=\{x} stripe_top=\{stripe_top} p0=\{p0_bit} p1=\{p1_bit} runlen=\{first_sig_pos}",
              )
            }
            // Push synthetic "not significant" for positions before first_sig_pos
            for j in 0..<first_sig_pos {
              let y = stripe_top + j
              if y < height {
                context_trace.push(0)
                decisions.push(0)
                kinds.push("RL-pre")
              }
            }
            // Mark first_sig_pos as significant and decode sign
            let y = stripe_top + first_sig_pos
            if y < height {
              let idx = y * width + x
              significant[idx] = true
              if trace_target_pass >= 0 &&
                tier1_trace_target_idx(width, height, idx) {
                println(
                  "recon-audit:mq-target-neighbor:pass=\{i} stage=cleanup-rl-sig idx=\{idx} label=\{tier1_trace_target_label(width, height, idx)} x=\{x} y=\{y} sign_ctx=pending first_magref_done=\{first_magref_done[idx]}",
                )
              }
              // Push "significant" decision
              context_trace.push(0)
              decisions.push(1)
              kinds.push("RL-sig")
              let rl_vsc = has_causal && y % 4 == 3
              let (h_contrib, v_contrib) = tier1_spec_neighbor_sign_contributions(
                width,
                height,
                significant,
                signs,
                x,
                y,
                mask_south=rl_vsc,
              )
              let (sign_ctx, xor_bit) = tier1_spec_sign_context(
                h_contrib, v_contrib,
              )
              let sign_v = tier1_annex_c_decode_one_with_context(
                state, active_contexts, sign_ctx,
              )
              guard sign_v
                is Ok((raw_sign, sign_kind, sign_state, sign_contexts)) else {
                return Err("annex-c cleanup run-length sign decode failed")
              }
              let true_sign = raw_sign ^ xor_bit
              context_trace.push(sign_ctx)
              decisions.push(true_sign)
              kinds.push(sign_kind)
              state = sign_state
              active_contexts = sign_contexts
              signs[idx] = if true_sign == 0 { 1 } else { -1 }
            }
          }
          // Code remaining positions in column after run-length position
          for j in 0..<stripe_height {
            if run_eligible && j <= first_sig_pos {
              continue // already handled by run-length
            }
            let y = stripe_top + j
            if y >= height {
              continue
            }
            let idx = y * width + x
            if significant[idx] || sigprop_member[idx] {
              continue
            }
            // Table D.1: significance context from (Hi, Vi, Di) per subband type
            let cl_vsc = has_causal && y % 4 == 3
            let (hi, vi, di) = tier1_spec_neighbor_sig_counts(
              width,
              height,
              significant,
              x,
              y,
              mask_south=cl_vsc,
            )
            let sig_ctx = tier1_spec_sig_context(hi, vi, di, subband_type)
            let sig_v = tier1_annex_c_decode_one_with_context(
              state, active_contexts, sig_ctx,
            )
            guard sig_v is Ok((sig, sig_kind, next_state, next_contexts)) else {
              return Err(
                "annex-c mini-block cleanup significance decode failed",
              )
            }
            context_trace.push(sig_ctx)
            decisions.push(sig)
            kinds.push(sig_kind)
            state = next_state
            active_contexts = next_contexts
            if sig == 0 {
              continue
            }
            significant[idx] = true
            if trace_target_pass >= 0 &&
              tier1_trace_target_idx(width, height, idx) {
              println(
                "recon-audit:mq-target-neighbor:pass=\{i} stage=cleanup-sig idx=\{idx} label=\{tier1_trace_target_label(width, height, idx)} x=\{x} y=\{y} hi=\{hi} vi=\{vi} di=\{di} sig_ctx=\{sig_ctx} first_magref_done=\{first_magref_done[idx]}",
              )
            }
            // Table D.3: sign context from neighbor sign contributions
            let (h_contrib, v_contrib) = tier1_spec_neighbor_sign_contributions(
              width,
              height,
              significant,
              signs,
              x,
              y,
              mask_south=cl_vsc,
            )
            let (sign_ctx, xor_bit) = tier1_spec_sign_context(
              h_contrib, v_contrib,
            )
            let sign_v = tier1_annex_c_decode_one_with_context(
              state, active_contexts, sign_ctx,
            )
            guard sign_v is Ok((raw_sign, sign_kind, sign_state, sign_contexts)) else {
              return Err("annex-c mini-block cleanup sign decode failed")
            }
            let true_sign = raw_sign ^ xor_bit
            context_trace.push(sign_ctx)
            decisions.push(true_sign)
            kinds.push(sign_kind)
            state = sign_state
            active_contexts = sign_contexts
            signs[idx] = if true_sign == 0 { 1 } else { -1 }
          }
        }
        stripe_top += 4
      }
      // SEGMARK (A.6.1 Table A.19 bit 5 = 0x20): decode 4 bits with CX=18
      // (UNIFORM context). T.800-2015 D.5: Expected pattern 1010 (0xA).
      // These are verification bits and must NOT be pushed to decisions array.
      if (code_block_style & 0x20) != 0 {
        let mut segmark_val = 0
        for _seg in 0..<4 {
          let seg_v = tier1_annex_c_decode_one_with_context(
            state, active_contexts, 18,
          )
          guard seg_v is Ok((seg_bit, _seg_kind, seg_state, seg_contexts)) else {
            return Err("annex-c mini-block SEGMARK decode failed")
          }
          segmark_val = (segmark_val << 1) | seg_bit
          state = seg_state
          active_contexts = seg_contexts
        }
        // T.800-2015 D.5: Verify expected segmentation symbol 1010 (0xA = 10)
        // Non-match indicates bit error in codeblock data; continue for robustness
        // but this may propagate errors to subsequent coefficients
        if segmark_val != 10 {
          // Log but continue - spec allows error detection without hard failure
          ()
        }
      }
      // T.800-2015 D.3: PI flags cleared after cleanup pass. Keep sigprop membership scoped
      // to the current bit-plane so later cleanup passes do not skip samples
      // that were only visited by the previous sigprop pass.
      for k in 0..<n {
        sigprop_member[k] = false
      }
      if bpno_plus_one > 0 {
        bpno_plus_one -= 1
      }
      continue
    }
    if pass_kind == 1 {
      // Significance propagation pass (D.3.2) - stripe-based scan
      // Snapshot significance state before this bit-plane's passes
      // (magref uses this to skip coefficients that became significant
      // in the current bit-plane's sigprop/cleanup — D.3.3)
      for k in 0..<n {
        sigprop_member[k] = false
        significant_before_bp[k] = significant[k]
      }
      if trace_target_pass >= 0 {
        let (trace_hi, trace_vi, trace_di) = tier1_spec_neighbor_sig_counts(
          width, height, significant, 0, 0,
        )
        println(
          "recon-audit:mq-target-idx:pass=\{i} stage=sigprop-snapshot idx=0 significant_before_bp=\{significant_before_bp[0]} first_magref_done=\{first_magref_done[0]} hi=\{trace_hi} vi=\{trace_vi} di=\{trace_di} right_sig=\{width > 1 && significant[1]} down_sig=\{height > 1 && significant[width]} diag_sig=\{width > 1 && height > 1 && significant[width + 1]}",
        )
      }
      let mut sp_stripe_top = 0
      while sp_stripe_top < height {
        let sp_stripe_h = if sp_stripe_top + 4 <= height {
          4
        } else {
          height - sp_stripe_top
        }
        for x in 0..<width {
          for j in 0..<sp_stripe_h {
            let y = sp_stripe_top + j
            let idx = y * width + x
            if significant[idx] {
              continue
            }
            let sp_vsc = has_causal && y % 4 == 3
            let (hi, vi, di) = tier1_spec_neighbor_sig_counts(
              width,
              height,
              significant,
              x,
              y,
              mask_south=sp_vsc,
            )
            if trace_target_pass >= 0 && idx == 0 {
              println(
                "recon-audit:mq-target-idx:pass=\{i} stage=sigprop-check idx=0 hi=\{hi} vi=\{vi} di=\{di} eligible=\{hi + vi + di > 0} first_magref_done=\{first_magref_done[idx]}",
              )
            }
            if hi + vi + di <= 0 {
              continue
            }
            // This coefficient is a sigprop member — mark it
            sigprop_member[idx] = true
            if use_raw {
              // D.6 BYPASS: read raw significance bit
              let sig = tier1_raw_read_bit(raw_reader)
              context_trace.push(0)
              decisions.push(sig)
              kinds.push("RAW-sp-sig")
              if sig == 0 {
                continue
              }
              significant[idx] = true
              // D.6 BYPASS: read raw sign bit (0=positive, 1=negative)
              let raw_sign = tier1_raw_read_bit(raw_reader)
              context_trace.push(0)
              decisions.push(raw_sign)
              kinds.push("RAW-sp-sign")
              signs[idx] = if raw_sign == 0 { 1 } else { -1 }
            } else {
              let sig_ctx = tier1_spec_sig_context(hi, vi, di, subband_type)
              let sig_ctx_before = active_contexts[sig_ctx]
              let sig_qe_v = tier1_annex_c_qe_value(sig_ctx_before.state_index)
              guard sig_qe_v is Ok(sig_qe_before) else {
                return Err("annex-c mini-block sigprop sig qe lookup failed")
              }
              let sig_a_before = state.a
              let sig_c_before = state.c
              let sig_ct_before = state.ct
              let sig_byte_pos_before = state.byte_pos
              let sig_prev_byte_before = state.prev_byte
              let sig_next_byte_before = if state.byte_pos <
                state.source.length() {
                state.source[state.byte_pos].to_int()
              } else {
                0xFF
              }
              let sig_v = tier1_annex_c_decode_one_with_context(
                state, active_contexts, sig_ctx,
              )
              guard sig_v is Ok((sig, sig_kind, next_state, next_contexts)) else {
                return Err(
                  "annex-c mini-block sigprop significance decode failed",
                )
              }
              context_trace.push(sig_ctx)
              decisions.push(sig)
              kinds.push(sig_kind)
              if i == trace_target_pass && trace_emitted < trace_max_events {
                let sig_ctx_after = next_contexts[sig_ctx]
                let sig_next_qe_v = tier1_annex_c_qe_value(
                  sig_ctx_after.state_index,
                )
                guard sig_next_qe_v is Ok(sig_qe_after) else {
                  return Err("annex-c mini-block sigprop next qe lookup failed")
                }
                println(
                  "recon-audit:mq-pass-state:pass=\{i} ord=\{trace_ord} kind=sigprop-sig x=\{x} y=\{y} idx=\{idx} ctx=\{sig_ctx} bit=\{sig} a_before=\{sig_a_before} c_before=\{sig_c_before} ct_before=\{sig_ct_before} byte_pos_before=\{sig_byte_pos_before} prev_byte_before=\{sig_prev_byte_before} next_byte_before=\{sig_next_byte_before} a_after=\{next_state.a} c_after=\{next_state.c} ct_after=\{next_state.ct} byte_pos_after=\{next_state.byte_pos} prev_byte_after=\{next_state.prev_byte} qeval_before=\{sig_qe_before} mps_before=\{sig_ctx_before.mps} qeval_after=\{sig_qe_after} mps_after=\{sig_ctx_after.mps}",
                )
                trace_emitted += 1
              }
              if i == trace_target_pass {
                trace_ord += 1
              }
              state = next_state
              active_contexts = next_contexts
              if sig == 0 {
                continue
              }
              significant[idx] = true
              if trace_target_pass >= 0 &&
                tier1_trace_target_idx(width, height, idx) {
                println(
                  "recon-audit:mq-target-neighbor:pass=\{i} stage=sigprop-sig idx=\{idx} label=\{tier1_trace_target_label(width, height, idx)} x=\{x} y=\{y} hi=\{hi} vi=\{vi} di=\{di} sig_ctx=\{sig_ctx} first_magref_done=\{first_magref_done[idx]}",
                )
              }
              let (h_contrib, v_contrib) = tier1_spec_neighbor_sign_contributions(
                width,
                height,
                significant,
                signs,
                x,
                y,
                mask_south=sp_vsc,
              )
              let (sign_ctx, xor_bit) = tier1_spec_sign_context(
                h_contrib, v_contrib,
              )
              let sign_ctx_before = active_contexts[sign_ctx]
              let sign_qe_v = tier1_annex_c_qe_value(
                sign_ctx_before.state_index,
              )
              guard sign_qe_v is Ok(sign_qe_before) else {
                return Err("annex-c mini-block sigprop sign qe lookup failed")
              }
              let sign_a_before = state.a
              let sign_c_before = state.c
              let sign_ct_before = state.ct
              let sign_byte_pos_before = state.byte_pos
              let sign_prev_byte_before = state.prev_byte
              let sign_next_byte_before = if state.byte_pos <
                state.source.length() {
                state.source[state.byte_pos].to_int()
              } else {
                0xFF
              }
              let sign_v = tier1_annex_c_decode_one_with_context(
                state, active_contexts, sign_ctx,
              )
              guard sign_v
                is Ok((raw_sign, sign_kind, sign_state, sign_contexts)) else {
                return Err("annex-c mini-block sigprop sign decode failed")
              }
              let true_sign = raw_sign ^ xor_bit
              if i == trace_target_pass && trace_emitted < trace_max_events {
                let sign_ctx_after = sign_contexts[sign_ctx]
                let sign_next_qe_v = tier1_annex_c_qe_value(
                  sign_ctx_after.state_index,
                )
                guard sign_next_qe_v is Ok(sign_qe_after) else {
                  return Err(
                    "annex-c mini-block sigprop sign next qe lookup failed",
                  )
                }
                println(
                  "recon-audit:mq-pass-state:pass=\{i} ord=\{trace_ord} kind=sigprop-sign x=\{x} y=\{y} idx=\{idx} ctx=\{sign_ctx} bit=\{raw_sign} xor_bit=\{xor_bit} a_before=\{sign_a_before} c_before=\{sign_c_before} ct_before=\{sign_ct_before} byte_pos_before=\{sign_byte_pos_before} prev_byte_before=\{sign_prev_byte_before} next_byte_before=\{sign_next_byte_before} a_after=\{sign_state.a} c_after=\{sign_state.c} ct_after=\{sign_state.ct} byte_pos_after=\{sign_state.byte_pos} prev_byte_after=\{sign_state.prev_byte} qeval_before=\{sign_qe_before} mps_before=\{sign_ctx_before.mps} qeval_after=\{sign_qe_after} mps_after=\{sign_ctx_after.mps} decoded_sign=\{true_sign}",
                )
                trace_emitted += 1
              }
              if i == trace_target_pass {
                trace_ord += 1
              }
              context_trace.push(sign_ctx)
              decisions.push(true_sign)
              kinds.push(sign_kind)
              state = sign_state
              active_contexts = sign_contexts
              signs[idx] = if true_sign == 0 { 1 } else { -1 }
            }
          }
        }
        sp_stripe_top += 4
      }
      continue
    }
    // Magnitude refinement pass (D.3.3) - stripe-based scan
    let mut mr_stripe_top = 0
    while mr_stripe_top < height {
      let mr_stripe_h = if mr_stripe_top + 4 <= height {
        4
      } else {
        height - mr_stripe_top
      }
      for x in 0..<width {
        for j in 0..<mr_stripe_h {
          let y = mr_stripe_top + j
          let idx = y * width + x
          if !significant_before_bp[idx] {
            continue
          }
          if use_raw {
            // D.6 BYPASS: read raw magnitude refinement bit
            let mag_bit = tier1_raw_read_bit(raw_reader)
            if trace_target_pass >= 0 && idx == 0 {
              println(
                "recon-audit:mq-target-idx:pass=\{i} stage=magref-raw idx=0 first_magref=\{!first_magref_done[idx]} bit=\{mag_bit}",
              )
            }
            context_trace.push(0)
            decisions.push(mag_bit)
            kinds.push("RAW-mr")
            first_magref_done[idx] = true
          } else {
            // Table D.4: magref context from first_magref and neighbor significance
            let mr_vsc = has_causal && y % 4 == 3
            let (hi, vi, di) = tier1_spec_neighbor_sig_counts(
              width,
              height,
              significant,
              x,
              y,
              mask_south=mr_vsc,
            )
            let has_sig_neighbor = hi + vi + di > 0
            let first_magref_before = !first_magref_done[idx]
            let mag_ctx = tier1_spec_magref_context(
              first_magref_before, has_sig_neighbor,
            )
            let ctx_before = active_contexts[mag_ctx]
            let qe_v = tier1_annex_c_qe_value(ctx_before.state_index)
            guard qe_v is Ok(qe_before) else {
              return Err("annex-c mini-block magref qe lookup failed")
            }
            let a_before = state.a
            let c_before = state.c
            let ct_before = state.ct
            let mag_v = tier1_annex_c_decode_one_with_context(
              state, active_contexts, mag_ctx,
            )
            guard mag_v is Ok((mag_bit, mag_kind, next_state, next_contexts)) else {
              return Err("annex-c mini-block magref decode failed")
            }
            if trace_target_pass >= 0 && idx == 0 {
              println(
                "recon-audit:mq-target-idx:pass=\{i} stage=magref idx=0 ctx=\{mag_ctx} first_magref=\{first_magref_before} has_sig_neighbor=\{has_sig_neighbor} bit=\{mag_bit}",
              )
            }
            if i == trace_target_pass && trace_emitted < trace_max_events {
              let ctx_after = next_contexts[mag_ctx]
              let next_qe_v = tier1_annex_c_qe_value(ctx_after.state_index)
              guard next_qe_v is Ok(qe_after) else {
                return Err("annex-c mini-block magref next qe lookup failed")
              }
              println(
                "recon-audit:mq-pass-state:pass=\{i} ord=\{trace_ord} kind=magref x=\{x} y=\{y} idx=\{idx} ctx=\{mag_ctx} first_magref=\{first_magref_before} has_sig_neighbor=\{has_sig_neighbor} bit=\{mag_bit} a_before=\{a_before} c_before=\{c_before} ct_before=\{ct_before} qeval_before=\{qe_before} mps_before=\{ctx_before.mps} a_after=\{next_state.a} c_after=\{next_state.c} ct_after=\{next_state.ct} qeval_after=\{qe_after} mps_after=\{ctx_after.mps}",
              )
              trace_emitted += 1
            }
            trace_ord += 1
            context_trace.push(mag_ctx)
            decisions.push(mag_bit)
            kinds.push(mag_kind)
            state = next_state
            active_contexts = next_contexts
            first_magref_done[idx] = true
          }
        }
      }
      mr_stripe_top += 4
    }
  }
  Ok((context_trace, decisions, kinds))
}

///|
// Spec basis (T.800-2015 B.10 / Annex C / Annex D):
// - Coding-pass segments (B.10) can be decoded as one continuous MQ byte
//   stream for staged Tier-1 preview in Annex C / D.3 order.
// - The mini-block core remains delegated to decode_mini_block_passes so that
//   existing behavior is preserved.
pub fn tier1_annex_c_decode_mini_block_pass_segments(
  pass_segments : Array[Bytes],
  contexts : Array[Tier1AnnexCContextState],
  width : Int,
  height : Int,
  coding_passes : Int,
  sigprop_discovery_enabled : Bool,
  code_block_style? : Int = 0,
  subband_type? : Int = 0,
  initial_bpno_plus_one? : Int = 0,
  roishift? : Int = 0,
) -> Result[(Array[Int], Array[Int], Array[String]), String] {
  let has_termall = (code_block_style & 0x04) != 0
  if has_termall && pass_segments.length() > 1 {
    // TERMALL: each pass has its own segment with independent MQ init.
    let mut first_seg : Bytes = Bytes::new(0)
    for seg in pass_segments {
      if seg.length() > 0 {
        first_seg = seg
        break
      }
    }
    if first_seg.length() == 0 {
      return Err("annex-c TERMALL: no non-empty pass segment")
    }
    let codewords : Array[Bytes] = [first_seg]
    let pass_segment_starts : Array[Bool] = []
    for _ in 0..<pass_segments.length() {
      // TERMALL segments are per-pass by definition, including zero-length passes.
      pass_segment_starts.push(true)
    }
    let boot_v = tier1_annex_c_bootstrap_from_codewords(codewords)
    guard boot_v is Ok(boot) else {
      return Err("annex-c TERMALL bootstrap failed")
    }
    tier1_annex_c_decode_mini_block_passes(
      boot,
      codewords,
      contexts,
      width,
      height,
      coding_passes,
      sigprop_discovery_enabled,
      code_block_style~,
      pass_segments~,
      pass_segment_starts~,
      subband_type~,
      initial_bpno_plus_one~,
      roishift~,
    )
  } else {
    let merged_v = tier1_annex_c_merge_pass_segments_to_codewords(pass_segments)
    guard merged_v is Ok(codewords) else {
      return Err("annex-c pass-segment merge failed")
    }
    let boot_v = tier1_annex_c_bootstrap_from_codewords(codewords)
    guard boot_v is Ok(boot) else { return Err("annex-c bootstrap failed") }
    tier1_annex_c_decode_mini_block_passes(
      boot,
      codewords,
      contexts,
      width,
      height,
      coding_passes,
      sigprop_discovery_enabled,
      code_block_style~,
      subband_type~,
      initial_bpno_plus_one~,
      roishift~,
    )
  }
}

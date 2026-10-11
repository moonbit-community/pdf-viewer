///|
// Spec grouping:
// - Annex C.3 MQ context state management
// - Context initialization, save/restore for coding pass boundaries

///|
// Spec basis (T.800-2015 Table D.7):
// Initialize context states according to Table D.7 initial states.
// CX 0 (all-zero-neighbours sig): initial state 4, MPS=0
// CX 17 (AGG / run-length aggregation): initial state 3, MPS=0
// CX 18 (UNI / uniform): initial state 46, MPS=0
// All others: initial state 0, MPS=0
pub fn tier1_annex_c_reset_contexts(
  context_count : Int,
) -> Result[Array[Tier1AnnexCContextState], String] {
  if context_count <= 0 {
    return Err("annex-c context count must be positive")
  }
  let out : Array[Tier1AnnexCContextState] = []
  for i in 0..<context_count {
    let state_index = if i == 0 {
      4
    } else if i == 17 {
      3
    } else if i == 18 {
      46
    } else {
      0
    }
    out.push({ state_index, mps: 0, })
  }
  Ok(out)
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// Serialize context states for checkpoint/restore across segment boundaries.
pub fn tier1_annex_c_save_contexts(
  contexts : Array[Tier1AnnexCContextState],
) -> Result[Array[Int], String] {
  if contexts.length() <= 0 {
    return Err("annex-c contexts are empty")
  }
  let out : Array[Int] = []
  for c in contexts {
    if c.state_index < 0 || c.state_index > 46 {
      return Err("annex-c state index is out of range")
    }
    if c.mps != 0 && c.mps != 1 {
      return Err("annex-c mps bit is out of range")
    }
    out.push((c.state_index << 1) + c.mps)
  }
  Ok(out)
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// Restore context states from serialized checkpoint.
pub fn tier1_annex_c_restore_contexts(
  snapshot : Array[Int],
) -> Result[Array[Tier1AnnexCContextState], String] {
  if snapshot.length() <= 0 {
    return Err("annex-c snapshot is empty")
  }
  let out : Array[Tier1AnnexCContextState] = []
  for v in snapshot {
    if v < 0 || v > 95 {
      return Err("annex-c snapshot value is out of range")
    }
    out.push({ state_index: v >> 1, mps: v & 1, })
  }
  Ok(out)
}

///|
// Spec grouping:
// - Annex C.2 Probability estimation (Table C.2 QE values)
// - MQ arithmetic decoder state transition tables

///|
// Spec basis (T.800-2015 Annex C.2 Table C.2):
// Returns (qe, nmps, nlps, switch) for the given state index.
// qe: probability estimate value
// nmps: next state after MPS (more probable symbol)
// nlps: next state after LPS (less probable symbol)
// switch: whether to switch MPS sense on LPS
fn tier1_annex_c_table_entry(
  state_index : Int,
) -> Result[(Int, Int, Int, Bool), String] {
  if state_index < 0 || state_index > 46 {
    return Err("annex-c state index is out of range")
  }
  let qe : Array[Int] = [
    0x5601, 0x3401, 0x1801, 0x0AC1, 0x0521, 0x0221, 0x5601, 0x5401, 0x4801, 0x3801,
    0x3001, 0x2401, 0x1C01, 0x1601, 0x5601, 0x5401, 0x5101, 0x4801, 0x3801, 0x3401,
    0x3001, 0x2801, 0x2401, 0x2201, 0x1C01, 0x1801, 0x1601, 0x1401, 0x1201, 0x1101,
    0x0AC1, 0x09C1, 0x08A1, 0x0521, 0x0441, 0x02A1, 0x0221, 0x0141, 0x0111, 0x0085,
    0x0049, 0x0025, 0x0015, 0x0009, 0x0005, 0x0001, 0x5601,
  ]
  let nmps : Array[Int] = [
    1, 2, 3, 4, 5, 38, 7, 8, 9, 10, 11, 12, 13, 29, 15, 16, 17, 18, 19, 20, 21, 22,
    23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42,
    43, 44, 45, 45, 46,
  ]
  let nlps : Array[Int] = [
    1, 6, 9, 12, 29, 33, 6, 14, 14, 14, 17, 18, 20, 21, 14, 14, 15, 16, 17, 18, 19,
    19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38,
    39, 40, 41, 42, 43, 46,
  ]
  let switch_bits : Array[Int] = [
    1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  ]
  Ok(
    (
      qe[state_index],
      nmps[state_index],
      nlps[state_index],
      switch_bits[state_index] == 1,
    ),
  )
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// Get QE probability value for a state index.
fn tier1_annex_c_qe_value(state_index : Int) -> Result[Int, String] {
  let entry_v = tier1_annex_c_table_entry(state_index)
  guard entry_v is Ok((qe, _, _, _)) else {
    return Err("annex-c state index is out of range")
  }
  Ok(qe)
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// Get next state after MPS for a state index.
fn tier1_annex_c_nmps_state(state_index : Int) -> Result[Int, String] {
  let entry_v = tier1_annex_c_table_entry(state_index)
  guard entry_v is Ok((_, nmps, _, _)) else {
    return Err("annex-c state index is out of range")
  }
  Ok(nmps)
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// Get next state after LPS for a state index.
fn tier1_annex_c_nlps_state(state_index : Int) -> Result[Int, String] {
  let entry_v = tier1_annex_c_table_entry(state_index)
  guard entry_v is Ok((_, _, nlps, _)) else {
    return Err("annex-c state index is out of range")
  }
  Ok(nlps)
}

///|
// Spec basis (T.800-2015 Annex C / Annex D):
// Check if MPS sense should be switched on LPS.
fn tier1_annex_c_switch_mps_on_lps(state_index : Int) -> Result[Bool, String] {
  let entry_v = tier1_annex_c_table_entry(state_index)
  guard entry_v is Ok((_, _, _, sw)) else {
    return Err("annex-c state index is out of range")
  }
  Ok(sw)
}

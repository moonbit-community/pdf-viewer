///|
// Spec grouping:
// - Profile validation and decode capability gates

///|
// Spec basis (T.800-2015 Annex A/B/D):
// - profile gates and packet/Tier-1 staging are derived from COD/QCD
//   signalling and B.10/D.3 decode structure.
pub fn non_simple_profile_reason(
  stream : @core.Codestream,
  siz : @core.SizMetadata,
) -> String {
  let csiz = siz.csiz
  let mut layers = -1
  let mut decomp = -1
  let mut uses_precincts = false
  let mut mct = -1
  if stream.metadata.cod is Some(cod) {
    layers = cod.layers
    decomp = cod.decomposition_levels
    uses_precincts = cod.uses_precincts
    mct = cod.multiple_component_transform
  }
  "non-simple-profile: csiz=\{csiz}, layers=\{layers}, decomp=\{decomp}, precincts=\{uses_precincts}, mct=\{mct}"
}

///|
fn read_u32_be_from_marker_payload(payload : Bytes, at : Int) -> Int? {
  if at + 3 >= payload.length() {
    return None
  }
  Some(
    (payload[at].to_int() << 24) +
    (payload[at + 1].to_int() << 16) +
    (payload[at + 2].to_int() << 8) +
    payload[at + 3].to_int(),
  )
}

///|
fn first_cap_ccap15_word(stream : @core.Codestream) -> Int? {
  for segment in stream.segments {
    if segment.code != 0xFF50 {
      continue
    }
    let payload = segment.payload
    if payload.length() < 6 {
      continue
    }
    if payload[0].to_int() != 0x00 || payload[1].to_int() != 0x02 {
      continue
    }
    return read_u32_be_from_marker_payload(payload, 2)
  }
  None
}

///|
fn htj2k_component_override_signalled(stream : @core.Codestream) -> Bool {
  for coc in stream.metadata.coc {
    if coc.parameters.length() >= 4 && (coc.parameters[3] & 0x40) != 0 {
      return true
    }
  }
  false
}

///|
fn htj2k_has_non_main_header_component_override(
  stream : @core.Codestream,
) -> Bool {
  for coc in stream.metadata.coc {
    if !coc.in_main_header {
      return true
    }
  }
  for qcc in stream.metadata.qcc {
    if !qcc.in_main_header {
      return true
    }
  }
  false
}

///|
pub fn htj2k_signalled(stream : @core.Codestream) -> Bool {
  let ht_style = if stream.metadata.cod is Some(cod) {
    (cod.code_block_style & 0x40) != 0
  } else {
    false
  }
  let mut tile_ht_style = false
  for tile_cod in stream.metadata.tile_cod {
    if (tile_cod.cod.code_block_style & 0x40) != 0 {
      tile_ht_style = true
      break
    }
  }
  ht_style ||
  tile_ht_style ||
  htj2k_component_override_signalled(stream) ||
  first_cap_ccap15_word(stream) is Some(_)
}

///|
pub fn htj2k_not_supported_reason(stream : @core.Codestream) -> String {
  let mut code_block_style = -1
  if stream.metadata.cod is Some(cod) {
    code_block_style = cod.code_block_style
  }
  let mut tile_code_block_style = -1
  for tile_cod in stream.metadata.tile_cod {
    if (tile_cod.cod.code_block_style & 0x40) != 0 {
      tile_code_block_style = tile_cod.cod.code_block_style
      break
    }
  }
  let cap_reason = if first_cap_ccap15_word(stream) is Some(ccap15) {
    "cap_present=true, ccap15=\{ccap15}"
  } else {
    "cap_present=false"
  }
  let component_override_reason = if htj2k_has_non_main_header_component_override(
      stream,
    ) {
    ", component-override=tile-part-header"
  } else if htj2k_component_override_signalled(stream) {
    ", component-override=main-header"
  } else {
    ""
  }
  "DS-UNSUPPORTED-HTJ2K:cap_present_no_ht_decoder (\{cap_reason}, code-block-style=\{code_block_style}, tile-code-block-style=\{tile_code_block_style}\{component_override_reason})"
}

///|
fn htj2k_cleanup_only_subset_matches(
  code_block_style : Int,
  transformation : Int,
  quantization_style : Int,
) -> Bool {
  if (code_block_style & 0x40) == 0 {
    return false
  }
  if code_block_style != 0x40 && code_block_style != 0x48 {
    return false
  }
  if transformation == 1 && (quantization_style == 0 || quantization_style == 1) {
    return true
  }
  transformation == 0 &&
  (
    quantization_style == 0 ||
    quantization_style == 1 ||
    quantization_style == 2
  )
}

///|
fn tier1_minimal_subset_matches(
  code_block_style : Int,
  transformation : Int,
  quantization_style : Int,
) -> Bool {
  if (code_block_style & 0x40) != 0 {
    return htj2k_cleanup_only_subset_matches(
      code_block_style, transformation, quantization_style,
    )
  }
  if (code_block_style & 0x3F) != code_block_style {
    return false
  }
  if transformation == 1 && (quantization_style == 0 || quantization_style == 1) {
    return true
  }
  transformation == 0 &&
  (
    quantization_style == 0 ||
    quantization_style == 1 ||
    quantization_style == 2
  )
}

///|
fn profile_target_component_indices(
  stream : @core.Codestream,
  cod : @core.CodMetadata,
) -> Array[Int] {
  let csiz = match stream.metadata.siz {
    Some(siz) => siz.csiz
    None => 1
  }
  let targets : Array[Int] = []
  if cod.multiple_component_transform == 1 && csiz >= 3 {
    targets.push(0)
    targets.push(1)
    targets.push(2)
    return targets
  }
  if csiz > 0 {
    targets.push(0)
  }
  targets
}

///|
fn htj2k_cleanup_only_subset_enabled_for_context(
  stream : @core.Codestream,
  cod : @core.CodMetadata,
  qcd : @core.QcdMetadata,
  tile_index? : Int = -1,
) -> (Bool, Bool) {
  let mut has_relevant_ht = false
  for ci in profile_target_component_indices(stream, cod) {
    let (_, _, _, style, transformation, component_qcd_opt) = @geometry.get_component_decode_context(
      stream,
      ci,
      cod,
      fallback_qcd=Some(qcd),
      tile_index~,
    )
    if (style & 0x40) == 0 {
      continue
    }
    guard component_qcd_opt is Some(component_qcd) else { return (false, true) }
    if !htj2k_cleanup_only_subset_matches(
        style,
        transformation,
        component_qcd.quantization_style,
      ) {
      return (false, true)
    }
    has_relevant_ht = true
  }
  (true, has_relevant_ht)
}

///|
fn tier1_minimal_reversible_subset_enabled_for_context(
  stream : @core.Codestream,
  cod : @core.CodMetadata,
  qcd : @core.QcdMetadata,
  tile_index? : Int = -1,
) -> Bool {
  for ci in profile_target_component_indices(stream, cod) {
    let (_, _, _, style, transformation, component_qcd_opt) = @geometry.get_component_decode_context(
      stream,
      ci,
      cod,
      fallback_qcd=Some(qcd),
      tile_index~,
    )
    guard component_qcd_opt is Some(component_qcd) else { return false }
    if !tier1_minimal_subset_matches(
        style,
        transformation,
        component_qcd.quantization_style,
      ) {
      return false
    }
  }
  true
}

///|
fn htj2k_find_tile_cod(
  stream : @core.Codestream,
  tile_index : Int,
) -> @core.CodMetadata? {
  for tile_cod in stream.metadata.tile_cod {
    if tile_cod.tile_index == tile_index {
      return Some(tile_cod.cod)
    }
  }
  None
}

///|
fn htj2k_find_tile_qcd(
  stream : @core.Codestream,
  tile_index : Int,
) -> @core.QcdMetadata? {
  for tile_qcd in stream.metadata.tile_qcd {
    if tile_qcd.tile_index == tile_index {
      return Some(tile_qcd.qcd)
    }
  }
  None
}

///|
fn htj2k_tile_override_indices(stream : @core.Codestream) -> Array[Int] {
  let out : Array[Int] = []
  fn push_unique(out : Array[Int], tile_index : Int) -> Unit {
    if tile_index < 0 {
      return
    }
    let mut seen = false
    for existing in out {
      if existing == tile_index {
        seen = true
        break
      }
    }
    if !seen {
      out.push(tile_index)
    }
  }
  for tile_cod in stream.metadata.tile_cod {
    push_unique(out, tile_cod.tile_index)
  }
  for tile_qcd in stream.metadata.tile_qcd {
    push_unique(out, tile_qcd.tile_index)
  }
  for coc in stream.metadata.coc {
    if !coc.in_main_header {
      push_unique(out, coc.tile_index)
    }
  }
  for qcc in stream.metadata.qcc {
    if !qcc.in_main_header {
      push_unique(out, qcc.tile_index)
    }
  }
  out
}

///|
fn main_context_applies_to_any_tile(
  stream : @core.Codestream,
  tile_override_indices : Array[Int],
) -> Bool {
  if tile_override_indices.length() == 0 {
    return true
  }
  match stream.metadata.siz {
    Some(siz) => tile_override_indices.length() < siz.tile_count
    None => true
  }
}

///|
pub fn htj2k_cleanup_only_subset_enabled(stream : @core.Codestream) -> Bool {
  let main_cod = stream.metadata.cod
  let main_qcd = stream.metadata.qcd
  let tile_override_indices = htj2k_tile_override_indices(stream)
  let mut has_supported_ht = false
  if main_context_applies_to_any_tile(stream, tile_override_indices) &&
    main_cod is Some(cod) &&
    main_qcd is Some(qcd) {
    let (context_ok, context_has_ht) = htj2k_cleanup_only_subset_enabled_for_context(
      stream, cod, qcd,
    )
    if !context_ok {
      return false
    }
    has_supported_ht = has_supported_ht || context_has_ht
  }
  for tile_index in tile_override_indices {
    let effective_cod = match htj2k_find_tile_cod(stream, tile_index) {
      Some(tile_cod) => Some(tile_cod)
      None => main_cod
    }
    let effective_qcd = match htj2k_find_tile_qcd(stream, tile_index) {
      Some(tile_qcd) => Some(tile_qcd)
      None => main_qcd
    }
    guard effective_cod is Some(cod) else { continue }
    guard effective_qcd is Some(qcd) else { continue }
    let (context_ok, context_has_ht) = htj2k_cleanup_only_subset_enabled_for_context(
      stream,
      cod,
      qcd,
      tile_index~,
    )
    if !context_ok {
      return false
    }
    has_supported_ht = has_supported_ht || context_has_ht
  }
  if has_supported_ht {
    return true
  }
  true
}

///|
// Spec basis (T.800-2015 Annex A/B/D):
// - profile gates and packet/Tier-1 staging are derived from COD/QCD
//   signalling and B.10/D.3 decode structure.
pub fn tier1_minimal_reversible_subset_enabled(
  stream : @core.Codestream,
) -> Bool {
  // Spec basis (T.800-2015):
  // - A.6.1 Table A.19: code-block style flags (including termination on pass).
  // - A.6.1 Table A.20: transformation type (5-3 reversible / 9-7 irreversible).
  // - A.6.4/E.1: quantization signalling is carried by QCD quantization style.
  // - B.10 + D.3/D.4 define Tier-1 pass/segment semantics.
  // Staged implementation scope:
  // - reversible baseline: transformation=1 with qstyle=0
  // - irreversible staged bridge: transformation=0 with qstyle=2
  // In both cases code-block style is limited to baseline/TERMALL.
  guard stream.metadata.cod is Some(cod) else { return false }
  guard stream.metadata.qcd is Some(qcd) else { return false }
  let tile_override_indices = htj2k_tile_override_indices(stream)
  if main_context_applies_to_any_tile(stream, tile_override_indices) &&
    !tier1_minimal_reversible_subset_enabled_for_context(stream, cod, qcd) {
    return false
  }
  for tile_index in tile_override_indices {
    let effective_cod = match htj2k_find_tile_cod(stream, tile_index) {
      Some(tile_cod) => Some(tile_cod)
      None => Some(cod)
    }
    let effective_qcd = match htj2k_find_tile_qcd(stream, tile_index) {
      Some(tile_qcd) => Some(tile_qcd)
      None => Some(qcd)
    }
    guard effective_cod is Some(tile_cod) else { continue }
    guard effective_qcd is Some(tile_qcd) else { continue }
    if !tier1_minimal_reversible_subset_enabled_for_context(
        stream,
        tile_cod,
        tile_qcd,
        tile_index~,
      ) {
      return false
    }
  }
  true
}

///|
// Spec basis (T.800-2015 Annex A/B/D):
// - profile gates and packet/Tier-1 staging are derived from COD/QCD
//   signalling and B.10/D.3 decode structure.
pub fn tier1_minimal_reversible_subset_reason(
  stream : @core.Codestream,
) -> String {
  let mut transformation = -1
  let mut code_block_style = -1
  let mut qstyle = -1
  if stream.metadata.cod is Some(cod) {
    transformation = cod.transformation
    code_block_style = cod.code_block_style
  }
  if stream.metadata.qcd is Some(qcd) {
    qstyle = qcd.quantization_style
  }
  "tier1-minimal-reversible-subset: transformation=\{transformation}, code-block-style=\{code_block_style}, qstyle=\{qstyle}"
}

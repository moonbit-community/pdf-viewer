///|
fn find_main_header_coc(
  stream : @core.Codestream,
  component_index : Int,
) -> @core.CocMetadata? {
  for coc in stream.metadata.coc {
    if coc.in_main_header && coc.component == component_index {
      return Some(coc)
    }
  }
  None
}

///|
fn find_tile_header_coc(
  stream : @core.Codestream,
  tile_index : Int,
  component_index : Int,
) -> @core.CocMetadata? {
  if tile_index < 0 {
    return None
  }
  for coc in stream.metadata.coc {
    if !coc.in_main_header &&
      coc.tile_index == tile_index &&
      coc.component == component_index {
      return Some(coc)
    }
  }
  None
}

///|
fn find_effective_component_coc(
  stream : @core.Codestream,
  tile_index : Int,
  component_index : Int,
) -> @core.CocMetadata? {
  match find_tile_header_coc(stream, tile_index, component_index) {
    Some(coc) => Some(coc)
    None => find_main_header_coc(stream, component_index)
  }
}

///|
fn find_main_header_qcc(
  stream : @core.Codestream,
  component_index : Int,
) -> @core.QccMetadata? {
  for qcc in stream.metadata.qcc {
    if qcc.in_main_header && qcc.component == component_index {
      return Some(qcc)
    }
  }
  None
}

///|
fn find_tile_header_qcc(
  stream : @core.Codestream,
  tile_index : Int,
  component_index : Int,
) -> @core.QccMetadata? {
  if tile_index < 0 {
    return None
  }
  for qcc in stream.metadata.qcc {
    if !qcc.in_main_header &&
      qcc.tile_index == tile_index &&
      qcc.component == component_index {
      return Some(qcc)
    }
  }
  None
}

///|
fn find_effective_component_qcc(
  stream : @core.Codestream,
  tile_index : Int,
  component_index : Int,
) -> @core.QccMetadata? {
  match find_tile_header_qcc(stream, tile_index, component_index) {
    Some(qcc) => Some(qcc)
    None => find_main_header_qcc(stream, component_index)
  }
}

///|
fn get_component_transformation_with_fallback(
  stream : @core.Codestream,
  component_index : Int,
  fallback_cod : @core.CodMetadata,
  tile_index? : Int = -1,
) -> Int {
  if find_effective_component_coc(stream, tile_index, component_index)
    is Some(coc) &&
    coc.parameters.length() >= 5 {
    return coc.parameters[4]
  }
  fallback_cod.transformation
}

///|
fn get_component_decomposition_levels_with_fallback(
  stream : @core.Codestream,
  component_index : Int,
  fallback_cod : @core.CodMetadata,
  tile_index? : Int = -1,
) -> Int {
  if find_effective_component_coc(stream, tile_index, component_index)
    is Some(coc) &&
    coc.parameters.length() >= 1 {
    return coc.parameters[0]
  }
  fallback_cod.decomposition_levels
}

///|
fn get_component_codeblock_width_with_fallback(
  stream : @core.Codestream,
  component_index : Int,
  fallback_cod : @core.CodMetadata,
  tile_index? : Int = -1,
) -> Int {
  if find_effective_component_coc(stream, tile_index, component_index)
    is Some(coc) &&
    coc.parameters.length() >= 2 {
    return 1 << (coc.parameters[1] + 2)
  }
  1 << fallback_cod.code_block_width_exponent
}

///|
fn get_component_codeblock_height_with_fallback(
  stream : @core.Codestream,
  component_index : Int,
  fallback_cod : @core.CodMetadata,
  tile_index? : Int = -1,
) -> Int {
  if find_effective_component_coc(stream, tile_index, component_index)
    is Some(coc) &&
    coc.parameters.length() >= 3 {
    return 1 << (coc.parameters[2] + 2)
  }
  1 << fallback_cod.code_block_height_exponent
}

///|
fn get_component_code_block_style_with_fallback(
  stream : @core.Codestream,
  component_index : Int,
  fallback_cod : @core.CodMetadata,
  tile_index? : Int = -1,
) -> Int {
  if find_effective_component_coc(stream, tile_index, component_index)
    is Some(coc) &&
    coc.parameters.length() >= 4 {
    return coc.parameters[3]
  }
  fallback_cod.code_block_style
}

///|
fn get_component_precinct_size_bytes_with_fallback(
  stream : @core.Codestream,
  component_index : Int,
  fallback_cod : @core.CodMetadata,
  tile_index? : Int = -1,
) -> Array[Int] {
  if find_effective_component_coc(stream, tile_index, component_index)
    is Some(coc) {
    if (coc.scoc & 0x01) == 0 {
      return []
    }
    let bytes : Array[Int] = []
    for i in 5..<coc.parameters.length() {
      bytes.push(coc.parameters[i])
    }
    return bytes
  }
  fallback_cod.precinct_size_bytes
}

///|
fn get_component_qcd_with_explicit_fallback(
  stream : @core.Codestream,
  component_index : Int,
  fallback_qcd : @core.QcdMetadata,
  tile_index? : Int = -1,
) -> @core.QcdMetadata {
  if find_effective_component_qcc(stream, tile_index, component_index)
    is Some(qcc) {
    return @core.make_qcd_from_qcc(qcc)
  }
  fallback_qcd
}

///|
/// Spec basis (T.800-2015 A.6.2):
/// Get the effective transformation type for a component, checking COC overrides.
/// COC marker can override COD transformation for specific components.
/// Returns: 0 = 9/7 irreversible, 1 = 5/3 reversible
pub fn get_component_transformation(
  stream : @core.Codestream,
  component_index : Int,
  fallback_cod? : @core.CodMetadata? = None,
  tile_index? : Int = -1,
) -> Int {
  guard fallback_cod is Some(cod) else {
    guard stream.metadata.cod is Some(cod) else { return 1 }
    return get_component_transformation_with_fallback(
      stream,
      component_index,
      cod,
      tile_index~,
    )
  }
  get_component_transformation_with_fallback(
    stream,
    component_index,
    cod,
    tile_index~,
  )
}

///|
/// T.800-2015 A.6.2: Get decomposition levels for a specific component.
/// COC marker can override COD decomposition_levels per component.
/// Returns: decomposition_levels from COC if present, else from COD
pub fn get_component_decomposition_levels(
  stream : @core.Codestream,
  component_index : Int,
  fallback_cod? : @core.CodMetadata? = None,
  tile_index? : Int = -1,
) -> Int {
  guard fallback_cod is Some(cod) else {
    guard stream.metadata.cod is Some(cod) else { return 5 }
    return get_component_decomposition_levels_with_fallback(
      stream,
      component_index,
      cod,
      tile_index~,
    )
  }
  get_component_decomposition_levels_with_fallback(
    stream,
    component_index,
    cod,
    tile_index~,
  )
}

///|
/// Spec basis (T.800-2015 A.6.2, Table A.23):
/// Get the code-block width for a component, checking COC overrides.
/// COC marker can override COD code-block dimensions for specific components.
/// Returns: code-block width as power-of-2 value
pub fn get_component_codeblock_width(
  stream : @core.Codestream,
  component_index : Int,
  fallback_cod? : @core.CodMetadata? = None,
  tile_index? : Int = -1,
) -> Int {
  guard fallback_cod is Some(cod) else {
    guard stream.metadata.cod is Some(cod) else { return 64 }
    return get_component_codeblock_width_with_fallback(
      stream,
      component_index,
      cod,
      tile_index~,
    )
  }
  get_component_codeblock_width_with_fallback(
    stream,
    component_index,
    cod,
    tile_index~,
  )
}

///|
/// Spec basis (T.800-2015 A.6.2, Table A.23):
/// Get the code-block height for a component, checking COC overrides.
/// COC marker can override COD code-block dimensions for specific components.
/// Returns: code-block height as power-of-2 value
pub fn get_component_codeblock_height(
  stream : @core.Codestream,
  component_index : Int,
  fallback_cod? : @core.CodMetadata? = None,
  tile_index? : Int = -1,
) -> Int {
  guard fallback_cod is Some(cod) else {
    guard stream.metadata.cod is Some(cod) else { return 64 }
    return get_component_codeblock_height_with_fallback(
      stream,
      component_index,
      cod,
      tile_index~,
    )
  }
  get_component_codeblock_height_with_fallback(
    stream,
    component_index,
    cod,
    tile_index~,
  )
}

///|
/// Spec basis (T.800-2015 A.6.2, Table A.23):
/// Get the code-block style for a component, checking COC overrides.
/// Returns: cblksty flags (e.g. TERMALL/SEGSYM/etc.)
pub fn get_component_code_block_style(
  stream : @core.Codestream,
  component_index : Int,
  fallback_cod? : @core.CodMetadata? = None,
  tile_index? : Int = -1,
) -> Int {
  guard fallback_cod is Some(cod) else {
    guard stream.metadata.cod is Some(cod) else { return 0 }
    return get_component_code_block_style_with_fallback(
      stream,
      component_index,
      cod,
      tile_index~,
    )
  }
  get_component_code_block_style_with_fallback(
    stream,
    component_index,
    cod,
    tile_index~,
  )
}

///|
/// Spec basis (T.800-2015 A.6.2, Table A.23):
/// Get component-specific precinct bytes from COC (if present), else COD.
/// COC SPcoc layout:
///   [decomp_levels, cblk_w_exp, cblk_h_exp, cblk_style, transformation, precinct...]
pub fn get_component_precinct_size_bytes(
  stream : @core.Codestream,
  component_index : Int,
  fallback_cod? : @core.CodMetadata? = None,
  tile_index? : Int = -1,
) -> Array[Int] {
  guard fallback_cod is Some(cod) else {
    guard stream.metadata.cod is Some(cod) else { return [] }
    return get_component_precinct_size_bytes_with_fallback(
      stream,
      component_index,
      cod,
      tile_index~,
    )
  }
  get_component_precinct_size_bytes_with_fallback(
    stream,
    component_index,
    cod,
    tile_index~,
  )
}

///|
/// Get effective component quantization from QCC override or fallback QCD.
pub fn get_component_qcd_with_fallback(
  stream : @core.Codestream,
  component_index : Int,
  fallback_qcd : @core.QcdMetadata,
  tile_index? : Int = -1,
) -> @core.QcdMetadata {
  get_component_qcd_with_explicit_fallback(
    stream,
    component_index,
    fallback_qcd,
    tile_index~,
  )
}

///|
pub fn get_component_decode_context(
  stream : @core.Codestream,
  component_index : Int,
  fallback_cod : @core.CodMetadata,
  fallback_qcd? : @core.QcdMetadata? = None,
  tile_index? : Int = -1,
) -> (Int, Int, Int, Int, Int, @core.QcdMetadata?) {
  let decomp_levels = get_component_decomposition_levels(
    stream,
    component_index,
    fallback_cod=Some(fallback_cod),
    tile_index~,
  )
  let code_block_width = get_component_codeblock_width(
    stream,
    component_index,
    fallback_cod=Some(fallback_cod),
    tile_index~,
  )
  let code_block_height = get_component_codeblock_height(
    stream,
    component_index,
    fallback_cod=Some(fallback_cod),
    tile_index~,
  )
  let code_block_style = get_component_code_block_style(
    stream,
    component_index,
    fallback_cod=Some(fallback_cod),
    tile_index~,
  )
  let transformation = get_component_transformation(
    stream,
    component_index,
    fallback_cod=Some(fallback_cod),
    tile_index~,
  )
  let effective_qcd = match fallback_qcd {
    Some(qcd) =>
      Some(
        get_component_qcd_with_fallback(
          stream,
          component_index,
          qcd,
          tile_index~,
        ),
      )
    None => None
  }
  (
    decomp_levels, code_block_width, code_block_height, code_block_style, transformation,
    effective_qcd,
  )
}

///|
/// T.800-2015 A.4.2: Get tile-specific COD if available.
/// Returns tile-specific COD if present for this tile, else main header COD.
pub fn get_tile_cod(
  stream : @core.Codestream,
  tile_index : Int,
) -> @core.CodMetadata? {
  for tile_cod in stream.metadata.tile_cod {
    if tile_cod.tile_index == tile_index {
      return Some(tile_cod.cod)
    }
  }
  stream.metadata.cod
}

///|
/// T.800-2015 A.4.2: Get tile-specific QCD if available.
/// Returns tile-specific QCD if present for this tile, else main header QCD.
pub fn get_tile_qcd(
  stream : @core.Codestream,
  tile_index : Int,
) -> @core.QcdMetadata? {
  for tile_qcd in stream.metadata.tile_qcd {
    if tile_qcd.tile_index == tile_index {
      return Some(tile_qcd.qcd)
    }
  }
  stream.metadata.qcd
}

///|
// Collect tile-part-header POC entries grouped by tile index (Isot).
pub fn collect_tile_part_poc_by_tile(
  stream : @core.Codestream,
  csiz : Int,
) -> Map[Int, Array[@core.PocMetadata]] {
  let grouped : Map[Int, Array[@core.PocMetadata]] = {}
  let mut current_isot = -1
  let unit = if csiz < 257 { 7 } else { 9 }
  let mut poc_cursor = 0
  for segment in stream.segments {
    if segment.code == 0xFF90 {
      if segment.payload.length() >= 2 {
        current_isot = (segment.payload[0].to_int() << 8) |
          segment.payload[1].to_int()
      } else {
        current_isot = -1
      }
      continue
    }
    if segment.code != 0xFF5F {
      continue
    }
    if unit <= 0 || segment.payload.length() % unit != 0 {
      continue
    }
    let entry_count = segment.payload.length() / unit
    if current_isot >= 0 && entry_count > 0 {
      if not(grouped.contains(current_isot)) {
        grouped[current_isot] = []
      }
      if grouped.get(current_isot) is Some(acc) {
        for _ in 0..<entry_count {
          if poc_cursor < stream.metadata.poc.length() {
            let entry = stream.metadata.poc[poc_cursor]
            if !entry.in_main_header {
              acc.push(entry)
            }
            poc_cursor += 1
          }
        }
      } else {
        poc_cursor += entry_count
      }
    } else {
      poc_cursor += entry_count
    }
    if poc_cursor > stream.metadata.poc.length() {
      poc_cursor = stream.metadata.poc.length()
    }
  }
  grouped
}

///|
// Spec grouping:
// - B.10 Packet header shape candidate generation
// - Resolution dimension calculation for code-block grids

///|
// Spec basis (T.800-2015 Annex B progression/resolution structure):
// Resolution-domain dimensions are derived from component dimensions by
// decomposition-level shift; decoder uses ceil division for integer grids.
fn spec_resolution_dimension(
  component_dimension : Int,
  decomposition_levels : Int,
  resolution : Int,
) -> Int {
  let shift = decomposition_levels - resolution
  if shift <= 0 {
    return component_dimension
  }
  @math.ceil_div(component_dimension, 1 << shift)
}

///|
// Spec basis (T.800-2015 B.10):
// Add a unique shape candidate to the list if not already present.
fn push_shape_candidate_if_new(
  out : Array[PacketHeaderShapeCandidate],
  code_block_count : Int,
  width : Int,
  height : Int,
) -> Unit {
  if code_block_count <= 0 || width <= 0 || height <= 0 {
    return
  }
  for c in out {
    if c.code_block_count == code_block_count &&
      c.width == width &&
      c.height == height {
      return
    }
  }
  out.push({ code_block_count, width, height, })
}

///|
// Spec basis (T.800-2015 A.6.1 Table A.18 / B.10):
// Derive candidate code-block grid shapes from SIZ/COD geometry.
pub fn simple_profile_packet_header_shape_candidates(
  stream : @core.Codestream,
) -> Array[PacketHeaderShapeCandidate] {
  let out : Array[PacketHeaderShapeCandidate] = []
  guard stream.metadata.siz is Some(siz) else { return out }
  guard stream.metadata.cod is Some(cod) else { return out }
  if siz.components.length() <= 0 {
    return out
  }
  let dims_v = @input.component_dimensions_from_siz(siz, 0)
  guard dims_v is Ok((c0_width, c0_height)) else { return out }
  let cbw = 1 << cod.code_block_width_exponent
  let cbh = 1 << cod.code_block_height_exponent
  for resolution in 0..<=cod.decomposition_levels {
    let rw = spec_resolution_dimension(
      c0_width,
      cod.decomposition_levels,
      resolution,
    )
    let rh = spec_resolution_dimension(
      c0_height,
      cod.decomposition_levels,
      resolution,
    )
    let width = @math.ceil_div(rw, cbw)
    let height = @math.ceil_div(rh, cbh)
    push_shape_candidate_if_new(out, width * height, width, height)
    push_shape_candidate_if_new(out, width * height, height, width)
  }
  out
}

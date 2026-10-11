///|
// Spec grouping:
// - Annex H: Region of Interest (ROI) coding
// - H.1: ROI shift and maxshift method

///|
fn parse_rgn_component_and_shift(
  payload : Array[Int],
  csiz : Int,
) -> (Int, Int)? {
  let cbytes = if csiz < 257 { 1 } else { 2 }
  if payload.length() < cbytes + 2 {
    return None
  }
  let component = if cbytes == 1 {
    payload[0]
  } else {
    (payload[0] << 8) | payload[1]
  }
  Some((component, payload[cbytes + 1]))
}

///|
/// Spec basis (T.800-2015 A.6.5 / H.1):
/// Extract per-tile per-component ROI shift from RGN markers in the codestream.
/// Walks the segment list to associate tile-part RGN markers with their tile.
/// Returns: Map[tile_index, Map[component_index, roishift]].
/// Main-header RGN markers are stored under tile_index = -1.
pub fn extract_roi_shift_per_tile_component(
  stream : @core.Codestream,
) -> Map[Int, Map[Int, Int]] {
  let result : Map[Int, Map[Int, Int]] = {}
  // First, apply main-header RGN markers (stored under tile -1)
  for rgn in stream.metadata.rgn {
    if rgn.in_main_header && rgn.shift > 0 {
      if not(result.contains(-1)) {
        result[-1] = {}
      }
      if result.get(-1) is Some(m) {
        m[rgn.component] = rgn.shift
      }
    }
  }
  // Walk segments to associate tile-part RGN markers with their tile.
  // Tile-part markers appear between SOT (0xFF90) and SOD (0xFF93).
  let csiz = match stream.metadata.siz {
    Some(siz) => siz.csiz
    None => 0
  }
  let mut current_tile = -1
  for seg in stream.segments {
    if seg.code == 0xFF90 {
      // SOT: extract tile index from first 2 bytes of payload
      if seg.payload.length() >= 2 {
        current_tile = (seg.payload[0].to_int() << 8) | seg.payload[1].to_int()
      }
    } else if seg.code == 0xFF93 {
      // SOD: end of tile-part header
      current_tile = -1
    } else if seg.code == 0xFF5E && current_tile >= 0 {
      // RGN in tile-part header
      let payload_arr : Array[Int] = []
      for i in 0..<seg.payload.length() {
        payload_arr.push(seg.payload[i].to_int())
      }
      if parse_rgn_component_and_shift(payload_arr, csiz) is Some((comp, shift)) {
        if shift > 0 {
          if not(result.contains(current_tile)) {
            result[current_tile] = {}
          }
          if result.get(current_tile) is Some(m) {
            m[comp] = shift
          }
        }
      }
    }
  }
  result
}

///|
/// Spec basis (T.800-2015 A.6.5 / H.1):
/// Look up the ROI shift for a given tile and component.
/// Tile-part RGN overrides main-header RGN (T.800-2015 A.6.5).
pub fn get_roi_shift(
  roi_map : Map[Int, Map[Int, Int]],
  tile_idx : Int,
  component : Int,
) -> Int {
  // Check tile-specific RGN first
  if roi_map.get(tile_idx) is Some(tile_map) {
    if tile_map.get(component) is Some(shift) {
      return shift
    }
  }
  // Fall back to main-header RGN
  if roi_map.get(-1) is Some(main_map) {
    if main_map.get(component) is Some(shift) {
      return shift
    }
  }
  0
}

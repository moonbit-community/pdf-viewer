///|
// Shared helpers used across decoder orchestration files.

///|
// Initialize tag-tree node state arrays (low bounds + known values).
fn init_tag_tree_node_arrays(total_nodes : Int) -> (Array[Int], Array[Int?]) {
  let low : Array[Int] = []
  let known : Array[Int?] = []
  for _ in 0..<total_nodes {
    low.push(0)
    known.push(None)
  }
  (low, known)
}

///|
struct TileRelocatedHeaders {
  tile_ppt_headers_by_idx : Map[Int, Bytes]
  global_ppm_headers : Bytes
  has_ppt_headers : Bool
  has_ppm_headers : Bool
}

///|
// Collect PPT (per-tile) and PPM (global) relocated packet headers from stream.
fn collect_relocated_headers(stream : @core.Codestream) -> TileRelocatedHeaders {
  let tile_ppt_headers_by_idx : Map[Int, Bytes] = {}
  let mut has_ppt_headers = false
  match @input.collect_ppt_payloads_by_tile(stream) {
    Some(grouped_ppt) => {
      has_ppt_headers = true
      for entry in grouped_ppt {
        let (idx, data) = entry
        tile_ppt_headers_by_idx[idx] = data
      }
    }
    _ => ()
  }
  let mut has_ppm_headers = false
  let mut global_ppm_headers : Bytes = b""
  match @input.collect_ppm_payload_bytes(stream) {
    Some(ppm_bytes) => {
      has_ppm_headers = true
      global_ppm_headers = ppm_bytes
    }
    _ => ()
  }
  {
    tile_ppt_headers_by_idx,
    global_ppm_headers,
    has_ppt_headers,
    has_ppm_headers,
  }
}

///|
// Select between DWT tile result and HT bridge result based on DC fill detection.
// Returns (selected_pixels, consumed_headers).
fn tile_bridge_selection(
  tile_pixels : Array[Int],
  consumed_headers : Int,
  bridge_pixels : Array[Int],
  dc_fill : Int,
) -> (Array[Int], Int) {
  let mut tile_is_dc_fill = tile_pixels.length() > 0
  for v in tile_pixels {
    if v != dc_fill {
      tile_is_dc_fill = false
      break
    }
  }
  let mut bridge_has_signal = false
  for v in bridge_pixels {
    if v != dc_fill {
      bridge_has_signal = true
      break
    }
  }
  if tile_is_dc_fill && bridge_has_signal {
    (bridge_pixels, 0)
  } else {
    (tile_pixels, consumed_headers)
  }
}

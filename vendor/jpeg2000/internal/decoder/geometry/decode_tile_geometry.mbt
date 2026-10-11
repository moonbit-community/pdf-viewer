///|
// Spec basis (T.800-2015 B.3 Eq. B.3-1..B.3-4):
// Compute per-component tile dimensions and origins in component coordinates.
pub fn tile_component_dims_and_origin_from_siz(
  siz : @core.SizMetadata,
  tile_col : Int,
  tile_row : Int,
  comp_idx : Int,
) -> (Int, Int, Int, Int, Int, Int) {
  let tx0 = if siz.xtosiz + tile_col * siz.xtsiz > siz.xosiz {
    siz.xtosiz + tile_col * siz.xtsiz
  } else {
    siz.xosiz
  }
  let ty0 = if siz.ytosiz + tile_row * siz.ytsiz > siz.yosiz {
    siz.ytosiz + tile_row * siz.ytsiz
  } else {
    siz.yosiz
  }
  let tx1_raw = siz.xtosiz + (tile_col + 1) * siz.xtsiz
  let tx1 = if tx1_raw < siz.xsiz { tx1_raw } else { siz.xsiz }
  let ty1_raw = siz.ytosiz + (tile_row + 1) * siz.ytsiz
  let ty1 = if ty1_raw < siz.ysiz { ty1_raw } else { siz.ysiz }
  let xr = if comp_idx < siz.components.length() {
    siz.components[comp_idx].xrsiz
  } else {
    1
  }
  let yr = if comp_idx < siz.components.length() {
    siz.components[comp_idx].yrsiz
  } else {
    1
  }
  let cx0 = (tx0 + xr - 1) / xr
  let cy0 = (ty0 + yr - 1) / yr
  let cx1 = (tx1 + xr - 1) / xr
  let cy1 = (ty1 + yr - 1) / yr
  let img_x0 = (siz.xosiz + xr - 1) / xr
  let img_y0 = (siz.yosiz + yr - 1) / yr
  (cx0 - img_x0, cy0 - img_y0, cx1 - cx0, cy1 - cy0, cx0, cy0)
}

///|
// Find tile indices for the current component-0 tile payload.
pub fn find_tile_index_by_component0_origin(
  siz : @core.SizMetadata,
  c0_width : Int,
  c0_height : Int,
  tcx0 : Int,
  tcy0 : Int,
) -> (Int, Int)? {
  let num_tiles_x = (siz.xsiz - siz.xtosiz + siz.xtsiz - 1) / siz.xtsiz
  let num_tiles_y = (siz.ysiz - siz.ytosiz + siz.ytsiz - 1) / siz.ytsiz
  if num_tiles_x <= 1 && num_tiles_y <= 1 {
    return Some((0, 0))
  }
  for tile_row in 0..<num_tiles_y {
    for tile_col in 0..<num_tiles_x {
      let (_, _, tw, th, c0x, c0y) = tile_component_dims_and_origin_from_siz(
        siz, tile_col, tile_row, 0,
      )
      if tw == c0_width && th == c0_height && c0x == tcx0 && c0y == tcy0 {
        return Some((tile_col, tile_row))
      }
    }
  }
  None
}

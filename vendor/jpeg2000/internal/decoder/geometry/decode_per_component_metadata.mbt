///|
// Spec basis (T.800-2015 B.3/A.6.2):
// Shared per-component tile dimension and codec metadata collection,
// used by both decode_dwt_image_from_sequential_packets and
// decode_dwt_component_planes_from_sequential_packets.

///|
pub struct PerComponentTileDimensions {
  pub per_comp_w : Array[Int]
  pub per_comp_h : Array[Int]
  pub per_comp_xrsiz : Array[Int]
  pub per_comp_yrsiz : Array[Int]
  pub per_comp_tcx0 : Array[Int]
  pub per_comp_tcy0 : Array[Int]
  pub effective_tile_index : Int
}

///|
// T.800-2015 B.3: Compute per-component tile dimensions and origins from SIZ.
pub fn collect_per_component_tile_dimensions(
  stream : @core.Codestream,
  num_components : Int,
  c0_width : Int,
  c0_height : Int,
  tcx0 : Int,
  tcy0 : Int,
  tile_index : Int,
) -> PerComponentTileDimensions {
  let per_comp_w : Array[Int] = []
  let per_comp_h : Array[Int] = []
  let per_comp_xrsiz : Array[Int] = []
  let per_comp_yrsiz : Array[Int] = []
  let per_comp_tcx0 : Array[Int] = []
  let per_comp_tcy0 : Array[Int] = []
  let mut effective_tile_index = tile_index
  if stream.metadata.siz is Some(siz_meta) {
    let num_tiles_x = (siz_meta.xsiz - siz_meta.xtosiz + siz_meta.xtsiz - 1) /
      siz_meta.xtsiz
    let num_tiles_y = (siz_meta.ysiz - siz_meta.ytosiz + siz_meta.ytsiz - 1) /
      siz_meta.ytsiz
    let tile_pos_v = if effective_tile_index >= 0 &&
      num_tiles_x > 0 &&
      num_tiles_y > 0 {
      let tile_col = effective_tile_index % num_tiles_x
      let tile_row = effective_tile_index / num_tiles_x
      if tile_row >= 0 && tile_row < num_tiles_y {
        Some((tile_col, tile_row))
      } else {
        find_tile_index_by_component0_origin(
          siz_meta, c0_width, c0_height, tcx0, tcy0,
        )
      }
    } else {
      find_tile_index_by_component0_origin(
        siz_meta, c0_width, c0_height, tcx0, tcy0,
      )
    }
    if tile_pos_v is Some((tile_col, tile_row)) {
      if effective_tile_index < 0 && num_tiles_x > 0 {
        effective_tile_index = tile_row * num_tiles_x + tile_col
      }
      for ci in 0..<num_components {
        let (_, _, cw, ch, ccx0, ccy0) = tile_component_dims_and_origin_from_siz(
          siz_meta, tile_col, tile_row, ci,
        )
        per_comp_w.push(cw)
        per_comp_h.push(ch)
        let xr = if ci < siz_meta.components.length() {
          siz_meta.components[ci].xrsiz
        } else {
          1
        }
        let yr = if ci < siz_meta.components.length() {
          siz_meta.components[ci].yrsiz
        } else {
          1
        }
        per_comp_xrsiz.push(xr)
        per_comp_yrsiz.push(yr)
        per_comp_tcx0.push(ccx0)
        per_comp_tcy0.push(ccy0)
      }
    } else {
      let siz_c0_v = @input.component_dimensions_from_siz(siz_meta, 0)
      let is_full_image = match siz_c0_v {
        Ok((sw, sh)) => sw == c0_width && sh == c0_height
        _ => false
      }
      if is_full_image {
        if effective_tile_index < 0 && siz_meta.tile_count <= 1 {
          effective_tile_index = 0
        }
        for ci in 0..<num_components {
          let dims_v = @input.component_dimensions_from_siz(siz_meta, ci)
          if dims_v is Ok((cw, ch)) {
            per_comp_w.push(cw)
            per_comp_h.push(ch)
          } else {
            per_comp_w.push(c0_width)
            per_comp_h.push(c0_height)
          }
          let xr = if ci < siz_meta.components.length() {
            siz_meta.components[ci].xrsiz
          } else {
            1
          }
          let yr = if ci < siz_meta.components.length() {
            siz_meta.components[ci].yrsiz
          } else {
            1
          }
          per_comp_xrsiz.push(xr)
          per_comp_yrsiz.push(yr)
          per_comp_tcx0.push((siz_meta.xosiz + xr - 1) / xr)
          per_comp_tcy0.push((siz_meta.yosiz + yr - 1) / yr)
        }
      }
    }
  }
  {
    per_comp_w,
    per_comp_h,
    per_comp_xrsiz,
    per_comp_yrsiz,
    per_comp_tcx0,
    per_comp_tcy0,
    effective_tile_index,
  }
}

///|
// Fill remaining components that weren't resolved by SIZ tile lookup.
pub fn fill_remaining_component_dimensions(
  dims : PerComponentTileDimensions,
  stream : @core.Codestream,
  num_components : Int,
  c0_width : Int,
  c0_height : Int,
  tcx0 : Int,
  tcy0 : Int,
) -> Unit {
  for ci in dims.per_comp_w.length()..<num_components {
    let dims_v = if stream.metadata.siz is Some(siz_meta) {
      @input.component_dimensions_from_siz(siz_meta, ci)
    } else {
      Err("missing siz")
    }
    if dims_v is Ok((cw, ch)) {
      dims.per_comp_w.push(cw)
      dims.per_comp_h.push(ch)
    } else {
      dims.per_comp_w.push(c0_width)
      dims.per_comp_h.push(c0_height)
    }
    dims.per_comp_xrsiz.push(1)
    dims.per_comp_yrsiz.push(1)
    dims.per_comp_tcx0.push(tcx0)
    dims.per_comp_tcy0.push(tcy0)
  }
}

///|
pub struct PerComponentCodecMetadata {
  pub per_comp_decomp : Array[Int]
  pub per_comp_cbw : Array[Int]
  pub per_comp_cbh : Array[Int]
  pub per_comp_cblk_style : Array[Int]
  pub per_comp_precinct_size_bytes : Array[Array[Int]]
}

///|
// T.800-2015 A.6.2: Collect per-component codec metadata (decomposition levels,
// code-block sizes, code-block style, precinct sizes) from COC/COD.
pub fn collect_per_component_codec_metadata(
  stream : @core.Codestream,
  num_components : Int,
  cod : @core.CodMetadata,
  effective_tile_index : Int,
) -> PerComponentCodecMetadata {
  let per_comp_decomp : Array[Int] = []
  let per_comp_cbw : Array[Int] = []
  let per_comp_cbh : Array[Int] = []
  let per_comp_cblk_style : Array[Int] = []
  let per_comp_precinct_size_bytes : Array[Array[Int]] = []
  for ci in 0..<num_components {
    per_comp_decomp.push(
      get_component_decomposition_levels(
        stream,
        ci,
        fallback_cod=Some(cod),
        tile_index=effective_tile_index,
      ),
    )
    per_comp_cbw.push(
      get_component_codeblock_width(
        stream,
        ci,
        fallback_cod=Some(cod),
        tile_index=effective_tile_index,
      ),
    )
    per_comp_cbh.push(
      get_component_codeblock_height(
        stream,
        ci,
        fallback_cod=Some(cod),
        tile_index=effective_tile_index,
      ),
    )
    per_comp_cblk_style.push(
      get_component_code_block_style(
        stream,
        ci,
        fallback_cod=Some(cod),
        tile_index=effective_tile_index,
      ),
    )
    per_comp_precinct_size_bytes.push(
      get_component_precinct_size_bytes(
        stream,
        ci,
        fallback_cod=Some(cod),
        tile_index=effective_tile_index,
      ),
    )
  }
  {
    per_comp_decomp,
    per_comp_cbw,
    per_comp_cbh,
    per_comp_cblk_style,
    per_comp_precinct_size_bytes,
  }
}

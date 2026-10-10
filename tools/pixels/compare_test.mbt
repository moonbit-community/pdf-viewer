///|
fn raster(
  width : Int,
  height : Int,
  ink : (Int, Int) -> Bool,
) -> @pixels.Raster {
  let rgba = Bytes::makei(width * height * 4, index => {
    let pixel = index / 4
    if index % 4 == 3 || !ink(pixel % width, pixel / width) {
      b'\xFF'
    } else {
      b'\x00'
    }
  })
  @pixels.Raster::from_rgba(rgba, width, height).unwrap()
}

///|
test "identical and blank rasters have finite zero error" {
  let blank = raster(8, 8, (_, _) => false)
  let stats = @pixels.compare(blank, blank).stats
  assert_eq(stats.exact_changed, 0)
  assert_eq(stats.root_mean_square_error, 0.0)
  assert_eq(stats.changed_over_union_ink, 0.0)
  assert_eq(stats.changed_bounds, None)
  let text = raster(8, 8, (x, _) => x == 3)
  assert_eq(@pixels.compare(text, text).stats.changed_above_tolerance, 0)
}

///|
test "missing paint remains structural and has exact exclusive bounds" {
  let block = raster(12, 12, (x, y) => x >= 2 && x < 10 && y >= 2 && y < 10)
  let blank = raster(12, 12, (_, _) => false)
  let result = @pixels.compare(block, blank)
  assert_eq(result.stats.outside_neighborhood, 64)
  assert_eq(result.stats.missing_ink, 64)
  assert_eq(result.stats.extra_ink, 0)
  assert_eq(result.stats.changed_bounds, Some([2, 2, 10, 10]))
  assert_eq(result.heatmap[(2 * 12 + 2) * 4], b'\xDC')
  let reversed = @pixels.compare(blank, block)
  assert_eq(reversed.stats.extra_ink, 64)
  assert_eq(reversed.stats.outside_neighborhood, 64)
}

///|
test "one pixel shifts stay visible as raw and neighborhood differences" {
  let a = raster(12, 12, (x, _) => x == 4)
  let b = raster(12, 12, (x, _) => x == 5)
  let stats = @pixels.compare(a, b).stats
  assert_eq(stats.changed_above_tolerance, 24)
  assert_eq(stats.neighborhood_matched, 24)
  assert_eq(stats.outside_neighborhood, 0)
  assert_eq(stats.missing_ink, 12)
  assert_eq(stats.extra_ink, 12)
}

///|
test "larger shifts and color changes remain structural" {
  let a = raster(12, 12, (x, _) => x == 4)
  let b = raster(12, 12, (x, _) => x == 7)
  assert_eq(@pixels.compare(a, b).stats.outside_neighborhood, 24)
  let red = @pixels.Raster::from_rgba(b"\xFF\x00\x00\xFF", 1, 1).unwrap()
  let blue = @pixels.Raster::from_rgba(b"\x00\x00\xFF\xFF", 1, 1).unwrap()
  assert_eq(@pixels.compare(red, blue).stats.outside_neighborhood, 1)
}

///|
test "white alpha compositing and unequal dimensions do not rescale content" {
  let transparent = @pixels.Raster::from_rgba(b"\x00\x00\x00\x00", 1, 1).unwrap()
  let white = raster(1, 1, (_, _) => false)
  assert_eq(@pixels.compare(transparent, white).stats.exact_changed, 0)
  let wider = raster(2, 1, (_, _) => false)
  let stats = @pixels.compare(white, wider).stats
  assert_eq(stats.dimensions_match, false)
  assert_eq(stats.width, 2)
  assert_eq(stats.exact_changed, 0)
}

///|
test "invalid and oversized RGBA input is rejected before allocation" {
  assert_true(@pixels.Raster::from_rgba(b"", 0, 1) is None)
  assert_true(@pixels.Raster::from_rgba(b"", -1, 1) is None)
  assert_true(@pixels.Raster::from_rgba(b"abc", 1, 1) is None)
  assert_true(@pixels.Raster::from_rgba(b"", 2147483647, 2) is None)
  assert_true(@pixels.Raster::from_rgba(b"", 8192, 8192) is None)
}

///|
test "orthogonal narrow rasters cannot allocate an oversized union" {
  let a = raster(8192, 2, (_, _) => false)
  let b = raster(2, 8192, (_, _) => false)
  try @pixels.compare(a, b) catch {
    @pixels.PixelError::CombinedRasterTooLarge => ()
  } noraise {
    _ => fail("Expected rejection of the combined 8192 by 8192 raster")
  }
}

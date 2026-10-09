///|
/// A validation-only raster, composited on white during comparison.
pub struct Raster {
  rgba : Bytes
  width : Int
  height : Int
}

///|
pub fn Raster::from_rgba(rgba : Bytes, width : Int, height : Int) -> Raster? {
  guard width > 0 && height > 0 && width <= 8192 && height <= 8192 else {
    return None
  }
  // Bound allocation and validate before multiplying untrusted dimensions.
  guard width <= 16777216 / height else { return None }
  guard rgba.length() == width * height * 4 else { return None }
  Some({ rgba, width, height })
}

///|
pub struct PixelStats {
  width : Int
  height : Int
  dimensions_match : Bool
  pixels : Int
  exact_changed : Int
  changed_above_tolerance : Int
  neighborhood_matched : Int
  outside_neighborhood : Int
  reference_ink : Int
  viewer_ink : Int
  union_ink : Int
  missing_ink : Int
  extra_ink : Int
  changed_fraction : Double
  outside_neighborhood_fraction : Double
  changed_over_union_ink : Double
  mean_absolute_error : Double
  root_mean_square_error : Double
  max_channel_error : Int
  changed_bounds : Array[Int]?
  outside_neighborhood_bounds : Array[Int]?
} derive(ToJson)

///|
#deprecated
pub extend PixelStats with ToJson::{to_json}

///|
pub struct PixelComparison {
  stats : PixelStats
  heatmap : Bytes
}

///|
pub suberror PixelError {
  CombinedRasterTooLarge
}

///|
fn Raster::pixel(self : Raster, x : Int, y : Int) -> (Int, Int, Int) {
  if x < 0 || y < 0 || x >= self.width || y >= self.height {
    return (255, 255, 255)
  }
  let index = (y * self.width + x) * 4
  let alpha = self.rgba[index + 3].to_int()
  fn channel(value : Byte) -> Int {
    (value.to_int() * alpha + 255 * (255 - alpha) + 127) / 255
  }
  (
    channel(self.rgba[index]),
    channel(self.rgba[index + 1]),
    channel(self.rgba[index + 2]),
  )
}

///|
fn maximum(a : Int, b : Int) -> Int {
  if a > b { a } else { b }
}

///|
fn difference(a : (Int, Int, Int), b : (Int, Int, Int)) -> Int {
  maximum((a.0 - b.0).abs(), maximum((a.1 - b.1).abs(), (a.2 - b.2).abs()))
}

///|
fn Raster::near_color(
  self : Raster,
  x : Int,
  y : Int,
  color : (Int, Int, Int),
) -> Bool {
  for dy in -1..=1 {
    for dx in -1..=1 {
      if difference(color, self.pixel(x + dx, y + dy)) <= 8 {
        return true
      }
    }
  }
  false
}

///|
fn expand(bounds : Array[Int], x : Int, y : Int) -> Unit {
  if x < bounds[0] { bounds[0] = x }
  if y < bounds[1] { bounds[1] = y }
  if x + 1 > bounds[2] { bounds[2] = x + 1 }
  if y + 1 > bounds[3] { bounds[3] = y + 1 }
}

///|
/// Compare at the same device-pixel coordinates without rescaling either page.
/// Yellow means both colors occur within the other image's 1px neighborhood;
/// red means they do not. Yellow is a diagnostic candidate, never proof of
/// antialiasing: even a shifted thin line can be yellow. Raw counts remain.
pub fn compare(reference : Raster, viewer : Raster) -> PixelComparison raise PixelError {
  let width = maximum(reference.width, viewer.width)
  let height = maximum(reference.height, viewer.height)
  guard width <= 16777216 / height else { raise CombinedRasterTooLarge }
  let pixels = width * height
  let heatmap : FixedArray[Byte] = FixedArray::make(pixels * 4, b'\xFF')
  let bounds = [width, height, 0, 0]
  let structural_bounds = [width, height, 0, 0]
  let mut exact = 0
  let mut changed = 0
  let mut nearby = 0
  let mut structural = 0
  let mut reference_ink = 0
  let mut viewer_ink = 0
  let mut union_ink = 0
  let mut missing_ink = 0
  let mut extra_ink = 0
  let mut absolute_error = 0.0
  let mut squared_error = 0.0
  let mut max_error = 0
  for y in 0..<height {
    for x in 0..<width {
      let a = reference.pixel(x, y)
      let b = viewer.pixel(x, y)
      let error = difference(a, b)
      let a_ink = difference(a, (255, 255, 255)) > 24
      let b_ink = difference(b, (255, 255, 255)) > 24
      if a_ink { reference_ink += 1 }
      if b_ink { viewer_ink += 1 }
      if a_ink || b_ink { union_ink += 1 }
      if a_ink && !b_ink { missing_ink += 1 }
      if !a_ink && b_ink { extra_ink += 1 }
      if error > 0 { exact += 1 }
      max_error = maximum(max_error, error)
      let dr = (a.0 - b.0).to_double()
      let dg = (a.1 - b.1).to_double()
      let db = (a.2 - b.2).to_double()
      absolute_error += dr.abs() + dg.abs() + db.abs()
      squared_error += dr * dr + dg * dg + db * db
      let index = (y * width + x) * 4
      let color = if error <= 8 {
        ((a.0 + 765) / 4, (a.1 + 765) / 4, (a.2 + 765) / 4)
      } else {
        changed += 1
        expand(bounds, x, y)
        if viewer.near_color(x, y, a) && reference.near_color(x, y, b) {
          nearby += 1
          (255, 192, 0)
        } else {
          structural += 1
          expand(structural_bounds, x, y)
          (220, 0, 80)
        }
      }
      heatmap[index] = color.0.to_byte()
      heatmap[index + 1] = color.1.to_byte()
      heatmap[index + 2] = color.2.to_byte()
    }
  }
  let stats : PixelStats = {
    width, height, pixels,
    dimensions_match: reference.width == viewer.width && reference.height == viewer.height,
    exact_changed: exact,
    changed_above_tolerance: changed,
    neighborhood_matched: nearby,
    outside_neighborhood: structural,
    reference_ink, viewer_ink, union_ink, missing_ink, extra_ink,
    changed_fraction: changed.to_double() / pixels.to_double(),
    outside_neighborhood_fraction: structural.to_double() / pixels.to_double(),
    changed_over_union_ink: if union_ink == 0 { 0.0 } else { changed.to_double() / union_ink.to_double() },
    mean_absolute_error: absolute_error / (pixels.to_double() * 3.0),
    root_mean_square_error: (squared_error / (pixels.to_double() * 3.0)).sqrt(),
    max_channel_error: max_error,
    changed_bounds: if changed == 0 { None } else { Some(bounds) },
    outside_neighborhood_bounds: if structural == 0 { None } else { Some(structural_bounds) },
  }
  { stats, heatmap: Bytes::from_array(heatmap[:]) }
}

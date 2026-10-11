///|
// Reference-grid anchor for one precinct packet.
// For RPCL/PCRL/CPRL, packet position ordering is determined by these
// reference-grid coordinates (T.800-2015 B.12.1.3/4/5).
priv struct PrecinctAnchor {
  x : Int
  y : Int
  component : Int
  resolution : Int
  precinct : Int
}

///|
fn precinct_anchor_less(
  a : PrecinctAnchor,
  b : PrecinctAnchor,
  mode : Int,
) -> Bool {
  // mode 0: (y, x, c, p) for RPCL per-resolution ordering
  if mode == 0 {
    if a.y != b.y {
      return a.y < b.y
    }
    if a.x != b.x {
      return a.x < b.x
    }
    if a.component != b.component {
      return a.component < b.component
    }
    return a.precinct < b.precinct
  }
  // mode 1: (y, x, c, r, p) for PCRL
  if mode == 1 {
    if a.y != b.y {
      return a.y < b.y
    }
    if a.x != b.x {
      return a.x < b.x
    }
    if a.component != b.component {
      return a.component < b.component
    }
    if a.resolution != b.resolution {
      return a.resolution < b.resolution
    }
    return a.precinct < b.precinct
  }
  // mode 2: (c, y, x, r, p) for CPRL
  if a.component != b.component {
    return a.component < b.component
  }
  if a.y != b.y {
    return a.y < b.y
  }
  if a.x != b.x {
    return a.x < b.x
  }
  if a.resolution != b.resolution {
    return a.resolution < b.resolution
  }
  a.precinct < b.precinct
}

///|
// In-place insertion sort for deterministic packet ordering.
fn sort_precinct_anchors_in_place(
  anchors : Array[PrecinctAnchor],
  mode : Int,
) -> Unit {
  if anchors.length() <= 1 {
    return
  }
  for i in 1..<anchors.length() {
    let key = anchors[i]
    let mut pos = i
    while pos > 0 && precinct_anchor_less(key, anchors[pos - 1], mode) {
      anchors[pos] = anchors[pos - 1]
      pos -= 1
    }
    anchors[pos] = key
  }
}

///|
// Build precinct anchors in reference-grid coordinates for B.12 position-based
// progression orders (RPCL/PCRL/CPRL).
fn build_precinct_anchors(
  num_components : Int,
  comp_num_resolutions : Array[Int],
  comp_decomp_levels : Array[Int],
  comp_res_num_precincts : Array[Array[(Int, Int)]],
  comp_res_bounds : Array[Array[(Int, Int, Int, Int)]],
  comp_precinct_size_bytes : Array[Array[Int]],
  tcx0 : Int,
  tcy0 : Int,
  comp_xrsiz? : Array[Int] = [],
  comp_yrsiz? : Array[Int] = [],
) -> Array[PrecinctAnchor] {
  let anchors : Array[PrecinctAnchor] = []
  for c in 0..<num_components {
    if c >= comp_num_resolutions.length() ||
      c >= comp_decomp_levels.length() ||
      c >= comp_res_num_precincts.length() ||
      c >= comp_res_bounds.length() {
      continue
    }
    let c_num_res = comp_num_resolutions[c]
    let c_decomp = comp_decomp_levels[c]
    let c_xrsiz = if c < comp_xrsiz.length() { comp_xrsiz[c] } else { 1 }
    let c_yrsiz = if c < comp_yrsiz.length() { comp_yrsiz[c] } else { 1 }
    let c_precinct_size_bytes : Array[Int] = if c <
      comp_precinct_size_bytes.length() {
      comp_precinct_size_bytes[c]
    } else {
      []
    }
    let (comp_origin_x, comp_origin_y) = if c_num_res > 0 &&
      c_num_res - 1 < comp_res_bounds[c].length() {
      let (ox, oy, _, _) = comp_res_bounds[c][c_num_res - 1]
      (ox, oy)
    } else {
      (tcx0, tcy0)
    }
    for r in 0..<c_num_res {
      if r >= comp_res_num_precincts[c].length() ||
        r >= comp_res_bounds[c].length() {
        continue
      }
      let (npx, npy) = comp_res_num_precincts[c][r]
      if npx <= 0 || npy <= 0 {
        continue
      }
      let (trx0, try0, _, _) = comp_res_bounds[c][r]
      let (ppx_exp, ppy_exp) = get_precinct_exponents(c_precinct_size_bytes, r)
      let scale_shift = c_decomp - r
      let scale = 1 << scale_shift
      // T.800-2015 B.12: anchor comparison happens in reference grid.
      // Convert component-grid positions to reference grid with XRsiz/YRsiz.
      let step_x = (1 << (ppx_exp + scale_shift)) * c_xrsiz
      let step_y = (1 << (ppy_exp + scale_shift)) * c_yrsiz
      let grid_x0 = trx0 / (1 << ppx_exp)
      let grid_y0 = try0 / (1 << ppy_exp)
      let ref_trx0 = trx0 * scale * c_xrsiz
      let ref_try0 = try0 * scale * c_yrsiz
      // T.800-2015 B.12.1.{3,4,5}: x=tx0 / y=ty0 special-case when the first
      // precinct boundary is misaligned with the tile origin in reference grid.
      let first_x = if ref_trx0 % step_x != 0 {
        comp_origin_x * scale * c_xrsiz
      } else {
        grid_x0 * scale * c_xrsiz
      }
      let first_y = if ref_try0 % step_y != 0 {
        comp_origin_y * scale * c_yrsiz
      } else {
        grid_y0 * scale * c_yrsiz
      }
      for py in 0..<npy {
        for px in 0..<npx {
          let anchor_x = if px == 0 {
            first_x
          } else {
            (grid_x0 + px) * scale * c_xrsiz
          }
          let anchor_y = if py == 0 {
            first_y
          } else {
            (grid_y0 + py) * scale * c_yrsiz
          }
          anchors.push({
            x: anchor_x,
            y: anchor_y,
            component: c,
            resolution: r,
            precinct: py * npx + px,
          })
        }
      }
    }
  }
  anchors
}

///|
// Build packet processing order as (resolution, layer, component, precinct).
// This follows T.800-2015 B.12 progression orders.
pub fn build_packet_order(
  progression : Int,
  num_layers : Int,
  num_resolutions : Int,
  num_components : Int,
  comp_num_resolutions : Array[Int],
  comp_decomp_levels : Array[Int],
  comp_res_num_precincts : Array[Array[(Int, Int)]],
  comp_res_bounds : Array[Array[(Int, Int, Int, Int)]],
  comp_precinct_size_bytes : Array[Array[Int]],
  tcx0 : Int,
  tcy0 : Int,
  comp_xrsiz? : Array[Int] = [],
  comp_yrsiz? : Array[Int] = [],
) -> Array[(Int, Int, Int, Int)] {
  let packet_order : Array[(Int, Int, Int, Int)] = []
  if progression == 0 {
    // LRCP: Layer, Resolution, Component, Position
    for l in 0..<num_layers {
      for r in 0..<num_resolutions {
        for c in 0..<num_components {
          if r < comp_num_resolutions[c] {
            let (npx, npy) = comp_res_num_precincts[c][r]
            for p in 0..<(npx * npy) {
              packet_order.push((r, l, c, p))
            }
          }
        }
      }
    }
    return packet_order
  }
  if progression == 1 {
    // RLCP: Resolution, Layer, Component, Position
    for r in 0..<num_resolutions {
      for l in 0..<num_layers {
        for c in 0..<num_components {
          if r < comp_num_resolutions[c] {
            let (npx, npy) = comp_res_num_precincts[c][r]
            for p in 0..<(npx * npy) {
              packet_order.push((r, l, c, p))
            }
          }
        }
      }
    }
    return packet_order
  }
  // Position-based orders (RPCL/PCRL/CPRL) use reference-grid anchors.
  if progression == 2 {
    // RPCL: Resolution, Position, Component, Layer
    // T.800-2015 B.12.1.3: RPCL progression
    // Handle component sampling and per-resolution precinct alignment.
    let mut ref_x0 = tcx0
    let mut ref_y0 = tcy0
    let mut ref_x1 = tcx0
    let mut ref_y1 = tcy0
    let mut have_ref_bounds = false
    let mut dx = 0
    let mut dy = 0
    for c in 0..<num_components {
      if c >= comp_num_resolutions.length() || c >= comp_res_bounds.length() {
        continue
      }
      let c_num_res = comp_num_resolutions[c]
      if c_num_res <= 0 || c_num_res - 1 >= comp_res_bounds[c].length() {
        continue
      }
      let c_xrsiz = if c < comp_xrsiz.length() { comp_xrsiz[c] } else { 1 }
      let c_yrsiz = if c < comp_yrsiz.length() { comp_yrsiz[c] } else { 1 }
      let c_precinct_size_bytes : Array[Int] = if c <
        comp_precinct_size_bytes.length() {
        comp_precinct_size_bytes[c]
      } else {
        []
      }
      let (c_rx0, c_ry0, c_rx1, c_ry1) = comp_res_bounds[c][c_num_res - 1]
      let c_ref_x0 = c_rx0 * c_xrsiz
      let c_ref_y0 = c_ry0 * c_yrsiz
      let c_ref_x1 = c_rx1 * c_xrsiz
      let c_ref_y1 = c_ry1 * c_yrsiz
      if !have_ref_bounds {
        have_ref_bounds = true
        ref_x0 = c_ref_x0
        ref_y0 = c_ref_y0
        ref_x1 = c_ref_x1
        ref_y1 = c_ref_y1
      } else {
        if c_ref_x0 < ref_x0 {
          ref_x0 = c_ref_x0
        }
        if c_ref_y0 < ref_y0 {
          ref_y0 = c_ref_y0
        }
        if c_ref_x1 > ref_x1 {
          ref_x1 = c_ref_x1
        }
        if c_ref_y1 > ref_y1 {
          ref_y1 = c_ref_y1
        }
      }
      for r in 0..<c_num_res {
        let level = c_num_res - 1 - r
        let (ppx_exp, ppy_exp) = get_precinct_exponents(
          c_precinct_size_bytes, r,
        )
        let cand_dx = c_xrsiz << (ppx_exp + level)
        let cand_dy = c_yrsiz << (ppy_exp + level)
        dx = if dx == 0 || cand_dx < dx { cand_dx } else { dx }
        dy = if dy == 0 || cand_dy < dy { cand_dy } else { dy }
      }
    }
    if !have_ref_bounds || dx <= 0 || dy <= 0 {
      return packet_order
    }
    // T.800-2015 B.12: deduplication bitmap to avoid emitting the same
    // packet key more than once when (x,y) scans revisit the same precinct.
    let seen_packet : Array[Array[Array[Bool]]] = []
    for c in 0..<num_components {
      let comp_seen : Array[Array[Bool]] = []
      let c_num_res = if c < comp_num_resolutions.length() {
        comp_num_resolutions[c]
      } else {
        0
      }
      for r in 0..<c_num_res {
        let flags : Array[Bool] = []
        if c < comp_res_num_precincts.length() &&
          r < comp_res_num_precincts[c].length() {
          let (npx, npy) = comp_res_num_precincts[c][r]
          for _ in 0..<(npx * npy) {
            flags.push(false)
          }
        }
        comp_seen.push(flags)
      }
      seen_packet.push(comp_seen)
    }
    for r in 0..<num_resolutions {
      let mut y = ref_y0
      while y < ref_y1 {
        let y_inc = dy - y % dy
        let mut x = ref_x0
        while x < ref_x1 {
          let x_inc = dx - x % dx
          for c in 0..<num_components {
            if c >= comp_num_resolutions.length() ||
              c >= comp_res_bounds.length() ||
              c >= comp_res_num_precincts.length() ||
              r >= comp_num_resolutions[c] ||
              r >= comp_res_bounds[c].length() ||
              r >= comp_res_num_precincts[c].length() {
              continue
            }
            let c_num_res = comp_num_resolutions[c]
            let level = c_num_res - 1 - r
            let c_xrsiz = if c < comp_xrsiz.length() {
              comp_xrsiz[c]
            } else {
              1
            }
            let c_yrsiz = if c < comp_yrsiz.length() {
              comp_yrsiz[c]
            } else {
              1
            }
            let c_precinct_size_bytes : Array[Int] = if c <
              comp_precinct_size_bytes.length() {
              comp_precinct_size_bytes[c]
            } else {
              []
            }
            let (ppx_exp, ppy_exp) = get_precinct_exponents(
              c_precinct_size_bytes, r,
            )
            let den_x = c_xrsiz << level
            let den_y = c_yrsiz << level
            if den_x <= 0 || den_y <= 0 {
              continue
            }
            let (trx0, try0, trx1, try1) = comp_res_bounds[c][r]
            let (npx, npy) = comp_res_num_precincts[c][r]
            if npx <= 0 || npy <= 0 || trx0 == trx1 || try0 == try1 {
              continue
            }
            let rpx = ppx_exp + level
            let rpy = ppy_exp + level
            let y_align = y % (c_yrsiz << rpy) == 0 ||
              (y == ref_y0 && (try0 << level) % (1 << rpy) != 0)
            if !y_align {
              continue
            }
            let x_align = x % (c_xrsiz << rpx) == 0 ||
              (x == ref_x0 && (trx0 << level) % (1 << rpx) != 0)
            if !x_align {
              continue
            }
            let qx = (x + den_x - 1) / den_x
            let qy = (y + den_y - 1) / den_y
            let prci = (qx >> ppx_exp) - (trx0 >> ppx_exp)
            let prcj = (qy >> ppy_exp) - (try0 >> ppy_exp)
            if prci < 0 || prci >= npx || prcj < 0 || prcj >= npy {
              continue
            }
            let prec = prci + prcj * npx
            if c < seen_packet.length() &&
              r < seen_packet[c].length() &&
              prec >= 0 &&
              prec < seen_packet[c][r].length() &&
              seen_packet[c][r][prec] {
              continue
            }
            if c < seen_packet.length() &&
              r < seen_packet[c].length() &&
              prec >= 0 &&
              prec < seen_packet[c][r].length() {
              seen_packet[c][r][prec] = true
            }
            for l in 0..<num_layers {
              packet_order.push((r, l, c, prec))
            }
          }
          x += x_inc
        }
        y += y_inc
      }
    }
    return packet_order
  }
  if progression == 3 {
    // PCRL: Position, Component, Resolution, Layer
    // T.800-2015 B.12.1.4: PCRL progression:
    // scan reference-grid positions (y,x), then components, then resolutions.
    let mut ref_x0 = tcx0
    let mut ref_y0 = tcy0
    let mut ref_x1 = tcx0
    let mut ref_y1 = tcy0
    let mut have_ref_bounds = false
    let mut dx = 0
    let mut dy = 0
    for c in 0..<num_components {
      if c >= comp_num_resolutions.length() || c >= comp_res_bounds.length() {
        continue
      }
      let c_num_res = comp_num_resolutions[c]
      if c_num_res <= 0 || c_num_res - 1 >= comp_res_bounds[c].length() {
        continue
      }
      let c_xrsiz = if c < comp_xrsiz.length() { comp_xrsiz[c] } else { 1 }
      let c_yrsiz = if c < comp_yrsiz.length() { comp_yrsiz[c] } else { 1 }
      let c_precinct_size_bytes : Array[Int] = if c <
        comp_precinct_size_bytes.length() {
        comp_precinct_size_bytes[c]
      } else {
        []
      }
      let (c_rx0, c_ry0, c_rx1, c_ry1) = comp_res_bounds[c][c_num_res - 1]
      let c_ref_x0 = c_rx0 * c_xrsiz
      let c_ref_y0 = c_ry0 * c_yrsiz
      let c_ref_x1 = c_rx1 * c_xrsiz
      let c_ref_y1 = c_ry1 * c_yrsiz
      if !have_ref_bounds {
        have_ref_bounds = true
        ref_x0 = c_ref_x0
        ref_y0 = c_ref_y0
        ref_x1 = c_ref_x1
        ref_y1 = c_ref_y1
      } else {
        if c_ref_x0 < ref_x0 {
          ref_x0 = c_ref_x0
        }
        if c_ref_y0 < ref_y0 {
          ref_y0 = c_ref_y0
        }
        if c_ref_x1 > ref_x1 {
          ref_x1 = c_ref_x1
        }
        if c_ref_y1 > ref_y1 {
          ref_y1 = c_ref_y1
        }
      }
      for r in 0..<c_num_res {
        let level = c_num_res - 1 - r
        let (ppx_exp, ppy_exp) = get_precinct_exponents(
          c_precinct_size_bytes, r,
        )
        let cand_dx = c_xrsiz << (ppx_exp + level)
        let cand_dy = c_yrsiz << (ppy_exp + level)
        dx = if dx == 0 || cand_dx < dx { cand_dx } else { dx }
        dy = if dy == 0 || cand_dy < dy { cand_dy } else { dy }
      }
    }
    if !have_ref_bounds || dx <= 0 || dy <= 0 {
      return packet_order
    }
    let seen_packet : Array[Array[Array[Bool]]] = []
    for c in 0..<num_components {
      let comp_seen : Array[Array[Bool]] = []
      let c_num_res = if c < comp_num_resolutions.length() {
        comp_num_resolutions[c]
      } else {
        0
      }
      for r in 0..<c_num_res {
        let flags : Array[Bool] = []
        if c < comp_res_num_precincts.length() &&
          r < comp_res_num_precincts[c].length() {
          let (npx, npy) = comp_res_num_precincts[c][r]
          for _ in 0..<(npx * npy) {
            flags.push(false)
          }
        }
        comp_seen.push(flags)
      }
      seen_packet.push(comp_seen)
    }
    let mut y = ref_y0
    while y < ref_y1 {
      let y_inc = dy - y % dy
      let mut x = ref_x0
      while x < ref_x1 {
        let x_inc = dx - x % dx
        for c in 0..<num_components {
          if c >= comp_num_resolutions.length() ||
            c >= comp_res_bounds.length() ||
            c >= comp_res_num_precincts.length() {
            continue
          }
          for r in 0..<num_resolutions {
            if r >= comp_num_resolutions[c] ||
              r >= comp_res_bounds[c].length() ||
              r >= comp_res_num_precincts[c].length() {
              continue
            }
            let c_num_res = comp_num_resolutions[c]
            let level = c_num_res - 1 - r
            let c_xrsiz = if c < comp_xrsiz.length() {
              comp_xrsiz[c]
            } else {
              1
            }
            let c_yrsiz = if c < comp_yrsiz.length() {
              comp_yrsiz[c]
            } else {
              1
            }
            let c_precinct_size_bytes : Array[Int] = if c <
              comp_precinct_size_bytes.length() {
              comp_precinct_size_bytes[c]
            } else {
              []
            }
            let (ppx_exp, ppy_exp) = get_precinct_exponents(
              c_precinct_size_bytes, r,
            )
            let den_x = c_xrsiz << level
            let den_y = c_yrsiz << level
            if den_x <= 0 || den_y <= 0 {
              continue
            }
            let (trx0, try0, trx1, try1) = comp_res_bounds[c][r]
            let (npx, npy) = comp_res_num_precincts[c][r]
            if npx <= 0 || npy <= 0 || trx0 == trx1 || try0 == try1 {
              continue
            }
            let rpx = ppx_exp + level
            let rpy = ppy_exp + level
            let y_align = y % (c_yrsiz << rpy) == 0 ||
              (y == ref_y0 && (try0 << level) % (1 << rpy) != 0)
            if !y_align {
              continue
            }
            let x_align = x % (c_xrsiz << rpx) == 0 ||
              (x == ref_x0 && (trx0 << level) % (1 << rpx) != 0)
            if !x_align {
              continue
            }
            let qx = (x + den_x - 1) / den_x
            let qy = (y + den_y - 1) / den_y
            let prci = (qx >> ppx_exp) - (trx0 >> ppx_exp)
            let prcj = (qy >> ppy_exp) - (try0 >> ppy_exp)
            if prci < 0 || prci >= npx || prcj < 0 || prcj >= npy {
              continue
            }
            let prec = prci + prcj * npx
            if c < seen_packet.length() &&
              r < seen_packet[c].length() &&
              prec >= 0 &&
              prec < seen_packet[c][r].length() &&
              seen_packet[c][r][prec] {
              continue
            }
            if c < seen_packet.length() &&
              r < seen_packet[c].length() &&
              prec >= 0 &&
              prec < seen_packet[c][r].length() {
              seen_packet[c][r][prec] = true
            }
            for l in 0..<num_layers {
              packet_order.push((r, l, c, prec))
            }
          }
        }
        x += x_inc
      }
      y += y_inc
    }
    return packet_order
  }
  if progression == 4 {
    // CPRL: Component, Position, Resolution, Layer
    // T.800-2015 B.12.1.5: CPRL progression:
    // component outer loop, then reference-grid (y,x), then resolution, then layer.
    let seen_packet : Array[Array[Array[Bool]]] = []
    for c in 0..<num_components {
      let comp_seen : Array[Array[Bool]] = []
      let c_num_res = if c < comp_num_resolutions.length() {
        comp_num_resolutions[c]
      } else {
        0
      }
      for r in 0..<c_num_res {
        let flags : Array[Bool] = []
        if c < comp_res_num_precincts.length() &&
          r < comp_res_num_precincts[c].length() {
          let (npx, npy) = comp_res_num_precincts[c][r]
          for _ in 0..<(npx * npy) {
            flags.push(false)
          }
        }
        comp_seen.push(flags)
      }
      seen_packet.push(comp_seen)
    }
    for c in 0..<num_components {
      if c >= comp_num_resolutions.length() ||
        c >= comp_res_bounds.length() ||
        c >= comp_res_num_precincts.length() {
        continue
      }
      let c_num_res = comp_num_resolutions[c]
      if c_num_res <= 0 || c_num_res - 1 >= comp_res_bounds[c].length() {
        continue
      }
      let c_xrsiz = if c < comp_xrsiz.length() { comp_xrsiz[c] } else { 1 }
      let c_yrsiz = if c < comp_yrsiz.length() { comp_yrsiz[c] } else { 1 }
      let c_precinct_size_bytes : Array[Int] = if c <
        comp_precinct_size_bytes.length() {
        comp_precinct_size_bytes[c]
      } else {
        []
      }
      let mut dx = 0
      let mut dy = 0
      for r in 0..<c_num_res {
        let level = c_num_res - 1 - r
        let (ppx_exp, ppy_exp) = get_precinct_exponents(
          c_precinct_size_bytes, r,
        )
        let cand_dx = c_xrsiz << (ppx_exp + level)
        let cand_dy = c_yrsiz << (ppy_exp + level)
        dx = if dx == 0 || cand_dx < dx { cand_dx } else { dx }
        dy = if dy == 0 || cand_dy < dy { cand_dy } else { dy }
      }
      if dx <= 0 || dy <= 0 {
        continue
      }
      let (rx0, ry0, rx1, ry1) = comp_res_bounds[c][c_num_res - 1]
      let c_ref_x0 = rx0 * c_xrsiz
      let c_ref_y0 = ry0 * c_yrsiz
      let c_ref_x1 = rx1 * c_xrsiz
      let c_ref_y1 = ry1 * c_yrsiz
      let mut y = c_ref_y0
      while y < c_ref_y1 {
        let y_inc = dy - y % dy
        let mut x = c_ref_x0
        while x < c_ref_x1 {
          let x_inc = dx - x % dx
          for r in 0..<num_resolutions {
            if r >= c_num_res ||
              r >= comp_res_bounds[c].length() ||
              r >= comp_res_num_precincts[c].length() {
              continue
            }
            let level = c_num_res - 1 - r
            let den_x = c_xrsiz << level
            let den_y = c_yrsiz << level
            if den_x <= 0 || den_y <= 0 {
              continue
            }
            let (trx0, try0, trx1, try1) = comp_res_bounds[c][r]
            let (npx, npy) = comp_res_num_precincts[c][r]
            if npx <= 0 || npy <= 0 || trx0 == trx1 || try0 == try1 {
              continue
            }
            let (ppx_exp, ppy_exp) = get_precinct_exponents(
              c_precinct_size_bytes, r,
            )
            let rpx = ppx_exp + level
            let rpy = ppy_exp + level
            let y_align = y % (c_yrsiz << rpy) == 0 ||
              (y == c_ref_y0 && (try0 << level) % (1 << rpy) != 0)
            if !y_align {
              continue
            }
            let x_align = x % (c_xrsiz << rpx) == 0 ||
              (x == c_ref_x0 && (trx0 << level) % (1 << rpx) != 0)
            if !x_align {
              continue
            }
            let qx = (x + den_x - 1) / den_x
            let qy = (y + den_y - 1) / den_y
            let prci = (qx >> ppx_exp) - (trx0 >> ppx_exp)
            let prcj = (qy >> ppy_exp) - (try0 >> ppy_exp)
            if prci < 0 || prci >= npx || prcj < 0 || prcj >= npy {
              continue
            }
            let prec = prci + prcj * npx
            if c < seen_packet.length() &&
              r < seen_packet[c].length() &&
              prec >= 0 &&
              prec < seen_packet[c][r].length() &&
              seen_packet[c][r][prec] {
              continue
            }
            if c < seen_packet.length() &&
              r < seen_packet[c].length() &&
              prec >= 0 &&
              prec < seen_packet[c][r].length() {
              seen_packet[c][r][prec] = true
            }
            for l in 0..<num_layers {
              packet_order.push((r, l, c, prec))
            }
          }
          x += x_inc
        }
        y += y_inc
      }
    }
    return packet_order
  }
  let anchors = build_precinct_anchors(
    num_components,
    comp_num_resolutions,
    comp_decomp_levels,
    comp_res_num_precincts,
    comp_res_bounds,
    comp_precinct_size_bytes,
    tcx0,
    tcy0,
    comp_xrsiz~,
    comp_yrsiz~,
  )
  // CPRL: Component, Position, Resolution, Layer
  sort_precinct_anchors_in_place(anchors, 2)
  for a in anchors {
    for l in 0..<num_layers {
      packet_order.push((a.resolution, l, a.component, a.precinct))
    }
  }
  packet_order
}

///|
// Clamp a progression-loop start bound into [0, limit].
fn clamp_progression_start(value : Int, limit : Int) -> Int {
  if value > 0 {
    if value < limit {
      value
    } else {
      limit
    }
  } else {
    0
  }
}

///|
// Clamp a progression-loop end bound into [0, limit].
fn clamp_progression_end(value : Int, limit : Int) -> Int {
  if value < limit {
    if value > 0 {
      value
    } else {
      0
    }
  } else {
    limit
  }
}

///|
// Append pending layers for one (component, resolution, precinct) packet key
// up to layer_end (exclusive), while preserving "no packet repetition" across
// POC volumes (T.800-2015 B.12.2).
fn append_packet_layers(
  packet_order : Array[(Int, Int, Int, Int)],
  next_layer_by_precinct : Array[Array[Array[Int]]],
  layer_end : Int,
  resolution : Int,
  component : Int,
  precinct : Int,
) -> Unit {
  if component < 0 || component >= next_layer_by_precinct.length() {
    return
  }
  if resolution < 0 || resolution >= next_layer_by_precinct[component].length() {
    return
  }
  if precinct < 0 ||
    precinct >= next_layer_by_precinct[component][resolution].length() {
    return
  }
  let mut next_layer = next_layer_by_precinct[component][resolution][precinct]
  while next_layer < layer_end {
    packet_order.push((resolution, next_layer, component, precinct))
    next_layer += 1
  }
  next_layer_by_precinct[component][resolution][precinct] = next_layer
}

///|
// Append packets for one progression-order volume.
fn append_packet_order_volume(
  packet_order : Array[(Int, Int, Int, Int)],
  progression : Int,
  layer_end : Int,
  resolution_start : Int,
  resolution_end : Int,
  component_start : Int,
  component_end : Int,
  num_layers : Int,
  num_resolutions : Int,
  num_components : Int,
  comp_num_resolutions : Array[Int],
  comp_decomp_levels : Array[Int],
  comp_res_num_precincts : Array[Array[(Int, Int)]],
  comp_res_bounds : Array[Array[(Int, Int, Int, Int)]],
  comp_precinct_size_bytes : Array[Array[Int]],
  tcx0 : Int,
  tcy0 : Int,
  comp_xrsiz : Array[Int],
  comp_yrsiz : Array[Int],
  next_layer_by_precinct : Array[Array[Array[Int]]],
) -> Unit {
  let l_end = clamp_progression_end(layer_end, num_layers)
  let r_start = clamp_progression_start(resolution_start, num_resolutions)
  let r_end = clamp_progression_end(resolution_end, num_resolutions)
  let c_start = clamp_progression_start(component_start, num_components)
  let c_end = clamp_progression_end(component_end, num_components)
  if l_end <= 0 || r_start >= r_end || c_start >= c_end {
    return
  }
  let order = if progression >= 0 && progression <= 4 { progression } else { 0 }
  if order == 0 {
    // LRCP: Layer, Resolution, Component, Position
    for l in 0..<l_end {
      for r in r_start..<r_end {
        for c in c_start..<c_end {
          if c < comp_num_resolutions.length() &&
            r < comp_num_resolutions[c] &&
            c < comp_res_num_precincts.length() &&
            r < comp_res_num_precincts[c].length() {
            let (npx, npy) = comp_res_num_precincts[c][r]
            for p in 0..<(npx * npy) {
              append_packet_layers(
                packet_order,
                next_layer_by_precinct,
                l + 1,
                r,
                c,
                p,
              )
            }
          }
        }
      }
    }
    return
  }
  if order == 1 {
    // RLCP: Resolution, Layer, Component, Position
    for r in r_start..<r_end {
      for l in 0..<l_end {
        for c in c_start..<c_end {
          if c < comp_num_resolutions.length() &&
            r < comp_num_resolutions[c] &&
            c < comp_res_num_precincts.length() &&
            r < comp_res_num_precincts[c].length() {
            let (npx, npy) = comp_res_num_precincts[c][r]
            for p in 0..<(npx * npy) {
              append_packet_layers(
                packet_order,
                next_layer_by_precinct,
                l + 1,
                r,
                c,
                p,
              )
            }
          }
        }
      }
    }
    return
  }
  if order == 4 {
    // Reuse the main CPRL iterator so POC volumes follow the same component /
    // position / resolution walk as the non-POC path.
    let base_order = build_packet_order(
      4,
      1,
      num_resolutions,
      num_components,
      comp_num_resolutions,
      comp_decomp_levels,
      comp_res_num_precincts,
      comp_res_bounds,
      comp_precinct_size_bytes,
      tcx0,
      tcy0,
      comp_xrsiz~,
      comp_yrsiz~,
    )
    for entry in base_order {
      let (resolution, _, component, precinct) = entry
      if component < c_start ||
        component >= c_end ||
        resolution < r_start ||
        resolution >= r_end {
        continue
      }
      append_packet_layers(
        packet_order, next_layer_by_precinct, l_end, resolution, component, precinct,
      )
    }
    return
  }
  if order == 2 {
    // Reuse the main RPCL iterator so POC volumes match the non-POC path,
    // especially for misaligned precinct grids at non-zero tile origins.
    let base_order = build_packet_order(
      2,
      1,
      num_resolutions,
      num_components,
      comp_num_resolutions,
      comp_decomp_levels,
      comp_res_num_precincts,
      comp_res_bounds,
      comp_precinct_size_bytes,
      tcx0,
      tcy0,
      comp_xrsiz~,
      comp_yrsiz~,
    )
    for entry in base_order {
      let (resolution, _, component, precinct) = entry
      if component < c_start ||
        component >= c_end ||
        resolution < r_start ||
        resolution >= r_end {
        continue
      }
      append_packet_layers(
        packet_order, next_layer_by_precinct, l_end, resolution, component, precinct,
      )
    }
    return
  }
  if order == 3 {
    // Reuse the main PCRL iterator so POC volumes match the non-POC path.
    let base_order = build_packet_order(
      3,
      1,
      num_resolutions,
      num_components,
      comp_num_resolutions,
      comp_decomp_levels,
      comp_res_num_precincts,
      comp_res_bounds,
      comp_precinct_size_bytes,
      tcx0,
      tcy0,
      comp_xrsiz~,
      comp_yrsiz~,
    )
    for entry in base_order {
      let (resolution, _, component, precinct) = entry
      if component < c_start ||
        component >= c_end ||
        resolution < r_start ||
        resolution >= r_end {
        continue
      }
      append_packet_layers(
        packet_order, next_layer_by_precinct, l_end, resolution, component, precinct,
      )
    }
    return
  }
  let anchors = build_precinct_anchors(
    num_components,
    comp_num_resolutions,
    comp_decomp_levels,
    comp_res_num_precincts,
    comp_res_bounds,
    comp_precinct_size_bytes,
    tcx0,
    tcy0,
    comp_xrsiz~,
    comp_yrsiz~,
  )
  // Fallback (currently CPRL-compatible sort for non-standard progression code)
  sort_precinct_anchors_in_place(anchors, 2)
  for a in anchors {
    if a.component < c_start ||
      a.component >= c_end ||
      a.resolution < r_start ||
      a.resolution >= r_end {
      continue
    }
    for l in 0..<l_end {
      append_packet_layers(
        packet_order,
        next_layer_by_precinct,
        l + 1,
        a.resolution,
        a.component,
        a.precinct,
      )
    }
  }
}

///|
// Build packet processing order with optional POC progression-order volumes.
// If POC is present, progression orders/ranges are taken from POC entries
// (T.800-2015 A.6.6, B.12.2). Any packets not covered by POC volumes are
// filled by COD progression as a fallback for robustness.
pub fn build_packet_order_with_poc(
  progression : Int,
  num_layers : Int,
  num_resolutions : Int,
  num_components : Int,
  comp_num_resolutions : Array[Int],
  comp_decomp_levels : Array[Int],
  comp_res_num_precincts : Array[Array[(Int, Int)]],
  comp_res_bounds : Array[Array[(Int, Int, Int, Int)]],
  comp_precinct_size_bytes : Array[Array[Int]],
  tcx0 : Int,
  tcy0 : Int,
  poc_entries : Array[(Int, Int, Int, Int, Int, Int)],
  comp_xrsiz? : Array[Int] = [],
  comp_yrsiz? : Array[Int] = [],
) -> Array[(Int, Int, Int, Int)] {
  if poc_entries.length() == 0 {
    return build_packet_order(
      progression,
      num_layers,
      num_resolutions,
      num_components,
      comp_num_resolutions,
      comp_decomp_levels,
      comp_res_num_precincts,
      comp_res_bounds,
      comp_precinct_size_bytes,
      tcx0,
      tcy0,
      comp_xrsiz~,
      comp_yrsiz~,
    )
  }
  let next_layer_by_precinct : Array[Array[Array[Int]]] = []
  for c in 0..<num_components {
    let comp_layers : Array[Array[Int]] = []
    let c_num_res = if c < comp_num_resolutions.length() {
      comp_num_resolutions[c]
    } else {
      0
    }
    for r in 0..<c_num_res {
      let prec_layers : Array[Int] = []
      if c < comp_res_num_precincts.length() &&
        r < comp_res_num_precincts[c].length() {
        let (npx, npy) = comp_res_num_precincts[c][r]
        for _ in 0..<(npx * npy) {
          prec_layers.push(0)
        }
      }
      comp_layers.push(prec_layers)
    }
    next_layer_by_precinct.push(comp_layers)
  }
  let packet_order : Array[(Int, Int, Int, Int)] = []
  for entry in poc_entries {
    let (rspoc, cspoc, lyepoc, repoc, cepoc, ppoc) = entry
    let order = if ppoc >= 0 && ppoc <= 4 { ppoc } else { progression }
    append_packet_order_volume(
      packet_order, order, lyepoc, rspoc, repoc, cspoc, cepoc, num_layers, num_resolutions,
      num_components, comp_num_resolutions, comp_decomp_levels, comp_res_num_precincts,
      comp_res_bounds, comp_precinct_size_bytes, tcx0, tcy0, comp_xrsiz, comp_yrsiz,
      next_layer_by_precinct,
    )
  }
  // Keep decoder robust for partially described/non-conformant POC ranges.
  append_packet_order_volume(
    packet_order, progression, num_layers, 0, num_resolutions, 0, num_components,
    num_layers, num_resolutions, num_components, comp_num_resolutions, comp_decomp_levels,
    comp_res_num_precincts, comp_res_bounds, comp_precinct_size_bytes, tcx0, tcy0,
    comp_xrsiz, comp_yrsiz, next_layer_by_precinct,
  )
  packet_order
}

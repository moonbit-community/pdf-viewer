///|
fn find_next_sot_or_eoc(data : Bytes, start : Int) -> Int {
  let mut i = start
  while i + 1 < data.length() {
    if data[i].to_int() == 0xFF {
      let n = data[i + 1].to_int()
      if n == 0x90 || n == 0xD9 {
        return i
      }
      if n == 0x00 {
        // Byte stuffing in packet data.
        i += 2
        continue
      }
    }
    i += 1
  }
  data.length()
}

///|
fn extract_in_bitstream_markers(
  packet : Bytes,
  packet_start_pos : Int,
) -> (Array[SopMetadata], Array[Int]) {
  let sops : Array[SopMetadata] = []
  let ephs : Array[Int] = []
  let mut k = 0
  while k + 1 < packet.length() {
    if packet[k].to_int() != 0xFF {
      k += 1
      continue
    }
    let n = packet[k + 1].to_int()
    if n == 0x00 {
      k += 2
      continue
    }
    if n == 0x91 &&
      k + 5 < packet.length() &&
      packet[k + 2].to_int() == 0x00 &&
      packet[k + 3].to_int() == 0x04 {
      let nsop = (packet[k + 4].to_int() << 8) + packet[k + 5].to_int()
      sops.push({ nsop, position: packet_start_pos + k, })
      k += 6
      continue
    }
    if n == 0x92 {
      ephs.push(packet_start_pos + k)
      k += 2
      continue
    }
    k += 1
  }
  (sops, ephs)
}

///|
fn validate_packet_bit_stuffing(packet : Bytes) -> Result[Unit, String] {
  // Spec (Annex B.10.1) defines packet-header stuffing, not a generic packet-body FFxx ban.
  let mut k = 0
  while k + 1 < packet.length() {
    if packet[k].to_int() != 0xFF {
      k += 1
      continue
    }
    let n = packet[k + 1].to_int()
    if n == 0x00 || n == 0x92 {
      k += 2
      continue
    }
    if n == 0x91 {
      if k + 5 >= packet.length() {
        return Err("truncated SOP marker in packet data")
      }
      if packet[k + 2].to_int() != 0x00 || packet[k + 3].to_int() != 0x04 {
        return Err("invalid SOP marker length in packet data")
      }
      k += 6
      continue
    }
    // Implementation policy: validate explicit SOP/EPH syntax only.
    k += 1
  }
  Ok(())
}

///|
fn read_bit(data : Bytes, bit_pos : Int) -> Result[Int, String] {
  let byte_index = bit_pos / 8
  if byte_index >= data.length() {
    return Err("packet header bitstream truncated")
  }
  let bit_index = 7 - bit_pos % 8
  Ok((data[byte_index].to_int() >> bit_index) & 1)
}

///|
fn read_bits(
  data : Bytes,
  bit_pos : Int,
  width : Int,
) -> Result[(Int, Int), String] {
  if width <= 0 {
    return Err("invalid bit width")
  }
  let mut v = 0
  let mut p = bit_pos
  for _ in 0..<width {
    let b = read_bit(data, p)
    guard b is Ok(bit) else { return Err("packet header bitstream truncated") }
    v = (v << 1) + bit
    p += 1
  }
  Ok((v, p))
}

///|
fn ceil_div2(v : Int) -> Int {
  (v + 1) / 2
}

///|
fn build_tag_tree_levels(
  width : Int,
  height : Int,
) -> Result[Array[TagTreeLevelMetadata], String] {
  if width <= 0 || height <= 0 {
    return Err("invalid tag-tree size")
  }
  let levels : Array[TagTreeLevelMetadata] = []
  let mut w = width
  let mut h = height
  let mut offset = 0
  while true {
    levels.push({ width: w, height: h, offset, })
    if w == 1 && h == 1 {
      break
    }
    offset += w * h
    w = ceil_div2(w)
    h = ceil_div2(h)
  }
  Ok(levels)
}

///|
pub fn decode_tag_tree_inclusion_flags(
  data : Bytes,
  width : Int,
  height : Int,
  threshold : Int,
) -> Result[(Array[Bool], Int), String] {
  if threshold <= 0 {
    return Err("tag-tree threshold must be positive")
  }
  let levels_v = build_tag_tree_levels(width, height)
  guard levels_v is Ok(levels) else { return Err("invalid tag-tree size") }
  let root_level = levels.length() - 1
  let total_nodes = levels[root_level].offset + 1
  let node_low : Array[Int] = []
  let node_known : Array[Int?] = []
  for _ in 0..<total_nodes {
    node_low.push(0)
    node_known.push(None)
  }
  let mut bit_pos = 0
  let flags : Array[Bool] = []
  for y in 0..<height {
    for x in 0..<width {
      let path : Array[Int] = []
      let mut px = x
      let mut py = y
      let mut level = 0
      while level < levels.length() {
        let meta = levels[level]
        let idx = meta.offset + py * meta.width + px
        path.push(idx)
        if level == root_level {
          break
        }
        px = px / 2
        py = py / 2
        level = level + 1
      }
      let mut low = 0
      let mut rev = path.length() - 1
      while rev >= 0 {
        let idx = path[rev]
        if node_low[idx] < low {
          node_low[idx] = low
        } else {
          low = node_low[idx]
        }
        while node_low[idx] < threshold && node_known[idx] is None {
          let bit = read_bit(data, bit_pos)
          guard bit is Ok(v) else { return Err("tag-tree bitstream truncated") }
          bit_pos += 1
          if v == 0 {
            node_low[idx] += 1
          } else {
            node_known[idx] = Some(node_low[idx])
          }
        }
        if node_known[idx] is Some(v) {
          low = v
        } else {
          low = node_low[idx]
        }
        rev = rev - 1
      }
      flags.push(low < threshold)
    }
  }
  Ok((flags, bit_pos))
}

///|
fn decode_tag_tree_member_with_state(
  levels : Array[TagTreeLevelMetadata],
  node_low : Array[Int],
  node_known : Array[Int?],
  x : Int,
  y : Int,
  threshold : Int,
  data : Bytes,
  start_bit_pos : Int,
) -> Result[(Bool, Int), String] {
  if threshold <= 0 {
    return Err("tag-tree threshold must be positive")
  }
  if levels.length() == 0 {
    return Err("invalid tag-tree size")
  }
  if x < 0 || y < 0 || x >= levels[0].width || y >= levels[0].height {
    return Err("tag-tree coordinate out of range")
  }
  let root_level = levels.length() - 1
  let path : Array[Int] = []
  let mut px = x
  let mut py = y
  let mut level = 0
  while level < levels.length() {
    let meta = levels[level]
    let idx = meta.offset + py * meta.width + px
    path.push(idx)
    if level == root_level {
      break
    }
    px = px / 2
    py = py / 2
    level = level + 1
  }
  let mut bit_pos = start_bit_pos
  let mut low = 0
  let mut rev = path.length() - 1
  while rev >= 0 {
    let idx = path[rev]
    if node_low[idx] < low {
      node_low[idx] = low
    } else {
      low = node_low[idx]
    }
    while node_low[idx] < threshold && node_known[idx] is None {
      let bit = read_bit(data, bit_pos)
      guard bit is Ok(v) else { return Err("tag-tree bitstream truncated") }
      bit_pos += 1
      if v == 0 {
        node_low[idx] += 1
      } else {
        node_known[idx] = Some(node_low[idx])
      }
    }
    if node_known[idx] is Some(v) {
      low = v
    } else {
      low = node_low[idx]
    }
    rev = rev - 1
  }
  Ok((low < threshold, bit_pos))
}

///|
fn decode_tag_tree_value_with_state(
  levels : Array[TagTreeLevelMetadata],
  node_low : Array[Int],
  node_known : Array[Int?],
  x : Int,
  y : Int,
  data : Bytes,
  start_bit_pos : Int,
) -> Result[(Int, Int), String] {
  let mut bit_pos = start_bit_pos
  let mut threshold = 1
  while threshold <= 128 {
    let step = decode_tag_tree_member_with_state(
      levels, node_low, node_known, x, y, threshold, data, bit_pos,
    )
    guard step is Ok((included, next_pos)) else {
      return Err("failed to decode tag-tree value")
    }
    bit_pos = next_pos
    if included {
      return Ok((threshold - 1, bit_pos))
    }
    threshold += 1
  }
  Err("tag-tree value exceeds supported range")
}

///|
fn decode_num_coding_passes(
  data : Bytes,
  bit_pos : Int,
) -> Result[(Int, Int), String] {
  let b0 = read_bit(data, bit_pos)
  guard b0 is Ok(v0) else { return Err("packet header bitstream truncated") }
  if v0 == 0 {
    return Ok((1, bit_pos + 1))
  }
  let b1 = read_bit(data, bit_pos + 1)
  guard b1 is Ok(v1) else { return Err("packet header bitstream truncated") }
  if v1 == 0 {
    return Ok((2, bit_pos + 2))
  }
  let b2 = read_bit(data, bit_pos + 2)
  guard b2 is Ok(v2) else { return Err("packet header bitstream truncated") }
  if v2 == 0 {
    let b3 = read_bit(data, bit_pos + 3)
    guard b3 is Ok(v3) else { return Err("packet header bitstream truncated") }
    return Ok((if v3 == 0 { 3 } else { 4 }, bit_pos + 4))
  }
  let b3 = read_bit(data, bit_pos + 3)
  guard b3 is Ok(v3) else { return Err("packet header bitstream truncated") }
  if v3 == 0 {
    return Ok((5, bit_pos + 4))
  }
  let mid = read_bits(data, bit_pos + 4, 5)
  guard mid is Ok((mid5, p5)) else {
    return Err("packet header bitstream truncated")
  }
  if mid5 < 31 {
    return Ok((6 + mid5, p5))
  }
  let tail = read_bits(data, p5, 7)
  guard tail is Ok((tail7, p7)) else {
    return Err("packet header bitstream truncated")
  }
  Ok((37 + tail7, p7))
}

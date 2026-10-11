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
// Spec basis (T.800-2015 B.10):
// - packet header syntax carries inclusion, coding-pass count, and
//   segment length signalling for code-block contributions.
pub fn parse_packet_header_single_packet_with_tag_tree(
  data : Bytes,
  width : Int,
  height : Int,
  layer_index : Int,
) -> Result[PacketHeaderMetadata, String] {
  // Spec basis (T.800-2015 B.10.4-B.10.7):
  // Per-code-block interleaved processing: for each CB in raster order,
  // decode inclusion (tag-tree) → ZBP (tag-tree) → passes → lengths.
  // Inclusion and ZBP use separate tag trees with shared node state.
  if layer_index < 0 {
    return Err("layer_index must be non-negative")
  }
  let code_block_count = width * height
  if code_block_count <= 0 {
    return Err("invalid tag-tree size")
  }
  let z = read_bit(data, 0)
  guard z is Ok(non_zero_flag) else {
    return Err("packet header bitstream truncated")
  }
  if non_zero_flag == 0 {
    let code_blocks : Array[PacketHeaderCodeBlockMetadata] = []
    for cb in 0..<code_block_count {
      code_blocks.push({
        code_block_index: cb,
        included: false,
        first_inclusion: false,
        zero_bit_planes: None,
        coding_passes: None,
        lblock_increment: None,
        segment_lengths: [],
        segment_passes: [],
      })
    }
    return Ok({ zero_length: true, code_blocks, consumed_bits: 1, })
  }
  let levels_v = build_tag_tree_levels(width, height)
  guard levels_v is Ok(levels) else { return Err("invalid tag-tree size") }
  let total_nodes = levels[levels.length() - 1].offset + 1
  let (incl_low, incl_known) = init_tag_tree_node_arrays(total_nodes)
  let (zbp_low, zbp_known) = init_tag_tree_node_arrays(total_nodes)
  let lblock_by_cb : Array[Int] = []
  for _ in 0..<code_block_count {
    lblock_by_cb.push(3)
  }
  let mut bit_pos = 1
  let code_blocks : Array[PacketHeaderCodeBlockMetadata] = []
  for y in 0..<height {
    for x in 0..<width {
      let cb = y * width + x
      let inc = decode_tag_tree_member_with_state(
        levels,
        incl_low,
        incl_known,
        x,
        y,
        layer_index + 1,
        data,
        bit_pos,
      )
      guard inc is Ok((inc_flag, inc_next_pos)) else {
        return Err("failed to decode tag-tree inclusion flags")
      }
      bit_pos = inc_next_pos
      if !inc_flag {
        code_blocks.push({
          code_block_index: cb,
          included: false,
          first_inclusion: false,
          zero_bit_planes: None,
          coding_passes: None,
          lblock_increment: None,
          segment_lengths: [],
          segment_passes: [],
        })
        continue
      }
      let zbp = decode_tag_tree_value_with_state(
        levels, zbp_low, zbp_known, x, y, data, bit_pos,
      )
      guard zbp is Ok((p, zbp_next_pos)) else {
        return Err("failed to decode zero bit-plane tag-tree")
      }
      bit_pos = zbp_next_pos
      let pass_v = decode_num_coding_passes(data, bit_pos)
      guard pass_v is Ok((coding_passes, next_pos)) else {
        return Err("failed to decode number of coding passes")
      }
      bit_pos = next_pos
      let lengths_v = decode_lengths_for_codeblock(
        data,
        bit_pos,
        lblock_by_cb[cb],
        coding_passes,
        [],
      )
      guard lengths_v
        is Ok((segment_lengths, next_len_pos, next_lblock, total_inc)) else {
        return Err("failed to decode code-block segment length")
      }
      bit_pos = next_len_pos
      lblock_by_cb[cb] = next_lblock
      code_blocks.push({
        code_block_index: cb,
        included: true,
        first_inclusion: true,
        zero_bit_planes: Some(p),
        coding_passes: Some(coding_passes),
        lblock_increment: Some(total_inc),
        segment_lengths,
        segment_passes: [coding_passes],
      })
    }
  }
  Ok({ zero_length: false, code_blocks, consumed_bits: bit_pos, })
}

///|
// Spec basis (T.800-2015 B.10):
// - packet header syntax carries inclusion, coding-pass count, and
//   segment length signalling for code-block contributions.
pub fn parse_packet_header_single_packet_with_tag_tree_and_pass_splits(
  data : Bytes,
  width : Int,
  height : Int,
  layer_index : Int,
  added_passes_per_code_block : Array[Array[Int]],
) -> Result[PacketHeaderMetadata, String] {
  // Spec basis (T.800-2015 B.10.4-B.10.7):
  // Per-code-block interleaved processing: for each CB in raster order,
  // decode inclusion (tag-tree) → ZBP (tag-tree) → passes → lengths.
  // Inclusion and ZBP use separate tag trees with shared node state.
  if layer_index < 0 {
    return Err("layer_index must be non-negative")
  }
  let code_block_count = width * height
  if code_block_count <= 0 {
    return Err("invalid tag-tree size")
  }
  let z = read_bit(data, 0)
  guard z is Ok(non_zero_flag) else {
    return Err("packet header bitstream truncated")
  }
  if non_zero_flag == 0 {
    let code_blocks : Array[PacketHeaderCodeBlockMetadata] = []
    for cb in 0..<code_block_count {
      code_blocks.push({
        code_block_index: cb,
        included: false,
        first_inclusion: false,
        zero_bit_planes: None,
        coding_passes: None,
        lblock_increment: None,
        segment_lengths: [],
        segment_passes: [],
      })
    }
    return Ok({ zero_length: true, code_blocks, consumed_bits: 1, })
  }
  let levels_v = build_tag_tree_levels(width, height)
  guard levels_v is Ok(levels) else { return Err("invalid tag-tree size") }
  let total_nodes = levels[levels.length() - 1].offset + 1
  let (incl_low, incl_known) = init_tag_tree_node_arrays(total_nodes)
  let (zbp_low, zbp_known) = init_tag_tree_node_arrays(total_nodes)
  let lblock_by_cb : Array[Int] = []
  for _ in 0..<code_block_count {
    lblock_by_cb.push(3)
  }
  let mut bit_pos = 1
  let code_blocks : Array[PacketHeaderCodeBlockMetadata] = []
  for y in 0..<height {
    for x in 0..<width {
      let cb = y * width + x
      let inc = decode_tag_tree_member_with_state(
        levels,
        incl_low,
        incl_known,
        x,
        y,
        layer_index + 1,
        data,
        bit_pos,
      )
      guard inc is Ok((inc_flag, inc_next_pos)) else {
        return Err("failed to decode tag-tree inclusion flags")
      }
      bit_pos = inc_next_pos
      if !inc_flag {
        code_blocks.push({
          code_block_index: cb,
          included: false,
          first_inclusion: false,
          zero_bit_planes: None,
          coding_passes: None,
          lblock_increment: None,
          segment_lengths: [],
          segment_passes: [],
        })
        continue
      }
      let zbp = decode_tag_tree_value_with_state(
        levels, zbp_low, zbp_known, x, y, data, bit_pos,
      )
      guard zbp is Ok((p, zbp_next_pos)) else {
        return Err("failed to decode zero bit-plane tag-tree")
      }
      bit_pos = zbp_next_pos
      let pass_v = decode_num_coding_passes(data, bit_pos)
      guard pass_v is Ok((coding_passes, next_pos)) else {
        return Err("failed to decode number of coding passes")
      }
      bit_pos = next_pos
      let added_passes_override = if cb < added_passes_per_code_block.length() {
        added_passes_per_code_block[cb]
      } else {
        []
      }
      let lengths_v = decode_lengths_for_codeblock(
        data,
        bit_pos,
        lblock_by_cb[cb],
        coding_passes,
        added_passes_override,
      )
      guard lengths_v
        is Ok((segment_lengths, next_len_pos, next_lblock, total_inc)) else {
        return Err("failed to decode code-block segment length")
      }
      bit_pos = next_len_pos
      lblock_by_cb[cb] = next_lblock
      code_blocks.push({
        code_block_index: cb,
        included: true,
        first_inclusion: true,
        zero_bit_planes: Some(p),
        coding_passes: Some(coding_passes),
        lblock_increment: Some(total_inc),
        segment_lengths,
        segment_passes: if added_passes_override.length() == 0 {
          [coding_passes]
        } else {
          added_passes_override
        },
      })
    }
  }
  Ok({ zero_length: false, code_blocks, consumed_bits: bit_pos, })
}

///|
// Spec basis (T.800-2015 B.10):
// - packet header syntax carries inclusion, coding-pass count, and
//   segment length signalling for code-block contributions.
pub fn parse_packet_headers_with_tag_tree_sequence(
  data : Bytes,
  width : Int,
  height : Int,
  packet_count : Int,
) -> Result[Array[PacketHeaderMetadata], String] {
  parse_packet_headers_with_tag_tree_sequence_and_pass_splits(
    data,
    width,
    height,
    packet_count,
    [],
  )
}

///|
// Spec basis (T.800-2015 B.10):
// - packet header syntax carries inclusion, coding-pass count, and
//   segment length signalling for code-block contributions.
pub fn parse_packet_headers_with_tag_tree_sequence_and_pass_splits(
  data : Bytes,
  width : Int,
  height : Int,
  packet_count : Int,
  added_passes_per_packet_per_code_block : Array[Array[Array[Int]]],
) -> Result[Array[PacketHeaderMetadata], String] {
  if packet_count <= 0 {
    return Err("packet_count must be positive")
  }
  let code_block_count = width * height
  if code_block_count <= 0 {
    return Err("invalid tag-tree size")
  }
  let levels_v = build_tag_tree_levels(width, height)
  guard levels_v is Ok(levels) else { return Err("invalid tag-tree size") }
  let total_nodes = levels[levels.length() - 1].offset + 1
  let (incl_low, incl_known) = init_tag_tree_node_arrays(total_nodes)
  let (zbp_low, zbp_known) = init_tag_tree_node_arrays(total_nodes)
  let included_before : Array[Bool] = []
  let lblock_by_cb : Array[Int] = []
  for _ in 0..<code_block_count {
    included_before.push(false)
    lblock_by_cb.push(3)
  }
  let headers : Array[PacketHeaderMetadata] = []
  let mut bit_pos = 0
  for layer in 0..<packet_count {
    let start = bit_pos
    let nz = read_bit(data, bit_pos)
    guard nz is Ok(non_zero_flag) else {
      return Err("packet header bitstream truncated")
    }
    bit_pos += 1
    let code_blocks : Array[PacketHeaderCodeBlockMetadata] = []
    if non_zero_flag == 0 {
      for cb in 0..<code_block_count {
        code_blocks.push({
          code_block_index: cb,
          included: false,
          first_inclusion: false,
          zero_bit_planes: None,
          coding_passes: None,
          lblock_increment: None,
          segment_lengths: [],
          segment_passes: [],
        })
      }
      headers.push({
        zero_length: true,
        code_blocks,
        consumed_bits: bit_pos - start,
      })
      bit_pos = (bit_pos + 7) / 8 * 8
      continue
    }
    for y in 0..<height {
      for x in 0..<width {
        let cb = y * width + x
        let mut is_included = false
        let mut first_inclusion = false
        let mut zero_bit_planes : Int? = None
        if !included_before[cb] {
          let inc = decode_tag_tree_member_with_state(
            levels,
            incl_low,
            incl_known,
            x,
            y,
            layer + 1,
            data,
            bit_pos,
          )
          guard inc is Ok((inc_flag, inc_next_pos)) else {
            return Err("failed to decode tag-tree inclusion flags")
          }
          bit_pos = inc_next_pos
          if inc_flag {
            is_included = true
            first_inclusion = true
            included_before[cb] = true
            let zbp = decode_tag_tree_value_with_state(
              levels, zbp_low, zbp_known, x, y, data, bit_pos,
            )
            guard zbp is Ok((p, zbp_next_pos)) else {
              return Err("failed to decode zero bit-plane tag-tree")
            }
            bit_pos = zbp_next_pos
            zero_bit_planes = Some(p)
          }
        } else {
          let inc = read_bit(data, bit_pos)
          guard inc is Ok(v) else {
            return Err("packet header bitstream truncated")
          }
          bit_pos += 1
          is_included = v == 1
        }
        if !is_included {
          code_blocks.push({
            code_block_index: cb,
            included: false,
            first_inclusion: false,
            zero_bit_planes: None,
            coding_passes: None,
            lblock_increment: None,
            segment_lengths: [],
            segment_passes: [],
          })
          continue
        }
        let pass_v = decode_num_coding_passes(data, bit_pos)
        guard pass_v is Ok((coding_passes, pass_next_pos)) else {
          return Err("failed to decode number of coding passes")
        }
        bit_pos = pass_next_pos
        let pass_override = if layer <
          added_passes_per_packet_per_code_block.length() &&
          cb < added_passes_per_packet_per_code_block[layer].length() {
          added_passes_per_packet_per_code_block[layer][cb]
        } else {
          []
        }
        let lengths_v = decode_lengths_for_codeblock(
          data,
          bit_pos,
          lblock_by_cb[cb],
          coding_passes,
          pass_override,
        )
        guard lengths_v
          is Ok((segment_lengths, len_next_pos, next_lblock, total_inc)) else {
          return Err("failed to decode code-block segment length")
        }
        bit_pos = len_next_pos
        lblock_by_cb[cb] = next_lblock
        code_blocks.push({
          code_block_index: cb,
          included: true,
          first_inclusion,
          zero_bit_planes,
          coding_passes: Some(coding_passes),
          lblock_increment: Some(total_inc),
          segment_lengths,
          segment_passes: if pass_override.length() == 0 {
            [coding_passes]
          } else {
            pass_override
          },
        })
      }
    }
    headers.push({
      zero_length: false,
      code_blocks,
      consumed_bits: bit_pos - start,
    })
    bit_pos = (bit_pos + 7) / 8 * 8
  }
  Ok(headers)
}

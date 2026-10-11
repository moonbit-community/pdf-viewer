///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn codeblock_segment_pass_splits_for_style(
  coding_passes : Int,
  code_block_style : Int,
) -> Array[Int] {
  // Spec basis (T.800-2015):
  // - A.6.1 Table A.19: "xxxx x1xx Termination on each coding pass".
  // - D.4: coder may terminate "at the end of every coding pass".
  // Implementation mapping:
  // - style bit 0x04 (TERMALL) => one signalled segment length per added pass.
  // JPEG 2000 style bit 0x04: TERMALL (termination after each coding pass).
  if coding_passes <= 0 {
    return []
  }
  if (code_block_style & 0x40) != 0 {
    let splits : Array[Int] = []
    let mut remaining = coding_passes
    let mut cleanup_segment = true
    while remaining > 0 {
      let take = if cleanup_segment {
        1
      } else if remaining >= 2 {
        2
      } else {
        remaining
      }
      splits.push(take)
      remaining -= take
      cleanup_segment = !cleanup_segment
    }
    return splits
  }
  if (code_block_style & 0x04) == 0 {
    return []
  }
  let splits : Array[Int] = []
  for _ in 0..<coding_passes {
    splits.push(1)
  }
  splits
}

///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn parse_packet_headers_series_with_code_blocks(
  data : Bytes,
  code_block_count : Int,
) -> Result[Array[PacketHeaderMetadata], String] {
  // Spec basis (T.800-2015 B.10):
  // - packet header carries "number of coding passes included" and
  //   "length of codeword segment".
  // Wrapper keeps historical default style=0 behavior.
  parse_packet_headers_series_with_code_blocks_and_style(
    data, code_block_count, 0,
  )
}

///|
// Spec basis (T.800-2015 Annex A/B):
// - marker payload validation and packet-header reconstruction follow
//   COD/COC and packet signalling rules.
fn parse_packet_headers_series_with_code_blocks_and_style(
  data : Bytes,
  code_block_count : Int,
  code_block_style : Int,
) -> Result[Array[PacketHeaderMetadata], String] {
  // Spec basis (T.800-2015):
  // - B.10.6: coding-pass count signalling in packet header.
  // - B.10.7.1/B.10.7.2: segment length signalling for single/multiple segments.
  // - A.6.1 Table A.19 + D.4: style controls pass termination pattern.
  if code_block_count <= 0 {
    return Err("code_block_count must be positive")
  }
  let headers : Array[PacketHeaderMetadata] = []
  let mut bit_pos = 0
  let included_before : Array[Bool] = []
  let lblock_by_cb : Array[Int] = []
  for _ in 0..<code_block_count {
    included_before.push(false)
    lblock_by_cb.push(3)
  }
  let total_bits = data.length() * 8
  while bit_pos < total_bits {
    let start = bit_pos
    let z = read_bit(data, bit_pos)
    guard z is Ok(non_zero_flag) else {
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
    for cb in 0..<code_block_count {
      let inclusion = read_bit(data, bit_pos)
      guard inclusion is Ok(included_bit) else {
        return Err("packet header bitstream truncated")
      }
      bit_pos += 1
      if included_bit == 0 {
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
      let mut first_inclusion = false
      let mut zero_bit_planes : Int? = None
      if !included_before[cb] {
        first_inclusion = true
        let mut p = 0
        while true {
          let bit = read_bit(data, bit_pos)
          guard bit is Ok(v) else {
            return Err("unterminated zero bit-plane code")
          }
          bit_pos += 1
          if v == 1 {
            break
          }
          p += 1
        }
        zero_bit_planes = Some(p)
        included_before[cb] = true
      }
      let pass_v = decode_num_coding_passes(data, bit_pos)
      guard pass_v is Ok((coding_passes, next_pos)) else {
        return Err("failed to decode number of coding passes")
      }
      bit_pos = next_pos
      let added_passes_override = codeblock_segment_pass_splits_for_style(
        coding_passes, code_block_style,
      )
      let lengths_v = decode_lengths_for_codeblock(
        data,
        bit_pos,
        lblock_by_cb[cb],
        coding_passes,
        added_passes_override,
      )
      guard lengths_v
        is Ok((segment_lengths, next_bit_pos, next_lblock, total_inc)) else {
        return Err("failed to decode code-block segment length")
      }
      bit_pos = next_bit_pos
      lblock_by_cb[cb] = next_lblock
      code_blocks.push({
        code_block_index: cb,
        included: true,
        first_inclusion,
        zero_bit_planes,
        coding_passes: Some(coding_passes),
        lblock_increment: Some(total_inc),
        segment_lengths,
        segment_passes: added_passes_override,
      })
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

///|
// Spec basis (T.800-2015 B.10):
// - packet header syntax carries inclusion, coding-pass count, and
//   segment length signalling for code-block contributions.
pub fn parse_packet_headers_single_codeblock(
  data : Bytes,
) -> Result[Array[PacketHeaderMetadata], String] {
  parse_packet_headers_series_with_code_blocks(data, 1)
}

///|
// Spec basis (T.800-2015 B.10):
// - packet header syntax carries inclusion, coding-pass count, and
//   segment length signalling for code-block contributions.
pub fn parse_packet_headers_with_code_blocks(
  data : Bytes,
  code_block_count : Int,
) -> Result[Array[PacketHeaderMetadata], String] {
  parse_packet_headers_series_with_code_blocks(data, code_block_count)
}

///|
// Spec basis (T.800-2015 B.10):
// - packet header syntax carries inclusion, coding-pass count, and
//   segment length signalling for code-block contributions.
pub fn parse_packet_headers_with_code_blocks_and_style(
  data : Bytes,
  code_block_count : Int,
  code_block_style : Int,
) -> Result[Array[PacketHeaderMetadata], String] {
  // Spec basis (T.800-2015):
  // - A.6.1 Table A.19 defines code-block style flags.
  // - B.10.7 says segment lengths depend on coding-pass segmentation.
  // This API exposes style-controlled packet-header decode to upper layers.
  parse_packet_headers_series_with_code_blocks_and_style(
    data, code_block_count, code_block_style,
  )
}

///|
// Spec basis (T.800-2015 B.10):
// - packet header syntax carries inclusion, coding-pass count, and
//   segment length signalling for code-block contributions.
pub fn parse_packet_header_first_packet_with_code_blocks_and_style(
  data : Bytes,
  code_block_count : Int,
  code_block_style : Int,
) -> Result[PacketHeaderMetadata, String] {
  // Spec basis (T.800-2015):
  // - B.10 defines one packet header decode order.
  // - first-packet extraction must stop after first header bits and not
  //   attempt to decode subsequent packet headers from packet body bytes.
  if code_block_count <= 0 {
    return Err("code_block_count must be positive")
  }
  let mut bit_pos = 0
  let start = bit_pos
  let z = read_bit(data, bit_pos)
  guard z is Ok(non_zero_flag) else {
    return Err("packet header bitstream truncated")
  }
  bit_pos += 1
  let code_blocks : Array[PacketHeaderCodeBlockMetadata] = []
  let lblock_by_cb : Array[Int] = []
  for _ in 0..<code_block_count {
    lblock_by_cb.push(3)
  }
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
    return Ok({
      zero_length: true,
      code_blocks,
      consumed_bits: bit_pos - start,
    })
  }
  for cb in 0..<code_block_count {
    let inclusion = read_bit(data, bit_pos)
    guard inclusion is Ok(included_bit) else {
      return Err("packet header bitstream truncated")
    }
    bit_pos += 1
    if included_bit == 0 {
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
    let mut p = 0
    while true {
      let bit = read_bit(data, bit_pos)
      guard bit is Ok(v) else { return Err("unterminated zero bit-plane code") }
      bit_pos += 1
      if v == 1 {
        break
      }
      p += 1
    }
    let pass_v = decode_num_coding_passes(data, bit_pos)
    guard pass_v is Ok((coding_passes, next_pos)) else {
      return Err("failed to decode number of coding passes")
    }
    bit_pos = next_pos
    let added_passes_override = codeblock_segment_pass_splits_for_style(
      coding_passes, code_block_style,
    )
    let lengths_v = decode_lengths_for_codeblock(
      data,
      bit_pos,
      lblock_by_cb[cb],
      coding_passes,
      added_passes_override,
    )
    guard lengths_v
      is Ok((segment_lengths, next_bit_pos, next_lblock, total_inc)) else {
      return Err("failed to decode code-block segment length")
    }
    bit_pos = next_bit_pos
    lblock_by_cb[cb] = next_lblock
    code_blocks.push({
      code_block_index: cb,
      included: true,
      first_inclusion: true,
      zero_bit_planes: Some(p),
      coding_passes: Some(coding_passes),
      lblock_increment: Some(total_inc),
      segment_lengths,
      segment_passes: added_passes_override,
    })
  }
  Ok({ zero_length: false, code_blocks, consumed_bits: bit_pos - start, })
}

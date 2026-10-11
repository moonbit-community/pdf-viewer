///|
// Spec grouping:
// - packet-part accumulation and staged-segment shape detection for HTJ2K.

///|
pub fn htj2k_accumulate_single_codeblock_packet_parts(
  parts_list : Array[@a8.SingleCodeblockPacketParts],
) -> Result[(Bytes, Int, Int, Array[Int], Array[Int]), String] {
  let codeword_bytes : Array[Byte] = []
  let segment_lengths : Array[Int] = []
  let segment_passes : Array[Int] = []
  let mut total_passes = 0
  let mut zero_bit_planes = -1
  let mut saw_included = false
  for parts in parts_list {
    if !parts.included {
      continue
    }
    guard parts.coding_passes is Some(passes) else { continue }
    saw_included = true
    total_passes += passes
    if zero_bit_planes < 0 && parts.zero_bit_planes is Some(zbp) {
      zero_bit_planes = zbp
    }
    for sl in parts.segment_lengths {
      segment_lengths.push(sl)
    }
    if parts.segment_passes.length() > 0 {
      for sp in parts.segment_passes {
        segment_passes.push(sp)
      }
    } else {
      segment_passes.push(passes)
    }
    for b in parts.codeword {
      codeword_bytes.push(b)
    }
  }
  if !saw_included || zero_bit_planes < 0 {
    return Err("missing HT first-inclusion metadata")
  }
  Ok(
    (
      Bytes::from_iter(codeword_bytes.iter()),
      total_passes,
      zero_bit_planes,
      segment_lengths,
      segment_passes,
    ),
  )
}

///|
pub fn accumulate_multi_codeblock_packet_parts(
  parts_list : Array[@a8.MultiCodeblockPacketParts],
) -> Result[@a8.MultiCodeblockPacketParts, String] {
  if parts_list.length() == 0 {
    return Err("missing multi-codeblock packet parts")
  }
  let code_block_count = parts_list[0].code_block_count
  let codeword_bytes_by_cb : Array[Array[Byte]] = []
  let segment_lengths_by_cb : Array[Array[Int]] = []
  let segment_passes_by_cb : Array[Array[Int]] = []
  let included_by_cb : Array[Bool] = []
  let non_zero_by_cb : Array[Bool] = []
  let zero_bit_planes_by_cb : Array[Int?] = []
  let coding_passes_by_cb : Array[Int] = []
  for _ in 0..<code_block_count {
    codeword_bytes_by_cb.push([])
    segment_lengths_by_cb.push([])
    segment_passes_by_cb.push([])
    included_by_cb.push(false)
    non_zero_by_cb.push(false)
    zero_bit_planes_by_cb.push(None)
    coding_passes_by_cb.push(0)
  }
  let mut saw_non_zero_packet = false
  for packet_parts in parts_list {
    if packet_parts.code_block_count != code_block_count ||
      packet_parts.parts.length() != code_block_count {
      return Err("inconsistent multi-codeblock packet part shape")
    }
    if packet_parts.non_zero_packet {
      saw_non_zero_packet = true
    }
    for cb_index in 0..<code_block_count {
      let parts = packet_parts.parts[cb_index]
      if parts.non_zero_packet {
        non_zero_by_cb[cb_index] = true
      }
      if !parts.included {
        continue
      }
      included_by_cb[cb_index] = true
      if zero_bit_planes_by_cb[cb_index] is None &&
        parts.zero_bit_planes is Some(zbp) {
        zero_bit_planes_by_cb[cb_index] = Some(zbp)
      }
      let packet_passes = if parts.coding_passes is Some(passes) {
        passes
      } else {
        @math.sum_ints(parts.segment_passes)
      }
      coding_passes_by_cb[cb_index] += packet_passes
      for sl in parts.segment_lengths {
        segment_lengths_by_cb[cb_index].push(sl)
      }
      if parts.segment_passes.length() > 0 {
        for sp in parts.segment_passes {
          segment_passes_by_cb[cb_index].push(sp)
        }
      } else if packet_passes > 0 {
        segment_passes_by_cb[cb_index].push(packet_passes)
      }
      for b in parts.codeword {
        codeword_bytes_by_cb[cb_index].push(b)
      }
    }
  }
  let accumulated_parts : Array[@a8.SingleCodeblockPacketParts] = []
  for cb_index in 0..<code_block_count {
    let included = included_by_cb[cb_index]
    if included && zero_bit_planes_by_cb[cb_index] is None {
      return Err("missing first-inclusion metadata for multi-codeblock part")
    }
    let segment_lengths = segment_lengths_by_cb[cb_index]
    let segment_passes = segment_passes_by_cb[cb_index]
    let total_passes = if coding_passes_by_cb[cb_index] > 0 {
      coding_passes_by_cb[cb_index]
    } else {
      @math.sum_ints(segment_passes)
    }
    let part : @a8.SingleCodeblockPacketParts = {
      segment_total: @math.sum_ints(segment_lengths),
      segment_lengths,
      segment_passes,
      non_zero_packet: non_zero_by_cb[cb_index],
      included,
      zero_bit_planes: zero_bit_planes_by_cb[cb_index],
      coding_passes: if included {
        Some(total_passes)
      } else {
        None
      },
      codeword: Bytes::from_iter(codeword_bytes_by_cb[cb_index].iter()),
    }
    accumulated_parts.push(part)
  }
  let result : @a8.MultiCodeblockPacketParts = {
    non_zero_packet: saw_non_zero_packet,
    code_block_count,
    parts: accumulated_parts,
  }
  Ok(result)
}

///|
pub fn htj2k_single_codeblock_uses_staged_segments(
  parts_list : Array[@a8.SingleCodeblockPacketParts],
) -> Bool {
  if parts_list.length() != 1 {
    return false
  }
  for parts in parts_list {
    if !parts.included {
      continue
    }
    if parts.coding_passes is Some(passes) && passes > 1 {
      return true
    }
    if parts.segment_lengths.length() > 1 {
      return true
    }
    for seg_passes in parts.segment_passes {
      if seg_passes > 1 {
        return true
      }
    }
  }
  false
}

///|
pub fn htj2k_multi_codeblock_uses_staged_segments(
  parts_list : Array[@a8.MultiCodeblockPacketParts],
) -> Bool {
  for packet_parts in parts_list {
    for parts in packet_parts.parts {
      if !parts.included {
        continue
      }
      if parts.coding_passes is Some(passes) && passes > 1 {
        return true
      }
      if parts.segment_lengths.length() > 1 {
        return true
      }
      for seg_passes in parts.segment_passes {
        if seg_passes > 1 {
          return true
        }
      }
    }
  }
  false
}

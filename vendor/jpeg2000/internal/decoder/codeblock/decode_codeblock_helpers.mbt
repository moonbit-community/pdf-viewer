///|
// Spec grouping:
// - Tier-1 and HTJ2K code-block helper routines used by decode paths.

///|
pub fn tier1_lossy_positioned_bitplane_count(
  passes : Int,
  quantization_style : Int,
  code_block_style : Int,
  cb_w : Int,
  cb_h : Int,
) -> Int {
  if passes <= 0 {
    return 0
  }
  if quantization_style == 1 {
    return (passes + 1) / 3 + 1
  }
  if quantization_style != 0 &&
    (
      (
        (code_block_style & 0x01) != 0 &&
        (code_block_style & 0x04) == 0 &&
        passes % 3 == 0
      ) ||
      (cb_w * cb_h == 1 && passes % 3 == 0 && passes <= 15) ||
      (cb_w * cb_h <= 4 && passes == 9)
    ) {
    return (passes + 1) / 3 + 1
  }
  (passes + 2) / 3
}

///|
pub fn tier1_merge_packet_contributions_into_final_segments(
  segment_lengths : Array[Int],
  per_segment_passes : Array[Int],
  code_block_style : Int,
) -> (Array[Int], Array[Int]) {
  let merged_lengths : Array[Int] = []
  let merged_passes : Array[Int] = []
  let mut current_maxpasses = 0
  let count = if segment_lengths.length() < per_segment_passes.length() {
    segment_lengths.length()
  } else {
    per_segment_passes.length()
  }
  for i in 0..<count {
    let seg_len = segment_lengths[i]
    let seg_passes = per_segment_passes[i]
    if seg_passes <= 0 {
      continue
    }
    let need_new_segment = merged_passes.length() == 0 ||
      merged_passes[merged_passes.length() - 1] >= current_maxpasses
    if need_new_segment {
      current_maxpasses = @a8.codeblock_segment_maxpasses(
        code_block_style,
        merged_passes.length() == 0,
        current_maxpasses,
      )
      merged_lengths.push(seg_len)
      merged_passes.push(seg_passes)
    } else {
      let last = merged_passes.length() - 1
      merged_lengths[last] += seg_len
      merged_passes[last] += seg_passes
    }
  }
  (merged_lengths, merged_passes)
}

///|
pub fn tier1_codeword_pass_segments(
  parts : @a8.SingleCodeblockPacketParts,
) -> Result[Array[Bytes], String] {
  // Spec basis (T.800-2015 B.10.7):
  // packet header signals code-block contribution lengths as one/multiple
  // codeword segments; decoder reconstructs segment byte ranges from signalled
  // lengths before Tier-1 pass processing.
  let mut offset = 0
  let segments : Array[Bytes] = []
  for n in parts.segment_lengths {
    if n < 0 {
      return Err("negative segment length is not allowed")
    }
    let next_offset = offset + n
    if next_offset > parts.codeword.length() {
      return Err("segment lengths exceed codeword payload")
    }
    let seg : Array[Byte] = []
    for i in offset..<next_offset {
      seg.push(parts.codeword[i])
    }
    segments.push(Bytes::from_iter(seg.iter()))
    offset = next_offset
  }
  if offset != parts.codeword.length() {
    return Err("segment lengths do not cover codeword payload")
  }
  Ok(segments)
}

///|
pub fn code_block_style_is_ht(code_block_style : Int) -> Bool {
  (code_block_style & 0x40) != 0
}

///|
pub fn htj2k_roi_descaled_fixedpoint(fixed_value : Int, roishift : Int) -> Int {
  if roishift <= 0 {
    return fixed_value
  }
  let mag = if fixed_value >= 0 { fixed_value } else { -fixed_value }
  let thresh = 2 << roishift
  if mag < thresh {
    return fixed_value
  }
  let descaled = mag >> roishift
  if fixed_value < 0 {
    -descaled
  } else {
    descaled
  }
}

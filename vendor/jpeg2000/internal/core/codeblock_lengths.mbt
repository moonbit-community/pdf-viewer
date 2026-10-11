///|
pub fn decode_codeblock_segment_lengths_from_bits(
  data : Bytes,
  lblock_initial : Int,
  added_passes : Array[Int],
) -> Result[(Array[Int], Int), String] {
  let internal = decode_codeblock_segment_lengths_from_bits_at(
    data, 0, lblock_initial, added_passes,
  )
  guard internal is Ok((lengths, bit_pos, _, _)) else {
    guard internal is Err(msg) else {
      return Err("failed to decode code-block segment lengths")
    }
    return Err(msg)
  }
  Ok((lengths, bit_pos))
}

///|
fn decode_codeblock_segment_lengths_from_bits_at(
  data : Bytes,
  start_bit_pos : Int,
  lblock_initial : Int,
  added_passes : Array[Int],
) -> Result[(Array[Int], Int, Int, Int), String] {
  if lblock_initial <= 0 {
    return Err("lblock_initial must be positive")
  }
  let lengths : Array[Int] = []
  let mut lblock = lblock_initial
  let mut bit_pos = start_bit_pos
  let mut total_lblock_increment = 0
  while true {
    let b = read_bit(data, bit_pos)
    guard b is Ok(bit) else { return Err("unterminated Lblock increment code") }
    bit_pos += 1
    if bit == 0 {
      break
    }
    lblock = lblock + 1
    total_lblock_increment += 1
  }
  for passes in added_passes {
    if passes <= 0 {
      return Err("added passes must be positive")
    }
    let width = lblock + @math.floor_log2(passes)
    let v = read_bits(data, bit_pos, width)
    guard v is Ok((length, next_pos)) else {
      return Err("failed to decode code-block segment length")
    }
    lengths.push(length)
    bit_pos = next_pos
  }
  Ok((lengths, bit_pos, lblock, total_lblock_increment))
}

///|
fn sum_positive_values(values : Array[Int]) -> Result[Int, String] {
  let mut sum = 0
  for v in values {
    if v <= 0 {
      return Err("added passes must be positive")
    }
    sum += v
  }
  Ok(sum)
}

///|
fn decode_lengths_for_codeblock(
  data : Bytes,
  bit_pos : Int,
  lblock_current : Int,
  coding_passes : Int,
  added_passes_override : Array[Int],
) -> Result[(Array[Int], Int, Int, Int), String] {
  let added_passes = if added_passes_override.length() == 0 {
    [coding_passes]
  } else {
    added_passes_override
  }
  let sum_v = sum_positive_values(added_passes)
  guard sum_v is Ok(total_added) else {
    return Err("invalid added passes override")
  }
  if total_added != coding_passes {
    return Err("added passes override does not match coding passes")
  }
  decode_codeblock_segment_lengths_from_bits_at(
    data, bit_pos, lblock_current, added_passes,
  )
}

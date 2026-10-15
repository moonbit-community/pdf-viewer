///|
/// Validate once before the JS typed-array bulk copy. Subtraction keeps invalid
/// offsets/counts from overflowing. TypedArray.set also preserves overlap.
#cfg(target="js")
fn pdf_copy_bytes(
  destination : FixedArray[Byte],
  destination_offset : Int,
  source : Bytes,
  source_offset : Int,
  length : Int,
) -> Unit {
  guard! destination_offset >= 0 &&
    source_offset >= 0 &&
    length >= 0 &&
    destination_offset <= destination.length() &&
    source_offset <= source.length() &&
    length <= destination.length() - destination_offset &&
    length <= source.length() - source_offset
  pdf_copy_bytes_unchecked(
    destination, destination_offset, source, source_offset, length,
  )
}

///|
#cfg(target="js")
extern "js" fn pdf_copy_bytes_unchecked(
  destination : FixedArray[Byte],
  destination_offset : Int,
  source : Bytes,
  source_offset : Int,
  length : Int,
) -> Unit =
  #| (destination, offset, source, start, length) => {
  #|   destination.set(source.subarray(start, start + length), offset);
  #| }

///|
#cfg(not(target="js"))
fn pdf_copy_bytes(
  destination : FixedArray[Byte],
  destination_offset : Int,
  source : Bytes,
  source_offset : Int,
  length : Int,
) -> Unit {
  destination.blit_from_bytes(destination_offset, source, source_offset, length)
}

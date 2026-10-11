///|
// Spec grouping:
// - decode_samples output contract model

///|
// Spec basis (decoder internal contract):
// - decode pipeline uses internal field names for staging and post-processing.
pub(all) struct DecodeSamplesInternalResult {
  samples : Bytes
  bits_per_sample : Int
  signed_samples : Bool
  num_points : Int
  width : Int
  height : Int
  components : Int
  layout : String
}

///|
// Spec basis (public decode contract):
// - public result keeps explicit image metadata with normalized field names.
pub(all) struct DecodeSamplesResult {
  width : Int
  height : Int
  num_components : Int
  bits_per_component : Int
  is_signed : Bool
  sample_layout : String
  samples : Bytes
}

///|
// Verification-only full component dump contract for internal tooling.
pub(all) struct DecodeSamplesComponentResult {
  component_index : Int
  width : Int
  height : Int
  bits_per_component : Int
  is_signed : Bool
  sample_layout : String
  samples : Bytes
}

///|
// Verification-only aggregate result for all decoded components.
pub(all) struct DecodeAllComponentsResult {
  num_components : Int
  sample_layout : String
  components : Array[DecodeSamplesComponentResult]
}

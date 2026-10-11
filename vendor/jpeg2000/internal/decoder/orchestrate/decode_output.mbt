///|
// Spec basis (T.800-2015 Annex A/B/D):
// - profile gates and packet/Tier-1 staging are derived from COD/QCD
//   signalling and B.10/D.3 decode structure.
fn clamp_sample_for_signedness(
  v : Int,
  signed_samples : Bool,
  precision_bits? : Int = 8,
) -> Int {
  if signed_samples {
    let half = 1 << (precision_bits - 1)
    if v < -half {
      return -half
    }
    if v >= half {
      return half - 1
    }
    return v
  }
  let max_val = (1 << precision_bits) - 1
  if v < 0 {
    return 0
  }
  if v > max_val {
    return max_val
  }
  v
}

///|
// Spec basis (public decode contract):
// - public field names are normalized over decoder internal output.
pub fn decode_samples_from_internal(
  result : DecodeSamplesInternalResult,
) -> DecodeSamplesResult {
  {
    width: result.width,
    height: result.height,
    num_components: result.components,
    bits_per_component: result.bits_per_sample,
    is_signed: result.signed_samples,
    sample_layout: result.layout,
    samples: result.samples,
  }
}

///|
// Spec basis (project decode contract):
// - decode API returns explicit width/height/components/layout metadata with samples.
fn make_decode_samples_result(
  samples : Bytes,
  bits_per_sample : Int,
  signed_samples : Bool,
  num_points : Int,
  width : Int,
  height : Int,
  components : Int,
  layout : String,
) -> DecodeSamplesInternalResult {
  {
    samples,
    bits_per_sample,
    signed_samples,
    num_points,
    width,
    height,
    components,
    layout,
  }
}

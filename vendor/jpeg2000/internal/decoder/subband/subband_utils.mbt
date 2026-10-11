///|
// Spec grouping:
// - Subband coordinate utilities for JPEG 2000 coefficient layout
// - T.800-2015 F.3: Subband positions in resolution level

///|
// Spec basis (T.800-2015 F.3):
// Compute subband origin within resolution level coefficient array.
// For resolution > 0:
//   HL (subband_index=0): origin at (ll_width, 0) - top right
//   LH (subband_index=1): origin at (0, ll_height) - bottom left
//   HH (subband_index=2): origin at (ll_width, ll_height) - bottom right
// ll_width, ll_height are the LL subband dimensions at this level.
pub fn subband_origin(
  subband_index : Int,
  ll_width : Int,
  ll_height : Int,
) -> (Int, Int) {
  if subband_index == 0 {
    (ll_width, 0) // HL: top right
  } else if subband_index == 1 {
    (0, ll_height) // LH: bottom left
  } else {
    (ll_width, ll_height) // HH: bottom right
  }
}

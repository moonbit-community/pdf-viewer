///|
/// A sampled line needs at most two vertices. Avoid constructing the generic
/// multidimensional evaluator's coordinate, stride, vertex and weight arrays
/// for every adaptive probe. Keep its arithmetic and unsigned sample decoding.
/// Malformed or nonfinite coordinates retain the generic evaluator's policy.
fn pdf_colour_sampled_line(
  function : @pdflite.PdfFunction,
  sampled : @pdflite.PdfSampledFunction,
  input : Double,
) -> Array[Double]? {
  guard function.range is Some(range) else { return None }
  let outputs = range.length() / 2
  guard sampled.size is [size] &&
    size > 0 &&
    sampled.encode is [e0, e1] &&
    sampled.decode.length() == outputs * 2 &&
    range.length() == outputs * 2 &&
    outputs > 0 &&
    outputs <= 2147483647 / size &&
    sampled.samples.length() >= outputs * size &&
    sampled.bits_per_sample >= 1 &&
    sampled.bits_per_sample <= 32 else {
    return None
  }
  let low = function.domain[0]
  let high = function.domain[1]
  if input.is_nan() ||
    input.is_inf() ||
    low.is_nan() ||
    low.is_inf() ||
    high.is_nan() ||
    high.is_inf() ||
    e0.is_nan() ||
    e0.is_inf() ||
    e1.is_nan() ||
    e1.is_inf() {
    return None
  }
  let clamped = input.max(low).min(high)
  let ratio = if high == low { 0.0 } else { (clamped - low) / (high - low) }
  let value = (e0 + ratio * (e1 - e0)).max(0.0).min((size - 1).to_double())
  if value.is_nan() || value.is_inf() {
    return None
  }
  let floor = @math.floor(value).to_int()
  let fraction = value - floor.to_double()
  let base = floor * outputs
  let max_sample = @math.pow(2.0, sampled.bits_per_sample.to_double()) - 1.0
  Some(
    [
      for i in 0..<outputs => {
        let mut weighted = 0.0
        let left_weight = if value == floor.to_double() {
          1.0
        } else {
          1.0 - fraction
        }
        if left_weight != 0.0 {
          weighted += left_weight *
            sampled.samples[base + i].reinterpret_as_uint().to_double()
        }
        if fraction != 0.0 {
          weighted += fraction *
            sampled.samples[base + outputs + i]
            .reinterpret_as_uint()
            .to_double()
        }
        let decoded = sampled.decode[i * 2] +
          weighted /
          max_sample *
          (sampled.decode[i * 2 + 1] - sampled.decode[i * 2])
        decoded.max(range[i * 2]).min(range[i * 2 + 1])
      }
    ],
  )
}

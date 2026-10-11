///|
/// Error-checked adaptive shading cells. A tree record has three doubles:
/// [firstChild, splitAxis, splitValue], or [-sampleOffset-1, 0, 0] for a leaf.
/// A leaf contains 2^dimensions RGB corners, with axis zero varying fastest.
/// Corner values approach cell boundaries from inside; a stitching jump never
/// interpolates across a leaf boundary. No executable function enters JSON.
priv struct PdfShadingSamplerBuilder {
  functions : Array[@pdflite.PdfFunction]
  transform : PdfColourTransform
  components : Int
  dimensions : Int
  tree : Array[Double]
  samples : Array[Double]
  boundaries : Array[Double]
  process : Bool
  process_samples : Array[Double]
  black_generation : @pdflite.PdfFunction?
  undercolour_removal : @pdflite.PdfFunction?
  source_ranges : Array[Double]
  source_samples : Array[Double]
}

///|
fn pdf_shading_sample_inputs(
  builder : PdfShadingSamplerBuilder,
  inputs : ArrayView[Double],
) -> Array[Double] raise @core.PdfError {
  let values : Array[Double] = if builder.functions.is_empty() {
    inputs.to_owned()
  } else {
    let output : Array[Double] = []
    for function in builder.functions {
      if function.domain.length() != inputs.length() * 2 {
        raise @core.PdfError::BadFunctionEvaluation(
          "shading function requires \{function.domain.length()/2} inputs but shading supplies \{inputs.length()}",
        )
      }
      output.append(pdf_colour_eval_function(function, inputs))
    }
    output
  }
  if values.length() != builder.components {
    raise @core.PdfError::BadFunctionEvaluation("shading function output arity")
  }
  let (r, g, b) = pdf_colour_rgb_of_transform(builder.transform, values)
  let output = [
    pdf_colour_clamp_unit(r) * 255.0,
    pdf_colour_clamp_unit(g) * 255.0,
    pdf_colour_clamp_unit(b) * 255.0,
  ]
  if builder.process {
    let process = pdf_shading_process_components(
      builder.transform,
      values,
      black_generation=builder.black_generation,
      undercolour_removal=builder.undercolour_removal,
    )
    if process.length() != 4 {
      raise @core.PdfError::BadFunctionEvaluation(
        "CMYK shading source transform unavailable",
      )
    }
    for value in process {
      output.push(pdf_colour_clamp_unit(value) * 255.0)
    }
  }
  if !builder.source_ranges.is_empty() {
    let source = pdf_shading_source_components(builder.transform, values)
    if source.length() * 2 != builder.source_ranges.length() {
      raise @core.PdfError::BadFunctionEvaluation(
        "original shading source component arity",
      )
    }
    for index, value in source {
      let lo = builder.source_ranges[index * 2]
      let hi = builder.source_ranges[index * 2 + 1]
      output.push(
        if lo == hi {
          0.0
        } else {
          pdf_colour_clamp_unit((value - lo) / (hi - lo)) * 255.0
        },
      )
    }
  }
  output
}

///|
/// Evaluate the entire tint chain before handing original components to the
/// target-profile CMM. An ICC display RGB conversion never enters this path.
fn pdf_shading_source_components(
  transform : PdfColourTransform,
  values : ArrayView[Double],
) -> Array[Double] raise @core.PdfError {
  match transform {
    Tint(base, Some(function)) =>
      pdf_shading_source_components(
        base,
        pdf_colour_eval_function(function, values),
      )
    Icc(_, _, ranges) => pdf_icc_clip(values, ranges)
    Samples(space) =>
      match space {
        @pdflite.PdfCalGray(_, _, _) | @pdflite.PdfCalRGB(_, _, _, _) =>
          match pdf_colour_calibrated_pcs(space, values) {
            Some(pcs) => pcs
            None =>
              raise @core.PdfError::BadFunctionEvaluation(
                "calibrated shading PCS transform unavailable",
              )
          }
        _ => values.to_owned()
      }
    _ =>
      raise @core.PdfError::BadFunctionEvaluation(
        "original shading source transform unavailable",
      )
  }
}

///|
fn pdf_shading_stitch_boundaries(
  function : @pdflite.PdfFunction,
  scale : Double,
  offset : Double,
  output : Array[Double],
  depth : Int,
) -> Unit {
  if depth > 32 || scale == 0.0 {
    return
  }
  if depth == 0 && function.domain.length() >= 2 {
    output.push(scale * function.domain[0] + offset)
    output.push(scale * function.domain[1] + offset)
  }
  match function.func {
    @pdflite.PdfFunctionStitching(stitch) => {
      for boundary in stitch.bounds {
        output.push(scale * boundary + offset)
      }
      for i, child in stitch.functions {
        if stitch.stitch_encode.length() < i * 2 + 2 ||
          function.domain.length() < 2 {
          continue
        }
        let a = if i == 0 {
          function.domain[0]
        } else {
          stitch.bounds.get(i - 1).unwrap_or(function.domain[0])
        }
        let b = stitch.bounds.get(i).unwrap_or(function.domain[1])
        let e0 = stitch.stitch_encode[i * 2]
        let e1 = stitch.stitch_encode[i * 2 + 1]
        if e0 != e1 {
          let child_scale = scale * (b - a) / (e1 - e0)
          let child_offset = offset + scale * a - child_scale * e0
          pdf_shading_stitch_boundaries(
            child,
            child_scale,
            child_offset,
            output,
            depth + 1,
          )
        }
      }
    }
    _ => ()
  }
}

///|
fn pdf_shading_tint_boundaries(
  transform : PdfColourTransform,
  output : Array[Double],
) -> Unit {
  match transform {
    Tint(_, Some(function)) =>
      pdf_shading_stitch_boundaries(function, 1.0, 0.0, output, 0)
    _ => ()
  }
}

///|
fn pdf_shading_adaptive_cell(
  builder : PdfShadingSamplerBuilder,
  bounds : Array[Double],
  node : Int,
  depth : Int,
) -> Unit raise @core.PdfError {
  let count = builder.dimensions
  let colors : Array[Array[Double]] = []
  let inputs = Array::make(count, 0.0)
  for corner in 0..<(1 << count) {
    for axis in 0..<count {
      let lo = bounds[2 * axis]
      let hi = bounds[2 * axis + 1]
      inputs[axis] = if ((corner >> axis) & 1) == 0 {
        pdf_shading_inside(lo, hi)
      } else {
        pdf_shading_inside(hi, lo)
      }
    }
    colors.push(pdf_shading_sample_inputs(builder, inputs))
  }
  let probes = [
    0.125, 0.25, 0.3819660112501051, 0.5, 0.6180339887498949, 0.75, 0.875,
  ]
  let mut max_error = 0.0
  let mut probes_total = 1
  for _ in 0..<count {
    probes_total *= probes.length()
  }
  for index in 0..<probes_total {
    let fractions = Array::make(count, 0.0)
    let mut rest = index
    for axis in 0..<count {
      let f = probes[rest % probes.length()]
      rest /= probes.length()
      fractions[axis] = f
      inputs[axis] = bounds[axis * 2] +
        f * (bounds[axis * 2 + 1] - bounds[axis * 2])
    }
    let exact = pdf_shading_sample_inputs(builder, inputs)
    let predicted = Array::make(
      (if builder.process { 7 } else { 3 }) + builder.source_ranges.length() / 2,
      0.0,
    )
    for corner in 0..<(1 << count) {
      let mut weight = 1.0
      for axis in 0..<count {
        weight *= if ((corner >> axis) & 1) == 0 {
          1.0 - fractions[axis]
        } else {
          fractions[axis]
        }
      }
      for channel in 0..<predicted.length() {
        predicted[channel] += weight * colors[corner][channel]
      }
    }
    for channel in 0..<predicted.length() {
      let error = (exact[channel] - predicted[channel]).abs()
      let source_start = if builder.process { 7 } else { 3 }
      // Source interpolation is checked to 0.25 of a UInt16 unit, before
      // packing. A target CMM can be nonlinear, so it executes after lookup.
      let factor = if channel >= source_start {
        (if count == 1 { 0.35 } else { 0.75 }) * 1028.0
      } else {
        1.0
      }
      max_error = max_error.max(error * factor)
    }
  }
  // Explicit type-3 boundaries are split before numerical error checks, even
  // if the probes happen to miss a very narrow stitching segment.
  let mut split_axis = if count == 1 { 0 } else { depth % count }
  if bounds[split_axis * 2] == bounds[split_axis * 2 + 1] && count == 2 {
    split_axis = 1 - split_axis
  }
  let mut split = (bounds[split_axis * 2] + bounds[split_axis * 2 + 1]) / 2.0
  let mut boundary_found = false
  if count == 1 {
    let lo = bounds[0]
    let hi = bounds[1]
    for boundary in builder.boundaries {
      if boundary > lo &&
        boundary < hi &&
        (
          !boundary_found ||
          (boundary - (lo + hi) / 2.0).abs() < (split - (lo + hi) / 2.0).abs()
        ) {
        split = boundary
        boundary_found = true
      }
    }
  }
  let tolerance = if count == 1 { 0.35 } else { 0.75 }
  if max_error <= tolerance && !boundary_found {
    if builder.samples.length() + colors.length() * 3 > 240000 {
      raise @core.PdfError::BadFunctionEvaluation(
        "unsupported shading sampling: checked error (0.35 byte for 1D, 0.75 byte for 2D) exceeds 80000 RGB-sample budget",
      )
    }
    builder.tree[node * 3] = -builder.samples.length().to_double() - 1.0
    for color in colors {
      builder.samples.append(color[0:3])
      if builder.process {
        builder.process_samples.append(color[3:7])
      }
      let source_start = if builder.process { 7 } else { 3 }
      builder.source_samples.append(color[source_start:])
    }
    return
  }
  if depth >= 24 ||
    split <= bounds[split_axis * 2] ||
    split >= bounds[split_axis * 2 + 1] ||
    builder.tree.length() >= 300000 {
    raise @core.PdfError::BadFunctionEvaluation(
      "unsupported shading sampling: discontinuity or frequency exceeds adaptive depth/budget at checked error (0.35 byte for 1D, 0.75 byte for 2D)",
    )
  }
  let child = builder.tree.length() / 3
  builder.tree[node * 3] = child.to_double()
  let mut encoded_axis = split_axis
  if count == 1 && boundary_found {
    let exact = pdf_shading_sample_inputs(builder, [split])
    let before = pdf_shading_sample_inputs(builder, [
      pdf_shading_inside(split, bounds[0]),
    ])
    let after = pdf_shading_sample_inputs(builder, [
      pdf_shading_inside(split, bounds[1]),
    ])
    let mut left_error = 0.0
    let mut right_error = 0.0
    for c in 0..<exact.length() {
      let factor = if c >= (if builder.process { 7 } else { 3 }) {
        tolerance * 1028.0
      } else {
        1.0
      }
      left_error = left_error.max((exact[c] - before[c]).abs() * factor)
      right_error = right_error.max((exact[c] - after[c]).abs() * factor)
    }
    if left_error.min(right_error) > tolerance {
      raise @core.PdfError::BadFunctionEvaluation(
        "unsupported shading sampling: isolated value at stitching boundary",
      )
    }
    if right_error > tolerance {
      encoded_axis = -split_axis - 1
    }
  }
  // A negative encoded axis selects the left branch at exact equality. This
  // preserves nested stitching functions whose Encode reverses their domain.
  builder.tree[node * 3 + 1] = encoded_axis.to_double()
  builder.tree[node * 3 + 2] = split
  builder.tree.append([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
  let left = bounds.copy()
  let right = bounds.copy()
  left[split_axis * 2 + 1] = split
  right[split_axis * 2] = split
  pdf_shading_adaptive_cell(builder, left, child, depth + 1)
  pdf_shading_adaptive_cell(builder, right, child + 1, depth + 1)
}

///|
fn pdf_shading_build_sampler_once(
  functions : Array[@pdflite.PdfFunction],
  domain : Array[Double],
  transform : PdfColourTransform,
  components : Int,
  black_generation? : @pdflite.PdfFunction? = None,
  undercolour_removal? : @pdflite.PdfFunction? = None,
  want_process? : Bool = true,
  source_ranges? : Array[Double] = [],
  source_samples? : Array[Double] = [],
) -> (Array[Int], Array[Double], Array[Double], Array[Double]) raise @core.PdfError {
  let count = domain.length() / 2
  if count < 1 || count > 4 || domain.length() != count * 2 {
    raise @core.PdfError::BadFunctionEvaluation(
      "unsupported shading sampling: \{count} source components; supports one to four source components",
    )
  }
  let builder : PdfShadingSamplerBuilder = {
    functions,
    transform,
    components,
    dimensions: count,
    tree: [0.0, 0.0, 0.0],
    samples: [],
    boundaries: [],
    process: want_process && pdf_shading_has_process_transform(transform),
    process_samples: [],
    black_generation,
    undercolour_removal,
    source_ranges,
    source_samples,
  }
  if count <= 2 {
    if count == 1 {
      for function in functions {
        pdf_shading_stitch_boundaries(function, 1.0, 0.0, builder.boundaries, 0)
      }
      if functions.is_empty() {
        pdf_shading_tint_boundaries(transform, builder.boundaries)
      }
    }
    let bounds : Array[Double] = []
    for axis in 0..<count {
      bounds.push(domain[axis * 2].min(domain[axis * 2 + 1]))
      bounds.push(domain[axis * 2].max(domain[axis * 2 + 1]))
    }
    pdf_shading_adaptive_cell(builder, bounds, 0, 0)
    (
      Array::make(count, 2),
      builder.samples,
      builder.tree,
      builder.process_samples,
    )
  } else {
    let (size, samples) = pdf_shading_sample_table(
      functions,
      domain,
      transform,
      components~,
    )
    if builder.process || !source_ranges.is_empty() {
      let inputs = Array::make(count, 0.0)
      for index in 0..<(samples.length() / 3) {
        let mut rest = index
        for axis in 0..<count {
          inputs[axis] = domain[axis * 2] +
            (rest % size[axis]).to_double() /
            (size[axis] - 1).to_double() *
            (domain[axis * 2 + 1] - domain[axis * 2])
          rest /= size[axis]
        }
        let output = pdf_shading_sample_inputs(builder, inputs)
        if builder.process {
          builder.process_samples.append(output[3:7])
        }
        let source_start = if builder.process { 7 } else { 3 }
        builder.source_samples.append(output[source_start:])
      }
    }
    pdf_shading_check_regular_sampler(builder, domain, size, samples)
    (size, samples, [], builder.process_samples)
  }
}

///|
/// Higher-dimensional colour lookups remain regular, but each cell is checked
/// at its centre and two off-centre probes. A failed bounded grid is public,
/// never an unchecked approximation silently returned as successful shading.
fn pdf_shading_check_regular_sampler(
  builder : PdfShadingSamplerBuilder,
  domain : Array[Double],
  size : Array[Int],
  samples : Array[Double],
) -> Unit raise @core.PdfError {
  let count = size.length()
  let mut cells = 1
  for edge in size {
    cells *= edge - 1
  }
  for cell in 0..<cells {
    let lows = Array::make(count, 0)
    let mut rest = cell
    for axis in 0..<count {
      lows[axis] = rest % (size[axis] - 1)
      rest /= size[axis] - 1
    }
    for f in [0.2113248654051871, 0.5, 0.7886751345948129] {
      let inputs = Array::make(count, 0.0)
      for axis in 0..<count {
        inputs[axis] = domain[axis * 2] +
          (lows[axis].to_double() + f) /
          (size[axis] - 1).to_double() *
          (domain[axis * 2 + 1] - domain[axis * 2])
      }
      let exact = pdf_shading_sample_inputs(builder, inputs)
      let predicted = Array::make(
        (if builder.process { 7 } else { 3 }) +
        builder.source_ranges.length() / 2,
        0.0,
      )
      for corner in 0..<(1 << count) {
        let mut offset = 0
        let mut stride = 3
        let mut weight = 1.0
        for axis in 0..<count {
          let high = (corner >> axis) & 1
          offset += (lows[axis] + high) * stride
          stride *= size[axis]
          weight *= if high == 0 { 1.0 - f } else { f }
        }
        for c in 0..<predicted.length() {
          predicted[c] += weight *
            (if c < 3 {
              samples[offset + c]
            } else if builder.process && c < 7 {
              builder.process_samples[offset / 3 * 4 + c - 3]
            } else {
              let source_start = if builder.process { 7 } else { 3 }
              builder.source_samples[offset /
              3 *
              (builder.source_ranges.length() / 2) +
              c -
              source_start]
            })
        }
      }
      for c in 0..<predicted.length() {
        if (exact[c] - predicted[c]).abs() >
          (if c >= (if builder.process { 7 } else { 3 }) {
            0.25 / 257.0
          } else {
            0.75
          }) {
          raise @core.PdfError::BadFunctionEvaluation(
            "unsupported shading sampling: higher-dimensional colour grid exceeds 0.75-byte checked error",
          )
        }
      }
    }
  }
}

///|
/// The adjacent representable interior number is required at narrow stitching
/// intervals: multiplying the width by an epsilon can round back to the jump.
fn pdf_shading_inside(value : Double, toward : Double) -> Double {
  if value == toward {
    return value
  }
  if value == 0.0 {
    let tiny = 1L.reinterpret_as_double()
    return if toward > 0.0 { tiny } else { -tiny }
  }
  let bits = value.reinterpret_as_int64()
  let result = (if (value > 0.0) == (toward > value) {
    bits + 1L
  } else {
    bits - 1L
  }).reinterpret_as_double()
  if toward > value {
    result.min(toward)
  } else {
    result.max(toward)
  }
}

///|
/// Only genuine process components are retained. In particular, an RGB result
/// is never inverted to invent CMYK inks. Whole tint alternates are evaluated
/// before returning their DeviceCMYK values. An active ICC profile requires a
/// source-to-CMYK CMM target transform, not its RGB transform or Alternate.
fn pdf_shading_has_process_transform(transform : PdfColourTransform) -> Bool {
  match transform {
    Samples(@pdflite.PdfDeviceCMYK)
    | Samples(@pdflite.PdfDeviceRGB)
    | Samples(@pdflite.PdfDeviceGray) => true
    Tint(base, Some(_)) | Icc(None, base, _) =>
      pdf_shading_has_process_transform(base)
    _ => false
  }
}

///|
fn pdf_shading_process_components(
  transform : PdfColourTransform,
  values : ArrayView[Double],
  black_generation? : @pdflite.PdfFunction? = None,
  undercolour_removal? : @pdflite.PdfFunction? = None,
) -> Array[Double] raise @core.PdfError {
  match transform {
    Samples(@pdflite.PdfDeviceCMYK) => values.to_owned()
    Samples(@pdflite.PdfDeviceRGB) =>
      pdf_colour_device_rgb_process(
        values, black_generation, undercolour_removal,
      )
    Samples(@pdflite.PdfDeviceGray) =>
      [0.0, 0.0, 0.0, 1.0 - pdf_colour_clamp_unit(values.get(0).unwrap_or(0.0))]
    Tint(base, Some(function)) =>
      pdf_shading_process_components(
        base,
        pdf_colour_eval_function(function, values),
        black_generation~,
        undercolour_removal~,
      )
    Icc(None, base, ranges) =>
      pdf_shading_process_components(
        base,
        pdf_icc_clip(values, ranges),
        black_generation~,
        undercolour_removal~,
      )
    _ => []
  }
}

///|
/// An unavailable CMYK approximation must not break the ordinary RGB route.
/// Retry RGB-only when adding process-plane checks exhausts the same budget.
/// The resource advertises absent process samples as a separate diagnostic.
fn pdf_shading_build_sampler(
  functions : Array[@pdflite.PdfFunction],
  domain : Array[Double],
  transform : PdfColourTransform,
  components : Int,
  black_generation? : @pdflite.PdfFunction? = None,
  undercolour_removal? : @pdflite.PdfFunction? = None,
  source_ranges? : Array[Double] = [],
  source_samples? : Array[Double] = [],
) -> (Array[Int], Array[Double], Array[Double], Array[Double]) raise @core.PdfError {
  if !source_ranges.is_empty() {
    let result = Some(
      pdf_shading_build_sampler_once(
        functions,
        domain,
        transform,
        components,
        black_generation~,
        undercolour_removal~,
        source_ranges~,
        source_samples~,
      ),
    ) catch {
      _ => None
    }
    if result is Some(result) {
      return result
    }
    source_samples.clear()
    // Explicit device BG/UCR may be harder to approximate than the original
    // source. Do not repeat costly source-budget failures for default policy.
    if pdf_shading_has_process_transform(transform) &&
      (black_generation is Some(_) || undercolour_removal is Some(_)) {
      let source_only = Some(
        pdf_shading_build_sampler_once(
          functions,
          domain,
          transform,
          components,
          black_generation~,
          undercolour_removal~,
          source_ranges~,
          source_samples~,
          want_process=false,
        ),
      ) catch {
        _ => None
      }
      if source_only is Some(result) {
        return result
      }
      source_samples.clear()
    }
  }
  pdf_shading_build_sampler_once(
    functions,
    domain,
    transform,
    components,
    black_generation~,
    undercolour_removal~,
  ) catch {
    error =>
      if pdf_shading_has_process_transform(transform) {
        pdf_shading_build_sampler_once(
          functions,
          domain,
          transform,
          components,
          black_generation~,
          undercolour_removal~,
          want_process=false,
        )
      } else {
        raise error
      }
  }
}

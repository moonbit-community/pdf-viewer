///|
/// Retained, straight source components for a subtractive overprint compositor.
/// `None` never contributes shape or alpha. Display RGB is not a substitute
/// for these components because conversion discards process/spot planes.
pub(all) struct PdfSourceColour {
  space : String
  components : Array[Double]
  colorants : Array[String]
  paints : Bool
  all : Bool
  process_cmyk : Array[Double]?
  alternate : PdfSourceColour?
  rendering_intent : String
  icc_profile_id : String?
  whitepoint_xyy : Array[Double]?
  component_ranges : Array[Double]?
  pcs_xyz : Array[Double]?
  calibration : PdfColourCalibration?
} derive(Debug, Eq, ToJson)

///|
fn pdf_colour_source(
  space : @pdflite.PdfColourSpace,
  values : @pdflite.PdfContentColourValues,
  document? : @pdflite.PdfDocument? = None,
  black_generation? : @syntax.PdfObject = @syntax.PdfNull,
  undercolour_removal? : @syntax.PdfObject = @syntax.PdfNull,
  rendering_intent? : String = "/RelativeColorimetric",
  resource_context? : PdfResourceBuildContext? = None,
) -> PdfSourceColour {
  let components = match values {
    @pdflite.PdfContentColourFloats(values)
    | @pdflite.PdfContentColourNamed(_, values) =>
      [
        for value in values => value
      ]
    _ => []
  }
  let (kind, names, cmyk) = match space {
    @pdflite.PdfDeviceCMYK =>
      ("DeviceCMYK", ["Cyan", "Magenta", "Yellow", "Black"], Some(components))
    @pdflite.PdfDeviceRGB =>
      (
        "DeviceRGB",
        ["Red", "Green", "Blue"],
        Some(
          pdf_colour_device_rgb_process(
            components[:],
            pdf_colour_device_function(document, black_generation),
            pdf_colour_device_function(document, undercolour_removal),
          ),
        ),
      )
    @pdflite.PdfDeviceGray => ("DeviceGray", ["Gray"], None)
    @pdflite.PdfSeparation(name, _, _) =>
      ("Separation", [pdf_colour_colorant_name(name)], None)
    @pdflite.PdfDeviceN(names, _, _, _) =>
      ("DeviceN", [ for name in names => pdf_colour_colorant_name(name) ], None)
    @pdflite.PdfPatternWithBaseColourSpace(base) =>
      return pdf_colour_source(
        base,
        values,
        document~,
        black_generation~,
        undercolour_removal~,
        rendering_intent~,
        resource_context~,
      )
    @pdflite.PdfICCBased(_, _, _, _, _) => ("ICCBased", [], None)
    @pdflite.PdfCalGray(_, _, _) => ("CalGray", [], None)
    @pdflite.PdfCalRGB(_, _, _, _) => ("CalRGB", [], None)
    @pdflite.PdfLab(_, _, _) => ("Lab", [], None)
    @pdflite.PdfIndexed(base, table) =>
      return pdf_colour_source(
        base,
        @pdflite.PdfContentColourFloats(
          pdf_colour_indexed_components(
            table,
            pdf_colour_component_ranges(base),
            components[:],
          ),
        ),
        document~,
        black_generation~,
        undercolour_removal~,
        rendering_intent~,
        resource_context~,
      )
    @pdflite.PdfPattern => ("Pattern", [], None)
  }
  let alternate = match space {
    @pdflite.PdfICCBased(n, base, range, _, _) => {
      let base = pdf_colour_icc_alternate(n, base)
      let alternate = pdf_colour_source(
        base,
        @pdflite.PdfContentColourFloats(
          pdf_icc_clip(components[:], pdf_icc_ranges(n, range)),
        ),
        document~,
        black_generation~,
        undercolour_removal~,
        rendering_intent~,
        resource_context~,
      )
      // ICC alternate inputs are the current original components, including
      // for image/shading samples supplied later by the host. Preserve the
      // parametric Cal mapping rather than a PCS value evaluated at zero.
      Some({
        ..alternate,
        calibration: pdf_colour_calibration(base, require_invertible=false),
      })
    }
    @pdflite.PdfSeparation(_, base, function)
    | @pdflite.PdfDeviceN(_, base, function, _) =>
      match document {
        Some(doc) => {
          let values = pdf_colour_eval_function(
            doc.parse_function(function),
            components[:],
          ) catch {
            _ => []
          }
          if values.is_empty() {
            None
          } else {
            Some(
              pdf_colour_source(
                base,
                @pdflite.PdfContentColourFloats(values),
                document~,
                black_generation~,
                undercolour_removal~,
                rendering_intent~,
                resource_context~,
              ),
            )
          }
        }
        None => None
      }
    _ => None
  }
  {
    pcs_xyz: pdf_colour_calibrated_pcs(space, components),
    // Scalar paints carry evaluated PCS; dynamic samplers attach calibration.
    calibration: None,
    space: kind,
    components,
    colorants: names,
    paints: names.is_empty() || names.any(name => name != "None"),
    all: names.any(name => name == "All"),
    process_cmyk: cmyk,
    alternate,
    rendering_intent,
    icc_profile_id: pdf_colour_space_profile_id(
      document, space, resource_context,
    ),
    component_ranges: match space {
      @pdflite.PdfICCBased(_, _, _, _, _) | @pdflite.PdfLab(_, _, _) => {
        let flat : Array[Double] = []
        for (lower, upper) in pdf_colour_component_ranges(space) {
          flat.push(lower)
          flat.push(upper)
        }
        Some(flat)
      }
      _ => None
    },
    whitepoint_xyy: match space {
      @pdflite.PdfLab(white, _, _) => {
        let sum = white.x + white.y + white.z
        if sum > 0.0 {
          Some([white.x / sum, white.y / sum, white.y])
        } else {
          None
        }
      }
      _ => None
    },
  }
}

///|
fn pdf_colour_colorant_name(name : @core.PdfName) -> String {
  let text = pdf_annotation_name_text(name)
  if text.has_prefix("/") {
    text[1:].to_owned()
  } else {
    text
  }
}

///|
fn pdf_colour_space_paints(space : @pdflite.PdfColourSpace) -> Bool {
  match space {
    @pdflite.PdfSeparation(name, _, _) =>
      pdf_colour_colorant_name(name) != "None"
    @pdflite.PdfDeviceN(names, _, _, _) =>
      names.any(name => pdf_colour_colorant_name(name) != "None")
    @pdflite.PdfPatternWithBaseColourSpace(base)
    | @pdflite.PdfIndexed(base, _) => pdf_colour_space_paints(base)
    _ => true
  }
}

///|
/// Use pdflite's parser and calculator, correcting its type-0 interpolation
/// and zero-width domains. Table layout and multilinear interpolation follow
/// PDF.js src/core/function.js at the pinned reference revision (Apache-2.0).
fn pdf_colour_eval_function(
  function : @pdflite.PdfFunction,
  inputs : ArrayView[Double],
) -> Array[Double] raise @core.PdfError {
  let count = inputs.length()
  if function.domain.length() != count * 2 {
    raise @core.PdfError::BadFunctionEvaluation("colour function input arity")
  }
  let clamped = [
    for i in 0..<count => {
      inputs[i].max(function.domain[i * 2]).min(function.domain[i * 2 + 1])
    }
  ]
  let result = match function.func {
    @pdflite.PdfFunctionSampled(sampled) => {
      guard function.range is Some(range) else {
        raise @core.PdfError::BadFunctionEvaluation("sampled function range")
      }
      let outputs = range.length() / 2
      if count > 32 ||
        sampled.size.length() != count ||
        sampled.encode.length() != count * 2 ||
        sampled.decode.length() != outputs * 2 ||
        outputs < 1 ||
        sampled.bits_per_sample < 1 ||
        sampled.bits_per_sample > 32 {
        raise @core.PdfError::BadFunctionEvaluation(
          "sampled colour function shape",
        )
      }
      let steps : Array[Int] = []
      let fractions : Array[Double] = []
      let mut stride = outputs
      let mut base = 0
      for i in 0..<count {
        let size = sampled.size[i]
        if size <= 0 || stride > 2147483647 / size {
          raise @core.PdfError::BadFunctionEvaluation(
            "sampled colour function size",
          )
        }
        let low = function.domain[i * 2]
        let high = function.domain[i * 2 + 1]
        let ratio = if high == low {
          0.0
        } else {
          (clamped[i] - low) / (high - low)
        }
        let value = (sampled.encode[i * 2] +
          ratio * (sampled.encode[i * 2 + 1] - sampled.encode[i * 2]))
          .max(0.0)
          .min((size - 1).to_double())
        let floor = @math.floor(value).to_int()
        base += floor * stride
        if value != floor.to_double() {
          steps.push(stride)
          fractions.push(value - floor.to_double())
        }
        stride *= size
      }
      if sampled.samples.length() < stride {
        raise @core.PdfError::BadFunctionEvaluation(
          "sampled colour function table",
        )
      }
      let vertices = [base]
      let weights = [1.0]
      if count <= 8 {
        for i in 0..<steps.length() {
          let length = vertices.length()
          for j in 0..<length {
            vertices.push(vertices[j] + steps[i])
            weights.push(weights[j] * fractions[i])
            weights[j] *= 1.0 - fractions[i]
          }
        }
      } else if !steps.is_empty() {
        // Match the pinned PDF.js bounded high-dimensional simplex policy.
        // This avoids 2^32 vertices for a valid 32-colourant DeviceN space.
        let order : Array[Int] = []
        for i in 0..<steps.length() {
          let mut position = order.length()
          order.push(i)
          while position > 0 && fractions[order[position - 1]] < fractions[i] {
            order[position] = order[position - 1]
            position -= 1
          }
          order[position] = i
        }
        weights[0] = 1.0 - fractions[order[0]]
        for i in 0..<order.length() {
          let axis = order[i]
          vertices.push(vertices[i] + steps[axis])
          weights.push(
            if i + 1 < order.length() {
              fractions[axis] - fractions[order[i + 1]]
            } else {
              fractions[axis]
            },
          )
        }
      }
      let output = Array::make(outputs, 0.0)
      for vertex in 0..<vertices.length() {
        if weights[vertex] != 0.0 {
          for i in 0..<outputs {
            output[i] += weights[vertex] *
              sampled.samples[vertices[vertex] + i]
              .reinterpret_as_uint()
              .to_double()
          }
        }
      }
      let max_sample = @math.pow(2.0, sampled.bits_per_sample.to_double()) - 1.0
      for i in 0..<outputs {
        output[i] = sampled.decode[i * 2] +
          output[i] /
          max_sample *
          (sampled.decode[i * 2 + 1] - sampled.decode[i * 2])
      }
      output
    }
    @pdflite.PdfFunctionStitching(stitching) => {
      if count != 1 ||
        stitching.functions.is_empty() ||
        stitching.stitch_encode.length() != stitching.functions.length() * 2 ||
        stitching.bounds.length() + 1 != stitching.functions.length() {
        raise @core.PdfError::BadFunctionEvaluation(
          "stitching colour function shape",
        )
      }
      let mut segment = 0
      while segment < stitching.bounds.length() &&
            clamped[0] >= stitching.bounds[segment] {
        segment += 1
      }
      let low = if segment == 0 {
        function.domain[0]
      } else {
        stitching.bounds[segment - 1]
      }
      let high = if segment == stitching.bounds.length() {
        function.domain[1]
      } else {
        stitching.bounds[segment]
      }
      let ratio = if high == low {
        0.0
      } else {
        (clamped[0] - low) / (high - low)
      }
      let value = stitching.stitch_encode[segment * 2] +
        ratio *
        (
          stitching.stitch_encode[segment * 2 + 1] -
          stitching.stitch_encode[segment * 2]
        )
      pdf_colour_eval_function(stitching.functions[segment], [value])
    }
    _ => function.eval(clamped[:])
  }
  match function.range {
    Some(range) => {
      if range.length() != result.length() * 2 {
        raise @core.PdfError::BadFunctionEvaluation(
          "colour function output arity",
        )
      }
      [
        for i in 0..<result.length() => {
          result[i].max(range[i * 2]).min(range[i * 2 + 1])
        }
      ]
    }
    None => result
  }
}

///|
/// Shared untagged CMYK preview for host colour-plane composition.
pub fn process_cmyk_to_rgb(
  cyan : Double,
  magenta : Double,
  yellow : Double,
  black : Double,
) -> Array[Double] {
  let (r, g, b) = pdf_colour_rgb_of_cmyk(cyan, magenta, yellow, black)
  [r, g, b]
}

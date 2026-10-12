///|
/// Metadata for a terminal source-component sample table of a shading. The sampler owns
/// function and whole-tint evaluation; this helper does not evaluate a tint at
/// a dummy sample or mistake source tint inputs for terminal components.
fn pdf_colour_shading_source(
  document : @pdflite.PdfDocument,
  space : @pdflite.PdfColourSpace,
  resource_context : PdfResourceBuildContext,
  rendering_intent? : String = "/RelativeColorimetric",
) -> PdfSourceColour? {
  let mut terminal = space
  for _ in 0..<64 {
    match terminal {
      @pdflite.PdfSeparation(_, alternate, _)
      | @pdflite.PdfDeviceN(_, alternate, _, _)
      | @pdflite.PdfPatternWithBaseColourSpace(alternate) =>
        terminal = alternate
      @pdflite.PdfICCBased(_, _, _, _, _)
      | @pdflite.PdfDeviceRGB
      | @pdflite.PdfDeviceGray
      | @pdflite.PdfDeviceCMYK
      | @pdflite.PdfLab(_, _, _) => {
        let ranges = pdf_colour_component_ranges(terminal)
        let n = ranges.length()
        let source = pdf_colour_source(
          terminal,
          @pdflite.PdfContentColourFloats(Array::make(n, 0.0)),
          document=Some(document),
          resource_context=Some(resource_context),
          rendering_intent~,
        )
        // A missing source profile retains its legal same-component
        // alternate. Actual target profiles still require a valid catalog ID.
        let flat : Array[Double] = []
        for (low, high) in ranges {
          flat.push(low)
          flat.push(high)
        }
        // Components are placeholders, so a precomputed process vector would
        // become stale as the host supplies each interpolated source sample.
        return Some({
          ..source,
          process_cmyk: None,
          component_ranges: Some(flat),
        })
      }
      @pdflite.PdfCalGray(_, _, _) | @pdflite.PdfCalRGB(_, _, _, _) => {
        guard pdf_colour_calibrated_pcs_ranges(terminal) is Some(ranges) else {
          return None
        }
        let source = pdf_colour_source(
          terminal,
          @pdflite.PdfContentColourFloats([]),
          rendering_intent~,
        )
        let flat : Array[Double] = []
        for (low, high) in ranges {
          flat.push(low)
          flat.push(high)
        }
        return Some({
          ..source,
          space: "PCSXYZ",
          components: [0.0, 0.0, 0.0],
          pcs_xyz: None,
          calibration: None,
          component_ranges: Some(flat),
        })
      }
      _ => return None
    }
  }
  None
}

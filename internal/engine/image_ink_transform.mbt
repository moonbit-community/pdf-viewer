///|
/// Resolve lookup/tint spaces to the components actually passed to their
/// terminal colour space. Source inks must not retain a constant zero-tint
/// alternate or reconstruct these components from display RGB.
fn pdf_image_ink_terminal_space(
  space : @pdflite.PdfColourSpace,
) -> @pdflite.PdfColourSpace {
  match space {
    @pdflite.PdfSeparation(_, base, _)
    | @pdflite.PdfDeviceN(_, base, _, _)
    | @pdflite.PdfIndexed(base, _)
    | @pdflite.PdfPatternWithBaseColourSpace(base) =>
      pdf_image_ink_terminal_space(base)
    _ => space
  }
}

///|
/// Reuse the image's already-compiled tint functions and palette. ICC is a
/// terminal source profile, not an instruction to evaluate its alternate.
fn pdf_image_ink_terminal_values(
  transform : PdfColourTransform,
  values : Array[Double],
) -> Array[Double] {
  match transform {
    Samples(_) | Icc(_, _, _) => values
    Tint(base, Some(function)) => {
      let samples = pdf_colour_eval_function(function, values[:]) catch {
        _ => []
      }
      pdf_image_ink_terminal_values(base, samples)
    }
    Tint(_, None) => []
    Indexed(base, table, ranges) => {
      let index = (values.get(0).unwrap_or(0.0) + 0.5)
        .to_int()
        .max(0)
        .min(table.length() - 1)
      let sample = for (key, sample) in table {
        if key == index {
          break sample
        }
      } nobreak {
        []
      }
      let components : Array[Double] = []
      for i, sample in sample {
        let (lower, upper) = ranges.get(i).unwrap_or((0.0, 1.0))
        components.push(lower + sample.to_double() / 255.0 * (upper - lower))
      }
      pdf_image_ink_terminal_values(base, components)
    }
  }
}

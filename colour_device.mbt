///|
/// ISO 32000-1 10.3.4 device RGB-to-CMYK conversion. The reader's declared
/// default device policy uses identity BG/UCR; explicit PDF functions win.
/// This operates on original RGB components, never inverse display colours.
fn pdf_colour_device_rgb_process(
  values : ArrayView[Double],
  black_generation : @pdflite.PdfFunction?,
  undercolour_removal : @pdflite.PdfFunction?,
) -> Array[Double] {
  let c = 1.0 - pdf_colour_clamp_unit(values.get(0).unwrap_or(0.0))
  let m = 1.0 - pdf_colour_clamp_unit(values.get(1).unwrap_or(0.0))
  let y = 1.0 - pdf_colour_clamp_unit(values.get(2).unwrap_or(0.0))
  let k = c.min(m).min(y)
  fn evaluate(function : @pdflite.PdfFunction?, value : Double) -> Double {
    match function {
      Some(function) => {
        let output = pdf_colour_eval_function(function, [value]) catch {
          _ => []
        }
        match output.get(0) {
          Some(result) if !result.is_nan() && !result.is_inf() => result
          _ => value
        }
      }
      None => value
    }
  }
  let bg = evaluate(black_generation, k)
  let ucr = evaluate(undercolour_removal, k)
  [
    pdf_colour_clamp_unit(c - ucr),
    pdf_colour_clamp_unit(m - ucr),
    pdf_colour_clamp_unit(y - ucr),
    pdf_colour_clamp_unit(bg),
  ]
}

///|
fn pdf_colour_device_function(
  document : @pdflite.PdfDocument?,
  object : @syntax.PdfObject,
) -> @pdflite.PdfFunction? {
  match document {
    Some(document) => Some(document.parse_function(object)) catch { _ => None }
    None => None
  }
}

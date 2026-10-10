///|
fn pdf_font_finite_number(object : @syntax.PdfObject) -> Bool {
  match object {
    @syntax.PdfInteger(_) => true
    @syntax.PdfReal(value) => !value.is_nan() && !value.is_inf()
    _ => false
  }
}

///|
/// CID width ranges are expanded by the dependency. Retain valid clauses
/// verbatim, discard malformed clauses, and cap expansion before that read.
/// This changes a shadow dictionary only; PDF charcodes/CMaps stay intact.
fn pdf_font_cid_widths_shadow(
  object : @syntax.PdfObject,
  vertical : Bool,
) -> (@syntax.PdfObject, Bool) {
  guard object is @syntax.PdfArray(values) else {
    return (@syntax.PdfArray([]), true)
  }
  let kept : Array[@syntax.PdfObject] = []
  let stride = if vertical { 3 } else { 1 }
  let mut index = 0
  let mut expanded = 0
  let mut changed = false
  while index < values.length() {
    guard values.get(index) is Some(@syntax.PdfInteger(first)) else {
      index += 1
      changed = true
      continue
    }
    let (size, count, valid) = match values.get(index + 1) {
      Some(@syntax.PdfArray(widths)) =>
        (
          2,
          widths.length() / stride,
          widths.length() % stride == 0 && widths.all(pdf_font_finite_number),
        )
      Some(@syntax.PdfInteger(last)) =>
        (
          2 + stride,
          if first >= 0 && last >= first && last <= 65535 {
            last - first + 1
          } else {
            0
          },
          last >= first &&
          last <= 65535 &&
          index + 2 + stride <= values.length() &&
          [
            for offset in 0..<stride => {
              values
              .get(index + 2 + offset)
              .map(pdf_font_finite_number)
              .unwrap_or(false)
            }
          ].all(value => value),
        )
      _ => (1, 0, false)
    }
    if valid &&
      first >= 0 &&
      first <= 65535 &&
      count <= 65536 - first &&
      count <= 131072 - expanded {
      for offset in 0..<size {
        kept.push(values[index + offset])
      }
      expanded += count
    } else {
      changed = true
    }
    index += size
  }
  (@syntax.PdfArray(kept), changed)
}

///|
fn pdf_font_cid_metrics_shadow(
  dictionary : @syntax.PdfObject,
) -> (@syntax.PdfObject, Bool) raise @core.PdfError {
  guard dictionary.lookup_immediate(pdf_name_key("/DescendantFonts"))
    is Some(@syntax.PdfArray([descendant])) &&
    descendant is @syntax.PdfDictionary(_) else {
    return (dictionary, false)
  }
  let mut shadow = descendant
  let mut changed = false
  for key in ["/W", "/W2"] {
    if descendant.lookup_immediate(pdf_name_key(key)) is Some(value) {
      let (widths, recovered) = pdf_font_cid_widths_shadow(value, key == "/W2")
      if recovered {
        shadow = shadow.add_dict_entry(pdf_name_key(key), widths)
        changed = true
      }
    }
  }
  if descendant.lookup_immediate(pdf_name_key("/DW")) is Some(value) &&
    !pdf_font_finite_number(value) {
    shadow = shadow.add_dict_entry(
      pdf_name_key("/DW"),
      @syntax.PdfInteger(1000),
    )
    changed = true
  }
  if descendant.lookup_immediate(pdf_name_key("/DW2")) is Some(value) {
    let valid = value is @syntax.PdfArray(values) &&
      values.length() == 2 &&
      values.all(pdf_font_finite_number)
    if !valid {
      shadow = shadow.add_dict_entry(
        pdf_name_key("/DW2"),
        @syntax.PdfArray([@syntax.PdfInteger(880), @syntax.PdfInteger(-1000)]),
      )
      changed = true
    }
  }
  if changed {
    (
      dictionary.add_dict_entry(
        pdf_name_key("/DescendantFonts"),
        @syntax.PdfArray([shadow]),
      ),
      true,
    )
  } else {
    (dictionary, false)
  }
}

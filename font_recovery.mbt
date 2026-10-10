///|
/// Retain the strict reader's workflow, recovering metrics and a complete
/// checksum-mismatched ToUnicode through local dictionaries. The source
/// document and its font/descriptor/stream objects remain unchanged.
fn pdf_read_font_for_viewer(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> @pdflite.PdfFont raise @core.PdfError {
  pdf_font_unicode_for_viewer(pdf_read_font_recovery_result(document, object).0)
}

///|
fn pdf_read_font_with_viewer_metrics(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> @pdflite.PdfFont raise @core.PdfError {
  document.read_font(object) catch {
    @core.FontWidthsExpected
    | @core.FontWidthExpected
    | @core.FontFirstCharExpected
    | @core.FontLastCharExpected =>
      pdf_read_simple_font_with_recovered_metrics(document, object)
    @core.CIDFontDescriptorExpected => {
      let dictionary = document.direct(object)
      guard document.lookup_direct(pdf_name_key("/DescendantFonts"), dictionary)
        is Some(@syntax.PdfArray([descendant, .. rest])) else {
        raise @core.CIDFontDescriptorExpected
      }
      let descendant = document.direct(descendant)
      guard descendant is @syntax.PdfDictionary(_) else {
        raise @core.CIDFontDescriptorExpected
      }
      // Existing descriptors, including malformed embedded font programs,
      // follow the reader's normal diagnostics rather than this recovery.
      if document.lookup_direct(pdf_name_key("/FontDescriptor"), descendant)
        is Some(@syntax.PdfDictionary(_)) {
        raise @core.CIDFontDescriptorExpected
      }
      let name = document
        .lookup_direct(pdf_name_key("/BaseFont"), descendant)
        .unwrap_or(@syntax.PdfNameObject(pdf_name_key("/UnknownCIDFont")))
      let descriptor : @syntax.PdfObject = @syntax.PdfDictionary([
        (
          pdf_name_key("/Type"),
          @syntax.PdfNameObject(pdf_name_key("/FontDescriptor")),
        ),
        (pdf_name_key("/FontName"), name),
        (pdf_name_key("/Flags"), @syntax.PdfInteger(4)),
        (
          pdf_name_key("/FontBBox"),
          @syntax.PdfArray([
            @syntax.PdfInteger(0),
            @syntax.PdfInteger(-120),
            @syntax.PdfInteger(1000),
            @syntax.PdfInteger(880),
          ]),
        ),
        (pdf_name_key("/Ascent"), @syntax.PdfInteger(880)),
        (pdf_name_key("/Descent"), @syntax.PdfInteger(-120)),
        (pdf_name_key("/ItalicAngle"), @syntax.PdfInteger(0)),
        (pdf_name_key("/StemV"), @syntax.PdfInteger(80)),
      ])
      let recovered = dictionary.add_dict_entry(
        pdf_name_key("/DescendantFonts"),
        @syntax.PdfArray(
          [
            descendant.add_dict_entry(
              pdf_name_key("/FontDescriptor"),
              descriptor,
            ),
            ..rest,
          ],
        ),
      )
      document.read_font(recovered)
    }
    error => raise error
  }
}

///|
/// PDF.js accepts partial simple-font width tables. Build a complete shadow
/// table for the stricter reader, retaining valid widths, descriptor defaults
/// and known Standard 14 metrics. Source dictionaries are never changed.
fn pdf_read_simple_font_with_recovered_metrics(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> @pdflite.PdfFont raise @core.PdfError {
  let dictionary = document.direct(object)
  guard document.is_simple_font(dictionary) else {
    raise @core.FontWidthsExpected
  }
  let descriptor = document
    .lookup_direct(pdf_name_key("/FontDescriptor"), dictionary)
    .unwrap_or(dictionary)
  let missing_width = match
    document.lookup_direct(pdf_name_key("/MissingWidth"), descriptor) {
    Some(value) => document.get_number(value) catch { _ => 0.0 }
    None => 0.0
  }
  let missing_width = if missing_width.is_nan() || missing_width.is_inf() {
    0.0
  } else {
    missing_width
  }
  let original_widths = document.lookup_direct(
    pdf_name_key("/Widths"),
    dictionary,
  )
  let standard = if original_widths is Some(@syntax.PdfArray(_)) {
    None
  } else {
    match document.lookup_direct(pdf_name_key("/BaseFont"), dictionary) {
      Some(@syntax.PdfNameObject(name)) =>
        pdf_standard_font_of_base_name(pdf_annotation_name_text(name))
      _ => None
    }
  }
  let standard = match standard {
    Some(font) =>
      Some(
        @pdflite.PdfFontStandard({
          font,
          encoding: document.read_encoding(dictionary),
        }),
      )
    None => None
  }
  let first_char = match
    document.lookup_direct(pdf_name_key("/FirstChar"), dictionary) {
    Some(@syntax.PdfInteger(first)) if first >= 0 && first <= 255 => first
    _ => 0
  }
  let widths : Array[@syntax.PdfObject] = []
  for code in 0..<256 {
    let default = match standard {
      Some(font) => font.content_width_of_charcode(code).0
      None => missing_width
    }
    let width = match original_widths {
      Some(@syntax.PdfArray(values)) if code >= first_char =>
        match values.get(code - first_char) {
          Some(value) => document.get_number(value) catch { _ => default }
          None => default
        }
      _ => default
    }
    widths.push(
      @syntax.PdfReal(
        if width.is_nan() || width.is_inf() {
          default
        } else {
          width
        },
      ),
    )
  }
  let recovered = dictionary
    .add_dict_entry(pdf_name_key("/FirstChar"), @syntax.PdfInteger(0))
    .add_dict_entry(pdf_name_key("/LastChar"), @syntax.PdfInteger(255))
    .add_dict_entry(pdf_name_key("/Widths"), @syntax.PdfArray(widths))
  document.read_font(recovered)
}

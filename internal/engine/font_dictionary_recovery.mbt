///|
/// Normalize only font-reader fields in a local object. Stream references
/// keep their PDF object identity; alias cycles become null rather than
/// entering the reader's unbounded direct() loop. The PDF is never mutated.
fn pdf_font_safe_dictionary(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  depth : Int,
) -> @syntax.PdfObject raise @core.PdfError {
  guard depth < 16 else { raise @core.SoftError("Font dictionary depth limit") }
  guard pdf_direct_for_viewer(document, object) is Some(direct) else {
    raise @core.SoftError("Font reference cycle")
  }
  match direct {
    @syntax.PdfDictionary(entries) => {
      let normalized : Array[(@core.PdfName, @syntax.PdfObject)] = []
      for (name, value) in entries {
        let key = pdf_annotation_name_text(name)
        let value = if [
            "/Type", "/Subtype", "/BaseFont", "/Encoding", "/BaseEncoding", "/Differences",
            "/Widths", "/FirstChar", "/LastChar", "/FontDescriptor", "/DescendantFonts",
            "/FontBBox", "/FontMatrix", "/Flags", "/MissingWidth", "/Ascent", "/Descent",
            "/ItalicAngle", "/StemV", "/AvgWidth", "/MaxWidth", "/CapHeight", "/XHeight",
            "/DW", "/W", "/DW2", "/W2", "/CIDSystemInfo", "/Registry", "/Ordering",
            "/Supplement", "/Length", "/Filter", "/F", "/DecodeParms", "/DP", "/Predictor",
            "/Colors", "/Columns", "/BitsPerComponent", "/EarlyChange", "/CharSet",
          ].contains(key) {
          pdf_font_safe_dictionary(document, value, depth + 1)
        } else if [
            "/FontFile", "/FontFile2", "/FontFile3", "/ToUnicode", "/CIDToGIDMap",
          ].contains(key) &&
          pdf_direct_for_viewer(document, value) is None {
          @syntax.PdfNull
        } else {
          value
        }
        normalized.push((name, value))
      }
      @syntax.PdfDictionary(normalized)
    }
    @syntax.PdfArray(values) => {
      guard values.length() <= 131072 else {
        raise @core.SoftError("Font array limit")
      }
      @syntax.PdfArray(
        [
          for value in values => {
            pdf_font_safe_dictionary(document, value, depth + 1)
          }
        ],
      )
    }
    @syntax.PdfStreamObject(_) => object
    _ => direct
  }
}

///|
fn pdf_font_encoding_shadow(
  dictionary : @syntax.PdfObject,
) -> @syntax.PdfObject raise @core.PdfError {
  let original = dictionary.lookup_immediate(pdf_name_key("/Encoding"))
  let base = match original {
    Some(@syntax.PdfDictionary(_) as encoding) =>
      match encoding.lookup_immediate(pdf_name_key("/BaseEncoding")) {
        Some(@syntax.PdfNameObject(name)) =>
          @pdflite.pdf_encoding_of_name(name).unwrap_or(
            @pdflite.PdfStandardEncoding,
          )
        _ => @pdflite.PdfStandardEncoding
      }
    _ => @pdflite.PdfStandardEncoding
  }
  let differences : Array[@syntax.PdfObject] = []
  if original is Some(encoding) &&
    encoding.lookup_immediate(pdf_name_key("/Differences"))
    is Some(@syntax.PdfArray(values)) {
    let mut code : Int? = None
    for value in values {
      match value {
        @syntax.PdfInteger(next) =>
          code = if next >= 0 && next <= 255 { Some(next) } else { None }
        @syntax.PdfNameObject(_) =>
          if code is Some(next) && next <= 255 {
            differences.push(@syntax.PdfInteger(next))
            differences.push(value)
            code = Some(next + 1)
          }
        _ => ()
      }
    }
  }
  let base_name = match base {
    @pdflite.PdfWinAnsiEncoding => "/WinAnsiEncoding"
    @pdflite.PdfMacRomanEncoding => "/MacRomanEncoding"
    @pdflite.PdfMacExpertEncoding => "/MacExpertEncoding"
    _ => "/StandardEncoding"
  }
  dictionary.add_dict_entry(
    pdf_name_key("/Encoding"),
    @syntax.PdfDictionary([
      (
        pdf_name_key("/BaseEncoding"),
        @syntax.PdfNameObject(pdf_name_key(base_name)),
      ),
      (pdf_name_key("/Differences"), @syntax.PdfArray(differences)),
    ]),
  )
}

///|
fn pdf_font_descriptor_shadow(
  document : @pdflite.PdfDocument,
  dictionary : @syntax.PdfObject,
) -> @syntax.PdfObject raise @core.PdfError {
  let original = dictionary
    .lookup_immediate(pdf_name_key("/FontDescriptor"))
    .unwrap_or(@syntax.PdfDictionary([]))
  let mut descriptor = match original {
    @syntax.PdfDictionary(_) => original
    _ => @syntax.PdfDictionary([])
  }
  for
    key in [
      "/Flags", "/Ascent", "/Descent", "/ItalicAngle", "/StemV", "/AvgWidth", "/MaxWidth",
      "/CapHeight", "/XHeight", "/MissingWidth",
    ] {
    let value = original
      .lookup_immediate(pdf_name_key(key))
      .map(value => document.get_number(value) catch { _ => 0.0 })
      .unwrap_or(
        if key == "/MissingWidth" {
          600.0
        } else if key == "/Flags" {
          32.0
        } else {
          0.0
        },
      )
    descriptor = descriptor.add_dict_entry(
      pdf_name_key(key),
      @syntax.PdfReal(
        if value.is_inf() || value.is_nan() {
          0.0
        } else {
          value
        },
      ),
    )
  }
  let bbox = original.lookup_immediate(pdf_name_key("/FontBBox"))
  let valid = bbox
    .map(value => {
      try {
        ignore(document.parse_rectangle(value))
        true
      } catch {
        _ => false
      }
    })
    .unwrap_or(false)
  if !valid {
    descriptor = descriptor.add_dict_entry(
      pdf_name_key("/FontBBox"),
      @syntax.PdfArray([
        @syntax.PdfInteger(0),
        @syntax.PdfInteger(-200),
        @syntax.PdfInteger(1000),
        @syntax.PdfInteger(800),
      ]),
    )
  }
  dictionary.add_dict_entry(pdf_name_key("/FontDescriptor"), descriptor)
}

///|
fn pdf_missing_font_for_viewer() -> @pdflite.PdfFont {
  @pdflite.PdfFontStandard({
    font: @pdflite.PdfHelvetica,
    encoding: @pdflite.PdfWinAnsiEncoding,
  })
}

///|
fn pdf_read_font_recovery_result(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  resource_context? : PdfResourceBuildContext? = None,
) -> (@pdflite.PdfFont, Array[PdfTextDiagnosticKind]) raise @core.PdfError {
  let kinds : Array[PdfTextDiagnosticKind] = []
  let mut shadow = pdf_font_safe_dictionary(document, object, 0) catch {
    _ => return (pdf_missing_font_for_viewer(), [FontDictionaryRecovered])
  }
  let (metrics, recovered_metrics) = pdf_font_cid_metrics_shadow(shadow)
  shadow = metrics
  if recovered_metrics {
    kinds.push(FontMetricsRecovered)
  }
  let (prepared, encoding, limited, unicode) = pdf_font_cmap_reader_shadow(
    document,
    shadow,
    resource_context~,
  )
  shadow = prepared
  if limited {
    kinds.push(CMapReaderFallback)
  }
  let first = try document.read_font(shadow) catch {
    _ => None
  } noraise {
    font => Some(pdf_font_restore_reader_unicode(font, unicode))
  }
  if first is Some(font) {
    if font is @pdflite.PdfFontSimple({ fontmetrics: None, .. }) {
      let recovered = try
        pdf_read_simple_font_with_recovered_metrics(
          document,
          pdf_font_descriptor_shadow(document, shadow),
        )
      catch {
        _ => None
      } noraise {
        font => Some(pdf_font_restore_reader_unicode(font, unicode))
      }
      if recovered is Some(font) {
        if !kinds.contains(FontMetricsRecovered) {
          kinds.push(FontMetricsRecovered)
        }
        return (
          pdf_font_with_recovered_tounicode(document, shadow, font),
          kinds,
        )
      }
    }
    return (
      pdf_font_restore_lazy_cmap(
        pdf_font_with_recovered_tounicode(document, shadow, font),
        encoding,
      ),
      kinds,
    )
  }
  let recovered = try
    pdf_read_font_with_viewer_metrics(document, shadow)
  catch {
    _ => None
  } noraise {
    font => Some(pdf_font_restore_reader_unicode(font, unicode))
  }
  if recovered is Some(font) {
    if !kinds.contains(FontMetricsRecovered) {
      kinds.push(FontMetricsRecovered)
    }
    return (
      pdf_font_restore_lazy_cmap(
        pdf_font_with_recovered_tounicode(document, shadow, font),
        encoding,
      ),
      kinds,
    )
  }
  if document.is_simple_font(shadow) {
    shadow = pdf_font_encoding_shadow(shadow)
    kinds.push(FontEncodingRecovered)
    shadow = pdf_font_descriptor_shadow(document, shadow)
    let recovered = try
      pdf_read_simple_font_with_recovered_metrics(document, shadow)
    catch {
      _ => None
    } noraise {
      font => Some(pdf_font_restore_reader_unicode(font, unicode))
    }
    if recovered is Some(font) {
      if !kinds.contains(FontMetricsRecovered) {
        kinds.push(FontMetricsRecovered)
      }
      return (
        pdf_font_restore_lazy_cmap(
          pdf_font_with_recovered_tounicode(document, shadow, font),
          encoding,
        ),
        kinds,
      )
    }
  }
  kinds.push(FontDictionaryRecovered)
  (pdf_missing_font_for_viewer(), kinds)
}

///|
/// Observations about recovered text and the selected render path. A host
/// fallback can be intentional, and a literal U+FFFD is not proof that the
/// source mapping was damaged.
pub(all) enum PdfTextDiagnosticKind {
  ReplacementCharacter
  MissingFontResource
  HostFontFallback
  MissingEmbeddedOutline
  MissingClipOutline
  FontStreamChecksumRecovered
  FontStreamUnavailable
  FontMetricsRecovered
  FontEncodingRecovered
  FontDictionaryRecovered
  InvalidCharacterCode
  UnicodeMappingFallback
  CMapMalformedTokens(Int)
  CMapIncompleteSection(String)
  CMapCycle
  CMapSourceUnavailable
  CMapReaderFallback
} derive(Eq, Debug, ToJson)

///|
/// A diagnostic tied to a glyph and resource. CMap observations describe the
/// resource as a whole, not proof that this particular glyph was misdecoded.
/// object_number identifies the inspected font/CMap stream when available;
/// an inherited CMap fault may originate in one of its parents. Checksum
/// recovery means the DEFLATE body completed, not proof of original bytes.
pub(all) struct PdfTextDiagnostic {
  page : Int
  source : PdfTextSourceRange
  kind : PdfTextDiagnosticKind
  resource : String
  object_number : Int?
} derive(Eq, Debug, ToJson)

///|
/// Inspect the page's render fallback and decoded characters without reading
/// PDF objects. Browser font-loading success is outside this model's scope.
pub fn PdfPageModel::text_diagnostics(
  self : PdfPageModel,
) -> Array[PdfTextDiagnostic] {
  let output : Array[PdfTextDiagnostic] = []
  let items = self.text_content().items
  let sources = pdf_text_source_ranges(items[:])
  for index, item in items {
    let kinds : Array[PdfTextDiagnosticKind] = []
    if item.text.contains("\uFFFD") {
      kinds.push(ReplacementCharacter)
    }
    let visible = pdf_text_mode_fills(item.rendering_mode) ||
      pdf_text_mode_strokes(item.rendering_mode)
    if !item.text.trim().is_empty() && item.type3_outline is None {
      if item.rendering_mode >= 4 && item.rendering_mode <= 7 {
        kinds.push(MissingClipOutline)
      }
      if visible {
        match self.fonts.search_by(font => font.name == item.font) {
          None => kinds.push(MissingFontResource)
          Some(font_index) => {
            let font = self.fonts[font_index]
            if font.format == "cff" || font.format == "type1" {
              kinds.push(MissingEmbeddedOutline)
              kinds.push(HostFontFallback)
            } else if font.data_uri is None {
              kinds.push(HostFontFallback)
            }
          }
        }
      }
    }
    for kind in kinds {
      output.push({
        page: self.number,
        source: sources[index],
        kind,
        resource: item.font,
        object_number: None,
      })
    }
  }
  output
}

///|
fn pdf_text_cmap_diagnostic_kinds(
  recovery : PdfViewerCMapRecovery,
) -> Array[PdfTextDiagnosticKind] {
  let kinds : Array[PdfTextDiagnosticKind] = []
  let diagnostics = recovery.diagnostics
  if diagnostics.malformed_tokens > 0 {
    kinds.push(CMapMalformedTokens(diagnostics.malformed_tokens))
  }
  for section in diagnostics.incomplete_sections {
    kinds.push(CMapIncompleteSection(section))
  }
  if diagnostics.usecmap_cycle {
    kinds.push(CMapCycle)
  }
  if diagnostics.source_unavailable {
    kinds.push(CMapSourceUnavailable)
  }
  kinds
}

///|
fn pdf_text_font_stream_objects(
  document : @pdflite.PdfDocument,
  font_object : @syntax.PdfObject,
) -> Array[(String, @syntax.PdfObject)] {
  let output : Array[(String, @syntax.PdfObject)] = []
  let font_object = pdf_direct_for_viewer(document, font_object).unwrap_or(
    @syntax.PdfNull,
  )
  for key in ["/Encoding", "/ToUnicode"] {
    let seen : Map[Int, Bool] = Map([])
    let mut path = key
    let mut object = font_object.lookup_immediate(pdf_name_key(key))
    for _ in 0..<64 {
      guard object is Some(current) else { break }
      if current is @syntax.PdfIndirect(number) {
        guard !seen.contains(number) else { break }
        seen[number] = true
      }
      guard pdf_direct_for_viewer(document, current)
        is Some(@syntax.PdfStreamObject(stream)) else {
        break
      }
      output.push((path, current))
      path += "/UseCMap"
      object = stream.dictionary.lookup_immediate(pdf_name_key("/UseCMap"))
    }
  }
  let (descendant, prefix) = match
    font_object
    .lookup_immediate(pdf_name_key("/DescendantFonts"))
    .bind(value => pdf_direct_for_viewer(document, value)) {
    Some(@syntax.PdfArray([descendant, ..])) =>
      (
        pdf_direct_for_viewer(document, descendant).unwrap_or(@syntax.PdfNull),
        "/DescendantFonts[0]",
      )
    _ => (font_object, "")
  }
  match descendant.lookup_immediate(pdf_name_key("/CIDToGIDMap")) {
    Some(object) => output.push((prefix + "/CIDToGIDMap", object))
    None => ()
  }
  match
    descendant
    .lookup_immediate(pdf_name_key("/FontDescriptor"))
    .bind(value => pdf_direct_for_viewer(document, value)) {
    Some(descriptor) =>
      for key in ["/FontFile", "/FontFile2", "/FontFile3"] {
        match descriptor.lookup_immediate(pdf_name_key(key)) {
          Some(object) =>
            output.push((prefix + "/FontDescriptor" + key, object))
          None => ()
        }
      }
    None => ()
  }
  output
}

///|
/// Also expose viewer CMap recovery observations. This opt-in inspection
/// rebuilds the page and collects its text-resource scopes; it respects the
/// document's optional-content state and leaves source PDF objects unchanged.
/// Recovered checksums include font programs, CIDToGIDMap and up to 64 streams
/// in each CMap chain; object_number identifies the recovered stream itself.
/// Invalid page numbers return None.
pub fn PdfViewerDocument::text_diagnostics(
  self : PdfViewerDocument,
  page_number : Int,
) -> Array[PdfTextDiagnostic]? raise @core.PdfError {
  self
  .text_recovery_diagnostics(page_number)
  .map(items => {
    let output : Array[PdfTextDiagnostic] = []
    for item in items {
      if item.source is Some(source) {
        output.push({
          page: item.page,
          source,
          kind: item.kind,
          resource: item.resource,
          object_number: item.object_number,
        })
      }
    }
    output
  })
}

///|
/// Recovery observations also retain glyphs whose copy mapping is empty.
/// source is absent for such glyphs; item_index/charcode and string_source
/// still locate their PDF operand. Observations do not imply file corruption.
pub(all) struct PdfTextRecoveryDiagnostic {
  page : Int
  item_index : Int
  charcode : Int
  font : String
  source : PdfTextSourceRange?
  string_source : PdfTextStringSource?
  kind : PdfTextDiagnosticKind
  resource : String
  object_number : Int?
} derive(Eq, Debug, ToJson)

///|
/// Inspect the same active font bindings and decoded codes used by paint and
/// copy. This includes missing Tf requests, empty mappings, metrics/encoding
/// recovery, Unicode fallback and inherited CMap/checksum observations.
pub fn PdfViewerDocument::text_recovery_diagnostics(
  self : PdfViewerDocument,
  page_number : Int,
) -> Array[PdfTextRecoveryDiagnostic]? raise @core.PdfError {
  guard self.page(page_number) is Some(page) else { return None }
  let output : Array[PdfTextRecoveryDiagnostic] = []
  let sources : Map[Int, PdfTextSourceRange] = Map([])
  for source in page.text_sources() {
    sources[source.item_index] = source
  }
  let entries = pdf_collected_entries_of_page(
    self.document,
    self.pages[page_number - 1],
    optional_content_view=pdf_optional_content_view(
      self.document,
      self.optional_content_state,
    ),
    collect_text_sources=true,
    font_fallbacks=self.font_fallbacks[:],
  )
  for item in page.text_diagnostics() {
    output.push({
      page: item.page,
      item_index: item.source.item_index,
      charcode: item.source.charcode,
      font: item.source.font,
      source: Some(item.source),
      string_source: entries
      .get(item.source.item_index)
      .bind(entry => entry.text_source.map(value => value.string_source)),
      kind: item.kind,
      resource: item.resource,
      object_number: item.object_number,
    })
  }
  let cached : Map[Int, Array[PdfTextDiagnosticKind]] = Map([])
  let streams : Map[Int, Int] = Map([])
  let fonts : Map[Int, Array[PdfTextDiagnosticKind]] = Map([])
  for item_index, entry in entries {
    guard entry.entry.object is @pdflite.PdfContentGlyphObject(charcode, _, _) else {
      continue
    }
    let source = sources.get(item_index)
    let name = match page.items.get(item_index) {
      Some(Text(item)) => item.font
      _ => entry.state.text_state.font
    }
    let string_source = entry.text_source.map(value => value.string_source)
    fn emit(
      kind : PdfTextDiagnosticKind,
      path : String,
      number : Int?,
    ) -> Unit {
      output.push({
        page: page_number,
        item_index,
        charcode,
        font: name,
        source,
        string_source,
        kind,
        resource: name + path,
        object_number: number,
      })
    }
    if entry.font_resource_missing {
      emit(MissingFontResource, "", None)
    }
    if string_source is Some({ charcode_valid: false, .. }) {
      emit(
        InvalidCharacterCode,
        "/Encoding",
        entry.font_object.bind(pdf_text_object_number),
      )
    }
    guard entry.font_object is Some(object) else {
      if !entry.font_resource_missing {
        emit(MissingFontResource, "", None)
      }
      continue
    }
    let font_number = pdf_text_object_number(object)
    let kinds = match font_number {
      Some(number) if fonts.get(number) is Some(kinds) => kinds
      _ => {
        let kinds = pdf_read_font_recovery_result(self.document, object).1 catch {
            _ => [FontDictionaryRecovered]
          }
        if font_number is Some(number) {
          fonts[number] = kinds
        }
        kinds
      }
    }
    for kind in kinds {
      emit(kind, "", font_number)
    }
    guard pdf_direct_for_viewer(self.document, object) is Some(font_object) else {
      continue
    }
    for
      (path, object) in pdf_text_font_stream_objects(self.document, font_object) {
      guard pdf_direct_for_viewer(self.document, object)
        is Some(@syntax.PdfStreamObject(_)) else {
        continue
      }
      let number = pdf_text_object_number(object)
      let status = match number {
        Some(number) if streams.get(number) is Some(status) => status
        _ => {
          let status = try {
            if pdf_decode_font_stream_result(self.document, object).1 {
              1
            } else {
              0
            }
          } catch {
            _ => 2
          }
          if number is Some(number) {
            streams[number] = status
          }
          status
        }
      }
      if status == 1 {
        emit(FontStreamChecksumRecovered, path, number)
      }
      if status == 2 {
        emit(FontStreamUnavailable, path, number)
      }
    }
    let unicode_object = font_object.lookup_immediate(
      pdf_name_key("/ToUnicode"),
    )
    let unicode = pdf_viewer_tounicode_recovery_for_font(
      self.document,
      Some(font_object),
    )
    let fallback = if unicode_object is Some(_) {
      unicode
      .map(map => pdf_viewer_unicode_text_with_recovery(map, charcode) is None)
      .unwrap_or(true)
    } else {
      match entry.state.text_state.current_font {
        @pdflite.PdfFontCIDKeyed(_) => true
        @pdflite.PdfFontSimple(simple) =>
          pdf_viewer_ttf_encoding_glyph(simple, charcode)
          .map(glyph => glyph.codepoints.is_empty())
          .unwrap_or(true) catch {
            _ => true
          }
        _ => false
      }
    }
    if fallback {
      emit(
        UnicodeMappingFallback,
        "/ToUnicode",
        unicode_object.bind(pdf_text_object_number),
      )
    }
    for key in ["/Encoding", "/ToUnicode"] {
      guard font_object.lookup_immediate(pdf_name_key(key)) is Some(object) else {
        continue
      }
      let number = pdf_text_object_number(object)
      let direct = pdf_direct_for_viewer(self.document, object)
      if !(direct is Some(@syntax.PdfStreamObject(_))) {
        // An indirect simple-font Encoding dictionary is not an external CMap.
        let cid = font_object
          .lookup_immediate(pdf_name_key("/Subtype"))
          .bind(value => pdf_direct_for_viewer(self.document, value)) ==
          Some(@syntax.PdfNameObject(pdf_name_key("/Type0")))
        if key == "/Encoding" &&
          (!cid || direct is Some(@syntax.PdfNameObject(_))) {
          continue
        }
        if number is None {
          continue
        }
      }
      let kinds = match number {
        Some(number) if cached.get(number) is Some(kinds) => kinds
        _ => {
          let kinds = pdf_viewer_cmap_recovery_of_object(
              self.document,
              object,
              Map([]),
            )
            .map(pdf_text_cmap_diagnostic_kinds)
            .unwrap_or([])
          if number is Some(number) {
            cached[number] = kinds
          }
          kinds
        }
      }
      for kind in kinds {
        emit(kind, key, number)
      }
    }
  }
  Some(output)
}

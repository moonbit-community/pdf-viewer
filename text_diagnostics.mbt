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
  CMapMalformedTokens(Int)
  CMapIncompleteSection(String)
  CMapCycle
  CMapSourceUnavailable
} derive(Eq, Debug, ToJson)

///|
/// A diagnostic tied to a glyph and resource. CMap observations describe the
/// resource as a whole, not proof that this particular glyph was misdecoded.
/// object_number identifies the immediate CMap stream when available; an
/// inherited fault may originate in one of its parents.
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
/// Also expose viewer CMap recovery observations. This opt-in inspection
/// rebuilds the page and collects its text-resource scopes; it respects the
/// document's optional-content state and leaves source PDF objects unchanged.
/// Invalid page numbers return None.
pub fn PdfViewerDocument::text_diagnostics(
  self : PdfViewerDocument,
  page_number : Int,
) -> Array[PdfTextDiagnostic]? raise @core.PdfError {
  guard self.page(page_number) is Some(page) else { return None }
  let output = page.text_diagnostics()
  let sources : Map[Int, PdfTextSourceRange] = Map([])
  for source in page.text_sources() {
    sources[source.item_index] = source
  }
  let cached : Map[Int, Array[PdfTextDiagnosticKind]] = Map([])
  let entries = pdf_collected_entries_of_page(
    self.document,
    self.pages[page_number - 1],
    optional_content_view=pdf_optional_content_view(
      self.document,
      self.optional_content_state,
    ),
  )
  for item_index, entry in entries {
    guard sources.get(item_index) is Some(source) else { continue }
    let font_object = pdf_viewer_ttf_font_object(
      self.document,
      entry.resources,
      source.font,
    )
    guard font_object is Some(font_object) else { continue }
    for key in ["/Encoding", "/ToUnicode"] {
      let object = self.document.lookup_direct(pdf_name_key(key), font_object)
      // Named encodings are not streams and are handled by the reader or
      // builtin CMap assets. Only inspect an actual stream/reference here.
      guard object is Some(object) else { continue }
      let number = match font_object.lookup_immediate(pdf_name_key(key)) {
        Some(@syntax.PdfIndirect(number)) => Some(number)
        _ => None
      }
      if !(object is @syntax.PdfStreamObject(_)) && number is None {
        continue
      }
      let kinds = match number {
        Some(number) if cached.get(number) is Some(kinds) => kinds
        _ => {
          let object = number
            .map(number => @syntax.PdfIndirect(number))
            .unwrap_or(object)
          let kinds = match
            pdf_viewer_cmap_recovery_of_object(self.document, object, Map([])) {
            Some(recovery) => pdf_text_cmap_diagnostic_kinds(recovery)
            None => []
          }
          if number is Some(number) {
            cached[number] = kinds
          }
          kinds
        }
      }
      for kind in kinds {
        output.push({
          page: page_number,
          source,
          kind,
          resource: source.font + key,
          object_number: number,
        })
      }
    }
  }
  Some(output)
}

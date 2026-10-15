///|
/// A parsed PDF document with immutable editor snapshots.
pub struct PdfViewerDocument {
  source_length : Int
  priv source_bytes : Bytes
  priv source_stream_spans : Map[Int, PdfByteSpan]
  document : @pdflite.PdfDocument
  pages : Array[@page.PdfPage]
  optional_content_state : PdfOptionalContentState?
  font_fallbacks : Array[PdfFontFallback]
  priv canvas_resources : PdfCanvasResourceCache
  priv parsed_fonts : PdfParsedFontCache?
  priv accessibility_sources : Ref[(Int, Array[PdfTextStringSource?])?]
  priv reader_observations : Array[PdfReaderDiagnostic]
  priv editor_security : PdfEditorSecurity?
}

///|
/// Parse a PDF from bytes and resolve its page tree.
///
/// Unencrypted files follow the same path as
/// `open_document_with_passwords(bytes)` with no passwords. Encrypted files
/// raise `SoftError` when a nonempty password is required.
pub fn open_document(bytes : Bytes) -> PdfViewerDocument raise @core.PdfError {
  let document = match pdf_reader_strict_document_for_viewer(bytes) {
    Some(document) => document
    None => @pdflite.pdf_read_document_from_bytes(bytes)
  }
  if document.is_encrypted() {
    guard document.decrypt_with_user_password(b"") is Some(result) else {
      raise @core.SoftError("PDF password authentication failed")
    }
    let view = pdf_viewer_document_of_parsed_document(bytes, result.document)
    return {
      ..view,
      editor_security: Some({ password: b"", owner_authenticated: false, }),
    }
  }
  pdf_viewer_document_of_parsed_document(bytes, document)
}

///|
/// Parse a PDF using optional user and owner passwords, then resolve its page
/// tree. Password bytes are passed through unchanged; callers that accept a
/// text password should encode it as UTF-8 before calling this function.
///
/// A wrong or missing password raises `SoftError` with a stable message. This
/// keeps password authentication distinguishable from malformed PDF input
/// while preserving the pdflite error type used by the existing API.
pub fn open_document_with_passwords(
  bytes : Bytes,
  user_password? : Bytes? = None,
  owner_password? : Bytes? = None,
) -> PdfViewerDocument raise @core.PdfError {
  if user_password is None && owner_password is None {
    return open_document(bytes)
  }
  let parsed = pdf_reader_strict_document_for_viewer(bytes)
  fn decrypt(
    user : Bytes?,
    owner : Bytes?,
  ) -> @pdflite.PdfDecryptionResult? raise @core.PdfError {
    match parsed {
      Some(document) =>
        document.decrypt_with_passwords(
          user_password=user.map(password => password[:]),
          owner_password=owner.map(password => password[:]),
        )
      None =>
        @pdflite.pdf_read_document_from_bytes_with_passwords(
          bytes,
          user_password=user.map(password => password[:]),
          owner_password=owner.map(password => password[:]),
        )
    }
  }
  // Authenticate an owner credential separately: a valid user password must
  // never make an incorrect supplied owner password grant owner permissions.
  let owner_result = owner_password.bind(password => {
    decrypt(None, Some(password)) catch {
      _ => None
    }
  })
  let result = match owner_result {
    Some(result) => Some(result)
    None => decrypt(user_password, owner_password)
  }
  let document = match result {
    Some(result) => result.document
    None => raise @core.SoftError("PDF password authentication failed")
  }
  let view = pdf_viewer_document_of_parsed_document(bytes, document)
  if document.saved_encryption is Some(_) {
    let owner_authenticated = owner_result is Some(_)
    let password = if owner_authenticated {
      owner_password.unwrap()
    } else {
      user_password.unwrap_or(b"")
    }
    {
      ..view,
      editor_security: Some({
        password: password[:].to_owned(),
        owner_authenticated,
      }),
    }
  } else {
    view
  }
}

///|
fn pdf_viewer_document_of_parsed_document(
  bytes : Bytes,
  document : @pdflite.PdfDocument,
) -> PdfViewerDocument raise @core.PdfError {
  let source_stream_spans : Map[Int, PdfByteSpan] = Map([])
  let document = if !document.is_encrypted() &&
    pdf_reader_has_dropped_page_contents(document) {
    pdf_recover_compressed_document(
      bytes,
      document,
      source_spans=Some(source_stream_spans),
    ) catch {
      _ => document
    }
  } else {
    document
  }
  let (document, pages, reader_observations) = pdf_page_tree_for_viewer(
    document,
  ) catch {
    original_error => {
      let recovered = pdf_recover_compressed_document(
        bytes,
        document,
        source_spans=Some(source_stream_spans),
      ) catch {
        _ => raise original_error
      }
      pdf_page_tree_for_viewer(recovered) catch {
        _ => raise original_error
      }
    }
  }
  {
    source_length: bytes.length(),
    source_bytes: bytes,
    source_stream_spans,
    document,
    pages,
    optional_content_state: None,
    font_fallbacks: [],
    canvas_resources: pdf_canvas_resource_cache(),
    parsed_fonts: Some(pdf_parsed_font_cache()),
    accessibility_sources: Ref(None),
    reader_observations,
    editor_security: None,
  }
}

///|
/// Return a copy of the document view using host-provided font family
/// replacements. The original parsed document and page cache remain shared;
/// explicit replacements also suppress bundled Standard 14 paint/clip contours.
/// Embedded font programs retain precedence.
pub fn PdfViewerDocument::with_font_fallbacks(
  self : PdfViewerDocument,
  fallbacks : Array[PdfFontFallback],
) -> PdfViewerDocument {
  { ..self, font_fallbacks: fallbacks, accessibility_sources: Ref(None), }
}

///|
/// Return the font replacements currently attached to this document view.
pub fn PdfViewerDocument::font_fallbacks(
  self : PdfViewerDocument,
) -> Array[PdfFontFallback] {
  self.font_fallbacks
}

///|
/// Return a copy of the document view using a selected optional-content
/// configuration and explicit OCG object-number overrides.
pub fn PdfViewerDocument::with_optional_content_state(
  self : PdfViewerDocument,
  state : PdfOptionalContentState,
) -> PdfViewerDocument {
  {
    ..self,
    optional_content_state: Some(state),
    accessibility_sources: Ref(None),
  }
}

///|
/// Return the optional-content state selected for this viewer instance.
pub fn PdfViewerDocument::optional_content_state(
  self : PdfViewerDocument,
) -> PdfOptionalContentState? {
  self.optional_content_state
}

///|
/// Number of readable pages retained after page-tree recovery.
pub fn PdfViewerDocument::page_count(self : PdfViewerDocument) -> Int {
  self.pages.length()
}

///|
/// Number of source bytes. This is useful for host-side diagnostics and
/// makes it possible to report parse work without retaining the original
/// bytes in a browser model.
pub fn PdfViewerDocument::source_length(self : PdfViewerDocument) -> Int {
  self.source_length
}

///|
/// Build one normalized page model. Page numbers follow pdf.js and PDF tools:
/// they are one-based.
pub fn PdfViewerDocument::page(
  self : PdfViewerDocument,
  page_number : Int,
  optional_content_intent? : PdfOptionalContentIntent = Display,
) -> PdfPageModel? raise @core.PdfError {
  self.accessibility_sources.val = None
  if page_number < 1 || page_number > self.pages.length() {
    None
  } else {
    let sources : Ref[Array[PdfTextStringSource?]?] = Ref(None)
    let tagged = optional_content_intent == Display &&
      self.document.lookup_direct(
        pdf_name_key("/StructTreeRoot"),
        self.document.catalog(),
      )
      is Some(_)
    let model = pdf_page_model(
      self.document,
      self.pages[page_number - 1],
      page_number,
      self.optional_content_state,
      self.font_fallbacks,
      optional_content_intent~,
      parsed_fonts=self.parsed_fonts,
      text_sources=if tagged { Some(sources) } else { None },
    )
    if sources.val is Some(values) {
      self.accessibility_sources.val = Some((page_number, values))
    }
    Some(model)
  }
}

///|
/// Return all page models in source order.
pub fn PdfViewerDocument::pages(
  self : PdfViewerDocument,
  optional_content_intent? : PdfOptionalContentIntent = Display,
) -> Array[PdfPageModel] raise @core.PdfError {
  [
    for index, page in self.pages => {
      pdf_page_model(
        self.document,
        page,
        index + 1,
        self.optional_content_state,
        self.font_fallbacks,
        optional_content_intent~,
        parsed_fonts=self.parsed_fonts,
      )
    }
  ]
}

///|
/// Export the page model as JSON for a host that does not want to depend on
/// MoonBit data constructors.
pub fn PdfViewerDocument::page_json(
  self : PdfViewerDocument,
  page_number : Int,
) -> Json? raise @core.PdfError {
  match self.page(page_number) {
    Some(page) => Some(ToJson::to_json(page))
    None => None
  }
}

///|
/// Select text by a PDF-space rectangle. The returned text is ordered in
/// content order and the selected item indices retain the exact source
/// mapping for a richer Agent payload.
pub fn PdfViewerDocument::select(
  self : PdfViewerDocument,
  page_number : Int,
  rectangle : PdfBounds,
) -> PdfSelection? raise @core.PdfError {
  match self.page(page_number) {
    None => None
    Some(page) => Some(pdf_select_page(page, rectangle))
  }
}

///|
/// Render one page as a self-contained SVG document.
pub fn PdfViewerDocument::render_svg(
  self : PdfViewerDocument,
  page_number : Int,
  scale? : Double = 1.0,
) -> String? raise @core.PdfError {
  match self.page(page_number) {
    Some(page) => Some(pdf_render_page_svg(page, scale, page.rotation))
    None => None
  }
}

///|
/// Render one page with an explicit clockwise rotation, matching the optional
/// rotation argument accepted by pdf.js' `getViewport`.
pub fn PdfViewerDocument::render_svg_with_rotation(
  self : PdfViewerDocument,
  page_number : Int,
  rotation : Int,
  scale? : Double = 1.0,
) -> String? raise @core.PdfError {
  match self.page(page_number) {
    Some(page) => Some(pdf_render_page_svg(page, scale, rotation))
    None => None
  }
}

///|
/// A compact document summary for a CLI or browser status bar.
pub fn PdfViewerDocument::summary_json(
  self : PdfViewerDocument,
) -> Json raise @core.PdfError {
  Json::object({
    "pages": Json::number(self.page_count().to_double()),
    "source_bytes": Json::number(self.source_length().to_double()),
    "page_models": Json::array(
      [
        for page in self.pages() => ToJson::to_json(page)
      ],
    ),
  })
}

///|
/// Return the document outline in pdflite's bookmark JSON schema.
/// This is a reader adapter, not the pdf.js `getOutline()` schema.
pub fn PdfViewerDocument::outline_json(
  self : PdfViewerDocument,
) -> Json raise @core.PdfError {
  self.document.bookmarks_json()
}

///|
/// Return page-label definitions (`/PageLabels`) as JSON. A missing page-label
/// tree is represented by an empty array. Entries use pdflite's schema.
pub fn PdfViewerDocument::page_labels_json(
  self : PdfViewerDocument,
) -> Json raise @core.PdfError {
  Json::array(
    [
      for label in self.document.read_page_labels() => ToJson::to_json(label)
    ],
  )
}

///|
/// Return a display label for every page. Unlike pdf.js' nullable
/// `getPageLabels()`, documents without a `/PageLabels` tree return one-based
/// decimal labels.
pub fn PdfViewerDocument::page_labels(
  self : PdfViewerDocument,
) -> Array[String] raise @core.PdfError {
  let labels = self.document.read_page_labels()
  [
    for page_number in 1..<=self.pages.length() => {
      match @label.pdf_page_label_text_of_page_number(page_number, labels) {
        Some(value) =>
          try @utf8.decode(value[:]) catch {
            _ => page_number.to_string()
          } noraise {
            text => text
          }
        None => page_number.to_string()
      }
    }
  ]
}

///|
/// Return embedded file attachments, including their decoded bytes when
/// pdflite made them available.
pub fn PdfViewerDocument::attachments_json(
  self : PdfViewerDocument,
) -> Json raise @core.PdfError {
  Json::array(
    [
      for attachment in self.document.list_attached_files() => {
        ToJson::to_json(attachment)
      }
    ],
  )
}

///|
/// Return attachment metadata without embedding every attachment's bytes.
///
/// The index is stable for the lifetime of this document view and can be
/// passed to `attachment_bytes` by a host that wants to download one file.
pub fn PdfViewerDocument::attachment_manifest_json(
  self : PdfViewerDocument,
) -> Json raise @core.PdfError {
  let attachments = self.document.list_attached_files()
  Json::array(
    [
      for index, attachment in attachments => {
        {
          "index": index,
          "name": attachment.name,
          "page": attachment.pagenumber,
          "description": attachment.description,
          "relationship": attachment.relationship,
          "size": match attachment.data {
            Some(data) => data.length()
            None => 0
          },
          "available": attachment.data is Some(_),
        }
      }
    ],
  )
}

///|
/// Return one embedded attachment's decoded bytes, if it has a file stream.
pub fn PdfViewerDocument::attachment_bytes(
  self : PdfViewerDocument,
  index : Int,
) -> Bytes? raise @core.PdfError {
  if index < 0 {
    return None
  }
  match self.document.list_attached_files().get(index) {
    Some(attachment) => attachment.data
    None => None
  }
}

///|
/// Return optional-content configuration (layers) when the document defines
/// an `/OCProperties` dictionary.
pub fn PdfViewerDocument::optional_content_json(
  self : PdfViewerDocument,
) -> Json? raise @core.PdfError {
  match self.document.read_optional_content_groups() {
    Some(config) => Some(ToJson::to_json(config))
    None => None
  }
}

///|
/// Return the tagged-PDF structure tree when present.
pub fn PdfViewerDocument::struct_tree_json(
  self : PdfViewerDocument,
) -> Json raise @core.PdfError {
  self.document.extract_struct_tree()
}

///|
/// Return the classic Info dictionary in a host-friendly JSON form.
pub fn PdfViewerDocument::info_json(
  self : PdfViewerDocument,
) -> Json raise @core.PdfError {
  self.document.info_json()
}

///|
/// Return the document's XMP metadata packet, if one is embedded.
pub fn PdfViewerDocument::metadata_bytes(
  self : PdfViewerDocument,
) -> Bytes? raise @core.PdfError {
  self.document.metadata()
}

///|
/// Return text content for one page, including the positioned text items used
/// to build an Agent selection payload.
pub fn PdfViewerDocument::text_content(
  self : PdfViewerDocument,
  page_number : Int,
) -> PdfTextContent? raise @core.PdfError {
  match self.page(page_number) {
    Some(page) => Some(page.text_content())
    None => None
  }
}

///|
/// Return the page display list. Items are kept in source paint order, which
/// is the same order consumed by `render_svg`.
pub fn PdfViewerDocument::operator_list(
  self : PdfViewerDocument,
  page_number : Int,
) -> Array[PdfPageItem]? raise @core.PdfError {
  match self.page(page_number) {
    Some(page) => Some(page.operator_list())
    None => None
  }
}

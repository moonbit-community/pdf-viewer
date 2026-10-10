///|
/// A point in PDF user-space coordinates.
pub(all) struct PdfPoint {
  x : Double
  y : Double
} derive(Eq, Debug, ToJson)

///|
/// The original quadrilateral emitted by `pdflite` for a text glyph run.
///
/// Keeping the quad alongside its normalized bounds preserves rotated and
/// skewed text geometry for a renderer and for later cursor selection.
pub(all) struct PdfQuad {
  p0 : PdfPoint
  p1 : PdfPoint
  p2 : PdfPoint
  p3 : PdfPoint
} derive(Eq, Debug, ToJson)

///|
/// A normalized rectangle in PDF user-space coordinates.
///
/// The origin is at the lower-left corner, as required by the PDF
/// specification. Keeping this coordinate system in the model means that a
/// browser renderer and an Agent selection adapter can share the same data.
pub(all) struct PdfBounds {
  min_x : Double
  min_y : Double
  max_x : Double
  max_y : Double
} derive(Eq, Debug, ToJson)

///|
/// A text glyph or text fragment emitted by `pdflite`.
pub(all) struct PdfTextItem {
  index : Int
  text : String
  /// Four-byte CMap codes retain their unsigned bit pattern in this Int.
  charcode : Int
  advance_x : Double
  advance_y : Double
  vertical : Bool
  /// Affine transform from a one-em glyph coordinate system (baseline at
  /// y=0, y up) into PDF user space. None is allowed for host-built models.
  glyph_transform : Array[Double]?
  bounds : PdfBounds
  quad : PdfQuad
  font : String
  font_size : Double
  rendering_mode : Int
  fill_color : String
  stroke_color : String
  fill_alpha : Double
  blend_mode : String
  clip_path : String?
  soft_mask : PdfSoftMaskResource?
  group : PdfTransparencyGroup?
  group_path : Array[PdfTransparencyGroup]
  /// An SVG outline for a Type 3, CFF, Type 1 or embedded TrueType glyph when the browser
  /// cannot use the PDF font's original character mapping.
  type3_outline : String?
} derive(Eq, Debug, ToJson)

///|
/// An embedded font made available to the SVG renderer.
///
/// `data_uri` is optional because standard PDF fonts and documents that omit
/// an embedded program must use the host's fallback policy.
pub(all) struct PdfFontResource {
  name : String
  family : String
  base_name : String
  /// Canonical Standard 14 name when this is an unembedded or embedded
  /// standard face. The host can use this to report which substitute policy
  /// was selected without having to parse the PDF font dictionary again.
  standard_font : String?
  /// AFM-derived metrics used by pdflite for Standard 14 placement. The
  /// viewer keeps them in the page model so a host can reproduce glyph
  /// advances without shipping a font program.
  metrics : PdfFontMetrics?
  weight : String
  style : String
  mime_type : String
  format : String
  data_uri : String?
} derive(Eq, Debug, ToJson)

///|
/// The compact subset of Adobe Font Metrics needed by a host to reason about
/// a Standard 14 face. Widths are in the PDF's 1000-unit glyph space.
pub(all) struct PdfFontMetrics {
  units_per_em : Int
  ascent : Int
  descent : Int
  cap_height : Int
  widths : Array[(Int, Int)]
} derive(Eq, Debug, ToJson)

///|
/// A host-provided replacement for a PDF font that has no browser-loadable
/// embedded program. `pdf_name` may be the resource name (for example `/F1`)
/// or the PDF `/BaseFont` name (for example `Helvetica-Bold`). The viewer
/// never bundles the host font; the value is emitted as a CSS family name and
/// is resolved by the browser or native host.
pub(all) struct PdfFontFallback {
  pdf_name : String
  family : String
  weight : String?
  style : String?
} derive(Eq, Debug, ToJson)

///|
/// A browser-ready coloured tiling pattern.
///
/// `tile_svg` contains the pattern cell's paint operations in the pattern's
/// local coordinate system. The SVG renderer installs it in a reusable
/// `<pattern>` definition when a path uses this resource.
pub(all) struct PdfPatternResource {
  name : String
  bbox : PdfBounds
  x_step : Double
  y_step : Double
  matrix : Array[Double]
  tile_svg : String
  /// Ordered cell paints. Retained images are sampled at the final paint-site
  /// transform and output scale; an empty array uses `tile_svg` verbatim.
  tile_parts : Array[PdfPatternTilePart]
  /// A shading pattern is kept separately from a tiling pattern.  The SVG
  /// renderer can clip this mesh to the path that selected the pattern,
  /// instead of pretending that a shading is a repeated tile.
  shading : PdfShadingResource?
} derive(Eq, Debug, ToJson)

///|
/// A lowered vector fragment or an image in PDF pattern-cell coordinates.
pub(all) enum PdfPatternTilePart {
  Svg(String)
  Image(PdfImageResource, PdfQuad)
} derive(Eq, Debug, ToJson)

///|
/// A vector path from the page content stream.
///
/// `svg_path` is already normalized to the page's top-left SVG coordinate
/// system. It is kept as a string so hosts do not need to depend on pdflite's
/// internal shape representation merely to draw a page.
pub(all) struct PdfPathItem {
  index : Int
  bounds : PdfBounds
  svg_path : String
  filled : Bool
  stroked : Bool
  fill_color : String
  stroke_color : String
  fill_alpha : Double
  stroke_alpha : Double
  line_width : Double
  line_cap : Int
  line_join : Int
  dash_array : Array[Double]
  dash_phase : Double
  /// Non-stroking tiling paint; independent of the stroking colour space.
  pattern : PdfPatternResource?
  /// Stroking tiling paint. Shading patterns are retained for future pixel
  /// backends but are not lowered to SVG strokes yet.
  stroke_pattern : PdfPatternResource?
  shading_pattern : PdfShadingResource?
  blend_mode : String
  clip_path : String?
  soft_mask : PdfSoftMaskResource?
  group : PdfTransparencyGroup?
  group_path : Array[PdfTransparencyGroup]
} derive(Eq, Debug, ToJson)

///|
/// Browser-ready image data for an image XObject.
///
/// Encoded formats keep their original bytes in a data URL. Raw PDF pixel
/// data is converted to a small PNG by the viewer package, so browser hosts
/// do not need to know about PDF colour spaces or filters.
pub(all) struct PdfImageResource {
  name : String
  mime_type : String
  data_uri : String?
  mask_data_uri : String?
  alpha_mask_data_uri : String?
  width : Int?
  height : Int?
  /// PDF `/Interpolate` (or inline `/I`); false keeps magnified pixels sharp.
  interpolate : Bool
  /// Source dimensions of a separately encoded alpha mask. Raw masks are
  /// integrated into the image PNG instead, retaining the larger resolution.
  alpha_mask_width : Int?
  alpha_mask_height : Int?
} derive(Eq, Debug, ToJson)

///|
/// One sampled colour in a PDF function shading.
pub(all) struct PdfGradientStop {
  offset : Double
  color : String
} derive(Eq, Debug, ToJson)

///|
/// One triangle from a PDF Gouraud or patch mesh.
///
/// PDF mesh colors are retained per vertex. SVG does not have a portable
/// Gouraud primitive, so the SVG backend lowers each triangle to barycentric
/// microtriangles while hosts can use the same data for Canvas or WebGL
/// interpolation later.
pub(all) struct PdfMeshTriangle {
  p0 : PdfPoint
  p1 : PdfPoint
  p2 : PdfPoint
  c0 : String
  c1 : String
  c2 : String
} derive(Eq, Debug, ToJson)

///|
/// A browser-ready description of a PDF shading resource.
pub(all) struct PdfShadingResource {
  name : String
  kind : String
  coords : Array[Double]
  matrix : Array[Double]
  stops : Array[PdfGradientStop]
  mesh : Array[PdfMeshTriangle]
  extend_start : Bool
  extend_end : Bool
} derive(Eq, Debug, ToJson)

///|
/// An image or shading item in page paint order.
pub(all) struct PdfVisualItem {
  index : Int
  bounds : PdfBounds
  quad : PdfQuad
  name : String
  resource : PdfImageResource?
  shading : PdfShadingResource?
  fill_color : String
  fill_alpha : Double
  stroke_alpha : Double
  blend_mode : String
  clip_path : String?
  soft_mask : PdfSoftMaskResource?
  group : PdfTransparencyGroup?
  group_path : Array[PdfTransparencyGroup]
} derive(Eq, Debug, ToJson)

///|
/// A soft mask attached to a paint item by an ExtGState. The mask data is a
/// browser image in its own local coordinate system; `bounds` places it in
/// page user space before the item is painted.
pub(all) struct PdfSoftMaskResource {
  data_uri : String
  bounds : PdfBounds
  luminosity : Bool
  background : String
} derive(Eq, Debug, ToJson)

///|
/// A normal appearance stream attached to an annotation.
///
/// `svg` is rendered in the appearance stream's own coordinate system. The
/// renderer maps it into the annotation rectangle using `bbox` and `matrix`,
/// following pdf.js' appearance-stream transform rules. Keeping the fragment
/// in the page model also lets non-SVG hosts decide whether to use the raw
/// geometry or the browser-ready fallback.
pub(all) struct PdfAnnotationAppearance {
  bbox : PdfBounds
  matrix : Array[Double]
  svg : String
} derive(Eq, Debug, ToJson)

///|
/// Metadata for a Form XObject transparency group. Items remain in source
/// paint order, while the renderer can use this marker to keep the group's
/// source compositing boundary visible in SVG.
pub(all) struct PdfTransparencyGroup {
  id : String
  isolated : Bool
  knockout : Bool
} derive(Eq, Debug, ToJson)

///|
/// A page annotation exposed to the standalone renderer and host adapters.
///
/// The typed fields keep the annotation layer independent from pdflite's PDF
/// object dictionaries while preserving the rectangle, visual style, text,
/// and link target needed by a read-only viewer.
pub(all) struct PdfAnnotationItem {
  /// Original index in `/Annots`, including gaps for skipped Popup or invalid entries.
  index : Int
  subtype : String
  /// Annotation flags from `/F`, plus the derived display/print decisions.
  flags : Int
  visible : Bool
  print : Bool
  bounds : PdfBounds
  /// Normalized PDF annotation quads, in bottom-left, bottom-right,
  /// top-right, top-left order. Markup annotations may contain more than one.
  quad_points : Array[PdfQuad]
  /// Endpoints from `/L` for line annotations.
  line_points : Array[PdfPoint]
  /// Vertices from `/Vertices` for polygon and polyline annotations.
  vertices : Array[PdfPoint]
  /// Paths from `/InkList` for ink annotations.
  ink_paths : Array[Array[PdfPoint]]
  appearance : PdfAnnotationAppearance?
  /// AcroForm metadata inherited from a widget's field parents.
  field_name : String?
  field_type : String?
  field_value : String?
  field_flags : Int?
  field_options : Array[String]
  field_tooltip : String?
  /// The widget's own on-state name and resolved check/radio state. These
  /// differ from the inherited `/V`, which is shared by a radio group.
  button_value : String?
  button_checked : Bool?
  contents : String?
  subject : String?
  color : String?
  border_width : Double
  border_style : String
  border_dash : Array[Int]
  uri : String?
} derive(Eq, Debug, ToJson)

///|
/// One page item in paint order.
pub(all) enum PdfPageItem {
  Text(PdfTextItem)
  Path(PdfPathItem)
  Image(PdfVisualItem)
  Shading(PdfVisualItem)
} derive(Eq, Debug, ToJson)

///|
/// Page data consumed by the standalone renderer and by a host such as
/// OpenSeek in a later integration.
pub(all) struct PdfPageModel {
  number : Int
  origin_x : Double
  origin_y : Double
  width : Double
  height : Double
  /// PDF `/UserUnit`, expressed as default PDF units per page unit.
  user_unit : Double
  rotation : Int
  fonts : Array[PdfFontResource]
  items : Array[PdfPageItem]
  annotations : Array[PdfAnnotationItem]
  text : String
} derive(Eq, Debug, ToJson)

///|
/// A selection returned by the PDF viewer. `item_indices` points into the
/// page model and lets an Agent host choose between plain text and richer
/// geometry without reparsing the source document.
pub(all) struct PdfSelection {
  page : Int
  bounds : PdfBounds
  text : String
  item_indices : Array[Int]
} derive(Eq, Debug, ToJson)

///|
/// The viewport used to place a page in a host renderer.
///
/// This mirrors the small, stable part of pdf.js' `PageViewport`: page
/// dimensions are scaled in CSS/SVG pixels and the transform is ready to put
/// PDF user-space content into a top-left browser coordinate system.
pub(all) struct PdfViewport {
  width : Double
  height : Double
  scale : Double
  /// The page's `/UserUnit`, kept separate from the requested scale like
  /// pdf.js' `PageViewport`.
  user_unit : Double
  rotation : Int
  matrix : Array[Double]
  transform : String
} derive(Eq, Debug, ToJson)

///|
/// Convert a PDF user-space point to viewport coordinates, matching pdf.js'
/// `PageViewport.convertToViewportPoint`.
pub fn PdfViewport::convert_to_viewport_point(
  self : PdfViewport,
  point : PdfPoint,
) -> PdfPoint {
  {
    x: self.matrix[0] * point.x + self.matrix[2] * point.y + self.matrix[4],
    y: self.matrix[1] * point.x + self.matrix[3] * point.y + self.matrix[5],
  }
}

///|
/// Convert a viewport point back to PDF user-space coordinates, matching
/// pdf.js' `PageViewport.convertToPdfPoint`.
pub fn PdfViewport::convert_to_pdf_point(
  self : PdfViewport,
  point : PdfPoint,
) -> PdfPoint {
  let a = self.matrix[0]
  let b = self.matrix[1]
  let c = self.matrix[2]
  let d = self.matrix[3]
  let e = self.matrix[4]
  let f = self.matrix[5]
  let determinant = a * d - b * c
  {
    x: (d * (point.x - e) - c * (point.y - f)) / determinant,
    y: (-b * (point.x - e) + a * (point.y - f)) / determinant,
  }
}

///|
/// Text content exposed in the shape used by browser PDF viewers.
pub(all) struct PdfTextContent {
  items : Array[PdfTextItem]
  text : String
} derive(Eq, Debug, ToJson)

///|
/// A parsed, read-only PDF document.
pub struct PdfViewerDocument {
  source_length : Int
  document : @pdflite.PdfDocument
  pages : Array[@page.PdfPage]
  optional_content_state : PdfOptionalContentState?
  font_fallbacks : Array[PdfFontFallback]
}

///|
/// Parse a PDF from bytes and resolve its page tree.
///
/// Unencrypted files follow the same path as
/// `open_document_with_passwords(bytes)` with no passwords. Encrypted files
/// raise `SoftError` when no supplied password authenticates.
pub fn open_document(bytes : Bytes) -> PdfViewerDocument raise @core.PdfError {
  let document = @pdflite.pdf_read_document_from_bytes(bytes)
  if document.is_encrypted() {
    raise @core.SoftError("PDF password authentication failed")
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
  let result = @pdflite.pdf_read_document_from_bytes_with_passwords(
    bytes,
    user_password=user_password.map(password => password[:]),
    owner_password=owner_password.map(password => password[:]),
  )
  let document = match result {
    Some(result) => result.document
    None => raise @core.SoftError("PDF password authentication failed")
  }
  pdf_viewer_document_of_parsed_document(bytes, document)
}

///|
fn pdf_viewer_document_of_parsed_document(
  bytes : Bytes,
  document : @pdflite.PdfDocument,
) -> PdfViewerDocument raise @core.PdfError {
  let document = if !document.is_encrypted() &&
    pdf_reader_has_dropped_page_contents(document) {
    pdf_recover_compressed_document(bytes, document) catch {
      _ => document
    }
  } else {
    document
  }
  let (document, pages) = (document, document.pages_of_pagetree()) catch {
    @core.PageTreeExpected => {
      let recovered = pdf_recover_compressed_document(bytes, document) catch {
        _ => raise @core.PageTreeExpected
      }
      (recovered, recovered.pages_of_pagetree())
    }
    error => raise error
  }
  {
    source_length: bytes.length(),
    document,
    pages,
    optional_content_state: None,
    font_fallbacks: [],
  }
}

///|
/// Return a copy of the document view using host-provided font family
/// replacements. The original parsed document and page cache remain shared;
/// only the generated page font metadata changes.
pub fn PdfViewerDocument::with_font_fallbacks(
  self : PdfViewerDocument,
  fallbacks : Array[PdfFontFallback],
) -> PdfViewerDocument {
  { ..self, font_fallbacks: fallbacks, }
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
  { ..self, optional_content_state: Some(state), }
}

///|
/// Return the optional-content state selected for this viewer instance.
pub fn PdfViewerDocument::optional_content_state(
  self : PdfViewerDocument,
) -> PdfOptionalContentState? {
  self.optional_content_state
}

///|
/// Number of pages in the source document.
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
) -> PdfPageModel? raise @core.PdfError {
  if page_number < 1 || page_number > self.pages.length() {
    None
  } else {
    Some(
      pdf_page_model(
        self.document,
        self.pages[page_number - 1],
        page_number,
        self.optional_content_state,
        self.font_fallbacks,
      ),
    )
  }
}

///|
/// Return all page models in source order.
pub fn PdfViewerDocument::pages(
  self : PdfViewerDocument,
) -> Array[PdfPageModel] raise @core.PdfError {
  [
    for index, page in self.pages => {
      pdf_page_model(
        self.document,
        page,
        index + 1,
        self.optional_content_state,
        self.font_fallbacks,
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

///|
/// Compute a pdf.js-style viewport for a page.
pub fn PdfPageModel::viewport(
  self : PdfPageModel,
  scale? : Double = 1.0,
  rotation? : Int = 0,
) -> PdfViewport {
  let safe_scale = if scale <= 0.0 { 1.0 } else { scale }
  let user_unit = pdf_safe_user_unit(self.user_unit)
  let paint_scale = safe_scale * user_unit
  let normalized_rotation = pdf_normalize_rotation(rotation)
  let scaled_width = self.width * paint_scale
  let scaled_height = self.height * paint_scale
  let (rotate_a, rotate_b, rotate_c, rotate_d) = match normalized_rotation {
    90 => (0.0, 1.0, 1.0, 0.0)
    180 => (-1.0, 0.0, 0.0, 1.0)
    270 => (0.0, -1.0, -1.0, 0.0)
    _ => (1.0, 0.0, 0.0, -1.0)
  }
  let center_x = self.origin_x + self.width / 2.0
  let center_y = self.origin_y + self.height / 2.0
  let (width, height, offset_x, offset_y) = if rotate_a == 0.0 {
    (
      scaled_height,
      scaled_width,
      (center_y - self.origin_y).abs() * paint_scale,
      (center_x - self.origin_x).abs() * paint_scale,
    )
  } else {
    (
      scaled_width,
      scaled_height,
      (center_x - self.origin_x).abs() * paint_scale,
      (center_y - self.origin_y).abs() * paint_scale,
    )
  }
  let matrix = [
    rotate_a * paint_scale,
    rotate_b * paint_scale,
    rotate_c * paint_scale,
    rotate_d * paint_scale,
    offset_x -
    rotate_a * paint_scale * center_x -
    rotate_c * paint_scale * center_y,
    offset_y -
    rotate_b * paint_scale * center_x -
    rotate_d * paint_scale * center_y,
  ]
  // Keep this field identical to pdf.js' `PageViewport.transform`: it maps
  // PDF user-space coordinates directly into the top-left viewport. The SVG
  // serializer uses a separate relative transform because page items already
  // have their media-box origin removed.
  let transform = "matrix(" + pdf_svg_matrix_values(matrix) + ")"
  {
    width,
    height,
    scale: safe_scale,
    user_unit,
    rotation: normalized_rotation,
    matrix,
    transform,
  }
}

///|
fn pdf_svg_matrix_values(values : ArrayView[Double]) -> String {
  let output = StringBuilder()
  for index, value in values {
    if index > 0 {
      output.write_char(' ')
    }
    output.write_string(value.to_string())
  }
  output.to_string()
}

///|
fn pdf_svg_relative_viewport_transform(
  width : Double,
  height : Double,
  rotation : Int,
) -> String {
  match rotation {
    90 => "translate(" + height.to_string() + " 0) rotate(90)"
    180 =>
      "translate(" +
      width.to_string() +
      " " +
      height.to_string() +
      ") rotate(180)"
    270 => "translate(0 " + width.to_string() + ") rotate(-90)"
    _ => "translate(0 0)"
  }
}

///|
/// Return the page's positioned text items and their reading-order text.
pub fn PdfPageModel::text_content(self : PdfPageModel) -> PdfTextContent {
  let items = pdf_text_reading_order_of_page_items(self.items[:])
  { items, text: pdf_join_text_items(items[:]), }
}

///|
/// Return the page display list without reparsing the source document.
pub fn PdfPageModel::operator_list(self : PdfPageModel) -> Array[PdfPageItem] {
  self.items
}

///|
fn pdf_normalize_rotation(rotation : Int) -> Int {
  let mut value = rotation % 360
  if value < 0 {
    value += 360
  }
  match value {
    0 | 90 | 180 | 270 => value
    _ => 0
  }
}

///|
fn pdf_safe_user_unit(value : Double) -> Double {
  if value <= 0.0 || value.is_nan() || value.is_inf() {
    1.0
  } else {
    value
  }
}

///|
fn pdf_normalize_rotation_strict(rotation : Int) -> Int raise @core.PdfError {
  let mut value = rotation % 360
  if value < 0 {
    value += 360
  }
  match value {
    0 | 90 | 180 | 270 => value
    _ => raise @core.PageRotationExpected(rotation)
  }
}

///|
fn pdf_page_model(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
  page_number : Int,
  optional_content_state : PdfOptionalContentState?,
  font_fallbacks : ArrayView[PdfFontFallback],
) -> PdfPageModel raise @core.PdfError {
  let rectangle = pdf_page_view_box(document, page)
  let user_unit = pdf_page_user_unit(document, page)
  let page_fonts : PdfPageFontScope = {
    fonts: [],
    sources: [],
    fallbacks: [
      for fallback in font_fallbacks => fallback
    ],
  }
  let items = pdf_items_of_page(
    document,
    page,
    rectangle.min_x,
    rectangle.min_y,
    rectangle.max_x - rectangle.min_x,
    rectangle.max_y - rectangle.min_y,
    page_fonts~,
    optional_content_view=pdf_optional_content_view(
      document, optional_content_state,
    ),
  )
  let text = pdf_text_of_items(items)
  let fonts = page_fonts.fonts
  let next_index = Ref(0)
  for item in items {
    next_index.val = next_index.val.max(pdf_page_item_index(item) + 1)
  }
  let annotations = pdf_annotation_items_of_page(
    document, page, page_number, next_index,
  )
  {
    number: page_number,
    origin_x: rectangle.min_x,
    origin_y: rectangle.min_y,
    width: rectangle.max_x - rectangle.min_x,
    height: rectangle.max_y - rectangle.min_y,
    user_unit,
    rotation: @page.pdf_page_int_of_rotation(page.rotate),
    fonts,
    items,
    annotations,
    text,
  }
}

///|
/// PDF.js exposes the effective page view box as the CropBox/MediaBox
/// intersection. pdflite keeps inherited page dictionaries in `rest`, so
/// resolve those entries here while preserving non-zero page origins.
fn pdf_page_view_box(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
) -> @geometry.PdfRectangle {
  let media = match pdf_page_rectangle_or_none(document, page.mediabox) {
    Some(rectangle) => rectangle
    None => pdf_page_default_media_box()
  }
  let crop_name = @core.pdf_name_of_bytes(@utf8.encode("/CropBox"))
  match document.lookup_direct(crop_name, page.rest) {
    Some(cropbox) => {
      let crop = match pdf_page_rectangle_or_none(document, cropbox) {
        Some(rectangle) => rectangle
        None => media
      }
      match pdf_page_rectangle_intersection(media, crop) {
        Some(intersection) => intersection
        None => media
      }
    }
    None => media
  }
}

///|
fn pdf_page_rectangle_or_none(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> @geometry.PdfRectangle? {
  try document.parse_rectangle(object) catch {
    _ => None
  } noraise {
    rectangle =>
      if rectangle.min_x < rectangle.max_x && rectangle.min_y < rectangle.max_y {
        Some(rectangle)
      } else {
        None
      }
  }
}

///|
fn pdf_page_rectangle_intersection(
  first : @geometry.PdfRectangle,
  second : @geometry.PdfRectangle,
) -> @geometry.PdfRectangle? {
  let min_x = first.min_x.max(second.min_x)
  let min_y = first.min_y.max(second.min_y)
  let max_x = first.max_x.min(second.max_x)
  let max_y = first.max_y.min(second.max_y)
  if min_x < max_x && min_y < max_y {
    Some({ min_x, min_y, max_x, max_y, })
  } else {
    None
  }
}

///|
fn pdf_page_default_media_box() -> @geometry.PdfRectangle {
  // PDF.js uses the US Letter media box when /MediaBox is missing or invalid.
  { min_x: 0.0, min_y: 0.0, max_x: 612.0, max_y: 792.0, }
}

///|
fn pdf_page_user_unit(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
) -> Double {
  let user_unit_name = @core.pdf_name_of_bytes(@utf8.encode("/UserUnit"))
  match document.lookup_direct(user_unit_name, page.rest) {
    Some(value) =>
      try document.get_number(value) catch {
        _ => 1.0
      } noraise {
        number => pdf_safe_user_unit(number)
      }
    None => 1.0
  }
}

///|
/// One content entry together with the interpreter state and resource scope
/// that produced it. `PdfContentJsonEntry` intentionally omits the CTM, which
/// is enough for text bounds but loses rotations and Form-XObject placement for
/// paths and images.
priv struct PdfCollectedEntry {
  entry : @pdflite.PdfContentJsonEntry
  state : @pdflite.PdfContentOperatorState
  text_glyph : @pdflite.PdfContentTextGlyphPlacement?
  text_source : PdfCollectedTextSource?
  font_object : @syntax.PdfObject?
  resources : @syntax.PdfObject
  inline_image : (@syntax.PdfObject, @syntax.PdfObject?, @core.PdfBytes)?
  clip_paths : Array[@shape.PdfPath]
  text_clip_groups : Array[PdfCollectedTextClipGroup]
  soft_mask : PdfCollectedSoftMask?
  group : PdfTransparencyGroup?
  group_path : Array[PdfTransparencyGroup]
  fill_color_explicit : Bool
  stroke_color_explicit : Bool
}

///|
priv struct PdfCollectedSoftMask {
  dictionary : @syntax.PdfObject
  resources : @syntax.PdfObject
}

///|
fn pdf_collected_entries_of_page(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
  optional_content_view? : PdfOptionalContentView? = None,
  collect_text_sources? : Bool = false,
) -> Array[PdfCollectedEntry] raise @core.PdfError {
  let rectangle = document.parse_rectangle(page.mediabox)
  let initial = @pdflite.pdf_content_initial_operator_state(
    rectangle.min_x,
    rectangle.min_y,
    rectangle.max_x,
    rectangle.max_y,
  )
  let ops = document.parse_content_ops_with_resources(
    page.resources,
    page.content,
  )
  pdf_collected_entries_of_ops(
    document,
    initial,
    page.resources,
    ops,
    initial.clipping_path,
    None,
    [],
    false,
    false,
    optional_content_view~,
    text_source_scope=Some(pdf_text_scope_for_page(page, collect_text_sources)),
  )
}

///|
fn pdf_name_key(text : String) -> @core.PdfName {
  @core.pdf_name_of_bytes(@utf8.encode(text))
}

///|
fn pdf_form_xobject_of_resources(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : @core.PdfName,
) -> @syntax.PdfObject? {
  match document.lookup_direct(pdf_name_key("/XObject"), resources) {
    Some(xobjects) => document.lookup_direct(name, xobjects)
    None => None
  }
}

///|
fn pdf_bool_entry(
  document : @pdflite.PdfDocument,
  key : @core.PdfName,
  object : @syntax.PdfObject,
  default : Bool,
) -> Bool {
  match document.lookup_direct(key, object) {
    Some(@syntax.PdfBoolean(value)) => value
    _ => default
  }
}

///|
/// Read the transparency group dictionary carried by a Form XObject. The
/// group is metadata on the flattened display list; actual source paints are
/// still collected by pdflite's normal content interpreter.
fn pdf_transparency_group_of_form(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : @core.PdfName,
  parent : PdfTransparencyGroup?,
) -> PdfTransparencyGroup? {
  match pdf_form_xobject_of_resources(document, resources, name) {
    Some(xobject) =>
      match document.lookup_direct(pdf_name_key("/Group"), xobject) {
        Some(group_dictionary) =>
          match document.lookup_direct(pdf_name_key("/S"), group_dictionary) {
            Some(@syntax.PdfNameObject(subtype)) if subtype ==
              pdf_name_key("/Transparency") => {
              let name_text = pdf_annotation_name_text(name)
              let id = match parent {
                Some(value) => value.id + name_text
                None => name_text
              }
              Some({
                id,
                isolated: pdf_bool_entry(
                  document,
                  pdf_name_key("/I"),
                  group_dictionary,
                  false,
                ),
                knockout: pdf_bool_entry(
                  document,
                  pdf_name_key("/K"),
                  group_dictionary,
                  false,
                ),
              })
            }
            _ => None
          }
        None => None
      }
    None => None
  }
}

///|
/// Track whether a PDF content stream explicitly changed either painting
/// colour. `pdflite`'s compact initial path state uses white as a placeholder,
/// while PDF's default non-stroking and stroking colours are black. Keeping
/// this bit alongside the collected entry lets the viewer correct that
/// dependency default without changing an explicit white paint operation.
fn pdf_color_explicit_after_op(
  op : @content.PdfContentOp,
  fill : Bool,
  stroke : Bool,
) -> (Bool, Bool) {
  match op {
    @content.Op_g(_)
    | @content.Op_rg(_, _, _)
    | @content.Op_k(_, _, _, _)
    | @content.Op_sc(_)
    | @content.Op_scn(_)
    | @content.Op_scnName(_, _) => (true, stroke)
    @content.Op_cs(_) => (true, stroke)
    @content.Op_G(_)
    | @content.Op_RG(_, _, _)
    | @content.Op_K(_, _, _, _)
    | @content.Op_SC(_)
    | @content.Op_SCN(_)
    | @content.Op_SCNName(_, _) => (fill, true)
    @content.Op_CS(_) => (fill, true)
    _ => (fill, stroke)
  }
}

///|
fn pdf_collected_entries_of_ops(
  document : @pdflite.PdfDocument,
  initial : @pdflite.PdfContentOperatorState,
  resources : @syntax.PdfObject,
  ops : ArrayView[@content.PdfContentOp],
  initial_clip_paths : ArrayView[@shape.PdfPath],
  initial_soft_mask : PdfCollectedSoftMask?,
  initial_group_path : ArrayView[PdfTransparencyGroup],
  initial_fill_color_explicit : Bool,
  initial_stroke_color_explicit : Bool,
  initial_text_clip_groups? : ArrayView[PdfCollectedTextClipGroup] = [],
  optional_content_view? : PdfOptionalContentView? = None,
  initial_optional_content_visible? : Bool = true,
  text_source_scope? : PdfTextCollectScope? = None,
) -> Array[PdfCollectedEntry] raise @core.PdfError {
  let text_source_scope = Some(
    text_source_scope.unwrap_or({
      content_streams: [],
      form_path: [],
      font_object: None,
      font_stack: [],
      collect_sources: false,
    }),
  )
  let mut state = initial
  let mut soft_mask = initial_soft_mask
  let group_path : Array[PdfTransparencyGroup] = [
    for value in initial_group_path => value
  ]
  let group = group_path.last()
  let mut clip_paths : Array[@shape.PdfPath] = [
    for path in initial_clip_paths => path
  ]
  let mut clip_stack : Array[Array[@shape.PdfPath]] = []
  let mut text_clip_groups = [ for group in initial_text_clip_groups => group ]
  let text_clip_stack : Array[Array[PdfCollectedTextClipGroup]] = []
  let pending_text_clip : Array[PdfCollectedTextClipGlyph] = []
  let mut soft_mask_stack : Array[PdfCollectedSoftMask?] = []
  let mut fill_color_explicit = initial_fill_color_explicit
  let mut stroke_color_explicit = initial_stroke_color_explicit
  let mut fill_color_stack : Array[Bool] = []
  let mut stroke_color_stack : Array[Bool] = []
  let output : Array[PdfCollectedEntry] = []
  for operator_index, op in ops {
    let text_sources = pdf_collect_text_string_sources(
      document,
      text_source_scope,
      state.text_state.current_font,
      op,
      operator_index,
    )
    match op {
      @content.Op_Do(name) =>
        match document.content_form_xobject_ops(resources, name) {
          Some(form_ops) => {
            let form_visible = pdf_optional_content_visible_form(
              document, resources, name, optional_content_view, initial_optional_content_visible,
            )
            let form_group = pdf_transparency_group_of_form(
              document, resources, name, group,
            )
            let child_group_path : Array[PdfTransparencyGroup] = [
              for value in group_path => value
            ]
            match form_group {
              Some(value) => child_group_path.push(value)
              None => ()
            }
            match
              (
                document.content_form_xobject_enter_state(
                  state, resources, name,
                ),
                document.content_form_xobject_resources(resources, name),
              ) {
              (Some(form_state), Some(form_resources)) => {
                // Resource names can resolve to different fonts inside a
                // Form. Preserve the inherited active font, but rebuild the
                // name-based cache on the next Tf in this resource scope.
                let form_state = {
                  ..form_state,
                  text_state: { ..form_state.text_state, font_cache: [], },
                }
                let form_clip_paths = if form_state.clipping_path.length() >
                  state.clipping_path.length() {
                  [
                    form_state.clipping_path[0].transform(form_state.ctm),
                    ..clip_paths,
                  ]
                } else {
                  [
                    for path in clip_paths => path
                  ]
                }
                output.append(
                  pdf_collected_entries_of_ops(
                    document,
                    form_state,
                    form_resources,
                    form_ops,
                    form_clip_paths,
                    soft_mask,
                    child_group_path,
                    fill_color_explicit,
                    stroke_color_explicit,
                    initial_text_clip_groups=text_clip_groups[:],
                    optional_content_view~,
                    initial_optional_content_visible=form_visible,
                    text_source_scope=pdf_text_scope_for_form(
                      document, resources, text_source_scope, name, operator_index,
                    ),
                  ),
                )
              }
              _ => ()
            }
          }
          None => {
            let (result, glyphs) = pdf_apply_op_for_viewer(
              document,
              state,
              resources,
              op,
              text_source_scope.bind(scope => scope.font_object),
            )
            let mut glyph_index = 0
            for entry in result.entries {
              if pdf_optional_content_visible_marked_content(
                  document,
                  resources,
                  result.state.marked_content[:],
                  optional_content_view,
                  initial_optional_content_visible,
                ) {
                let emitted_entry = match glyphs.get(glyph_index) {
                  Some(glyph) => { ..entry, bounding_box: glyph.bounding_box, }
                  None => entry
                }
                output.push({
                  entry: emitted_entry,
                  state: result.state,
                  text_glyph: glyphs.get(glyph_index),
                  text_source: None,
                  font_object: None,
                  resources,
                  inline_image: None,
                  clip_paths: [
                    for path in clip_paths => path
                  ],
                  text_clip_groups: [
                    for group in text_clip_groups => group
                  ],
                  soft_mask,
                  group,
                  group_path: [
                    for value in group_path => value
                  ],
                  fill_color_explicit,
                  stroke_color_explicit,
                })
              }
              glyph_index += 1
            }
            state = result.state
          }
        }
      @content.Op_InlineImage(dictionary, decode_parms, data) => {
        let result = document.content_apply_resource_op(state, resources, op)
        if pdf_optional_content_visible_marked_content(
            document,
            resources,
            result.state.marked_content[:],
            optional_content_view,
            initial_optional_content_visible,
          ) {
          for entry in result.entries {
            output.push({
              entry,
              state: result.state,
              text_glyph: None,
              text_source: None,
              font_object: None,
              resources,
              inline_image: Some((dictionary, decode_parms, data)),
              clip_paths: [
                for path in clip_paths => path
              ],
              text_clip_groups: [
                for group in text_clip_groups => group
              ],
              soft_mask,
              group,
              group_path: [
                for value in group_path => value
              ],
              fill_color_explicit,
              stroke_color_explicit,
            })
          }
        }
        state = result.state
      }
      @content.Op_gs(name) => {
        state = pdf_apply_extgstate_for_viewer(document, state, resources, name)
        soft_mask = pdf_update_soft_mask_for_viewer(
          document, resources, name, soft_mask,
        )
      }
      @content.Op_q => {
        clip_stack.push([ for path in clip_paths => path ])
        text_clip_stack.push([ for group in text_clip_groups => group ])
        soft_mask_stack.push(soft_mask)
        fill_color_stack.push(fill_color_explicit)
        stroke_color_stack.push(stroke_color_explicit)
        let result = document.content_apply_resource_op(state, resources, op)
        state = result.state
      }
      @content.Op_Q => {
        let result = document.content_apply_resource_op(state, resources, op)
        state = result.state
        match text_clip_stack.pop() {
          Some(previous) => text_clip_groups = previous
          None => ()
        }
        match clip_stack.last() {
          Some(previous) => {
            clip_paths.clear()
            clip_paths.append(previous)
            let stack_length = clip_stack.length()
            clip_stack = [
              for index in 0..<(stack_length - 1) => clip_stack[index]
            ]
          }
          None => ()
        }
        match soft_mask_stack.last() {
          Some(previous) => {
            soft_mask = previous
            let stack_length = soft_mask_stack.length()
            soft_mask_stack = [
              for index in 0..<(stack_length - 1) => soft_mask_stack[index]
            ]
          }
          None => ()
        }
        match fill_color_stack.last() {
          Some(previous) => {
            fill_color_explicit = previous
            let stack_length = fill_color_stack.length()
            fill_color_stack = [
              for index in 0..<(stack_length - 1) => fill_color_stack[index]
            ]
          }
          None => ()
        }
        match stroke_color_stack.last() {
          Some(previous) => {
            stroke_color_explicit = previous
            let stack_length = stroke_color_stack.length()
            stroke_color_stack = [
              for index in 0..<(stack_length - 1) => stroke_color_stack[index]
            ]
          }
          None => ()
        }
      }
      @content.Op_W | @content.Op_Wstar => {
        let previous_length = state.clipping_path.length()
        let result = document.content_apply_resource_op(state, resources, op)
        if result.state.clipping_path.length() > previous_length {
          let clipped = result.state.clipping_path[0].transform(state.ctm)
          clip_paths = [clipped, ..clip_paths]
        }
        state = result.state
      }
      _ => {
        let (result, glyphs) = pdf_apply_op_for_viewer(
          document,
          state,
          resources,
          op,
          text_source_scope.bind(scope => scope.font_object),
        )
        if op is @content.Op_BT {
          pending_text_clip.clear()
        }
        if op is @content.Op_ET && !pending_text_clip.is_empty() {
          text_clip_groups.push({
            glyphs: [
              for glyph in pending_text_clip => glyph
            ],
            path: None,
          })
          pending_text_clip.clear()
        }
        if pdf_optional_content_visible_marked_content(
            document,
            resources,
            result.state.marked_content[:],
            optional_content_view,
            initial_optional_content_visible,
          ) {
          pending_text_clip.append(
            pdf_collect_text_clip_glyphs(
              result.state,
              text_source_scope.bind(scope => scope.font_object),
              glyphs[:],
            ),
          )
        }
        let mut glyph_index = 0
        for entry in result.entries {
          if pdf_optional_content_visible_marked_content(
              document,
              resources,
              result.state.marked_content[:],
              optional_content_view,
              initial_optional_content_visible,
            ) {
            let emitted_entry = match glyphs.get(glyph_index) {
              Some(glyph) => { ..entry, bounding_box: glyph.bounding_box, }
              None => entry
            }
            output.push({
              entry: emitted_entry,
              state: result.state,
              text_glyph: glyphs.get(glyph_index),
              text_source: pdf_collected_text_source_for_glyph(
                text_sources[:],
                glyphs[:],
                glyph_index,
              ),
              font_object: text_source_scope.bind(scope => scope.font_object),
              resources,
              inline_image: None,
              clip_paths: [
                for path in clip_paths => path
              ],
              text_clip_groups: [
                for group in text_clip_groups => group
              ],
              soft_mask,
              group,
              group_path: [
                for value in group_path => value
              ],
              fill_color_explicit,
              stroke_color_explicit,
            })
          }
          glyph_index += 1
        }
        state = result.state
      }
    }
    pdf_text_scope_after_op(document, resources, text_source_scope, op)
    let (next_fill, next_stroke) = pdf_color_explicit_after_op(
      op, fill_color_explicit, stroke_color_explicit,
    )
    fill_color_explicit = next_fill
    stroke_color_explicit = next_stroke
  }
  output
}

///|
fn pdf_items_of_page(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
  origin_x : Double,
  origin_y : Double,
  width : Double,
  height : Double,
  index_offset? : Int = 0,
  appearance_fonts? : PdfAppearanceFontScope,
  page_fonts? : PdfPageFontScope,
  optional_content_view? : PdfOptionalContentView? = None,
) -> Array[PdfPageItem] raise @core.PdfError {
  let collected_entries = pdf_collected_entries_of_page(
    document,
    page,
    optional_content_view~,
  )
  let items : Array[PdfPageItem] = Array(capacity=collected_entries.length())
  let cff_fonts : Map[Int, PdfCffFont?] = Map([])
  let type1_fonts : Map[Int, PdfType1Font?] = Map([])
  let mut inline_index = 0
  for source_index, collected in collected_entries {
    let index = index_offset + source_index
    let entry = collected.entry
    let bounds = pdf_bounds_of_quad(entry.bounding_box)
    let paint = pdf_paint_attributes_of_state(collected.state)
    let clip_path = pdf_clip_path_of_collected(
      document, collected, cff_fonts, type1_fonts, origin_x, origin_y, height,
    )
    let soft_mask = pdf_soft_mask_resource_of_collected(
      document,
      origin_x,
      origin_y,
      width,
      height,
      collected.soft_mask,
    )
    match entry.object {
      @pdflite.PdfContentGlyphObject(charcode, _, text) => {
        let state = match entry.state {
          @pdflite.PdfContentStateGlyph(state) => state
          _ =>
            {
              rendering_mode: 0,
              knockout: false,
              font: "",
              font_size: 0.0,
              clipping_path: [],
            }
        }
        let fill_color = pdf_colour_hex_for_paint_in_space(
          collected.state.path_state.colourspace_non_stroke,
          collected.state.path_state.colour_non_stroke,
          collected.fill_color_explicit,
          document=Some(document),
        )
        let stroke_color = pdf_colour_hex_for_paint_in_space(
          collected.state.path_state.colourspace_stroke,
          collected.state.path_state.colour_stroke,
          collected.stroke_color_explicit,
          document=Some(document),
        )
        let (advance_x, advance_y, vertical) = match collected.text_glyph {
          Some(glyph) => {
            let font = collected.state.text_state.current_font
            (glyph.advance_x, glyph.advance_y, pdf_font_is_vertical(font))
          }
          None => (0.0, 0.0, false)
        }
        let type3_outline = pdf_type3_outline_of_glyph(
          document,
          collected.state.text_state.current_font,
          collected.font_object,
          charcode,
          pdf_quad_of_box(entry.bounding_box),
          state.rendering_mode,
          fill_color,
          stroke_color,
          paint.fill_alpha,
          paint.stroke_alpha,
          origin_x,
          origin_y,
          height,
        ) catch {
          _ => None
        }
        let glyph_matrix = match collected.text_glyph {
          Some(glyph) => Some(pdf_glyph_transform(collected.state, glyph))
          None => None
        }
        let cff_outline = match type3_outline {
          Some(value) => Some(value)
          None =>
            pdf_cff_outline_of_pdf_glyph(
              document,
              collected.state.text_state.current_font,
              cff_fonts,
              charcode,
              glyph_matrix,
              state.rendering_mode,
              fill_color,
              stroke_color,
              paint.fill_alpha,
              paint.stroke_alpha,
              origin_x,
              origin_y,
              height,
            )
        }
        let type1_outline = match cff_outline {
          Some(value) => Some(value)
          None =>
            pdf_type1_outline_of_pdf_glyph(
              document,
              collected.state.text_state.current_font,
              type1_fonts,
              charcode,
              glyph_matrix,
              state.rendering_mode,
              fill_color,
              stroke_color,
              paint.fill_alpha,
              paint.stroke_alpha,
              origin_x,
              origin_y,
              height,
            )
        }
        let glyph_outline = match type1_outline {
          Some(value) => Some(value)
          None =>
            pdf_truetype_outline_of_pdf_glyph(
              document,
              collected.state.text_state.current_font,
              collected.font_object,
              charcode,
              glyph_matrix,
              state.rendering_mode,
              fill_color,
              stroke_color,
              paint.fill_alpha,
              paint.stroke_alpha,
              origin_x,
              origin_y,
              height,
            ) catch {
              _ => None
            }
        }
        items.push(
          PdfPageItem::Text({
            index,
            text,
            charcode,
            advance_x,
            advance_y,
            vertical,
            glyph_transform: match glyph_matrix {
              Some(m) => Some([m.a, m.b, m.c, m.d, m.e, m.f])
              None => None
            },
            bounds,
            quad: pdf_quad_of_box(entry.bounding_box),
            font: match appearance_fonts {
              Some(scope) =>
                pdf_annotation_font_name(
                  document,
                  collected.resources,
                  state.font,
                  scope,
                  active_font=(
                    collected.state.text_state.current_font,
                    collected.font_object,
                  ),
                )
              None =>
                match page_fonts {
                  Some(scope) =>
                    pdf_page_font_name(
                      document,
                      collected.state.text_state.current_font,
                      collected.font_object,
                      state.font,
                      scope,
                    )
                  None => state.font
                }
            },
            font_size: state.font_size,
            rendering_mode: state.rendering_mode,
            fill_color,
            stroke_color,
            fill_alpha: paint.fill_alpha,
            blend_mode: paint.blend_mode,
            clip_path,
            soft_mask,
            group: collected.group,
            group_path: collected.group_path,
            type3_outline: glyph_outline,
          }),
        )
      }
      @pdflite.PdfContentPathObject(path) => {
        let drawn = path
        let (
          fill_color,
          stroke_color,
          line_width,
          line_cap,
          line_join,
          dash_array,
          dash_phase,
          pattern,
          stroke_pattern,
          shading_pattern,
        ) = match entry.state {
          @pdflite.PdfContentStatePath(state) => {
            let stroke_scale = pdf_ctm_stroke_scale(collected.state.ctm)
            let pattern = if drawn.filled {
              pdf_pattern_resource_of_paint(
                document,
                collected.resources,
                state.colourspace_non_stroke,
                state.colour_non_stroke,
                collected.state.ctm,
              )
            } else {
              None
            }
            let stroke_pattern = if drawn.stroked {
              pdf_pattern_resource_of_paint(
                document,
                collected.resources,
                state.colourspace_stroke,
                state.colour_stroke,
                collected.state.ctm,
              )
            } else {
              None
            }
            let (pattern, shading_pattern) = match pattern {
              Some(value) =>
                match value.shading {
                  Some(shading) => (None, Some(shading))
                  None => (Some(value), None)
                }
              None => (None, None)
            }
            (
              pdf_colour_hex_for_paint_in_space(
                state.colourspace_non_stroke,
                state.colour_non_stroke,
                collected.fill_color_explicit,
                document=Some(document),
              ),
              pdf_colour_hex_for_paint_in_space(
                state.colourspace_stroke,
                state.colour_stroke,
                collected.stroke_color_explicit,
                document=Some(document),
              ),
              state.line_width * stroke_scale,
              state.line_cap,
              state.line_join,
              [
                for value in state.dash_pattern.array => value * stroke_scale
              ],
              state.dash_pattern.phase * stroke_scale,
              pattern,
              stroke_pattern,
              shading_pattern,
            )
          }
          _ => ("#202124", "#202124", 1.0, 0, 0, [], 0.0, None, None, None)
        }
        items.push(
          PdfPageItem::Path({
            index,
            bounds,
            svg_path: pdf_svg_path_of_shape_direct(
              drawn.path.transform(collected.state.ctm),
              origin_x,
              origin_y,
              height,
            ),
            filled: drawn.filled,
            stroked: drawn.stroked,
            fill_color,
            stroke_color,
            fill_alpha: paint.fill_alpha,
            stroke_alpha: paint.stroke_alpha,
            line_width,
            line_cap,
            line_join,
            dash_array,
            dash_phase,
            pattern,
            stroke_pattern,
            shading_pattern,
            blend_mode: paint.blend_mode,
            clip_path,
            soft_mask,
            group: collected.group,
            group_path: collected.group_path,
          }),
        )
      }
      @pdflite.PdfContentImageObject(name) => {
        let resource = pdf_image_resource_of_resources(
          document,
          collected.resources,
          name,
        )
        items.push(
          PdfPageItem::Image({
            index,
            bounds,
            quad: pdf_quad_of_box(entry.bounding_box),
            name,
            resource,
            shading: None,
            fill_color: pdf_colour_hex_for_paint_in_space(
              collected.state.path_state.colourspace_non_stroke,
              collected.state.path_state.colour_non_stroke,
              collected.fill_color_explicit,
              document=Some(document),
            ),
            fill_alpha: paint.fill_alpha,
            stroke_alpha: paint.stroke_alpha,
            blend_mode: paint.blend_mode,
            clip_path,
            soft_mask,
            group: collected.group,
            group_path: collected.group_path,
          }),
        )
      }
      @pdflite.PdfContentInlineImageObject => {
        let name = "inline-image-" + inline_index.to_string()
        let resource = match collected.inline_image {
          Some((dictionary, decode_parms, data)) =>
            pdf_inline_image_resource_of(
              document,
              collected.resources,
              name,
              dictionary,
              data,
              decode_parms~,
            )
          None => None
        }
        inline_index += 1
        items.push(
          PdfPageItem::Image({
            index,
            bounds,
            quad: pdf_quad_of_box(entry.bounding_box),
            name,
            resource,
            shading: None,
            fill_color: pdf_colour_hex_for_paint_in_space(
              collected.state.path_state.colourspace_non_stroke,
              collected.state.path_state.colour_non_stroke,
              collected.fill_color_explicit,
              document=Some(document),
            ),
            fill_alpha: paint.fill_alpha,
            stroke_alpha: paint.stroke_alpha,
            blend_mode: paint.blend_mode,
            clip_path,
            soft_mask,
            group: collected.group,
            group_path: collected.group_path,
          }),
        )
      }
      @pdflite.PdfContentShadingObject(name) => {
        let shading = match
          pdf_shading_resource_of_resources(document, collected.resources, name) {
          Some(value) =>
            Some(pdf_shading_resource_with_ctm(value, collected.state.ctm))
          None => None
        }
        items.push(
          PdfPageItem::Shading({
            index,
            bounds,
            quad: pdf_quad_of_box(entry.bounding_box),
            name,
            resource: None,
            shading,
            fill_color: pdf_colour_hex_for_paint_in_space(
              collected.state.path_state.colourspace_non_stroke,
              collected.state.path_state.colour_non_stroke,
              collected.fill_color_explicit,
              document=Some(document),
            ),
            fill_alpha: paint.fill_alpha,
            stroke_alpha: paint.stroke_alpha,
            blend_mode: paint.blend_mode,
            clip_path,
            soft_mask,
            group: collected.group,
            group_path: collected.group_path,
          }),
        )
      }
    }
  }
  items
}

///|
/// Convert an entry's clipping state into SVG page-space path data. `pdflite`
/// prepends each explicit clip to the existing state, so the page boundary
/// installed by the PDF interpreter is the final path. The browser's SVG
/// viewport already supplies that clip, so only explicit additional clips are
/// serialized.
fn pdf_clip_path_of_paths(
  paths : ArrayView[@shape.PdfPath],
  origin_x : Double,
  origin_y : Double,
  height : Double,
) -> String? {
  if paths.length() <= 1 {
    None
  } else {
    let explicit_paths = [
      for index in 0..<(paths.length() - 1) => paths[index]
    ]
    pdf_svg_clip_path_of_shapes(explicit_paths, origin_x, origin_y, height)
  }
}

///|
/// The part of the graphics state that the SVG serializer can apply directly.
priv struct PdfPaintAttributes {
  fill_alpha : Double
  stroke_alpha : Double
  blend_mode : String
}

///|
/// Resolve `/ExtGState /Name` explicitly before applying it. This keeps the
/// viewer independent from the JSON entry's intentionally compact state view.
fn pdf_apply_extgstate_for_viewer(
  document : @pdflite.PdfDocument,
  state : @pdflite.PdfContentOperatorState,
  resources : @syntax.PdfObject,
  name : @core.PdfName,
) -> @pdflite.PdfContentOperatorState raise @core.PdfError {
  let extgstate_name = @core.pdf_name_of_bytes(@utf8.encode("/ExtGState"))
  match document.lookup_direct(extgstate_name, resources) {
    Some(extgstates) =>
      match document.lookup_direct(name, extgstates) {
        Some(extgstate) => {
          let mut output = state
          output = document.content_apply_extgstate_graphics_parameter_op(
            output, extgstate,
          )
          output = document.content_apply_extgstate_dash_op(output, extgstate)
          output = pdf_apply_extgstate_font_for_viewer(
            document, output, extgstate,
          )
          output = document.content_apply_extgstate_overprint_op(
            output, extgstate,
          )
          output = document.content_apply_extgstate_transfer_op(
            output, extgstate,
          )
          output = document.content_apply_extgstate_halftone_op(
            output, extgstate,
          )
          output = document.content_apply_extgstate_rendering_op(
            output, extgstate,
          )
          output = document.content_apply_extgstate_compositing_op(
            output, extgstate,
          )
          output = document.content_apply_extgstate_alpha_op(output, extgstate)
          output = document.content_apply_extgstate_text_op(output, extgstate)
          output
        }
        None => state
      }
    None => state
  }
}

///|
fn pdf_paint_attributes_of_state(
  state : @pdflite.PdfContentOperatorState,
) -> PdfPaintAttributes {
  {
    fill_alpha: state.alpha_constant_non_stroke,
    stroke_alpha: state.alpha_constant_stroke,
    blend_mode: pdf_svg_blend_mode(state.blend_mode),
  }
}

///|
/// Approximate the PDF stroke scale for a general affine CTM. A uniform CTM
/// is exact; for a shear or non-uniform scale the mean lengths of the two
/// transformed basis vectors keep line width and dash spacing stable without
/// losing the page-space path geometry already retained by the viewer.
fn pdf_ctm_stroke_scale(ctm : @geometry.TransformMatrix) -> Double {
  let x_scale = (ctm.a * ctm.a + ctm.b * ctm.b).sqrt()
  let y_scale = (ctm.c * ctm.c + ctm.d * ctm.d).sqrt()
  let scale = (x_scale + y_scale) / 2.0
  if scale > 0.0 {
    scale
  } else {
    1.0
  }
}

///|
fn pdf_svg_blend_mode(value : @syntax.PdfObject) -> String {
  match value {
    @syntax.PdfNameObject(name) => {
      let text = pdf_annotation_name_text(name).to_lower()
      let text = if text.has_prefix("/") { text[1:].to_owned() } else { text }
      match text {
        "normal" | "compatible" => "normal"
        "colordodge" => "color-dodge"
        "colorburn" => "color-burn"
        "hardlight" => "hard-light"
        "softlight" => "soft-light"
        _ => text
      }
    }
    _ => "normal"
  }
}

///|
/// Resolve a shading in the resource dictionary active at the paint site.
fn pdf_shading_resource_of_resources(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : String,
) -> PdfShadingResource? {
  let shading_dictionary_name = pdf_image_name("/Shading")
  let shading_name = pdf_image_name(name)
  match document.lookup_direct(shading_dictionary_name, resources) {
    Some(shadings) =>
      match document.lookup_direct(shading_name, shadings) {
        Some(shading) =>
          try
            Some(
              pdf_shading_resource_of_object(
                document,
                name,
                shading,
                resources~,
              ),
            )
          catch {
            _ => None
          } noraise {
            value => value
          }
        None => None
      }
    None => None
  }
}

///|
fn pdf_shading_resource_of_object(
  document : @pdflite.PdfDocument,
  name : String,
  object : @syntax.PdfObject,
  resources? : @syntax.PdfObject = @syntax.PdfNull,
) -> PdfShadingResource raise @core.PdfError {
  pdf_shading_resource_of_object_with_matrix(
    document,
    name,
    object,
    @geometry.transform_identity_matrix,
    resources~,
  )
}

///|
fn pdf_shading_resource_of_object_with_matrix(
  document : @pdflite.PdfDocument,
  name : String,
  object : @syntax.PdfObject,
  matrix : @geometry.TransformMatrix,
  resources? : @syntax.PdfObject = @syntax.PdfNull,
) -> PdfShadingResource raise @core.PdfError {
  let shading = document.content_read_shading(matrix, @syntax.PdfNull, object)
  let colour_object = document
    .lookup_direct(pdf_name_key("/ColorSpace"), object)
    .unwrap_or(shading.shading_colourspace)
  let colourspace = pdf_read_colour_space_for_viewer(
    document, resources, colour_object,
  ).unwrap_or(@pdflite.PdfDeviceRGB)
  let colour_transform = pdf_colour_transform(Some(document), colourspace)
  let matrix = [
    shading.shading_matrix.a,
    shading.shading_matrix.b,
    shading.shading_matrix.c,
    shading.shading_matrix.d,
    shading.shading_matrix.e,
    shading.shading_matrix.f,
  ]
  match shading.shading {
    @pdflite.PdfContentAxialShading(axial) => {
      let (x0, y0, x1, y1) = axial.axialshading_coords
      let (domain_min, domain_max) = axial.axialshading_domain
      {
        name,
        kind: "axial",
        coords: [x0, y0, x1, y1],
        matrix,
        stops: pdf_shading_stops(
          axial.axialshading_function,
          domain_min,
          domain_max,
          colour_transform,
        ),
        mesh: [],
        extend_start: axial.axialshading_extend.0,
        extend_end: axial.axialshading_extend.1,
      }
    }
    @pdflite.PdfContentRadialShading(radial) => {
      let (x0, y0, r0, x1, y1, r1) = radial.radialshading_coords
      let (domain_min, domain_max) = radial.radialshading_domain
      {
        name,
        kind: "radial",
        coords: [x0, y0, r0, x1, y1, r1],
        matrix,
        stops: pdf_shading_stops(
          radial.radialshading_function,
          domain_min,
          domain_max,
          colour_transform,
        ),
        mesh: [],
        extend_start: radial.radialshading_extend.0,
        extend_end: radial.radialshading_extend.1,
      }
    }
    @pdflite.PdfContentFunctionShading(function) => {
      let (domain_min, domain_max) = pdf_shading_function_domain([
        function.funshading_function,
      ])
      {
        name,
        kind: "function",
        coords: [],
        matrix,
        stops: pdf_shading_stops(
          [function.funshading_function],
          domain_min,
          domain_max,
          colour_transform,
        ),
        mesh: [],
        extend_start: true,
        extend_end: true,
      }
    }
    @pdflite.PdfContentFreeFormGouraudShading =>
      {
        name,
        kind: "mesh",
        coords: [],
        matrix,
        stops: [],
        mesh: pdf_mesh_triangles_of_shading(
          document,
          object,
          colour_object,
          resources~,
        ),
        extend_start: true,
        extend_end: true,
      }
    @pdflite.PdfContentLatticeFormGouraudShading =>
      {
        name,
        kind: "mesh",
        coords: [],
        matrix,
        stops: [],
        mesh: pdf_mesh_triangles_of_shading(
          document,
          object,
          colour_object,
          resources~,
        ),
        extend_start: true,
        extend_end: true,
      }
    @pdflite.PdfContentCoonsPatchMesh =>
      {
        name,
        kind: "mesh",
        coords: [],
        matrix,
        stops: [],
        mesh: pdf_mesh_triangles_of_shading(
          document,
          object,
          colour_object,
          resources~,
        ),
        extend_start: true,
        extend_end: true,
      }
    @pdflite.PdfContentTensorProductPatchMesh =>
      {
        name,
        kind: "mesh",
        coords: [],
        matrix: [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
        stops: [],
        mesh: pdf_mesh_triangles_of_shading(
          document,
          object,
          colour_object,
          resources~,
        ),
        extend_start: true,
        extend_end: true,
      }
  }
}

///|
/// Shading coordinates live in the current user space rather than image
/// unit-square space. Retain the full CTM on the resource so SVG can apply it
/// to both axial and radial gradients without approximating a sheared circle.
fn pdf_shading_resource_with_ctm(
  shading : PdfShadingResource,
  ctm : @geometry.TransformMatrix,
) -> PdfShadingResource {
  let base = if shading.matrix.length() >= 6 {
    shading.matrix
  } else {
    [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
  }
  let a = ctm.a * base[0] + ctm.c * base[1]
  let b = ctm.b * base[0] + ctm.d * base[1]
  let c = ctm.a * base[2] + ctm.c * base[3]
  let d = ctm.b * base[2] + ctm.d * base[3]
  let e = ctm.a * base[4] + ctm.c * base[5] + ctm.e
  let f = ctm.b * base[4] + ctm.d * base[5] + ctm.f
  { ..shading, matrix: [a, b, c, d, e, f], }
}

///|
fn pdf_shading_function_domain(
  functions : ArrayView[@pdflite.PdfFunction],
) -> (Double, Double) {
  match functions[0:] {
    [function, ..] if function.domain.length() >= 2 =>
      (function.domain[0], function.domain[1])
    _ => (0.0, 1.0)
  }
}

///|
fn pdf_shading_stops(
  functions : ArrayView[@pdflite.PdfFunction],
  domain_min : Double,
  domain_max : Double,
  colourspace : PdfColourTransform,
) -> Array[PdfGradientStop] {
  let stops : Array[PdfGradientStop] = []
  let sample_count = 16
  for index in 0..<=sample_count {
    let offset = index.to_double() / sample_count.to_double()
    let input = domain_min + (domain_max - domain_min) * offset
    match pdf_shading_sample(functions, input, colourspace) {
      Some(color) => stops.push({ offset, color, })
      None => ()
    }
  }
  stops
}

///|
fn pdf_shading_sample(
  functions : ArrayView[@pdflite.PdfFunction],
  input : Double,
  colourspace : PdfColourTransform,
) -> String? {
  let values : Array[Double] = []
  for function in functions {
    let result = try Some(function.eval([input])) catch {
      _ => None
    } noraise {
      value => value
    }
    match result {
      Some(output) =>
        for value in output {
          values.push(value)
        }
      None => return None
    }
  }
  if values.length() == 0 {
    None
  } else {
    Some(pdf_shading_colour_hex(values, colourspace))
  }
}

///|
fn pdf_shading_colour_hex(
  values : ArrayView[Double],
  colourspace : PdfColourTransform,
) -> String {
  let (r, g, b) = pdf_colour_rgb_of_transform(colourspace, values)
  pdf_rgb_hex(r, g, b)
}

///|
fn pdf_bounds_of_quad(quad : @pdflite.PdfContentBoundingBox) -> PdfBounds {
  let min_x = pdf_min4(quad.x0, quad.x1, quad.x2, quad.x3)
  let min_y = pdf_min4(quad.y0, quad.y1, quad.y2, quad.y3)
  let max_x = pdf_max4(quad.x0, quad.x1, quad.x2, quad.x3)
  let max_y = pdf_max4(quad.y0, quad.y1, quad.y2, quad.y3)
  { min_x, min_y, max_x, max_y, }
}

///|
fn pdf_quad_of_box(quad : @pdflite.PdfContentBoundingBox) -> PdfQuad {
  {
    p0: { x: quad.x0, y: quad.y0, },
    p1: { x: quad.x1, y: quad.y1, },
    p2: { x: quad.x2, y: quad.y2, },
    p3: { x: quad.x3, y: quad.y3, },
  }
}

///|
fn pdf_min4(a : Double, b : Double, c : Double, d : Double) -> Double {
  let ab = if a < b { a } else { b }
  let cd = if c < d { c } else { d }
  if ab < cd {
    ab
  } else {
    cd
  }
}

///|
fn pdf_max4(a : Double, b : Double, c : Double, d : Double) -> Double {
  let ab = if a > b { a } else { b }
  let cd = if c > d { c } else { d }
  if ab > cd {
    ab
  } else {
    cd
  }
}

///|
fn pdf_colour_hex(values : @pdflite.PdfContentColourValues) -> String {
  match values {
    @pdflite.PdfContentColourFloats(components) => {
      // Annotation /C uses component count to choose its device space.
      let space = match components.length() {
        1 => @pdflite.PdfDeviceGray
        3 => @pdflite.PdfDeviceRGB
        4 => @pdflite.PdfDeviceCMYK
        _ => return "#000000"
      }
      pdf_colour_hex_in_space(space, values)
    }
    _ => "#000000"
  }
}

///|
fn pdf_rgb_hex(red : Double, green : Double, blue : Double) -> String {
  "#" + pdf_hex_byte(red) + pdf_hex_byte(green) + pdf_hex_byte(blue)
}

///|
fn pdf_hex_byte(value : Double) -> String {
  let bounded = 0.0.max(1.0.min(value))
  let number = (bounded * 255.0 + 0.5).to_int()
  let alphabet = "0123456789ABCDEF"
  let high = alphabet.get_char(number / 16).unwrap()
  let low = alphabet.get_char(number % 16).unwrap()
  let output = StringBuilder()
  output.write_char(high)
  output.write_char(low)
  output.to_string()
}

///|
fn pdf_text_of_items(items : ArrayView[PdfPageItem]) -> String {
  let text_items = pdf_text_reading_order_of_page_items(items)
  pdf_join_text_items(text_items[:])
}

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
  bounds : PdfBounds
  quad : PdfQuad
  font : String
  font_size : Double
  fill_alpha : Double
  blend_mode : String
  clip_path : String?
  soft_mask : PdfSoftMaskResource?
} derive(Eq, Debug, ToJson)

///|
/// An embedded font made available to the SVG renderer.
///
/// `data_uri` is optional because standard PDF fonts and documents that omit
/// an embedded program must use the host's fallback policy.
pub(all) struct PdfFontResource {
  name : String
  family : String
  mime_type : String
  format : String
  data_uri : String?
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
  pattern : PdfPatternResource?
  blend_mode : String
  clip_path : String?
  soft_mask : PdfSoftMaskResource?
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
} derive(Eq, Debug, ToJson)

///|
/// One sampled colour in a PDF function shading.
pub(all) struct PdfGradientStop {
  offset : Double
  color : String
} derive(Eq, Debug, ToJson)

///|
/// A browser-ready description of a PDF shading resource.
pub(all) struct PdfShadingResource {
  name : String
  kind : String
  coords : Array[Double]
  matrix : Array[Double]
  stops : Array[PdfGradientStop]
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
/// A page annotation exposed to the standalone renderer and host adapters.
///
/// The typed fields keep the annotation layer independent from pdflite's PDF
/// object dictionaries while preserving the rectangle, visual style, text,
/// and link target needed by a read-only viewer.
pub(all) struct PdfAnnotationItem {
  index : Int
  subtype : String
  bounds : PdfBounds
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
}

///|
/// Parse a PDF from bytes and resolve its page tree.
pub fn open_document(bytes : Bytes) -> PdfViewerDocument raise @core.PdfError {
  let document = @pdflite.pdf_read_document_from_bytes(bytes)
  {
    source_length: bytes.length(),
    document,
    pages: document.pages_of_pagetree(),
  }
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
      pdf_page_model(self.document, self.pages[page_number - 1], page_number),
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
      pdf_page_model(self.document, page, index + 1)
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
  let normalized_rotation = pdf_normalize_rotation(rotation)
  let scaled_width = self.width * safe_scale
  let scaled_height = self.height * safe_scale
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
      (center_y - self.origin_y).abs() * safe_scale,
      (center_x - self.origin_x).abs() * safe_scale,
    )
  } else {
    (
      scaled_width,
      scaled_height,
      (center_x - self.origin_x).abs() * safe_scale,
      (center_y - self.origin_y).abs() * safe_scale,
    )
  }
  let matrix = [
    rotate_a * safe_scale,
    rotate_b * safe_scale,
    rotate_c * safe_scale,
    rotate_d * safe_scale,
    offset_x -
    rotate_a * safe_scale * center_x -
    rotate_c * safe_scale * center_y,
    offset_y -
    rotate_b * safe_scale * center_x -
    rotate_d * safe_scale * center_y,
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
  let items : Array[PdfTextItem] = []
  for item in self.items {
    match item {
      PdfPageItem::Text(text) => items.push(text)
      _ => ()
    }
  }
  { items, text: self.text, }
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
) -> PdfPageModel raise @core.PdfError {
  let rectangle = pdf_page_view_box(document, page)
  let items = pdf_items_of_page(
    document,
    page,
    rectangle.min_x,
    rectangle.min_y,
    rectangle.max_x - rectangle.min_x,
    rectangle.max_y - rectangle.min_y,
  )
  let text = pdf_text_of_items(items)
  let fonts = pdf_font_resources_of_items(document, page_number, items)
  let annotations = pdf_annotation_items_of_page(document, page)
  {
    number: page_number,
    origin_x: rectangle.min_x,
    origin_y: rectangle.min_y,
    width: rectangle.max_x - rectangle.min_x,
    height: rectangle.max_y - rectangle.min_y,
    rotation: @page.pdf_page_int_of_rotation(page.rotate),
    fonts,
    items,
    annotations,
    text,
  }
}

///|
/// PDF.js exposes the effective page view box (CropBox when present, otherwise
/// MediaBox). pdflite keeps inherited page dictionaries in `rest`, so resolve
/// that box here while leaving content parsing anchored to the source MediaBox.
fn pdf_page_view_box(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
) -> @geometry.PdfRectangle raise @core.PdfError {
  let crop_name = @core.pdf_name_of_bytes(@utf8.encode("/CropBox"))
  match document.lookup_direct(crop_name, page.rest) {
    Some(cropbox) => document.parse_rectangle(cropbox)
    None => document.parse_rectangle(page.mediabox)
  }
}

///|
fn pdf_annotation_items_of_page(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
) -> Array[PdfAnnotationItem] raise @core.PdfError {
  let annotations = document.annotations_of_page(page)
  [
    for index, annotation in annotations => {
      let rectangle = annotation.rectangle
      {
        index,
        subtype: pdf_annotation_subtype_name(annotation.subtype),
        bounds: {
          min_x: rectangle.min_x,
          min_y: rectangle.min_y,
          max_x: rectangle.max_x,
          max_y: rectangle.max_y,
        },
        contents: pdf_annotation_text(annotation.contents),
        subject: pdf_annotation_text(annotation.subject),
        color: match annotation.colour {
          Some(colour) =>
            Some(pdf_annotation_rgb_hex(colour.red, colour.green, colour.blue))
          None => None
        },
        border_width: annotation.border.width,
        border_style: pdf_annotation_border_style(annotation.border.style),
        border_dash: annotation.border.dash_array,
        uri: pdf_annotation_uri(document, annotation.rest),
      }
    }
  ]
}

///|
fn pdf_annotation_subtype_name(
  subtype : @annotation.PdfAnnotationSubtype,
) -> String {
  match subtype {
    @annotation.AnnotationText => "text"
    @annotation.AnnotationLink => "link"
    @annotation.AnnotationFreeText => "free-text"
    @annotation.AnnotationLine => "line"
    @annotation.AnnotationSquare => "square"
    @annotation.AnnotationCircle => "circle"
    @annotation.AnnotationPolygon => "polygon"
    @annotation.AnnotationPolyLine => "polyline"
    @annotation.AnnotationHighlight => "highlight"
    @annotation.AnnotationUnderline => "underline"
    @annotation.AnnotationSquiggly => "squiggly"
    @annotation.AnnotationStrikeOut => "strikeout"
    @annotation.AnnotationStamp => "stamp"
    @annotation.AnnotationCaret => "caret"
    @annotation.AnnotationInk => "ink"
    @annotation.AnnotationPopup(_) => "popup"
    @annotation.AnnotationFileAttachment => "file-attachment"
    @annotation.AnnotationSound => "sound"
    @annotation.AnnotationMovie => "movie"
    @annotation.AnnotationWidget => "widget"
    @annotation.AnnotationScreen => "screen"
    @annotation.AnnotationPrinterMark => "printer-mark"
    @annotation.AnnotationTrapNet => "trap-net"
    @annotation.AnnotationWatermark => "watermark"
    @annotation.AnnotationThreeDee => "three-dee"
    @annotation.AnnotationUnknown(name) => pdf_annotation_name_text(name)
  }
}

///|
fn pdf_annotation_name_text(name : @core.PdfName) -> String {
  try @utf8.decode(name.bytes()[:]) catch {
    _ => "unknown"
  } noraise {
    value => value
  }
}

///|
fn pdf_annotation_text(data : Bytes?) -> String? {
  match data {
    Some(bytes) =>
      try Some(@utf8.decode(bytes[:])) catch {
        _ => None
      } noraise {
        value => value
      }
    None => None
  }
}

///|
fn pdf_annotation_border_style(
  style : @annotation.PdfAnnotationStyle,
) -> String {
  match style {
    @annotation.AnnotationNoStyle => "none"
    @annotation.AnnotationSolid => "solid"
    @annotation.AnnotationDashed => "dashed"
    @annotation.AnnotationBeveled => "beveled"
    @annotation.AnnotationInset => "inset"
    @annotation.AnnotationUnderlineStyle => "underline"
  }
}

///|
fn pdf_annotation_rgb_hex(red : Int, green : Int, blue : Int) -> String {
  pdf_rgb_hex(
    red.to_double() / 255.0,
    green.to_double() / 255.0,
    blue.to_double() / 255.0,
  )
}

///|
fn pdf_annotation_uri(
  document : @pdflite.PdfDocument,
  rest : @syntax.PdfObject,
) -> String? {
  let action_name = @core.pdf_name_of_bytes(@utf8.encode("/A"))
  let uri_name = @core.pdf_name_of_bytes(@utf8.encode("/URI"))
  match document.lookup_direct(action_name, rest) {
    Some(action) =>
      match document.lookup_direct(uri_name, action) {
        Some(@syntax.PdfString(data)) => pdf_annotation_text(Some(data))
        _ => None
      }
    None => None
  }
}

///|
fn pdf_font_resources_of_items(
  document : @pdflite.PdfDocument,
  page_number : Int,
  items : ArrayView[PdfPageItem],
) -> Array[PdfFontResource] {
  let fonts : Array[PdfFontResource] = []
  let names : Array[String] = []
  for item in items {
    match item {
      PdfPageItem::Text(text) if !names.contains(text.font) => {
        names.push(text.font)
        fonts.push(pdf_font_resource_of(document, page_number, text.font))
      }
      _ => ()
    }
  }
  fonts
}

///|
fn pdf_font_resource_of(
  document : @pdflite.PdfDocument,
  page_number : Int,
  name : String,
) -> PdfFontResource {
  let family = pdf_svg_embedded_font_family(name)
  let (mime_type, format, data_uri) = try {
    match document.extract_fontfile_bytes(page_number, name) {
      Some(data) => {
        let (mime_type, format) = pdf_font_format_of_bytes(data)
        (
          mime_type,
          format,
          Some("data:" + mime_type + ";base64," + @base64.encode(data)),
        )
      }
      None => ("font/ttf", "truetype", None)
    }
  } catch {
    _ => ("font/ttf", "truetype", None)
  } noraise {
    data => data
  }
  { name, family, mime_type, format, data_uri, }
}

///|
fn pdf_font_format_of_bytes(data : Bytes) -> (String, String) {
  if pdf_bytes_start_with(data, [79, 84, 84, 79]) {
    ("font/otf", "opentype")
  } else if pdf_bytes_start_with(data, [119, 79, 70, 70]) {
    ("font/woff", "woff")
  } else if pdf_bytes_start_with(data, [119, 79, 70, 50]) {
    ("font/woff2", "woff2")
  } else {
    ("font/ttf", "truetype")
  }
}

///|
fn pdf_bytes_start_with(data : Bytes, prefix : ArrayView[Int]) -> Bool {
  if data.length() < prefix.length() {
    false
  } else {
    for index, value in prefix {
      if data[index].to_int() != value {
        return false
      }
    }
    true
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
  resources : @syntax.PdfObject
  inline_image : (@syntax.PdfObject, @core.PdfBytes)?
  clip_paths : Array[@shape.PdfPath]
  soft_mask : PdfCollectedSoftMask?
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
  )
}

///|
/// Recursive content walk that mirrors pdflite's entry collector while
/// retaining the active CTM and resource dictionary for every emitted item.
fn pdf_collected_entries_of_ops(
  document : @pdflite.PdfDocument,
  initial : @pdflite.PdfContentOperatorState,
  resources : @syntax.PdfObject,
  ops : ArrayView[@content.PdfContentOp],
  initial_clip_paths : ArrayView[@shape.PdfPath],
  initial_soft_mask : PdfCollectedSoftMask?,
) -> Array[PdfCollectedEntry] raise @core.PdfError {
  let mut state = initial
  let mut soft_mask = initial_soft_mask
  let mut clip_paths : Array[@shape.PdfPath] = [
    for path in initial_clip_paths => path
  ]
  let mut clip_stack : Array[Array[@shape.PdfPath]] = []
  let mut soft_mask_stack : Array[PdfCollectedSoftMask?] = []
  let output : Array[PdfCollectedEntry] = []
  for op in ops {
    match op {
      @content.Op_Do(name) =>
        match document.content_form_xobject_ops(resources, name) {
          Some(form_ops) =>
            match
              (
                document.content_form_xobject_enter_state(
                  state, resources, name,
                ),
                document.content_form_xobject_resources(resources, name),
              ) {
              (Some(form_state), Some(form_resources)) => {
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
                    document, form_state, form_resources, form_ops, form_clip_paths,
                    soft_mask,
                  ),
                )
              }
              _ => ()
            }
          None => {
            let result = document.content_apply_resource_op(
              state, resources, op,
            )
            for entry in result.entries {
              output.push({
                entry,
                state: result.state,
                resources,
                inline_image: None,
                clip_paths: [
                  for path in clip_paths => path
                ],
                soft_mask,
              })
            }
            state = result.state
          }
        }
      @content.Op_InlineImage(dictionary, _, data) => {
        let result = document.content_apply_resource_op(state, resources, op)
        for entry in result.entries {
          output.push({
            entry,
            state: result.state,
            resources,
            inline_image: Some((dictionary, data)),
            clip_paths: [
              for path in clip_paths => path
            ],
            soft_mask,
          })
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
        soft_mask_stack.push(soft_mask)
        let result = document.content_apply_resource_op(state, resources, op)
        state = result.state
      }
      @content.Op_Q => {
        let result = document.content_apply_resource_op(state, resources, op)
        state = result.state
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
        let result = document.content_apply_resource_op(state, resources, op)
        for entry in result.entries {
          output.push({
            entry,
            state: result.state,
            resources,
            inline_image: None,
            clip_paths: [
              for path in clip_paths => path
            ],
            soft_mask,
          })
        }
        state = result.state
      }
    }
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
) -> Array[PdfPageItem] raise @core.PdfError {
  let collected_entries = pdf_collected_entries_of_page(document, page)
  let items : Array[PdfPageItem] = Array(capacity=collected_entries.length())
  let mut inline_index = 0
  for index, collected in collected_entries {
    let entry = collected.entry
    let bounds = pdf_bounds_of_quad(entry.bounding_box)
    let paint = pdf_paint_attributes_of_state(collected.state)
    let clip_path = pdf_clip_path_of_paths(
      collected.clip_paths,
      origin_x,
      origin_y,
      height,
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
      @pdflite.PdfContentGlyphObject(_, _, text) =>
        if text != "" {
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
          items.push(
            PdfPageItem::Text({
              index,
              text,
              bounds,
              quad: pdf_quad_of_box(entry.bounding_box),
              font: state.font,
              font_size: state.font_size,
              fill_alpha: paint.fill_alpha,
              blend_mode: paint.blend_mode,
              clip_path,
              soft_mask,
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
        ) = match entry.state {
          @pdflite.PdfContentStatePath(state) => {
            // pdflite 0.2.2 currently records `scn` in the stroke colour
            // slot and `SCN` in the non-stroke slot. Look in both slots so a
            // named tiling fill remains visible until that dependency is
            // corrected; the path's fill flag controls SVG usage.
            let pattern_name = match state.colour_non_stroke {
              @pdflite.PdfContentColourNamed(name, _) => Some(name)
              _ =>
                match state.colour_stroke {
                  @pdflite.PdfContentColourNamed(name, _) => Some(name)
                  _ => None
                }
            }
            let pattern = match pattern_name {
              Some(name) =>
                match
                  pdf_pattern_resource_of(document, collected.resources, name) {
                  Some(value) =>
                    Some(
                      pdf_pattern_resource_with_ctm(value, collected.state.ctm),
                    )
                  None => None
                }
              None => None
            }
            (
              pdf_colour_hex(state.colour_non_stroke),
              pdf_colour_hex(state.colour_stroke),
              state.line_width,
              state.line_cap,
              state.line_join,
              state.dash_pattern.array,
              state.dash_pattern.phase,
              pattern,
            )
          }
          _ => ("#202124", "#202124", 1.0, 0, 0, [], 0.0, None)
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
            blend_mode: paint.blend_mode,
            clip_path,
            soft_mask,
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
            fill_color: pdf_colour_hex(
              collected.state.path_state.colour_non_stroke,
            ),
            fill_alpha: paint.fill_alpha,
            stroke_alpha: paint.stroke_alpha,
            blend_mode: paint.blend_mode,
            clip_path,
            soft_mask,
          }),
        )
      }
      @pdflite.PdfContentInlineImageObject => {
        let name = "inline-image-" + inline_index.to_string()
        let resource = match collected.inline_image {
          Some((dictionary, data)) =>
            pdf_inline_image_resource_of(
              document,
              collected.resources,
              name,
              dictionary,
              data,
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
            fill_color: pdf_colour_hex(
              collected.state.path_state.colour_non_stroke,
            ),
            fill_alpha: paint.fill_alpha,
            stroke_alpha: paint.stroke_alpha,
            blend_mode: paint.blend_mode,
            clip_path,
            soft_mask,
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
            fill_color: "#000000",
            fill_alpha: paint.fill_alpha,
            stroke_alpha: paint.stroke_alpha,
            blend_mode: paint.blend_mode,
            clip_path,
            soft_mask,
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
          output = document.content_apply_extgstate_font_op(output, extgstate)
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
            Some(pdf_shading_resource_of_object(document, name, shading))
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
) -> PdfShadingResource raise @core.PdfError {
  let shading = document.content_read_shading(
    @geometry.transform_identity_matrix,
    @syntax.PdfNull,
    object,
  )
  match shading.shading {
    @pdflite.PdfContentAxialShading(axial) => {
      let (x0, y0, x1, y1) = axial.axialshading_coords
      let (domain_min, domain_max) = axial.axialshading_domain
      {
        name,
        kind: "axial",
        coords: [x0, y0, x1, y1],
        matrix: [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
        stops: pdf_shading_stops(
          axial.axialshading_function,
          domain_min,
          domain_max,
          shading.shading_colourspace,
        ),
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
        matrix: [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
        stops: pdf_shading_stops(
          radial.radialshading_function,
          domain_min,
          domain_max,
          shading.shading_colourspace,
        ),
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
        matrix: [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
        stops: pdf_shading_stops(
          [function.funshading_function],
          domain_min,
          domain_max,
          shading.shading_colourspace,
        ),
        extend_start: true,
        extend_end: true,
      }
    }
    @pdflite.PdfContentFreeFormGouraudShading =>
      {
        name,
        kind: "mesh",
        coords: [],
        matrix: [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
        stops: [],
        extend_start: true,
        extend_end: true,
      }
    @pdflite.PdfContentLatticeFormGouraudShading =>
      {
        name,
        kind: "mesh",
        coords: [],
        matrix: [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
        stops: [],
        extend_start: true,
        extend_end: true,
      }
    @pdflite.PdfContentCoonsPatchMesh =>
      {
        name,
        kind: "mesh",
        coords: [],
        matrix: [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
        stops: [],
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
  { ..shading, matrix: [ctm.a, ctm.b, ctm.c, ctm.d, ctm.e, ctm.f], }
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
  colourspace : @syntax.PdfObject,
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
  colourspace : @syntax.PdfObject,
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
  _colourspace : @syntax.PdfObject,
) -> String {
  if values.length() == 1 {
    pdf_rgb_hex(values[0], values[0], values[0])
  } else if values.length() >= 4 {
    let cyan = values[0]
    let magenta = values[1]
    let yellow = values[2]
    let black = values[3]
    pdf_rgb_hex(
      1.0 - 1.0.min(cyan + black),
      1.0 - 1.0.min(magenta + black),
      1.0 - 1.0.min(yellow + black),
    )
  } else if values.length() >= 3 {
    pdf_rgb_hex(values[0], values[1], values[2])
  } else {
    "#000000"
  }
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
    @pdflite.PdfContentColourFloats(values) =>
      match values {
        [gray, ..] =>
          if values.length() == 1 {
            pdf_rgb_hex(gray, gray, gray)
          } else if values.length() >= 4 {
            let cyan = values[0]
            let magenta = values[1]
            let yellow = values[2]
            let black = values[3]
            pdf_rgb_hex(
              1.0 - 1.0.min(cyan + black),
              1.0 - 1.0.min(magenta + black),
              1.0 - 1.0.min(yellow + black),
            )
          } else if values.length() >= 3 {
            pdf_rgb_hex(values[0], values[1], values[2])
          } else {
            pdf_rgb_hex(0.0, 0.0, 0.0)
          }
        [] => "#000000"
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
  let output = StringBuilder()
  let mut previous_y : Double? = None
  for item in items {
    match item {
      PdfPageItem::Text(text) => {
        match previous_y {
          Some(y) if y - text.bounds.max_y > text.font_size * 0.8 =>
            output.write_string("\n")
          _ => ()
        }
        output.write_string(text.text)
        previous_y = Some(text.bounds.max_y)
      }
      _ => ()
    }
  }
  output.to_string()
}

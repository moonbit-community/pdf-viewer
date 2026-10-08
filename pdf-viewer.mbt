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
  width : Int?
  height : Int?
} derive(Eq, Debug, ToJson)

///|
/// An image or shading item in page paint order.
pub(all) struct PdfVisualItem {
  index : Int
  bounds : PdfBounds
  name : String
  resource : PdfImageResource?
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
  let (width, height, matrix, transform) = match normalized_rotation {
    90 =>
      (
        scaled_height,
        scaled_width,
        [0.0, safe_scale, safe_scale, 0.0, 0.0, 0.0],
        "translate(" + scaled_height.to_string() + " 0) rotate(90)",
      )
    180 =>
      (
        scaled_width,
        scaled_height,
        [-safe_scale, 0.0, 0.0, safe_scale, scaled_width, 0.0],
        "translate(" +
        scaled_width.to_string() +
        " " +
        scaled_height.to_string() +
        ") rotate(180)",
      )
    270 =>
      (
        scaled_height,
        scaled_width,
        [0.0, -safe_scale, -safe_scale, 0.0, scaled_height, scaled_width],
        "translate(0 " + scaled_width.to_string() + ") rotate(-90)",
      )
    _ =>
      (
        scaled_width,
        scaled_height,
        [safe_scale, 0.0, 0.0, -safe_scale, 0.0, scaled_height],
        "translate(0 0)",
      )
  }
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
  if value < 45 {
    0
  } else if value < 135 {
    90
  } else if value < 225 {
    180
  } else if value < 315 {
    270
  } else {
    0
  }
}

///|
fn pdf_page_model(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
  page_number : Int,
) -> PdfPageModel raise @core.PdfError {
  let rectangle = document.parse_rectangle(page.mediabox)
  let items = pdf_items_of_page(
    document,
    page,
    rectangle.min_x,
    rectangle.min_y,
    rectangle.max_y - rectangle.min_y,
  )
  let text = pdf_text_of_items(items)
  let fonts = pdf_font_resources_of_items(document, page_number, items)
  {
    number: page_number,
    origin_x: rectangle.min_x,
    origin_y: rectangle.min_y,
    width: rectangle.max_x - rectangle.min_x,
    height: rectangle.max_y - rectangle.min_y,
    rotation: @page.pdf_page_int_of_rotation(page.rotate),
    fonts,
    items,
    text,
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
fn pdf_items_of_page(
  document : @pdflite.PdfDocument,
  page : @page.PdfPage,
  origin_x : Double,
  origin_y : Double,
  height : Double,
) -> Array[PdfPageItem] raise @core.PdfError {
  let entries = document.content_entries_of_page(page)
  let items : Array[PdfPageItem] = Array(capacity=entries.length())
  for index, entry in entries {
    let bounds = pdf_bounds_of_quad(entry.bounding_box)
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
        ) = match entry.state {
          @pdflite.PdfContentStatePath(state) =>
            (
              pdf_colour_hex(state.colour_non_stroke),
              pdf_colour_hex(state.colour_stroke),
              state.line_width,
              state.line_cap,
              state.line_join,
              state.dash_pattern.array,
              state.dash_pattern.phase,
            )
          _ => ("#202124", "#202124", 1.0, 0, 0, [], 0.0)
        }
        items.push(
          PdfPageItem::Path({
            index,
            bounds,
            svg_path: pdf_svg_path_of_shape(
              drawn.path,
              origin_x,
              origin_y,
              height,
              bounds,
            ),
            filled: drawn.filled,
            stroked: drawn.stroked,
            fill_color,
            stroke_color,
            fill_alpha: 1.0,
            stroke_alpha: 1.0,
            line_width,
            line_cap,
            line_join,
            dash_array,
            dash_phase,
          }),
        )
      }
      @pdflite.PdfContentImageObject(name) => {
        let resource = pdf_image_resource_of(document, page, name)
        items.push(PdfPageItem::Image({ index, bounds, name, resource, }))
      }
      @pdflite.PdfContentInlineImageObject =>
        items.push(
          PdfPageItem::Image({
            index,
            bounds,
            name: "inline-image",
            resource: None,
          }),
        )
      @pdflite.PdfContentShadingObject(name) =>
        items.push(
          PdfPageItem::Shading({ index, bounds, name, resource: None, }),
        )
    }
  }
  items
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

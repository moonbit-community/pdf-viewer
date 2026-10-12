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
  /// Graphics-state pen retained independently of the text matrix.
  stroke : PdfTextStroke?
  /// Existing A1 outline in top-left page SVG coordinates for native fill replay.
  fill_path : String?
  pattern : PdfPatternResource?
  stroke_pattern : PdfPatternResource?
  /// Invocation-scoped BT/ET identity for implicit text knockout groups.
  text_object_id : String?
  /// PDF TK, initially true; applies to the whole text object.
  text_knockout : Bool
  bounds : PdfBounds
  quad : PdfQuad
  font : String
  font_size : Double
  rendering_mode : Int
  fill_color : String
  stroke_color : String
  fill_alpha : Double
  blend_mode : String
  fill_source : PdfSourceColour
  stroke_source : PdfSourceColour
  fill_overprint : Bool
  stroke_overprint : Bool
  overprint_mode : Int
  alpha_is_shape : Bool
  clip_path : String?
  /// Explicit page-space clip intersections, including their winding rules.
  clips : Array[PdfClipPath]
  soft_mask : PdfSoftMaskResource?
  group : PdfTransparencyGroup?
  group_path : Array[PdfTransparencyGroup]
  /// An SVG outline for a Type 3, CFF, Type 1 or embedded TrueType glyph when the browser
  /// cannot use the PDF font's original character mapping.
  type3_outline : String?
  /// Type 3 CharProc paints retained in enclosing page coordinates. Ordinary
  /// CFF/Type1/TrueType outlines do not have a scene.
  type3_scene : PdfPageModel?
  type3_scene_unresolved : String?
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
  tile_page : PdfPageModel?
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
  fill_even_odd : Bool
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
  /// Affine stroke geometry and metrics. The fields above retain their legacy
  /// page-space approximation for consumers that do not use affine strokes.
  stroke : PdfPathStroke?
  /// Non-stroking tiling paint; independent of the stroking colour space.
  pattern : PdfPatternResource?
  /// Stroking tiling paint. Shading patterns are retained for future pixel
  /// backends but are not lowered to SVG strokes yet.
  stroke_pattern : PdfPatternResource?
  shading_pattern : PdfShadingResource?
  blend_mode : String
  fill_source : PdfSourceColour
  stroke_source : PdfSourceColour
  fill_overprint : Bool
  stroke_overprint : Bool
  overprint_mode : Int
  alpha_is_shape : Bool
  clip_path : String?
  /// Explicit page-space clip intersections, including their winding rules.
  clips : Array[PdfClipPath]
  soft_mask : PdfSoftMaskResource?
  group : PdfTransparencyGroup?
  group_path : Array[PdfTransparencyGroup]
} derive(Eq, Debug, ToJson)

///|
/// A stroke in paint-time user space, with y reversed like an SVG path.
/// `transform` maps it into the unscaled, top-left SVG page coordinate system.
/// Width, dash lengths and phase are unscaled user-space values.
pub(all) struct PdfPathStroke {
  svg_path : String
  transform : Array[Double]
  line_width : Double
  dash_array : Array[Double]
  dash_phase : Double
  miter_limit : Double
} derive(Eq, Debug, ToJson)

///|
/// Browser-ready image data for an image XObject.
///
/// Encoded formats keep their original bytes in a data URL. Raw PDF pixel
/// data is converted to a small PNG by the viewer package, so browser hosts
/// do not need to know about PDF colour spaces or filters.
pub(all) struct PdfImageResource {
  name : String
  error : String?
  ink_samples : PdfImageInkSamples?
  has_local_mask : Bool
  alpha_is_explicit_shape : Bool
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
  /// Source-domain samples and patch geometry for a per-pixel host renderer.
  raster : PdfShadingRaster?
  pattern_state : PdfShadingPatternState?
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
  /// Nonstroking Pattern paint retained only for stencil ImageMask images.
  pattern : PdfPatternResource?
  fill_color : String
  fill_alpha : Double
  stroke_alpha : Double
  blend_mode : String
  fill_source : PdfSourceColour
  stroke_source : PdfSourceColour
  fill_overprint : Bool
  stroke_overprint : Bool
  overprint_mode : Int
  alpha_is_shape : Bool
  clip_path : String?
  /// Explicit page-space clip intersections, including their winding rules.
  clips : Array[PdfClipPath]
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
  page : PdfPageModel?
  matrix : Array[Double]
  backdrop : Array[Double]
  backdrop_components : Array[Double]
  transfer_map : Array[Int]?
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
  alpha : Double
  blend_mode : String
  alpha_is_shape : Bool
  bounds : PdfBounds?
  color_space : String
  rendering_intent : String
  icc_profile_id : String?
  calibration : PdfColourCalibration?
  soft_mask : PdfSoftMaskResource?
} derive(Eq, Debug, ToJson)

///|
/// One choice option, retaining its PDF export value and display label.
pub(all) struct PdfChoiceOption {
  index : Int
  export_value : String
  display_value : String
  selected : Bool
} derive(Eq, Debug, ToJson)

///|
/// Additional annotation appearance properties from its own dictionary.
pub(all) struct PdfAnnotationStyle {
  interior_color : String?
  opacity : Double
  icon : String
  line_endings : Array[String]
  caption : String?
  no_zoom : Bool
  no_rotate : Bool
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
  style : PdfAnnotationStyle
  /// AcroForm metadata inherited from a widget's field parents.
  field_name : String?
  field_type : String?
  field_value : String?
  field_flags : Int?
  field_options : Array[String]
  choice_options : Array[PdfChoiceOption]
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
  blend_space : String
  blend_profile_id : String?
  blend_calibration : PdfColourCalibration?
  icc_profiles : Array[PdfIccProfile]
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
/// Text content exposed in the shape used by browser PDF viewers.
pub(all) struct PdfTextContent {
  items : Array[PdfTextItem]
  text : String
} derive(Eq, Debug, ToJson)

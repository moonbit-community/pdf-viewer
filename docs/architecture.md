# Renderer architecture

The project is split around the same boundary that makes pdf.js testable:

```text
PDF bytes
  │
  ▼
pdflite reader/content entries
  │
  ▼
PdfViewerDocument ── page(n) ── PdfPageModel
                                  ├─ PdfViewport
                                  ├─ PdfTextContent
                                  ├─ PdfPageItem display list
                                  └─ selection mapping
  │
  ▼
SVG renderer / browser DOM text layer / future Canvas renderer / host adapter
```

`pdflite` owns PDF syntax, xref recovery, resources, font decoding, content
operators, and image decoding primitives. The viewer package owns the stable
host-facing model and coordinate conversion. This keeps an OpenSeek adapter (or
a future Rabbita browser shell) from depending on `pdflite` internals.

The first renderer deliberately serializes a display list instead of drawing
directly while parsing. That gives us three independently testable results:

1. page geometry and rotation;
2. positioned text and selection order;
3. SVG paint output.

Text items retain the original `pdflite` quadrilateral in addition to their
axis-aligned bounds. This lets SVG preserve a glyph run's direction while the
bounds remain convenient for cursor selection. Path items likewise carry the
PDF line cap, line join, and dash state needed by an SVG host.

Text paint mode and source fill/stroke colours are retained as part of each
text item. Path line widths and dash spacing are scaled by the affine paint
CTM before serialization; this is exact for uniform transforms and uses the
mean basis-vector scale for shears and non-uniform transforms.

Embedded TrueType fonts have a second rendering path. The viewer reads the
`head`, `maxp`, `loca`, and `glyf` tables, resolves a CID through
`CIDToGIDMap`, and lowers simple or composite glyph outlines into SVG paths.
This is needed for CID fonts whose embedded program has no browser-usable
Unicode `cmap`; the original font data is still emitted as a resource for
hosts that can use it. Filtered CIDToGIDMap streams are decoded before glyph
lookup. Vertical geometry is computed from the same text matrix and signed
advances as painting and clipping; no separate quad-direction correction is
applied afterwards.

Simple TrueType fonts resolve Encoding/Differences separately from ToUnicode.
The viewer selects a Windows Unicode/Symbol or MacRoman cmap before calling
`mizchi/font` 0.7.4's standalone `parse_cmap` for formats 0/4/6/12. Legacy format
2 is bounded and normalized into that decoder's format 12 input. MacRoman
glyph names use pdflite's reverse encoding lookup; supplementary scalars use
full-repertoire Unicode tables. Declared table bounds, segment/range ordering,
glyph IDs and expansion counts are checked before the library reads bytes.
Missing mappings in a selected table may recover through explicit post names;
unresolved mappings remain GID 0. Missing/unusable tables retain the existing
raw-GID recovery after trying post. A bounded shared cache holds only cmap
bytes and decoded mappings: eight entries, 1 MiB input and 262,144 mappings.
It retains no complete font or PDF document. General font parsing and outlines
still use the existing recovery paths because PDF subsets can omit tables.

`truetype_post.mbt` reuses the same library's standalone `parse_post` for version
2 names and supplies equivalent indices for versions 1 and 2.5. Signed version
2.5 offsets are checked against the library's Macintosh name catalog. Version
3 supplies no names. Counts and Pascal strings are checked within the declared
table before library reads. A separate cache retains at most eight post tables,
1 MiB of source and 131,072 names, keyed by table bytes and maxp glyph count.
The first matching name must select a nonempty glyph within loca/glyf bounds.
Windows/Symbol cmap mappings retain priority; Unicode-platform cmaps prefer
explicit Encoding/Differences names. Unknown names without usable post names
may recover through an explicit ToUnicode entry. Known Encoding names continue
to select independently of copied Unicode; PDF advances and matrices are kept.

`font_stream_recovery.mbt` reuses pdflite's pinned
`moonbit-community/flate` 0.8.1 engine for font programs, CIDToGIDMap and CMaps.
The strict decoder remains first; a complete zlib body/trailer with an
Adler-32 mismatch may be recovered by a bounded raw decode using that engine.
Invalid headers, dictionaries and truncated/invalid DEFLATE remain failures.
Recovery accepts one Flate filter without a transforming predictor, at most
4 MiB compressed input and 16 MiB output. Its shared cache retains only bytes,
with eight entries, 8 MiB input and 16 MiB output. These limits describe the
recovery path; pdflite's normal decoding limits are unchanged. ToUnicode retry
uses a shadow font dictionary so painting and copying share the recovered
descriptor. No source stream is changed. Opt-in document diagnostics report
`FontStreamChecksumRecovered` with the stream's resource path/object number,
including inherited CMap streams; completing DEFLATE does not prove that the
recovered bytes equal the producer's original bytes.

Text paint geometry is carried separately as `glyph_transform`: a one-em,
y-up glyph coordinate system mapped to PDF page coordinates, including CTM,
the per-glyph text matrix, font size, horizontal scale, rise, and vertical
origin. TrueType contours use this matrix and units-per-em normalization.
Fitting a font-wide BBox to a glyph's advance rectangle incorrectly squeezes
narrow letters. SVG fallback text uses the same matrix at font-size 1 and an
alphabetic baseline, so font selection/selection metrics cannot move a
FreeText appearance below its own clipping box. Host-built items may omit
the matrix and retain the older quad-based fallback.

Embedded CFF fonts are decoded into glyph outlines as well. The parser handles
raw CFF and OpenType `CFF ` tables, standard and expert encodings, Name-keyed
and CID-keyed charsets, FDArray/FDSelect, private dictionaries and subroutines,
and the Type 2 charstring operators used by the tested fonts. Parsed outlines
are cached per embedded font and glyph. Single-byte Type 1 programs are also
decoded in the viewer: eexec and PFB framing, ASCII-hex eexec, charstring
encryption, direct-index subroutines, `seac`, and common flex othersubrs are
supported. Hint-replacement OtherSubrs retain arguments for `pop`/`callsubr`;
flex points use relative displacements from the current baseline, following
the pinned PDF.js parser. This restores all 1,549 previously missing embedded
outlines on `tracemonkey.pdf` page 1. Single-FD CID-keyed Type 1 programs are also decoded from Binary/Hex
`StartData`, including CIDMap, SubrMap, `lenIV`, and empty-CID fallback.
Counted `1 array` FDArray declarations and headers without an FDArray
declaration are supported; other FDArray declaration forms use text fallback.
Multiple FDArray entries remain on the text fallback path. CMap-to-CID mapping
is shared with the TrueType and CFF paths.

When an embedded Type 1 program still has a glyph the native parser cannot
lower, SVG text fallback uses the font's family metadata. Nimbus Roman and
Computer Modern Roman/symbol names map to serif, CMTT/Nimbus Mono to
monospace, and medium/italic/slanted suffixes are retained. This improves the
fallback shape without claiming that host metrics equal the PDF font; the
selected visual baseline still tracks unresolved glyphs and raster differences.
Explicit PDF Encoding names select the CFF charset or `.notdef`, avoiding an
unrelated built-in encoding glyph. Damaged charstrings/programs retain copy
text, PDF advances and the remaining page, with located fallback observations.

`cid_mapping.mbt` resolves Identity, Adobe predefined and explicit external
CMap entries without using ToUnicode values as glyph CIDs. Explicit entries
and inherited mappings take precedence over notdef fallback. An unmapped code
without an inherited CMap uses CID 0. `text_layout.mbt` routes all CID text
operators through `cmap_text.mbt`. It decodes the reader's codespaces from one
to four bytes, choosing the shortest match and comparing four-byte ranges as
unsigned values. Named inherited codespaces are used when no local ranges
exist. Invalid or truncated codes consume one byte and preserve following text.

`cid_geometry.mbt` indexes `/W`, `/DW`, `/W2` and `/DW2` by the mapped CID and
computes placement directly using pdflite's matrix/metric types. Default
vertical origins use half the horizontal width; vertical displacement retains
the sign of W2/DW2 independently of that width. The original code and source
bytes drive Unicode extraction, and only a source one-byte 0x20 applies word
spacing. The original parsed font remains unchanged. One layout pass provides the
entries, glyph transforms, selection bounds, text clips, and next text matrix,
including consecutive `Tj`, `TJ` adjustments, and quote operators. The public
Int charcode preserves the bit pattern of unsigned four-byte values; original
byte spans remain internal. Complex external-stream inheritance and
reader-lost codespaces remain outside this correction.

`binary_cmap.mbt` decodes the binary CMap format from the pinned PDF.js
reference. `builtin_cmap_assets.mbt` embeds 168 Adobe mapping assets, with
licenses retained in `assets/cmaps/`; `tools/cmap_assets.mbtx` regenerates them
after checking the reference revision. `builtin_cmap.mbt` loads and caches
individual maps on demand, follows named inheritance for CID lookup,
codespaces and WMode, and supplies Adobe CID-to-Unicode data when ToUnicode is
absent. Local mappings and WMode take priority over the named base.

`font_recovery.mbt` uses the pinned reader through bounded font dictionaries.
Local shadows retain valid Differences, widths and descriptors; invalid fields
use documented fallback metrics or a replacement font without changing source
objects. Missing Tf resources retain the active binding. Malformed or absent
ToUnicode entries try the PDF Encoding extractor; empty mappings and literal
U+FFFD remain valid. CID W/W2 clauses are bounded before the dependency expands
them. Large CMap ranges stay in the existing lazy representation, with local
mapping and original code bytes preserved; parent traversal stops at 64 links.
Prepared stream dictionaries prevent reference-alias cycles entering decoding.

Text rendering modes 4–7 collect glyph outlines while a text object is read;
the combined path becomes active at `ET`. Later text-object clips are
intersected, and the collector saves/restores them with `q/Q`. Form XObjects
inherit the active clip while keeping their local text clips inside the Form.
Each text-object clip is resolved once and shared by subsequent page items.
The current path reconstruction covers CFF, single-byte and single-FD CID-keyed
Type 1, embedded TrueType and bundled Standard 14 outlines;
when a glyph outline cannot be decoded, the renderer leaves that clip
unavailable instead of treating the missing glyph as an empty path. Type 3
fonts do not contribute to this clip, as required by PDF text semantics.

`PdfPageModel::viewport` follows pdf.js' `PageViewport` affine matrix,
including nonzero page origins and `/UserUnit`. The requested `scale` remains
separate from the public `user_unit` field, while matrix coefficients and
dimensions use their product. The SVG renderer uses the equivalent relative
transform after subtracting the page origin from display-list coordinates, so
the public viewport matrix and rendered page stay in the same coordinate
convention. Invalid or disjoint CropBox values fall back to the effective
MediaBox, and malformed MediaBox values use the PDF.js letter-size fallback.

The current renderer has several concrete compatibility improvements: it emits the pdf.js-style
full viewport matrix, lowers path-only coloured tiling patterns to SVG `pattern` definitions,
and applies a retained `/Matrix` at the paint site. ShadingType 4/5/6/7 streams are decoded into
`PdfMeshTriangle` records; PatternType 2 resources are clipped to their source path, while the
SVG fallback uses barycentric microtriangles and leaves per-vertex colours available for a future
Canvas/WebGL Gouraud renderer. Explicit clipping paths are serialized as
nested clip paths so each additional path narrows the previous clip instead of becoming a union.
Their definitions carry the output scale, just like the paints they wrap;
leaving them unscaled cuts off zoomed glyphs and images. All clip intersections
use the same page-relative coordinate convention before the outer rotation.
PDF ImageMask, colour-key `/Mask`, image `/SMask`, and common Form soft-mask resources are lowered
to browser-ready mask images. A nested SVG applies image masks before the outer affine transform,
while page-space soft-mask definitions retain their `/BBox`, backdrop sample, and transfer-map
output. Adjacent items with the same soft mask are now emitted inside one SVG compositor group,
so the mask is applied to the accumulated source paint. Form XObject transparency dictionaries
are also read into each flattened item, preserving the source group id and its isolated/knockout
flags, including a `group_path` for nested Forms. SVG maps isolated groups to
`isolation:isolate`; a future canvas/WebGL compositor can use the data attributes for
non-isolated backdrops and knockout. Exact backdrop and knockout pixel compositing remains
outside the current SVG lowering.

Colour conversion lives in `colour.mbt`. Paints carry the declared
`PdfColourSpace`; component count never selects a conversion implicitly.
The content adapter resolves `CS/cs` in the active resource scope, initializes
that space's default samples and keeps `SCN/scn` fill/stroke pattern slots
independent. Pattern cells and Form soft masks use the same viewer content
collector as pages, including nested Form scopes. Paths expose separate
`pattern` and `stroke_pattern` resources. SVG lowers tiling strokes, while
shading-pattern strokes and complex pattern text/compositing remain pending.

CalGray, CalRGB and Lab use the pinned PDF.js curves, primary-matrix column
order and output transforms. CalRGB includes white-point normalization and
black-point compensation. CMYK uses PDF.js' fitted SWOP fallback; ICCBased
uses its declared alternate, not an ICC profile engine. Indexed lookup values
are expanded into their base space's component ranges. Separation/DeviceN
tint functions are prepared before repeated image/mesh sample conversion.
Rendering intent is not applied, matching the pinned PDF.js canvas behavior.

For raw images, `image_colour.mbt` asks pdflite to decode filters/predictors,
then reads byte-aligned rows of 1/2/4/8/16-bit original samples. Colour-key
mask comparisons happen before `/Decode` and conversion; the output is an
RGB/RGBA PNG. Encoded JPEG/JPX/JBIG2 and ImageMask retain their separate paths.
Matte, exact resampling, encoded-image colour management and large-image
allocation policies are still open. Viewer reader recovery also tolerates
legal comments between `endstream` and `endobj` when page content was dropped,
using declared stream lengths and the active xref chain rather than scanning
old revisions for deleted content. The raw-byte recovery is skipped for
authenticated encrypted documents with unresolved page contents.

`reader_page_tree.mbt` first uses pdflite's strict xref reader when its catalog
is available, avoiding the high-level reader's deep recursive page-tree probe on
cyclic input in JavaScript. pdflite still owns reconstruction and password
decryption. The viewer validates reference aliases and page-tree traversal
before pdflite materializes inherited page attributes. Traversal has a 256-level and
131,072-node limit. `reader_page_recovery.mbt` copies the document's object store,
removes invalid branches, and preserves retained page/font/content object IDs
and stream backing. `reader_diagnostics()` records original paths and node IDs;
if no page survives, the located original error propagates. This eager recovery
reports the surviving page count, unlike PDF.js's lazy failure for a bad page.

The standalone browser shell lives in `web/`, with a MoonBit JS bridge in
`cmd/browser/`. PDF bytes are decoded entirely by the MoonBit/pdflite module;
the JavaScript shell handles file input, DOM mounting and native browser
selection. `web/pdf-client.js` sends asynchronous operations to the native
module Worker in `web/pdf-worker.js`; the generated MoonBit bridge runs there.
The bridge includes `open_pdf`, `render_page`, `render_print_page`, `select_text`, `select_page_text`,
`search_pdf`, `document_info`, `page_layouts`, `cache_info`, downloads and close.
Page models use an LRU budget of eight pages/estimated 32 MiB; serialized render
responses use twelve entries/24 MiB. These bounds exclude parsed input and
temporary decoding. Closing/replacing a document terminates its Worker and
rejects outstanding work. AbortSignal removes queued tasks and discards active
results; a synchronous active operation can finish before the next RPC. The
host contract does not reproduce PDF.js loading/render task objects. Embedded
font families receive page prefixes so multiple SVGs do not replace
each other's @font-face rules. Rendering an already decoded page uses
`PdfPageModel::render_svg`.

The browser document panel consumes one `document_info` response containing
flattened outline destinations, display page labels, Info fields, attachment
metadata and XMP availability. Attachment and XMP bytes are requested by
index/on demand and converted to local browser downloads. Local outline targets
scroll to their one-based page; unresolved or remote targets stay disabled.
The shell also exposes thumbnails, print, continuous/single-page modes and a
`#page=N` history state. `PdfViewerDocument::page_viewport` and `page_layouts`
resolve geometry without interpreting content. `web/page-scheduler.js` keeps
those page boxes and uses IntersectionObserver to mount nearby paint/text DOM;
thumbnails use a separate visible-row observer. Scale/rotation cancels the
previous layout generation, and stale results cannot mount. Source selection
pins only its endpoints and neighbors, rather than every selected page.

`PdfViewerDocument::search` consumes the same page text/content model as
selection. It returns source UTF-16 offsets, original matched text, source item
indices and a union bounds rectangle. Unicode 16 NFKD, lowercase and general
categories come from pinned `normalization`/`ucd` packages. Each normalized
code unit retains its source interval through expansions and canonical mark
reordering; offsets never refer to the normalized string. The browser maps
item indices to its transparent text layer and emits `pdf-search-change`.
Search runs asynchronously through the Worker adapter; the underlying MoonBit
operation remains synchronous. Exact substring highlighting and complete
locale/case-fold policy remain future work.

`text_columns.mbt` partitions persistent horizontal-page gutters into reading
blocks before line grouping. `text_bidi.mbt` maps `bidi` code-point permutations
to complete glyph items, preferring source order when its forward UAX #9
projection matches geometry. A recovered visual-order candidate must pass the
same check. Ambiguous/split-glyph permutations preserve source order. Baseline
projection handles rotated/sheared blocks without changing original quads;
aligned compact tables read by row, long prose by column. Explicit bidi controls
and cross-direction gaps share the same separator/source calculations. Untagged
paragraphs and short tables remain geometric heuristics.

`text_sources.mbt` shares source UTF-16 ranges with search and the additive
`PdfPageModel::text_sources()` sidecar. Inferred separators have no source item.
`text_provenance.mbt` joins these logical ranges to decoded string-operand byte
ranges and available embedded-font CID/GID or Type1/Type3 names. Its collector
hook is opt-in: `text_provenance_collect.mbt` uses the existing CMap decoder and
tracks stream-reference scopes, Form invocation paths and the active font
object through Tf, gs, q/Q and implicit Form frames. `text_provenance_fonts.mbt`
reuses the existing TrueType/CFF/Type1 selectors, with a local program cache per
inspection. This decoded-operand API does not infer file lexical offsets or host-font GIDs. Empty
copied glyphs stay outside logical sources; their bytes still contribute to
following operand offsets. Public page and text records remain unchanged.
`text_lexical.mbt` adds `text_lexical_sources(n)` using pdflite's syntax lexer,
object parser and content-op parser. Escapes/hex spelling are checked against
the decoded operands and every operator is checked against the interpreter's
parse; inline-image EI candidates are accepted only by that parser. Glyphs
with empty copied strings retain origins here. A lazy stream's backing bytes
must match the original input before its encoded payload span is exposed;
file glyph spans additionally require no filters and identity crypt. Compressed
and encrypted streams retain decoded spelling and, when known, the whole encoded
payload range. In-memory replacement streams cannot claim original offsets.
The opt-in adapter bounds decoded input to 8 MiB, operations and mapped bytes
to 262,144, and inline-image candidates to 128; unverified spans have an explicit
failure instead of preventing rendering. The original input is retained by
reference, without an additional byte copy.
`text_structure.mbt` groups the same logical glyphs into font/baseline runs and
geometrically inferred paragraphs. Their UTF-16 ranges and source items join to
selection/search; separators have no fabricated glyph owner. This view does not
claim tagged-PDF semantics or change the original display list.
`text_diagnostics.mbt` exposes observed render fallbacks and replacement text;
`text_recovery_diagnostics(n)` additionally reads encoding/metrics/dictionary,
Unicode, invalid-code and font/CMap stream observations through the same active
bindings as painting. Empty copied glyphs retain operand bytes with no fabricated
logical interval. The old document method projects records with logical sources.
Both methods are opt-in and may rebuild a page; resource-level observations do
not establish per-glyph corruption. Stream paths and immediate object IDs locate
checksum recovery or unavailable bytes, including inherited CMaps.

`text_layer.mbt` maps the actual glyph quads through the public viewport and
retains source item indices. A layer item carries a unit-square affine matrix;
the browser normalizes its basis onto a rectangle with a normal CSS font size.
Using a 1px font and scaling it up looked correct under programmatic Range
selection but failed real Chromium mouse drag. Normal CSS glyph rectangles,
fitted text advances and DOM-order separators make native drag and copy work
with outline rendering as well. Font measurements are cached, and inline style
values are reused to avoid repeated synchronous layout during a multi-page
mount.

`PdfPageModel::select_text` normalizes cursor endpoints, validates UTF-16
boundaries, and returns source quads and item indices. The browser combines
these page ranges, attaches available file information and emits
`pdf-selection-change`; it restores ranges after zoom/rotation. Partial
ligatures retain a complete source glyph quad, and raw PDF byte spans are not
claimed. The writing-direction separator heuristic is independent of page
rotation; complex reading-order/bidi reconstruction still needs coverage.

The browser combines source ranges from unloaded pages through the Worker, so
whole-document selection/copy does not require mounting every text layer.
Native selection text reflects mounted DOM; `pdf-selection-change` and copy
retain the complete source range. Print preparation separately renders all
pages at their physical point sizes, waits for fonts/images, and clears that
temporary DOM after printing. Use the toolbar or Ctrl/Cmd+P for this asynchronous
preparation. Cache and sampled heap evidence is in
[validation.md](validation.md#browser-host-lifecycle-scheduling-and-pressure).
The body text layer does not reconstruct annotation appearance streams or
readonly widgets as DOM. `web/annotation-layer.js` independently mounts links
and comment controls over viewport-transformed rectangles/quads. Collapsed
clicks open markup comments while native drag-selection passes through.
Its popup lives outside clipped page boxes and is cleared on unmount, repaint,
scrolling or document close. Native anchors handle URI links; local destinations
and named page/history actions use the viewer navigation state. Unknown/remote
targets stay disabled. The visual SVG is inert to avoid duplicate interactive
links. Widget editing remains outside the readonly layer.

The validation renderer is separate from the standalone viewer. A temporary
loopback server in `tools/visual_test.mbtx` serves the pinned PDF.js build and
the same MoonBit browser bridge to an isolated Chromium profile. It captures
actual rendered DOM pages rather than converting SVG through an Image element,
so embedded fonts follow the viewer's rendering path. Pixel comparison runs
in MoonBit (`tools/pixels/`, `cmd/visual_diff/`) and never rescales either page.
Both original images, raw RGBA, a heatmap, viewport/text diagnostics, fixture
hashes, the browser version and the host font list are retained. Symmetric 1px
neighborhood matches are diagnostic candidates; they do not excuse raw errors.
Strict mode rejects differences, while measurement errors always fail the run.
The contract test deliberately shifts a visible control and removes an input
to verify that the harness cannot pass an empty or failed operation.

The A1 font/text main paths are complete; measured differences and retained
fallback branches are recorded in [validation.md](validation.md#a1-completion-validation).
The remaining implementation stages are ordered by the visible compatibility gap:

1. Larger visual/large-document baselines and CI, retaining measured
   font rasterization differences and fallback observations;
2. CTM-preserving path/image geometry, complete group-level mask compositing, and pixel-level
   Gouraud interpolation for mesh triangles;
3. complete annotation appearance and form/widget layers;
4. Canvas/WebGL output and incremental page loading for large documents.

The complete feature backlog and acceptance rules live in
[`TODO.md`](TODO.md). The two current core workstreams, text/fonts and
graphics/images, are recorded in [`PARALLEL.md`](PARALLEL.md). Font resources,
Type 3 glyphs, SVG text output and text selection have been moved unchanged to
`font_resources.mbt`, `type3_outline.mbt`, `svg_text.mbt` and
`text_selection.mbt` within the existing root package. Multiple-FD CID-keyed
Type 1 is an extension rather than a parity requirement: the pinned PDF.js
Type 1 parser also supports only one FD.

Annotation parsing and SVG lowering live in `annotations.mbt` and
`annotations_svg.mbt`. The viewer reads the original `/Annots` array: popup
children and malformed annotations are skipped without renumbering valid source
indices. PDFDocEncoding/UTF-16 strings, normalized `/C` components, quads, lines,
vertices, ink paths, and display/print flags are retained independently of the
fallback drawing.

`annotation_layer.mbt` provides lightweight `annotation_layer_json(n)` without
interpreting AP streams; original annotation indices join interaction data to
paint. It reuses the document's pdflite objects and destination model, bounds
named/dictionary resolution to 32 steps and preserves unresolved/remote targets.
`PdfPageModel::with_print_annotations()` clones only the annotation visibility
decisions, selecting Print independently of screen NoView. Browser print uses
`render_print_page` with a separate render-cache key; body paint stays shared.
Interaction/intent evidence and retained AP/icon limits are recorded in
[validation.md](validation.md#readonly-annotation-interaction-and-print-intent).

Normal appearance streams reuse the content collector with their own resource
dictionary and BBox. The fragment is clipped to its source box, then mapped
through `/Matrix` into `/Rect`; a zero-area transformed BBox uses the PDF
translation fallback. Item IDs are allocated after page content and preceding
appearances, avoiding SVG reference collisions. Appearance fonts are resolved
at each text paint site, including nested Form scopes, and embedded programs
receive appearance-specific CSS family names. The outer transparency group
preserves isolation/knockout metadata with the same compositing limits as page
Forms. A valid empty stream suppresses geometry fallback.

Widget metadata distinguishes inherited field values from each radio/checkbox
on-state and checked state. The current fallback is a simple read-only display;
it does not implement `/DA`/`/DR` layout, multiline/comb/password formatting,
choice selection or export mappings, editing, or JavaScript actions.

Document navigation/metadata methods adapt pdflite reader outputs without
claiming the pdf.js JSON schema. The viewer resolves both the legacy catalog
`/Dests` dictionary and the `/Names` `/Dests` name tree into `PdfDestination`.
It preserves the view parameters of `XYZ`/`Fit`-family destinations, maps local
page objects to one-based page numbers, and marks remote targets instead of
silently treating them as local. `named_destinations`, `named_destination`,
`destination_for_page`, and `outline_navigation_json` are library-level APIs;
the browser adapter consumes them for its directory and information panels.
Page labels provide a decimal fallback even when pdf.js would return null. Optional-content
configuration is applied during display-list collection: `/OC` marked content,
common OCMD policies and Form `/OC` entries are resolved against the selected
`PdfOptionalContentState`, so hidden paint never reaches the page model or text
selection. Usage-category controls and a browser layer panel remain host
features.

The current SVG path already handles image XObjects and inline images. Inline payloads
are collected with `parse_content_ops_with_resources`, including images nested in Form
XObjects, then passed through pdflite's colour-space/filter decoder. Axial, radial, and
function shading resources are sampled into SVG gradients. Basic alpha and blend mode
state is tracked in a parallel content walk because the compact pdflite JSON entry does
not expose those fields.

Each stage should add a narrow fixture from the pinned pdf.js corpus under
`reference/pdf.js/test/pdfs` and a MoonBit test that checks the structural
output before adding pixel or browser-level assertions. `tools/corpus.mbtx`
builds and runs the native CLI with per-file timeouts and fresh artifact paths,
checks error exit codes and SVG creation, and writes a JSON report. These are
selected-page conversion checks (page 1 by default), not visual conformance tests. The measured result
and known failures are recorded in `docs/validation.md`.
`tools/browser_test.mbtx` uses Chromium's DevTools protocol from MoonBit,
verifying native mouse/keyboard selection, source ranges, local file input,
error recovery and zoom/rotation across real fixtures. It captures screenshots
and records passed checks. This is interaction verification.
`tools/visual_test.mbtx` adds selected-page PDF.js pixel/viewport/text comparison;
coverage grows with each rendering feature, and does not yet include every
feature in the backlog or the entire upstream corpus.

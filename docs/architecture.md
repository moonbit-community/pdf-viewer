# Renderer architecture

## Package boundaries

The root package is a facade containing `api.mbt`, its `moon.pkg` and the generated
interface. It re-exports the existing eight functions and 65 types from the PDF
engine. Applications continue to import `moonbit-community/pdf-viewer`; methods,
fields and function parameters remain available through that entry point.

| Directory | Responsibility |
| --- | --- |
| `internal/engine/` | Document/page models, content collection, fonts, text, graphics, editing and whitebox tests |
| `internal/cmap_assets/` | Generated, pinned Adobe CMap bytes |
| `internal/font_assets/` | Generated, pinned Standard 14 font programs |
| `tests/api/` | Consumer tests that import the root facade |
| `codecs/` | Existing JPX and JBIG2 codec packages |
| `cmd/` | Reader CLI, browser bridge and Rabbita application |

Production dependencies run from the facade to the engine, then to resource and
codec packages. Internal packages never import the facade in production; the
engine imports it only for documentation tests. Models and their methods remain
in the same compilation unit, keeping implementation helpers private instead of
exporting them across artificial package boundaries.

Within the engine, `model.mbt` holds shared page data, `document.mbt` handles the
document API and opening, `page_api.mbt` defines viewport/page methods, and
`collector.mbt` assembles page models. Content-operator interpretation lives in
`collector_entries.mbt`, page-item lowering in `collector_items.mbt`, and graphics
state and Form-group resolution in `collector_state.mbt`. SVG serialization is
organized by traversal, paths, images, shading and clipping; Type 1 fonts separate
program parsing, CharString execution, encoding and outline entry points. These
remain files in the same package, with unchanged helper visibility and callers.
The [engine source map](../internal/engine/README.md) lists their responsibilities.
Public enum constructors should be qualified through the exported type,
for example `@pdf.PdfPageItem::Path(item)`; package-level shorthand such as
`@pdf.Path(item)` is not forwarded by a type re-export.

## Rendering flow

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
Canvas plan → shared Canvas2D runtime / SVG compatibility / DOM text layer
```

`pdflite` owns PDF syntax, xref recovery, resources, font decoding, content
operators, and image decoding primitives. The viewer package owns the stable
host-facing model and coordinate conversion. This keeps the Rabbita browser
interface and an OpenSeek adapter from depending on `pdflite` internals.

The collector retains a display list instead of drawing directly while parsing.
That gives us independently testable page geometry, positioned text/source
selection, a structured `PdfPageModel.canvas_plan()` and SVG compatibility output.
The shipped page/thumbnail pixel path is the Canvas plan replayed by
`web/pdf-runtime.mjs` / `web/pdf-canvas.mjs`; it does not rasterize a completed
page SVG. Public entry points, capability limits and focused evidence are in
[the A2 acceptance record](a2-acceptance.md).

Text items retain the original `pdflite` quadrilateral in addition to their
axis-aligned bounds. This lets SVG preserve a glyph run's direction while the
bounds remain convenient for cursor selection. Path items likewise carry the
PDF line cap, line join, and dash state needed by an SVG host.

Text paint mode and source fill/stroke colours are retained as part of each
text item. Canvas plans preserve full paint CTMs and independent affine pens,
including width, dash, caps, joins and miter, instead of collapsing a shear or
non-uniform transform to a scalar line width. Embedded and bundled Standard 14
contours share A1 glyph placement. Legacy SVG text may approximate an unresolved
host pen; that capability loss remains explicit in graphics diagnostics. See
[Standard 14 pens](validation/standard14-pen.md) and
[the host-outline boundary](validation/host-text-pen.md).

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

A1's `internal/engine/standard14.mbt` and `internal/font_assets/assets.mbt` reuse the existing CFF and
TrueType readers for fixed Standard 14 replacement programs, with AFM/PDF widths
preserving positioning. Embedded PDF programs remain preferred. A matching
`PdfFontFallback` / `set_font_fallbacks` override deliberately suppresses bundled
Standard 14 programs and contours, selecting host text instead. Its family,
weight and style affect SVG host text and the text layer, not only CSS metadata.
Clearing the override invalidates the page cache and restores bundled contours.
Independent non-similarity strokes of host text without contours still require
a capable optional `resolveTextOutline` callback; strict replay rejects the
unresolved case and warned preview retains its diagnostic. The default bundled
path needs no native callback or host font registration. See
[the asset provenance](../assets/standard14/README.md) and
[the public-path regression](validation/standard14-pen.md).

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
reference. `internal/cmap_assets/assets.mbt` embeds 168 Adobe mapping assets, with
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

Complete document views own a bounded parsed-font/CMap cache shared by public
page models, browser preparation and accessibility collection. It admits at
most 128 indirect fonts and 256 completely resolved CMaps, with a combined
8 MiB conservative metadata charge. Embedded font programs and Type 3 resource
objects remain references to the existing document. Direct dictionaries,
missing font dictionaries, unavailable CMap sources and cyclic inheritance
results are not retained across builds. CMap inheritance always resolves with
a fresh cycle guard before a top-level result can be admitted. Font fallback
and optional-content views share policy-independent parsed metadata; page
resources and paint state remain local. Editor/XFA snapshots and newly opened
documents receive fresh caches. Range views disable document sharing because
their object store can still change during hydration; a page build can retain
up to 128 CMaps with a separate 2 MiB transient budget. Full caches keep the
original parsing behavior without admitting more entries.

`syntax_keys.mbt` reuses immutable dictionary-key bytes through a native JS
Map, admitting at most 256 keys of at most 96 UTF-16 code units. Misses use the
original MoonBit UTF-8 encoder; native and Wasm targets retain their original
key construction. CMap grammar keywords are byte literals, so matching them
needs no runtime encoding. Accessibility traversal resolves children before
excluding an empty branch on another page, preserving descendant `/Pg`
overrides and traversal budgets while deferring unused role/text/attribute reads.

Opaque, unscaled 8-bit ICC RGB rows begin with a validated JS typed-array copy
and patch only pixels whose exact converted bytes differ from the raw source.
This does not assume that the profile or Decode is an identity: the same CMM,
clipping, rounding and failure fallback still determine every output pixel.
Other targets keep the original per-pixel writes. `byte_copy.mbt` validates
source/destination ranges without overflowing before using `TypedArray.set`;
its non-JS implementation delegates to the original core copy. Direct RGB rows
use the same copy helper, and overlapping JS ranges retain memmove semantics.

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

`canvas_plan.mbt` retains winding-rule clip stacks, delayed W/W*, empty clips,
Form intersections, images, original colour components, glyph outlines, affine
pens and nested scene resources. `graphics_diagnostics()` exposes capability
issues. The Canvas backend returns straight RGBA8 surfaces; PDF group work uses
premultiplied surfaces with independent shape and alpha. It implements isolated
and nonisolated backdrops, knockout, nested groups, process/ICC blend spaces,
text TK and all 16 PDF blend modes. Alpha/Luminosity soft masks retain their
installation CTM, BBox, BC in group space, TR and image-local precedence.
The [compositing report](a2-compositing-validation.md) records pixel evidence,
resource limits and reference disagreements. SVG retains explicit compatibility
approximations; its isolation/data attributes do not implement the Canvas model.

Pattern cells reuse the page content collector and active resource scopes.
Independent `pattern` and `stroke_pattern` paints retain coloured/uncoloured
base paint, base matrix and signed lattice. Complete cell plans include text,
images, Forms, groups and clips; each tile receives the actual parent backdrop.
Type 3 scenes reuse the same structured replay. PatternType 2 fill and stroke
also replay their own ExtGState/Background/mask through the shared compositor.
See [pattern stencils](validation/image-patterns.md),
[Type 3 scenes](validation/type3-scenes.md) and
[shading patterns](a2-shading-pattern-validation.md).

ShadingType 1–7 keeps functions and original sample-space components. The pixel
painter interpolates those components before Function/colour conversion,
including Gouraud, Coons/tensor, axial/radial Extend, two-dimensional functions,
adaptive checked lookup and device-space tessellation. Unsupported or excessive
sampling fails explicitly. Legacy SVG gradients/microtriangles remain an
approximation, not a deferred Canvas implementation. See
[the shading record](a2-shading-validation.md).

The shared colour modules retain the declared `PdfColourSpace`, source samples
and active resource scope; component count never selects a conversion implicitly.
`CS/cs`, Default colour resources and independent fill/stroke slots propagate
through pages, pattern cells and masks. CalGray/CalRGB/Lab and the device-CMYK
SWOP display fallback remain available. Actual LittleCMS ICC transforms add
source/target profiles, Range, rendering intent and PDF/X OutputIntent handling.
JS uses the locally staged extraWasm engine; native Linux loads LittleCMS2
dynamically.
Standalone Moon Wasm/Wasm-GC has no ICC host imports and uses the declared legal
Alternate with explicit capability. `icc_capability()` reports support and
`clear_icc_transforms()` releases active cached transforms. Indexed, complete
Separation/DeviceN tint/domain, None/All and process OP/OPM share these paths;
physical spot proofing requires a matching profile. See
[the colour record](a2-colour-validation.md) and
[LittleCMS assets](../web/vendor/lcms-wasm/README.md).

The image pipeline retains original samples for `/Decode`, colour-key `/Mask`,
SMask/explicit-mask precedence, embedded alpha and Matte before final colour
conversion. Raw 1/2/4/8/16-bit samples, row padding and encoded JPEG/JPX/JBIG2
join the same bounded PNG/RGBA path, including affine sampling and downsampling.
[JPEG](jpeg-decoder.md) and [JPX](../codecs/jpx/README.md) use MoonBit decoders;
[JBIG2](../codecs/jbig2/README.md) uses JS-hosted PDFium Wasm or isolated native
Linux decoding. Unsupported hosts fail explicitly rather than forwarding
unrenderable compressed media to the browser. Allocations, resource recursion
and caches are bounded, but these limits are not a whole-document RSS guarantee
or a synchronous-JS hard-cancellation promise. Real samples and retained edge
residuals are in [image sampling](validation/image-sampling.md).

Browser codec/CMM assets come from exact npm dependencies `lcms-wasm@1.0.5`,
`pako@2.1.0` and `pdfjs-dist@6.4.299` in `tools/web-assets/`, with archive integrity and the
dependency tree fixed by the lockfile. After explicit `npm ci` setup,
`tools/prepare_web_assets.mjs` verifies versions and asset hashes and copies
LittleCMS JS/Wasm plus standalone JBIG2 Wasm to ignored local paths. The web
build also runs `tools/prepare_flate_assets.mjs`, which verifies pako source
hashes from `tools/ci/pako-assets.json` before bundling the image adapter and
copying its MIT/Zlib license. A local build transform updates compression hash
positions two 16-bit entries at a time, retaining upstream match decisions and
exact zlib output; its exhaustive and upstream-byte comparisons run in CI.
The bounded inflater also replaces validated distance-one output matches with
native byte fills; window-backed matches retain the upstream loop. CI compares
stream transitions, checksums and output bytes against the pinned driver.
The Worker installs
synchronous typed-array Flate/PNG compression hooks; other hosts retain the
portable MoonBit codecs.
The host decoder validates the first zlib trailer, ignores trailing streams,
and stops at the image output bound. Failed or oversized attempts fall back to
the portable decoder, retaining its damaged-stream prefix and error behavior.
PNG samples, colour conversion, masks and SVG portability stay the same;
browser PNG compression uses level 1 rather than the portable encoder's level 6.
ICC and JBIG2 fetch/compile initialization runs concurrently, and both attempts
must settle before the Worker accepts PDF operations. The web
build invokes preparation and stages the same-origin assets and license notices
for the Worker and Canvas host; it does not install npm packages automatically.
No PDF.js renderer or npm/CDN fetch is needed when opening a PDF. Native JBIG2
C++ sources and text licenses stay tracked. This establishes repeatable asset
acquisition, not a verified bit-identical source rebuild; see
[development setup](development.md#本地运行) and the adapter provenance records.

Viewer reader recovery also tolerates legal comments between `endstream` and `endobj` when page content was dropped,
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

The standalone browser interface uses Rabbita 0.16.4. MoonBit views, typed
messages, navigation, search, selection, document lifecycle and print orchestration
live in `cmd/viewer/`, compiled to `web/_generated/viewer.js`. Rabbita reconciles
the toolbar, sidebars and status; stable empty page/print containers preserve
native Canvas and selection nodes across model updates. `web/viewer.js` loads
the application and preserves the host exports. The small `web/viewer-host.mjs`
adapter connects the existing rendering engines and page scheduler to MoonBit.
See [frontend boundaries](frontend.md) for module responsibilities.

`cmd/browser/` provides the PDF engine bridge.
`web/pdf-client.js` sends asynchronous operations to the native
module Worker in `web/pdf-worker.js`; the generated MoonBit bridge runs there.
`initializePdfGraphics()` installs the image/colour host adapters before
MoonBit/pdflite parses PDF bytes in that Worker. The Rabbita application handles
file input, navigation and native browser selection through DOM bindings and
narrow native API calls. The main thread initializes the graphics host needed
for Canvas replay.

The published Pages build compacts compiler-emitted static data before
minification. `tools/compact_pdf_data.mjs` uses pinned acorn 8.15.0 AST ranges
to replace large int32 literal arrays with memoized getters, and defer the
audited pure pdflite CMap unpackers that would otherwise force those arrays at
module initialization. Arrays use lossless column-delta varints or int32 bytes,
whichever compresses smaller. Large embedded CMap/font base64 strings are
compressed inside their existing lookup functions. `web/pdf-static-data.mjs`
decodes these trusted build constants synchronously with the already bundled
pako adapter and preserves ordinary Array/String representations and table
identity. No PDF stream enters this data loader, no runtime `eval` or secondary
Worker request is introduced, and readiness still waits for both graphics
engines. First use pays for only the needed tables; the same module retains
them thereafter. The readable development bridge and MoonBit package sources
remain available for profiling; public interfaces and native targets are
unchanged. `tools/compact_pdf_data_test.mjs` compares every transformed table,
all embedded CMap/font bytes, and import/memoization behavior against the
untouched release bridge.

The bridge includes `open_pdf`, `open_pdf_with_password`, `render_page`,
`render_print_page`, `select_text`, `select_page_text`, `search_pdf`,
`document_info`, `page_layouts`,
`cache_info`, `download_attachment`, `download_metadata`, `set_font_fallbacks`
and `close_pdf`.

Page models use an LRU budget of eight pages/estimated 32 MiB; serialized render
responses use twelve entries/24 MiB, including the Canvas plan, compatibility
SVG and text layer. These bounds exclude parsed input, temporary decoding and
main-thread Canvas working surfaces. Closing/replacing a document terminates
its Worker and rejects outstanding work. AbortSignal removes queued tasks and
discards active results; a synchronous active operation can finish before the
next RPC. The host contract does not reproduce PDF.js loading/render task
objects or promise hard cancellation of synchronous Canvas replay. Embedded
font families receive page prefixes so multiple SVGs do not replace
each other's @font-face rules. `render_page` retains the existing SVG and text
layer fields and additionally returns the Canvas plan. `renderPdfPage()` installs
pattern/shading painters and delegates to `renderPdfCanvas()` on the main thread;
main pages and thumbnails use that result and surface graphics diagnostics.
`render_svg()` remains the compatibility API.

The browser can opt into a compiled Canvas projection for resource-free,
fill-only Type3 CharProcs. A document cache retains at most 512 compiled glyphs
and an estimated 8 MiB of numeric geometry. Each page retains only its used
resources and calls; its geometry is also conservatively charged against the
page-cache budget. Build contexts release their document-cache references when
preparation completes, including when Range hydration replaces a document view.
Resource keys identify CharProc streams within one immutable document. Colour,
FontMatrix/placement, clips and group state remain invocation data. Complex
CharProcs retain the ordinary interpreter. Public page models and legacy bridge
calls keep their complete scenes; explicit SVG requests upgrade a compact cached
projection to the complete model. Version-2 browser plans carry a local glyph
resource table, expanded by `web/pdf-canvas-program.mjs` into the existing
native/retained rendering boundaries. The viewer replaces each owned compact
response with its expanded plan once; generic runtime calls expand before
choosing the native surface budget or tiled output. Text selection and semantics consume the
same top-level provenance and geometry as the complete model.

The native public route writes `.canvas.json` through `cmd/main`, then replays
it with `tools/render_canvas.mjs` in a Canvas host. `.svg` selects compatibility
output. It uses the same plan/runtime, not a separate MoonBit software rasterizer;
setup and generated-bridge prerequisites are in
[native Canvas setup](validation/native-canvas-setup.md).

The shipped web bridge/runtime has been tested with a native Canvas API host.
Chromium was blocked by socket EPERM in the recorded A2 environment, so those
runs do not establish a new DOM/interaction or browser screenshot pass.
The upstream Worker's separate browser/pressure evidence is retained in
[validation.md](validation.md#browser-host-lifecycle-scheduling-and-pressure),
with `1f9db19` annotation/print-intent evidence in
[its own section](validation.md#readonly-annotation-interaction-and-print-intent).
Neither is a fresh run of the merged A2 graphics path.

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
operation remains synchronous. `PdfSearchOptions::find_matches` supplies the
same original-offset policy for PDF and XFA. Native DOM Ranges and CSS Custom
Highlights paint exact substrings without replacing glyph text nodes. Complete
locale-specific case folding remains outside this normalization policy.

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

The MoonBit/Rabbita editor mounts a separate native field and annotation layer.
It converts pointer gestures through the inverse viewport matrix, applies immutable
snapshots through `with_editor_changes`, and invalidates page/thumbnail caches.
The Worker keeps the original snapshot baseline and uses pdflite's incremental
writer for downloads, with a full rewrite fallback for recovered sources.
It completes validated Range sources before editing, so
unvisited objects are retained. Explicit AP streams persist text, choices, button
states and Ink/Stamp signatures across readers. See [editor details](editor.md)
for original-font encoding, Unicode raster fallback, XFA dataset editing,
encryption and validation. XFA reuses the pinned binder/XML serializer;
`editor_xfa.mbt` only replaces the supplied data packets in the pdflite object graph.

`accessibility.mbt` associates tagged structure with the existing collector's
glyph indices and string/Form provenance. A bounded marked-content pass keeps
the originating MCID stream distinct from the Form invocation that paints its
text; ParentTree can resolve page-local integer references without `/Pg`.
`RoleMap`, namespace-scoped `RoleMapNS`, `/Lang`, `/Alt`, `/ActualText`, table attributes and annotation OBJR
references form a page-local semantic view. Unmapped visible text retains the
A1 geometrical paragraph order. Cycles/depth/node/operation limits retain
fallback text; the JSON reports mapped/unmapped/excluded counts and truncation.

The display response includes this view. `web/accessibility-layer.js` creates
clipped, unselectable DOM/ARIA narration and hides the geometric glyph layer
from AX. Plain text replaces character-by-character duplicate narration;
tagged links own the existing native annotation controls with `aria-owns`.
Formula tags expose math semantics with alternative text. MathML-tagged structure
uses native MathML elements from a fixed whitelist; attributes and scripts from
the source are not copied into the DOM. XFA input labels reuse template field names
when the template supplies no explicit accessible name.
Paint, native selection and A1 copy/search source indices are retained. The
semantic DOM shares page mount/unload lifetime; labelled native page controls
load subsequent pages. Print responses omit this layer. A semantic extraction
error leaves the original glyph layer available rather than blanking paint.
AX evidence and remaining assistive-technology/tag coverage are recorded in
[validation.md](validation.md#tagged-page-accessibility-and-source-association).

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
A2's Canvas, image/colour adapters and group/mask/pattern/shading main paths are
implemented with target-specific capabilities and measured residuals documented
in [a2-acceptance.md](a2-acceptance.md). Remaining implementation work includes:

1. Complete annotation appearance, read-only form/widget and link/interaction layers;
2. Accessible tagged DOM, larger real-document visual/pressure baselines and CI;
3. Range/incremental page loading and the separately tracked XFA scope.

Worker lifecycle/cancellation, page virtualization and bounded page/render
caches have their own upstream acceptance. Revalidate their integration with
A2's Canvas path; cache/working-resource budgets are not whole-document RSS
limits. Expanded tests must preserve known font/rasterization differences and
explicit host fallbacks instead of turning conversion or test counts into
visual pass rates.

The complete feature backlog and acceptance rules live in
[`TODO.md`](TODO.md). The two current core workstreams, text/fonts and
graphics/images, are recorded in [`PARALLEL.md`](PARALLEL.md). Font resources,
Type 3 glyphs, SVG text output and text selection have been moved unchanged to
`font_resources.mbt`, `type3_outline.mbt`, `svg_text.mbt` and
`text_selection.mbt` within the existing root package. Multiple-FD CID-keyed
Type 1 is an extension rather than a parity requirement: the pinned PDF.js
Type 1 parser also supports only one FD.

Annotation parsing and compatibility SVG lowering live in `annotations.mbt`
and `annotations_svg.mbt`; appearance scenes also enter the shared Canvas plan.
The viewer reads the original `/Annots` array: popup children and malformed annotations are skipped without renumbering valid source
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
receive appearance-specific CSS family names. Outer transparency groups reuse
the same Canvas isolation/knockout replay and resource limits as page Forms;
SVG retains the declared compatibility limits. A valid empty stream suppresses
geometry fallback.

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

Image XObjects and inline payloads, including nested Form images, are collected
with `parse_content_ops_with_resources` and passed through pdflite filters plus
the viewer's original-sample/codec adapters. The content walk additionally retains
alpha, blend, group, mask and paint state that compact pdflite JSON entries do
not expose. Both Canvas plans and compatibility SVG consume this shared model;
SVG's sampled gradients and mask images do not replace structured pixel replay.

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

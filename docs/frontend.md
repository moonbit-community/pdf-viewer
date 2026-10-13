# Browser interface

The browser application uses [Rabbita](https://mooncakes.io/docs/moonbit-community/rabbita)
0.16.4, pinned in `moon.mod`. The application source is MoonBit; the build compiles
it to an ES module for the browser. No separate JavaScript application controller
or handwritten virtual DOM is used.

`cmd/viewer/view.mbt` assembles the application with Rabbita HTML;
`toolbar.mbt` defines the reader controls and `sidebar.mbt` the document panels.
Authored UI text, ARIA labels and diagnostic messages
use English; PDF content and multilingual regression fixtures retain their
original text. `model.mbt` holds typed view snapshots and message types;
Rabbita state and commands connect them in `main.mbt`. The async reader session
tracks document generations, abort controllers and page/selection lifetimes in
MoonBit. `pages.mbt` connects page scheduling and surface mounting;
`text_layer.mbt` constructs native text layers and measures glyphs, and
`navigation.mbt` handles paging, zoom and annotation destinations. Search and native
selection live in their corresponding files, and file/print lifecycle in `document.mbt`
and `print.mbt`. Native browser events are connected in `events.mbt`.
`layers.mbt` implements the Rabbita layer panel and configuration changes,
including editor flushing, cache invalidation and stale-reply suppression.
`status.mbt` defines viewer states independently of their status-bar text;
runtime transitions match variants rather than message prefixes. `json.mbt`
shares JSON access and update helpers between reader panels and the editor.

The editor follows the same boundary: `editor_model.mbt` defines its typed state,
`editor_view.mbt` builds Rabbita controls, and `editor.mbt` applies snapshots,
undo/redo and saving. Native field mounting and PDF-space pointer geometry live in
`editor_layers.mbt` and `editor_gestures.mbt`. `editor_platform.mbt` binds pixel
acquisition, Canvas previews and native control properties. It contains no
JavaScript editor state or application controller. Selection highlights and XFA
field events live in `editor_selection.mbt` and `editor_xfa.mbt`. The engine reuses
pdflite objects, content operations and its incremental/complete-document writers; there is no
second PDF serializer.

Rabbita owns the application DOM. The empty `#pages`, `#print-pages` and thumbnail
preview containers retain their identity across view updates; rendering adapters
own their contents. This preserves Canvas pixels, native selection endpoints and
annotation focus. Code that needs the new view waits for Rabbita's `AfterRender`
command before observing or measuring it.

`web/viewer.js` loads the generated module and exposes the existing host helpers
(`loadFile`, search, selection, close, print and diagnostics). `web/viewer-host.mjs`
connects existing Canvas, Worker, annotation, accessibility and XFA engines.
`platform.mbt` contains narrow FFI for native APIs and opaque render plans. DOM
operations use Rabbita's DOM package where available; Selection/Range and PDF
engine calls use native bindings. Worker transport, page scheduling and rendering
modules remain adapters rather than application views or navigation controllers.

The PDF parser runs in the Worker. Canvas process-colour conversion uses the
MoonBit primitive compiled into the UI module, without loading the parser again
on the main thread. The reader, thumbnails and printing ask the bridge to omit
the unused whole-page SVG. The public `render_page` and `render_print_page`
exports still include SVG by default; their optional fourth argument enables
`omit_svg` and preserves all other page payloads.

Display rendering (`returnPixels: false`) paints ordinary RGB source-over pages
directly through Canvas2D. Opaque fill-only Type3 glyphs reuse their vector paths,
including multi-path charprocs; empty charprocs skip painting. Independent
normal RGB groups at unit opacity flatten to their native child paints.
Knockout groups take this path only for opaque vector paints whose shape equals
alpha. Other isolated normal groups render into
bounded transparent surfaces before applying group opacity once. Independent RGB
tiling fills use Canvas colour surfaces; transparent cells replay once at their
device coordinates without page-sized shape or component buffers. Compound or
stroked patterns and opaque normal shading scenes use the retained rasterizers
while ordinary sibling paints stay on Canvas. Backdrop-dependent blending, knockout,
masks, CMYK, calibrated/ICC blend groups and proof/component outputs retain the
PDF compositor wherever needed. `nativeCanvas: false` selects the retained
renderer for comparisons. Native display uses the browser's RGBA8 rasterization;
its antialiasing and rounding can differ from Float32 replay. Pixel-returning
calls retain the previous renderer and its shape/component arrays.

Opaque built-in RGB shadings reuse colour alpha as coverage, preserving exact
retained samples while avoiding a second raster/transfer pass. The existing
direct `shading_pattern` and pattern-carried shading representations use the
same proof. A structured shading scene requires one independent unit-opacity
source against transparency; scene annotations and soft-mask backdrop colours
keep the separate coverage pass. Translucent paints, component/proof domains,
calibrated/ICC groups and custom adapters retain their existing passes.
`fullShapeReplay: true` selects separate coverage for reference comparisons.
Internal scene, mask and backdrop-pattern consumers retain their Float32 colour
and coverage buffers and omit unused RGBA encoding/Canvas uploads. Surfaces
actually drawn, including nested tiles and annotation-bearing scenes, still
produce their normal Canvas output.

Page images use the existing MoonBit Flate whole-buffer encoder and checksum
library for PNG output. Opaque identity RGB rows use the core byte copy when
their horizontal size is unchanged; decoded masks, calibrated colours and
retained process samples keep their existing conversion rules. Opaque, unscaled
8-bit ICC RGB images use an exact 4096-colour byte palette and a compact row
loop, retaining the same LittleCMS, Decode, clipping and rounding. Failed
transforms keep retryable Alternate recovery. Indirect fonts
share at most 128 successful parses within one page build, including nested
resources. Every binding still resolves its current resource dictionary;
direct dictionaries follow the original font reader, and page, document,
editing and Range retries receive fresh contexts. A simple pattern's
compatibility SVG borrows images already converted for its cell, preserving its
original resource indices and colour policy. Tagged pages retain at most 16,384
text-source entries for one semantic projection, so accessibility does not repeat
the content interpreter.
Font or layer view changes discard that provenance; uncached projections retain
the normal collector path.

Canvas replay skips paints outside each tile and shares a
bounded image/annotation raster cache across tiles, nested groups, masks and
pattern cells. It releases that
cache after completion or cancellation. The host's document-owned
`PdfRenderAssets` keeps shared decoded rasters across pages and zoom, with a
64 MiB/256-entry LRU budget. Active renders lease each raster; eviction or document
close releases it after its last consumer finishes. Independent RGB pattern
cells also retain prepared colour/coverage bitmaps in a separate 16 MiB/32-entry
document pool, using the same leases and eviction. Its keys include complete
cell contents, raster dimensions, sampling and size policies, and host identity,
so newly parsed viewport objects can reuse unchanged cells. The image loader
stays stable for the document pool; active paints capture their own pools before
document replacement. Editing, font and layer invalidation clear both pools.
Backdrop-dependent, masked and component/proof patterns retain their existing
per-paint rendering. Transparent cells retain only a coverage classification
and replay their device-space edges; full-coverage shapes use an opaque rectangle
instead of uploading an alpha-only pixel buffer.
Diagnostics report bytes, entries, loads and reuse, with prepared tiles under
`patterns`. These are cache budgets, not process RSS limits.
Replay yields to browser events and checks the
MoonBit task's lifetime before continuing. Pages, thumbnails and printing use
the same cancellation boundary. The reader keeps
scroll navigation active during page loading and shows a loading label on each
pending page. The MoonBit view attaches the page's Canvas before painting, so
finished tiles appear while the remaining tiles are still loading. Cancellation
removes only that task's partial paint; text, annotation and editing layers
mount after the page completes.

Completed reader pages retain their Canvas and native text layer in an LRU
cache with a limit of eight pages and 256 MiB of estimated Canvas RGBA storage.
Visible and selection-pinned pages remain available even when they exceed that
limit. Returning to a cached page needs no Worker request, painting or text-layer
rebuild. Eviction clears the Canvas backing store and page-local selection data.
Document replacement, scale/rotation changes, editing and layer visibility
changes invalidate these surfaces; unchanged zoom or a height-only fit resize
reuse them. Speculative neighboring pages begin after the requested page finishes
painting and mounting, rather than competing with its first display.

Mounted text layers retain their original PDF-space glyph quads and resolve
selection locally through MoonBit's `PdfTextLayer::select_text`, using the same
UTF-16 validation and separator rules as `PdfPageModel::select_text`. Dragging
displayed text does not wait behind Worker rendering or reschedule the page for
every cursor change. Clipboard events and the copy button refresh the current
native range before copying. Unloaded pages and XFA retain the Worker path;
unmounting a page releases its local selection index. Nearby page mounting
preserves an active native drag range.

Search uses native DOM Ranges and CSS Custom Highlights for exact original UTF-16
substrings, including matches inside a multi-character glyph. It retains the
original text nodes and current user selection. Browsers lacking this API use
the item-level highlight fallback. PDF and XFA search share MoonBit normalization
and source-offset mapping, including compatibility ligatures and common case folds.

To compare rendering with the pinned PDF.js checkout, build both static outputs
as described in [the reference setup](../reference/README.md), then run
`node tools/render_benchmark.mjs /path/to/document.pdf 1,2,12`.
`PDF_BROWSER=chromium` selects Chromium; the default is WebKit at DPR 2.
`PDF_BENCH_REPLAYS=9` increases ordinary drawing samples from the default three;
the accepted range is 3–30 and applies to both renderers. Worker zoom sampling
remains separate.
`PDF_BENCH_VIEWER_ROOT=/path/to/static/viewer` selects another packaged build for
before/after comparisons.
The tool uses identical Canvas dimensions and finishes reader prefetch before
timing replay. Reports separate reader startup, Worker payloads, paint time and
pixel-flush time. `PDF_BENCH_COMPARE_RETAINED=1` also compares native display
against retained replay and reports both renderers' differences from PDF.js.
Input files stay local and reports are written only under ignored `_build/`.
The benchmark checks the reference checkout/build, records source and module
hashes, and times three uncached zoom payloads separately from completed page
navigation. Worker round-trip time excludes client queue/startup waiting.
`PDF_BENCH_PROFILE=1` adds a separate diagnostic process/browser with Canvas call counts,
pixel traffic, nested scene self time, host yields and resource cache activity.
It also records fresh PDF.js operator-list preparation. Ordinary paint/flush
samples use the original Canvas modules and prototypes, with no profiler hooks.
An additional replay clones the Canvas plan, excluding cloning from paint time,
and verifies its complete RGBA SHA-256 against the ordinary replay. Reports also
include PDF.js pixel hashes, allowing before/after comparisons to require
identical reader and reference pixels within each browser engine.
`PDF_BENCH_SAMPLES=6 node tools/first_load_benchmark.mjs /path/to/document.pdf`
measures file opening through the ordinary reader input with fresh browser
contexts and Workers. `PDF_BENCH_BASELINE_ROOT=/path/to/previous/static-build`
adds sequential before/after pairs in alternating order. Timing starts after
the application shell has loaded and ends after the complete first-page Canvas,
a pixel flush and two animation frames. Full-page hashes are checked afterwards;
the separate reader-ready marker includes mounted text, annotations and fonts
but may precede document metadata completion. The PDF.js reference uses its
Canvas API without reader UI. Both tools use local files and keep their detailed
reports under ignored `_build/`.
`node tools/pixels/profile_page_stages.mjs /path/to/document.pdf _build/stages.json 1,2,12`
profiles the readable release bridge on Node, checks cached Canvas/semantic
hashes, and separates inclusive stage time from self time. These measurements
are independent of the browser runs; see [the speed investigation](validation/render-speed.md).

Cached pages retain their accessibility manifests within the same 32 MiB page
budget. Zoom and rotation reuse their original semantic coordinates without
collecting PDF text or reading fonts again. Font, layer, document and editor
changes invalidate the page cache. Range hydration invalidates semantic metadata
while preserving completed page geometry. Failed semantic reads are retried.

The Worker starts through `pdf-graphics.mjs`, which initializes the synchronous
ICC/JBIG2 adapters without importing Canvas, pattern or shading renderers. XFA
binding and its DOM renderer load only when an XFA document requires them.
Document replacement cancels a pending XFA DOM import before mounting its layer.
The Pages build bundles the parser, Range loader and graphics adapters into one
Worker entry with the existing locked esbuild. Ordinary Worker startup needs no
secondary JS modules; ICC/JBIG2 Wasm URLs stay below the repository subpath.
XFA remains an external dynamic import. Optional `?profile=startup` on the Worker
URL includes startup timings in its ready message for diagnostic benchmark runs.

`tools/pages_browser_test.mjs` checks document pattern reuse through the actual
viewer host, cloned-plan pixels, changed cell contents and document invalidation,
alongside page reuse, unchanged viewport resizing,
bounded eviction and Canvas release. It exercises Chromium and WebKit selection while
holding Worker selection requests, checks immediate copy before a
`selectionchange` update, and compares local source indices and quads exactly
with the Worker. Pass a published repository URL to run the same browser flow
against a deployment after building the local static artifact.

`tools/build_web.mbtx` builds both `cmd/browser` and `cmd/viewer`. Static hosting
must include both generated modules and the existing codec/XFA assets. Develop
with `moon run tools/dev.mbtx 4312` after installing MoonBit and web dependencies.
For a public static site, `moon run tools/build_pages.mbtx` packages the same
application in `_build/pages/`. The GitHub Pages workflow verifies it under a
repository subpath before deploying; see [Pages setup](pages.md).

`tools/browser_test.mbtx` passes 110 checks against the compiled application in Chromium. It
checks all existing reader behavior plus view updates preserving Canvas/native
selection, stale thumbnail/print draws suppressing publication and warnings,
selections outside the PDF text layer,
repeated page clicks, files captured during native drop events, and real warnings
published by page/thumbnail/print rendering.
These checks replace the former test that extracted JavaScript controller
functions into a VM; Worker/Canvas and scheduler tests remain separately runnable.

`node tools/editor_browser_test.mjs <viewer-url>` exercises 25 editing paths using
native Chromium inputs and Pointer Events. It covers inherited fields, duplicate
choice exports, moving/resizing, multiple signature strokes, undo/redo, active-input
Ctrl/Cmd+S, saved-state tracking, replacement races (including late preparation
and image-decoder failures), Range hydration and a real
PDF.js form fixture. Password-protected RC4/AES documents retain encryption and
permissions, while the toolbar/native fields reflect user versus owner access.
The pinned PDF.js reader reopens the downloaded bytes and
renders saved annotation appearances; Chromium also exports edited print output.
CI retains these reports and PDFs alongside the existing reader reports. See
[editor behavior and limits](editor.md).

`node tools/layers_browser_test.mjs <viewer-url>` adds 11 layer checks for Unicode
order, usage, radio/locked constraints, actual print pixels, thumbnail updates,
editor snapshots, Range hydration, wrapped toolbars and replacement races.
Two real PDF.js layer fixtures compare sampled paint in three visibility states.
Layer manifests and constraints reuse pdflite; see [layer behavior](layers.md).

`node tools/text_interaction_browser_test.mjs <viewer-url>` adds six checks in
both Chromium and WebKit for precise search, affine/cross-page highlight persistence,
XFA editing/saving, inherited access and unsupported controls, radio display/print
state and native namespace/MathML accessibility semantics. The CI
report gate requires every check in both browsers. Automated DOM and Chromium
accessibility-tree evidence do not replace VoiceOver/NVDA user acceptance.

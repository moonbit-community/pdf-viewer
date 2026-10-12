# Browser interface

The browser application uses [Rabbita](https://mooncakes.io/docs/moonbit-community/rabbita)
0.16.4, pinned in `moon.mod`. The application source is MoonBit; the build compiles
it to an ES module for the browser. No separate JavaScript application controller
or handwritten virtual DOM is used.

`cmd/viewer/view.mbt` and `sidebar.mbt` define the toolbar, document panels and
status with Rabbita HTML. `model.mbt` holds typed view snapshots and message types;
Rabbita state and commands connect them in `main.mbt`. The async reader session
tracks document generations, abort controllers and page/selection lifetimes in
MoonBit. Navigation and page/text mounting live in `pages.mbt`, search and native
selection in their corresponding files, and file/print lifecycle in `document.mbt`
and `print.mbt`. Native browser events are connected in `events.mbt`.
`layers.mbt` implements the Rabbita layer panel and configuration changes,
including editor flushing, cache invalidation and stale-reply suppression.

The editor follows the same boundary: `editor_model.mbt` defines its typed state,
`editor_view.mbt` builds Rabbita controls, and `editor.mbt` applies snapshots,
undo/redo and saving. Native field mounting and PDF-space pointer geometry live in
`editor_layers.mbt` and `editor_gestures.mbt`. `editor_platform.mbt` binds pixel
acquisition, Canvas previews and native control properties. It contains no
JavaScript editor state or application controller. The root editor package reuses
pdflite objects, content operations and its complete-document writer; there is no
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
directly through Canvas2D. Opaque Type3 glyphs containing one filled path reuse
that path, and empty charprocs skip painting. Isolated normal groups render into
bounded transparent surfaces before applying group opacity once. Simple patterns
and opaque normal shading scenes reuse the existing rasterizers while ordinary
sibling paints stay on Canvas. Backdrop-dependent blending, knockout,
masks, CMYK, calibrated/ICC blend groups and proof/component outputs retain the
PDF compositor wherever needed. `nativeCanvas: false` selects the retained
renderer for comparisons. Native display uses the browser's RGBA8 rasterization;
its antialiasing and rounding can differ from Float32 replay. Pixel-returning
calls retain the previous renderer and its shape/component arrays.

Canvas replay skips paints outside each tile and shares a
bounded image/annotation raster cache across tiles, nested groups, masks and
pattern cells. It releases that
cache after completion or cancellation, yields to browser events and checks the
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

To compare rendering with the pinned PDF.js checkout, build both static outputs
as described in [the reference setup](../reference/README.md), then run
`node tools/render_benchmark.mjs /path/to/document.pdf 1,2,12`.
`PDF_BROWSER=chromium` selects Chromium; the default is WebKit at DPR 2.
The tool uses identical Canvas dimensions and finishes reader prefetch before
timing replay. Reports separate reader startup, Worker payloads, paint time and
pixel-flush time. `PDF_BENCH_COMPARE_RETAINED=1` also compares native display
against retained replay and reports both renderers' differences from PDF.js.
Input files stay local and reports are written only under ignored `_build/`.

`tools/pages_browser_test.mjs` checks page reuse, unchanged viewport resizing,
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

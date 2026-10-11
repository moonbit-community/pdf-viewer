# A2 graphics/image acceptance record

This is the workstream acceptance record, not a general PDF compatibility rate.
The reference fixture revision is PDF.js
`89b500f5e1d98ed89bb90211e45b28730b2d99ac`. PDF.js, Poppler and Ghostscript
are independent oracles, not interchangeable specifications. Where they disagree,
the focused reports retain both measurements and the ISO 32000-1 rule used.

The recommended pixel path is `PdfPageModel.canvas_plan()` →
`web/pdf-canvas.mjs`. The shipped web viewer calls this path. `render_svg()`
remains a compatibility API and emits graphics diagnostics in SVG metadata;
it is not an equivalent implementation of groups, masks or shading.

Current integration status: all fourteen A2 items have checked main-path evidence,
including the default Standard 14 affine-text path integrated from A1 `a22a190`.
Explicit host overrides and fonts without usable contours retain the capability
boundary described below. The authoritative
50-item checklist is [TODO.md](TODO.md). A checked item does not mean every
reference-renderer pixel agrees or every execution target has the same host
capabilities.

## Item inventory

| ID | Status | Implemented path | Acceptance evidence and remaining boundary |
| --- | --- | --- | --- |
| I-01 | Checked main path | Pinned MoonBit JPEG2000 all-component decoder, JP2 palette/sYCC/ICC, embedded alpha, PDF Decode/masks, bounded allocations | `codecs/jpx/README.md`, original component fixtures on four Moon targets; real `bug_jpx`, `jp2k-resetprob`, `jpx_smaskindata` sample planes. Large-image decode latency is recorded, not called interactive performance. |
| I-02 | Checked main path | PDFium native Linux and Mozilla/PDFium JS-hosted Wasm adapter; globals and masks flow into ordinary PNG resources | `codecs/jbig2/README.md`; real packed decode hashes and large `JBIG2Globals.pdf` resource/entry timing. Other native platforms and standalone Moon Wasm lack this adapter and report unavailable decode. |
| I-04 | Checked main path | JPEG original samples, encoded JPX/JBIG2 masks, original-domain color-key/Matte, explicit/soft mask precedence, opt-in ink planes | `docs/jpeg-decoder.md`, `tools/jpeg_alpha.mbtx`, image source/alpha/pixel regressions. `issue13931` has 12,750,976 exact alpha samples and zero visible pixels above 8. Whole-page sampling/annotation differences remain separately measured. |
| C-01 | Checked main path | Actual LittleCMS source/target ICC transforms, rendering intent, bounded profile catalogs and active transform lifecycle | Real v2/v4 images and original Altona solid/overprint controls independently verified. All 4,707 original flat-reference residuals are localized by source paint and policy; this is colour-stage acceptance, not whole-page equality. `docs/a2-colour-validation.md` includes dynamic legal ICC Alternate recovery. JS uses bundled extraWasm; native Linux dynamically loads LittleCMS2. Standalone Moon Wasm uses the specified PDF Alternate and exposes capability. |
| C-03 | Checked main path | Whole tint function/domain, None/All, display alternates, original components, explicit process-space OP/OPM | `tools/pixels/compare_ink_planes.mjs`, `docs/a2-compositing-validation.md`;16 CMYK blends and process group cases compared with Ghostscript tiffsep. Arbitrary physical spot-ink proofing requires an actual matching profile; display alternates follow ISO8.6.6. |
| G-01 | Checked main path | Affine path pen, A1 embedded/Standard 14 contours and optional native host outlines; independent width/dash/caps/joins | 56 original and 8 CFF variants; default shipped web bridge/runtime passes 24 exact same-font Standard 14 fill/stroke/viewport controls with no native resolver. Native public default output is byte-identical. Explicit host overrides and nonstandard fonts without contours retain `PDF_TEXT_STROKE_GEOMETRY`, strict rejection and visible warning. See `docs/validation/standard14-pen.md` and `docs/validation/host-text-pen.md`. |
| G-02 | Checked main path | Independent fill/clip winding, delayed W/W*, empty clips, Form intersections, hairline dashes and degenerate caps | `path_clip_wbtest.mbt`, `tools/pixels/hairline_test.mjs`, real affine and CFF clipping fixtures. Subpixel non-hairline minimum coverage differs between reference-renderer policies; it is not silently clamped to one pixel. |
| G-03 | Checked main path | Reusable Canvas2D pixel backend with RGBA8 public surfaces, Float32 premultiplied group data, separate shape/alpha and resource limits | Actual web JS-entry smoke and native CLI→plan→PNG path; `tools/render_canvas.mjs`. Native Canvas host tested. Chromium process cannot launch in this environment (socket EPERM), so full DOM/browser interaction is not claimed. |
| M-01 | Checked main path | Isolated/nonisolated groups, backdrop removal, knockout, nested boundaries, process and ICC blend spaces, text TK | `docs/a2-compositing-validation.md`, `docs/validation/text-knockout.md`; authored full PDFs and real regression pages, multiple reference renderers. |
| M-02 | Checked main path | Structured Alpha/Luminosity soft-mask replay, installation CTM, BC in group space before CMM, TR and image-local mask precedence | Mask model and Canvas pixel tests; nested knockout/masked-TK reference disagreements recorded rather than hidden. |
| M-03 | Checked main path | All16 PDF blend modes plus preference arrays and CompatibleOverprint semantics | RGB full-PDF and CMYK tiffsep pixel oracles; unsupported host blend primitives fail explicitly. |
| H-01 | Checked main path | Uncolored base paints applied before glyph lowering, independent fill/stroke resources, base matrix and signed lattice | Original pattern PDFs plus `tiling_patterns_variations`; documented antialias/filter-policy residuals are not counted as a whole-page pass. |
| H-02 | Checked main path | Complete cell plans containing text, images, Forms, groups, clips and local resources; per-tile backdrop and independent shape | Original complex-cell, Multiply-backdrop and knockout-pattern PDFs. Negative-step geometry matches Ghostscript exactly; backdrop/knockout pages within1 byte. |
| H-03 | Checked main path | Raw sample-domain interpolation; type1 two-dimensional functions; axial/radial Extend; Gouraud/Coons/tensor; adaptive checked lookup and device tessellation | `docs/a2-shading-validation.md`;100,000 analytical RGB and40,000 CMYK plane pixels plus real Coons/tensor PDFs. Over-budget/unsupported function sampling is explicit `raster.error`; no hidden black fallback. |

The tiling resource builder bounds nesting to16 and total cell builds to256 per page; exceeding those limits is an explicit `PDF_PATTERN_RESOURCE`, including repeated uses. Runtime tile, decoded-image, mask and ICC caches are separately bounded. These working-resource limits are not a whole-document peak-RSS guarantee.

Checked main paths do not imply universal font or platform support. The
2026-10-10 baseline passed **458 JS, 466 native, 459 Wasm and 459 Wasm-GC**
tests. Fresh A1-integrated common checks and their source identity are recorded
below; historical real-corpus measurements are not silently reassigned to the
new tree. The backend passes 37 Canvas replay tests, 64 bit-identical dirty/full replay
combinations, eight exact pattern-region comparisons and eight exact affine
nested-scene crop comparisons. Resource reuse/ownership and the actual default
viewer warning path are also checked. No reference-image measurement count is
reported as a fidelity pass count.

The actual original Altona page's matched Ghostscript CMYK→LittleCMS AA4
comparison has 259,173 pixels above channel error 8 out of 1,004,360, mean
absolute RGB error 7.06356. Five independently converted ICC/CalRGB solid
controls and six independently composed process-overprint controls match
exactly. Those controls establish real colour paths, but do not attribute all
remaining whole-page residuals. Follow-up source attribution now accounts for
all 4,707 flat-reference residuals without changing the reference mask or
tolerances: plate availability, forced reference intent, reference glyph
selection, per-paint coverage, and independently reconstructed bitmap sampling.
The original whole-page count remains unchanged. See [the colour-stage report](a2-colour-validation.md).

The shared ICC catalog is retained once across embedded scenes: the real
Altona plan is about 21.27 MB, including 43 Type3 scenes totaling 98,216
bytes, rather than repeating roughly 313.6 MB of profiles. Backdrop-dependent
pattern cells share only bounded glyph rasters, not mutable compositing
results. Real nested Type3 replay completes with empty diagnostics; its
reference-host pixel differences remain in the Type3 report.

## Host capabilities and public entry points

Browser assets are delivered from locked `lcms-wasm@1.0.5` and
`pdfjs-dist@6.4.299` npm dependencies. The build verifies pinned versions and
SHA-256 values, then copies LittleCMS JS/Wasm and standalone JBIG2 Wasm to
ignored local paths with tracked license notices. Native C++ sources remain
tracked. The deployed Worker and Canvas host use the same-origin assets; no
PDF.js renderer or runtime npm/CDN request is introduced. This is repeatable
acquisition of release assets, not a proven bit-identical C/C++ rebuild, and
does not change the historical measurements below.

| Host | Decode / colour capability | Pixel output and limitations |
| --- | --- | --- |
| JS web host | Moon JPEG/JPX; bundled JBIG2 and LittleCMS extraWasm installed before parsing | Canvas2D groups, masks, patterns and shading. Actual shipped bridge/runtime tested with a native Canvas host; real browser DOM is untested here. Bundled Standard 14 paints directly from A1 contours. Explicit host overrides/nonstandard text without contours retain the geometry warning. The default viewer decodes in its Worker; queued tasks can be cancelled and active results discarded. Closing/replacing the document terminates the Worker. Canvas replay remains on the main thread. |
| JS Node host | Same JS/Wasm adapters | `renderPdfPage` / `renderPdfCanvas` accept host `createCanvas`, `Path2D`, `loadImage`. Public runner installs the native text-outline callback when available. |
| Moon native Linux | Moon JPEG/JPX; vendored PDFium C++20 child-process JBIG2; dynamically loaded LittleCMS2 | Native parsing produces public Canvas JSON. The Node Canvas runner produces the PNG; a standalone Moon software rasterizer is not implied. Native host text-outline adapter tested. |
| Moon native macOS/Windows | JPEG/JPX source path; JBIG2 deliberately unavailable without equivalent process isolation. Native ICC availability is target-specific and untested here | No native-platform acceptance claimed. Explicit codec/colour capability boundaries remain. |
| Standalone Moon Wasm / Wasm-GC | Four-target JPEG/JPX tests pass; no JBIG2 or LittleCMS host imports; legal ICC Alternate path | Model, diagnostics and SVG compatibility APIs compile/test. No full pixel-host or profile-conversion claim from those test totals. |

- Existing `open_document` / `open_document_with_passwords` parsing remains
  available on the Moon targets. `icc_capability()` reports host conversion
  capability; `clear_icc_transforms()` explicitly releases active cached
  transforms. Direct JS codec/colour consumers must install their host engine
  before parsing, as documented in the adapter READMEs.
- `PdfPageModel.canvas_plan()` retains source geometry, image samples, colour,
  transparency and diagnostics. `graphics_diagnostics()` exposes capability
  issues; `render_svg()` keeps the existing compatibility output and records
  its approximate graphics branches in metadata.
- `cmd/browser`'s existing `open_pdf` / `open_pdf_with_password` and
  `render_page` calls remain usable. `render_page` retains `svg` and the text
  layer and additionally returns `canvas`. `set_font_fallbacks` keeps its
  existing family-selection interface; no font-selection semantics are added.
- `web/pdf-worker.js` calls `initializePdfGraphics()` before accepting RPC.
  `web/pdf-client.js` preserves the asynchronous browser API, priority queue and
  document-reset semantics from `eb4e017`. Lightweight `page_layouts`, bounded
  `cache_info` and off-screen `select_page_text` remain available.
- `initializePdfGraphics()` installs colour/image host engines before parsing;
  `renderPdfPage()` installs the pattern/shading painters and delegates to
  `renderPdfCanvas()`. The shared `process_cmyk_to_rgb` export supplies the
  established device-CMYK display conversion to host painters. The default viewer and thumbnails consume that result
  and surface diagnostics in the existing alert. Strict API replay rejects
  unresolved geometry; warning replay retains it without claiming exactness.
- `cmd/main input.pdf output.canvas.json [page]` and
  `node tools/render_canvas.mjs output.canvas.json output.png` are the public
  native-parse / host-replay route. `.svg` destinations still select the
  existing compatibility renderer. Bundled Standard 14 contours require no
  native text callback; that callback remains optional for host-selected fonts.

The unchanged 621-byte G-01 reproduction is generated by
`moon run tools/text_host_pen.mbtx`. `tools/pixels/standard14_pen_test.mjs`
checks 24 default bundled-font cases through the shipped runtime, without a
native outline callback, against same-font embedded geometry and actual pixels.
`tools/pixels/text_diagnostic_test.mjs` deliberately selects a host override
and checks structured rejection, nonblank warning preview and page/thumbnail
alert bindings; no DOM pass is inferred from the element-double check. See
[Standard 14 pens](validation/standard14-pen.md) and the remaining
[host text boundary](validation/host-text-pen.md).

The final public saved-plan replay of the original Altona page takes 10.62 s
and peaks at 783,416 KiB process RSS, with empty diagnostics. Its 4,017,440
RGBA bytes are identical to the pre-allocation-fix result. The same-probe
comparison is 36.19 s / 3.563 GB before versus 9.94 s / 791.8 MB after.
These are saved-plan replay measurements, excluding PDF parsing; process RSS
includes host/runtime storage beyond owned working-plane limits. See the
[allocation report](a2-allocation-validation.json).

## A1-integrated check (2026-10-11)

A1 `a22a190`, the Worker host from `eb4e017`, and the annotation/print-intent entry from `1f9db19` are integrated with the A2 pixel model. The final common command
passed **635 JS, 643 native, 636 Wasm and 636 Wasm-GC** tests, all-target
checking, release native/web builds and all authored pixel assertions. It now
includes the 24 strict Standard 14 cases and the public native plan→PNG exact
RGBA comparison. The two new A1 native CLI packages carry the same C++ link
requirement as the other PDFium-consuming executables.

Retained pattern/soft-mask text inherits the document's existing explicit
fallback policy. Real xref-backed tests cover resource-name and BaseFont
overrides inside shadowing Forms, independent paint/clip contours, active font
bindings and unchanged provenance. A true `tracemonkey.pdf` SVG parse failure
also exposed repeated XML metacharacters being escaped only once; the shared
compatibility serializer now escapes every occurrence, with public-SVG tests.

The default viewer now keeps upstream Worker scheduling and both cache budgets.
ICC/JBIG2 engines are initialized inside the Worker before it accepts PDF work;
Canvas replay installs its own main-thread CMM. Page, thumbnail and print replay
use detached Canvases and check cancellation/document generation before publishing.
The actual shipped Worker and client run over Node worker_threads in
[the Worker regression](validation/worker-canvas.md), including decoded JBIG2/ICC pixels, bounded
cache eviction, cancellation, reset/reopen and startup-error transport. Scheduler
lifecycle tests use element doubles. The upstream 53 Worker checks and later 78 annotation-inclusive Chromium checks remain
historical `eb4e017` / `1f9db19` evidence; the updated browser suite is compile-checked here,
not represented as a new DOM run. Actual Worker/Canvas controls also preserve
display-only, print-only and Hidden annotation pixels at all four rotations,
with separate display/print caches and annotation lifecycle cleanup.

A clean source-only worktree installs the locked npm dependencies with scripts
and optional packages disabled, then builds and passes the actual Worker tests.
Neither the source tree nor the new delivery commit history contains Wasm.
Generated bytes retain the recorded hashes; see [the dependency delivery record](validation/npm-assets.json).

The final bounded sampler cache and conservative direct-shading clip loops retain
byte-identical results. Tracemonkey page 11 generation fell from 15.206 s to
4.217 s, and saved-plan replay from 11.243 s to 2.790 s; full-size surfaces still
use substantial memory. Nine Moon cache regressions and seven host clipping
cases are in the common check. See [the performance record](validation/shading-reuse.md).

[The integrated check record](validation/a2-a1-integration.json) identifies the
built bridge and tool versions. [Standard 14 evidence](validation/standard14-pen.md)
retains exact controls and unmatched-reference differences. The earlier Oct 11
`84079e0` measurement of pinned `jpx_smaskindata.pdf` plus all 14 `tracemonkey.pdf` pages produced
15 actual Canvas measurements with empty plan diagnostics. The JPX page is
pixel-identical to PDF.js; Tracemonkey retains measured RGB MAE from 0.02235 to
2.45030, including 28,446 pixels above error 8 on page 10. These are measurements,
not 15 fidelity passes. [The full record](validation/a2-a1-real.json) gives the
command, hashes and per-page differences. That run also found public native CLI/runner pixels
matching the direct shipped web runtime exactly for page 1 of both real PDFs.
SVG is explicitly skipped in this
rerun: a prior compatibility comparison did not finish Resvg page 13, although
Canvas completed that page. No SVG performance pass is claimed.

The Oct 10 full Altona/codec/compositing reports remain historical measurements
of their stated source baseline; fresh unit/pixel checks are not a claim that
those entire corpora or the browser DOM were rerun after A1 changed font geometry.

## Public native rendering path

1. Install the locked asset dependencies with the `npm ci` command below, then
   build `cmd/main` for native and `tools/build_web.mbtx` for the shared JS colour
   bridge and local web runtime assets.
2. Run `pdf-viewer input.pdf output.canvas.json 1` (the native executable exported
   by Moon). This performs PDF parsing and image decoding once.
3. Run `node tools/render_canvas.mjs output.canvas.json output.png` with
   `@napi-rs/canvas` installed. `PDF_CANVAS_PACKAGE` may point to an existing host
   `package.json`; `PDF_VIEWER_BRIDGE` may select another built Moon JS module
   exporting `process_cmyk_to_rgb`.

The host runner consumes the public JSON, not a special test-only renderer. The
native Pattern Multiply fixture produces zero pixels above8 and maximum1 byte
against Ghostscript. No remote PDF upload or external rendering service is used.

## Common reproduction

Use the tested MoonBit toolchain, Linux C++20 compiler, Node 22.13.0+, and the
external reference CLIs (`pdftoppm` and `gs`). Install the locked runtime-asset
dependencies and the separate local test host:

```sh
npm ci --prefix tools/web-assets --ignore-scripts --omit=optional
npm install --prefix _build/a2-host @napi-rs/canvas@1.0.10 pdfjs-dist@6.4.299 @resvg/resvg-js@2.6.2
PDF_CANVAS_PACKAGE="$PWD/_build/a2-host/package.json" moon run tools/a2_check.mbtx
```

The `.mbtx` entry runs info/format, four target test suites, all-target checking,
a fresh release bridge/web build, Canvas/CMM resource tests and authored shading
assertions. The build runs `tools/prepare_web_assets.mjs`; it does not install
npm dependencies automatically. It does not download real PDFs or replace
their separately recorded measurements. Stage-specific documents list the
real-corpus reproduction.

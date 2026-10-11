# A2 structured Canvas compositing validation

## Implemented contract

`PdfPageModel.canvas_plan` retains source-order path geometry, winding-rule clip
stacks, affine pens, image sources, A1 glyph fragments/outlines, group invocation
IDs, independent shape/alpha, source colour components and mask/pattern plans.
The page is not rasterized from its completed SVG. Canvas2D supplies path/image
rasterization and the 16 standard blend kernels; PDF backdrop removal, nested
isolation, knockout, soft masks and process-ink compositing are explicit code.

Host output is tightly packed, top-left, straight RGBA8 (`stride = width * 4`).
Working RGB and process surfaces are Float32 premultiplied components with
independent shape and accumulated alpha. Process order is C, M, Y, K, then any
explicit proof colourants; `inkProof.stride` includes alpha. Geometry stays in
unscaled page coordinates until the viewport transform. Mask installation CTM,
Form matrix, BBox, `/BC`, `/TR`, `/AIS`, group boundary alpha and blend mode are
replayed separately. CMYK luminosity masks composite BC in process space before
output conversion. DeviceGray sources convert before group blending.

Nonisolated groups inherit their parent colour space. Isolated CMYK groups may
blend in CMYK inside RGB pages and convert once at their boundary. Combined fill
and stroke use the implicit groups required by ISO 32000-1 §11.7.4.4, including
text modes 2/6. Text outlines and font resolution are the existing A1 results.

`renderPdfCanvas(..., {backdrop, transparent:true})` supports nonisolated small
resource replay and returns the extracted source. Pattern adapters receive the
borrowed, knockout-aware `env.backdrop`, `env.blendSpace`, and shared diagnostics.

## Targets and safety

MoonBit JS, wasm, wasm-gc and native targets can emit the structured plan. The
pixel adapter itself needs a real Canvas2D host (browser/OffscreenCanvas or the
Node Canvas test host); this is not a claim of a native MoonBit raster backend.
The shipped browser entry initializes codec/CMM modules and invokes the adapter.

Surface pixel count, live group bytes, depth, mask recursion and resource build
counts are bounded. Mask resources are memoized within one page build and reject
self-reference. Source readback is cropped to conservative geometry bounds;
glyph source images are bounded per glyph, not cached as full-page bitmaps.
Unknown image decodes and missing colour conversions fail rather than silently
painting blank. Explicit `unsupported:'warn'` previews carry diagnostics for the
supported fallback cases. Ordinary additive display uses each Separation or
DeviceN's whole evaluated alternate; optional physical spot proofing requires a
transform of the complete colourant vector.

## Reproduction

Use the repository MoonBit toolchain and installed Node validation dependencies:

```sh
moon run tools/compositing_fixtures.mbtx -- _build/compositing-fixtures
moon build --release --target js cmd/pixel_plan
cp _build/js/release/build/cmd/pixel_plan/pixel_plan.js _build/pixel-plan.mjs
node tools/pixels/compositor_test.mjs
node tools/pixels/canvas_test.mjs
node tools/pixels/hairline_test.mjs
node tools/pixels/ink_compositor_test.mjs
node tools/pixels/compare_canvas.mjs _build/pixel-plan.mjs fixture.pdf
node tools/pixels/compare_ink_planes.mjs _build/pixel-plan.mjs \
  _build/compositing-fixtures/cmyk-blend-modes.pdf 1
node tools/pixels/compare_ink_planes.mjs _build/pixel-plan.mjs \
  _build/compositing-fixtures/ink-groups.pdf 5
```

`PDF_CANVAS_PACKAGE` can point to the package.json holding `@napi-rs/canvas`,
`pdfjs-dist`, and `@resvg/resvg-js`; `PDF_PIXEL_OUTPUT` selects the artifact folder.
The independent ink oracle also uses Ghostscript `tiffsep`, Python, Pillow and
numpy. It compares process components before display profiles can obscure a
compositing error. Reports include fixture SHA-256, oracle version, per-channel
errors and generated PNG/TIFF evidence. Upstream fixtures are pinned to PDF.js
`89b500f5e1d98ed89bb90211e45b28730b2d99ac`.

## Measured evidence

Host versions: @napi-rs/canvas 1.0.10, PDF.js 6.4.299, resvg 2.6.2,
Ghostscript 10.05.1. Pixel discrepancy counts use max RGB error >8, unless noted.

- Original `blend-modes.pdf`: all 16 RGB modes plus array fallback and Compatible;
  0 differing pixels, maximum error 2 versus PDF.js. Legacy SVG: 22,400 pixels.
- Original `cmyk-blend-modes.pdf`: all 16 CMYK modes, including the specified
  CMY-complement and separate K rules for nonseparable modes. Every C/M/Y/K sample
  agrees with Ghostscript within 1/255; no sample differs by more than 2.
  PDF.js instead differs in 20,800 RGB pixels on this explicit CMYK-space case.
- Original `ink-groups.pdf`: partial-alpha isolated overprint, nonisolated
  backdrop, nonisolated knockout, and Multiply+overprint agree with Ghostscript
  process plates within 1/255. Isolated knockout plus OPM1 has a documented
  oracle disagreement below.
- Pinned knockout_blend_multiply, knockout_inner_backdrop,
  knockout_nonisolated_sparse, knockout_isolated_overlap and
  knockout_nested_group_alpha: 0 differing pixels (max 0–1) versus PDF.js.
  Legacy SVG differs by 2,400–12,000 pixels on these pages.
- Pinned smask_alpha_bc and smask_luminosity_oob_transfer: 0 differing pixels,
  maximum 1. Pinned transparent.pdf: 0 differing pixels, maximum 3.
- Paint-space hairline dashes retain lengths and phase before affine projection.
  Four linear cases exactly match Skia's own dash effect. Cubic lengths are
  independently integrated to <0.001 user-unit error. Skia's coarser cubic dash
  approximation differs at 23–36 edge pixels; that difference is reported,
  not hidden behind a looser visual threshold. Zero-length on-dashes survive.
- Affine A1 text paths now replay directly instead of sampling glyph SVG images.
  The text-stroke workstream supplies the larger rotations/scales comparison.

### Oracle disagreements retained deliberately

1. `knockout_nested.pdf` and `knockout_smask.pdf`: 4,000 overlap pixels differ
   from PDF.js because group/soft-mask opacity is not the geometric knockout
   shape. Our result agrees with Ghostscript to rounding. At (90,70), nested
   output is (128,128,255), Ghostscript (127,127,255), PDF.js (128,64,191).
2. Combined text fill/stroke with unequal alpha uses the normative knockout
   rule. Ghostscript agrees; Poppler/PDF.js composite stroke over fill in the
   authored text fixture. With Ghostscript 4-bit antialiasing, direct Canvas
   page-4 MAE is 0.346 versus legacy SVG 0.961 and Poppler 1.015.
3. Isolated CMYK knockout plus OPM1: our alpha/shape equations and PDF.js give
   only 50% magenta in the overwritten area. Ghostscript tiffsep also marks
   C/Y/K at 50%. The other four process-group cases match. This remains an
   explicitly recorded cross-renderer disagreement, not a claimed match.
4. Degenerate whole subpaths paint only with round caps, per ISO 32000-1
   §8.5.3.2. Ghostscript agrees; PDF.js/Skia also draw projecting-square caps.
   The adapter filters those whole subpaths while preserving zero-length dash
   marks. Hairline zero-length dashes retain the transformed tangent with a
   1/1024-device-pixel orientation carrier, below a one-byte coverage change.
5. PDF.js clamps some nonzero subpixel strokes to one device pixel. The backend
   retains geometric 0.25/0.5-pixel coverage rather than blanket-clamping all
   strokes; zero-width hairlines are one device pixel. `/SA` requires separate
   graphics-state policy and must not be inferred from this oracle difference.

### Further source integration

The current adapter reconstructs retained CMYK image components through the
same Canvas affine image geometry and interpolation as display images. The
progressive CMYK JPEG group fixture (Multiply, constant alpha 0.65) matches every
Ghostscript process-plane sample within 2/255, with no sample above that error.
Image explicit masks contribute shape; image soft masks contribute opacity
unless AIS is true. Image-local masks replace the graphics-state soft mask.

TK-enabled text objects now use implicit nonisolated knockout groups keyed by
invocation-scoped BT/ET identity. Actual six-page text fixtures distinguish TK
false, separate BT objects and repeated Forms. Unmasked TK knockout agrees with
Ghostscript; masked TK reveals another documented cross-renderer disagreement
where references composite rather than knock out overlapping glyphs.

Pattern cell shape and backdrop are now replayed independently, including four
process-component passes. Per-paint cache identity is shared across colour and
shape, never reused after the backdrop mutates. Backdrop-dependent pattern
interiors agree with Ghostscript, while cached fractional-cell edge resampling
remains separately measured by the pattern workstream.

## Profile-scoped group replay

The Canvas adapter creates an asynchronous-safe page profile scope and shares it
with nested masks and pattern cells. Original ICC RGB/Gray/CMYK components are
blended in the declared group domain, then converted through the actual output
profile. Isolated cross-space/profile groups convert only at the group boundary;
nonisolated groups retain the parent's domain. Group rendering intent is retained.
Luminosity-mask BC is composited in the mask's original component domain before
output conversion and luminosity extraction.

`tools/pixels/group_colour_test.mjs _build/pixel-plan.mjs` parses an original
ICC-RGB Multiply PDF and checks raw group values, profile-transformed output,
concurrent pages using identical local profile IDs, and cleanup after failure.
The focused suite passes alongside all 37 Canvas replay regressions. Add
`--ghostscript` to reproduce the independent fifteen-PDF pixel oracle: ICC path,
image, stencil, pattern, shading, mask BC, isolated Form and CalRGB
path/image/stencil/pattern cases all have maximum error 1 byte; CalGray
path/image/stencil/pattern cases are
pixel-exact. The report records source hashes and
Ghostscript version. Image
replay restores original component ranges and uses the shared Float32 affine
sampling and axis-aligned device-edge policy. Shadings and patterns receive the
active original-component transform and inherited profile scope.

## Remaining integration boundaries

Calibrated CalRGB/CalGray targets now retain original component values, convert
sources through D50 PCS, and apply the analytic calibration inverse before
blending. Authored parsed PDFs verify Multiply in both domains. ICC paths,
images, shadings, patterns, masks and isolated Forms have end-to-end regressions.
Terminal image tint/Indexed/PCS sample expansion is integrated. Retained
PatternType2 and Type3 scenes use the common source-scene replay API. Nine
original shading-pattern PDFs exercise Background knockout, internal ExtGState
alpha/blend/mask, independent outer paint attributes and patterned strokes.
Fourteen Type3 pages across eight scale/rotation combinations retain colored
CharProc paints and match equivalent ordinary-paint controls. See the dedicated
[Type3 report](validation/type3-scenes.md). Native A1 fill outlines, fallback
fill/stroke masks and image stencils retain tiling/shading patterns; the
[text-paint report](validation/text-paints.md) covers 96 authored viewports. Optional spot
proof output needs a real full-vector transform; ordinary additive display uses
the standard whole-alternate policy. These limits are not silently labelled
complete by the analytic or fixture results above.

Normative basis: [ISO 32000-1:2008](https://opensource.adobe.com/dc-acrobat-sdk-docs/standards/pdfstandards/pdf/PDF32000_2008.pdf),
§§8.6.6, 10.3.4, 11.3–11.7 (especially 11.7.4.4 and Table 149).

Decoded image reuse is bounded to 64 entries and the smaller of 64 MiB or one
eighth of the working budget. Eviction and completion release owned bitmap
handles; failure cleanup is covered. Retained source-plane image buffers and
soft-mask samples count toward nested replay budgets. Type3 scene surfaces and
readback use the union of actual child-paint bounds,
including affine pen and filter expansion. Missing bounds, shading, incompatible
page coordinates and diagnostic cases retain full-page fallback. Outer text
selection bounds are never used to clip arbitrary CharProc marks.

Optional additive proof planes reserve process/spot arrays, registration, alpha,
shape, coverage and resolved output against the same working-memory limit before
allocation. Plane growth is checked before adding a colorant. RGB/CMYK working
budgets also reserve raster staging and simultaneous blend scratch surfaces.

## Bounded replay and performance

`tools/pixels/dirty_region_test.mjs` compares full-surface and conservative-region
composition for all 16 blend modes, RGB/CMYK groups and both knockout settings:
64 complete pixel/shape results are bit-identical.
`tools/pixels/pattern_region_test.mjs` additionally compares full-page and
region-bounded nonisolated pattern cell replay for eight RGB/CMYK affine cases;
pixels and independent shape are exact. Cropping changes work, not equations.
Fallback glyph/stencil patterns tighten their tile region using the already
rasterized nonzero alpha mask. The existing per-paint cell limit stays enforced.
Retained scene and pattern-field bitmaps are explicitly released after the last
component/shape pass, including failure paths.

A fresh-process, renderer-only comparison using one parsed `issue13931` plan
measured 4.038 seconds with full paint loops and 0.635 seconds with bounded loops,
with identical pixels. A separate glyph-raster correction bases padding on the
transformed em rather than the raw PDF font-size operand; this reduced that
renderer-only peak retained footprint from roughly 2.02 GB to 278 MB. That
separate crop changes bitmap resampling and is not included in the pixel-identity
claim. Native A1 fill outlines now bypass these temporary glyph bitmaps entirely.
These measurements exclude parsing/bridge/CMM setup and are not directly
comparable to full-entry RSS figures.

The same saved 6,521-paint Altona plan was also rendered with bounded loops and
`fullSurfaceReplay:true` in fresh processes: all RGBA bytes were identical.
Replay time was 32.37 seconds versus 173.60 seconds (5.36× faster). This comparison
uses the same current renderer and does not mix in parsing or glyph-payload
changes.

Identical fallback glyph rasters share a per-render LRU across nested pattern and
Type3 replay. The 64-entry cache counts both decoded pixels and SVG key bytes,
is capped at 16 MiB or one thirty-second of the configured working limit, and
reserves that capacity once in the shared budget. Only the outer owner disposes
it; uncached/evicted images release immediately. Oversized glyph rasters reject
before host allocation. This reduces the pinned real nested-Type3 fixture to
16 SVG loads across 20,613 tiny-cell Canvas allocations and completes strict
replay in 4.05 seconds with zero diagnostics. At 1×, Canvas RGB MAE is 0.8794
versus PDF.js, 0.9815 versus Poppler and 0.6368 versus Ghostscript; legacy SVG
versus PDF.js is 2.8208. The differences remain reported rather than hidden by
tolerance changes. RGB and CMYK blend scratch is released on both isolated
group exit and failed page replay.

A host may optionally supply `resolveTextOutline(svg, {paint, page})` for ordinary
stroked glyphs whose A1 pen outline is unavailable. The awaited result contains
page-SVG `fill_path` and pen-local `stroke_path`; successful native-path validation
removes only that item's `PDF_TEXT_STROKE_GEOMETRY` diagnostic. `null` retains the
existing strict diagnostic, unrelated diagnostics are preserved, and Type3 scenes
never use this hook. The callback does not modify PDF font selection or decoding.
It is an explicit host capability, not an assertion that every browser can
extract arbitrary system-font outlines.

## Explicit host raster boundary: shared-edge antialiasing

`node tools/pixels/coverage_seams.mjs _build/pixel-plan.mjs` generates and parses
a minimal PDF containing two adjacent opaque equal-colour rectangles. Their
shared edge is at x=30.221. The installed Canvas host supplies separate coverages
0.2196078 and 0.7764706, whose source-over alpha is 0.8255594. The adapter produces
RGB (175,177,178); direct host drawing produces (175,176,177). All pixels differ
by at most one byte between these two implementations. A single compound path
and Ghostscript both produce solid (158,160,161) at that edge.

This characterizes a remaining independent-fill antialias seam, reproduced in
534 Altona table pixels. The installed Canvas API exposes no supported path-AA
coverage control. It is not a colour transform or premultiplied equation defect.
The real source pair also uses different component-marking semantics: DeviceCMYK
with OPM1 preserves zero C/M/Y while DeviceGray marks those components. Their
matching result on this backdrop does not authorize merging their paints.
Geometry expansion, coordinate snapping, broad fill batching and tolerance
changes are deliberately not used to erase the difference. The source hash,
measurements and oracle version are in [the reproduction report](a2-coverage-seams.json).

## Replay allocation closure

The final deduplicated Altona plan was replayed without PDF parsing or forced GC
in fresh Node processes. The instrumented baseline took 36.19 seconds and peaked
at 3,562,938,368 bytes RSS. Actual-child scene bounds, bounded parent readback,
reusable CMYK paint/blend scratch and explicitly recycled group frames produced
the identical 4,017,440 RGBA bytes in 9.94 seconds with peak RSS 791,789,568 bytes.
The common loaded-plan/CMM baseline was approximately 228 MB. These are process
measurements, not a claim that total process RSS equals `maxWorkingBytes`: that
limit governs owned raster/plane/frame storage, while host/runtime allocations
and garbage-collection timing remain outside it.

The separate, uninstrumented public `tools/render_canvas.mjs` command completed
in 10.62 seconds with kernel peak RSS 783,416 KiB (802,217,984 bytes). Its PNG
decodes to the same byte-identical RGBA result and reports no diagnostics. Since
GNU `/usr/bin/time` is absent from this environment, a fresh parent process used
POSIX `getrusage(RUSAGE_CHILDREN)` to collect the child's kernel high-water mark;
no sampling hooks or forced GC were installed in the renderer.

The phase probe localized most of the spike to full-page Type3 bitmap/readback
allocation near the end of the page. `Canvas2D.reset()` alone did not fix it and
was not retained. The maximum tracked Canvas pixel area fell from 7,438,061 to
2,374,304 pixels. `tools/pixels/profile_canvas_allocations.mjs` reproduces the
replay-only measurement and records plan/renderer/pixel hashes, typed-array and
heap counters, live tracked surface area and process peak RSS. The compact
[allocation report](a2-allocation-validation.json) retains the comparison without
redistributing the source PDF or ICC catalog.

`scene_region_test.mjs` verifies eight RGB/CMYK affine nested-scene results against
full-page replay, including masks, strokes and deliberately misleading outer
text-selection bounds. `surface_reuse_test.mjs` checks leased-frame budget
enforcement, exact zero outside recycled source regions, storage reuse and
unchanged ownership of default exported group results. Pool and scratch bytes
are included in nested-resource accounting; recycling is explicit and occurs
only after the parent consumes the result. All prior 64 dirty-region and 37
Canvas regressions, 15 profile PDFs, nine shading-pattern PDFs and the fourteen
authored Type3 pages continue to pass. The complete 112-page/scale/rotation
Type3 sweep was also rerun against this change: every Canvas PNG and every
PDF.js/Poppler/Ghostscript comparison record is identical to its saved control;
no tolerance, fixture or reference selection changed.

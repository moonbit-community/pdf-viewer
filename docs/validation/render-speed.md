# Render speed investigation

Measured on 2026-10-13 through 2026-10-15 against PDF.js revision
`89b500f5e1d98ed89bb90211e45b28730b2d99ac` (generic build 6.5.1),
Playwright 1.58.2 and a local 13-page PDF. The input and detailed reports stay in
ignored `_build/`; no document text, images or input bytes are published here.

## Reproduce

Build the [pinned reference](../../reference/README.md) and the packaged viewer:

```sh
moon run tools/build_pages.mbtx
PDF_BENCH_PROFILE=1 node tools/render_benchmark.mjs /path/to/document.pdf 1,2,12
PDF_BROWSER=chromium PDF_BENCH_PROFILE=1 node tools/render_benchmark.mjs /path/to/document.pdf 1,2,12
PDF_BENCH_REPLAYS=9 PDF_BENCH_PROFILE=1 node tools/render_benchmark.mjs /path/to/document.pdf 2,12
node tools/pixels/profile_page_stages.mjs /path/to/document.pdf _build/stages.json 1,2,12
PDF_BENCH_BASELINE_ROOT=/path/to/previous/static-build PDF_BENCH_SAMPLES=6 node tools/first_load_benchmark.mjs /path/to/document.pdf
PDF_BROWSER=chromium PDF_BENCH_BASELINE_ROOT=/path/to/previous/static-build PDF_BENCH_SAMPLES=6 node tools/first_load_benchmark.mjs /path/to/document.pdf
```

Browser runs use DPR 2 and matching Canvas dimensions (2432 x 3436 for this
input). Reader prefetch finishes before replay. Worker replay requests three
distinct zoom levels: the parsed page is cached, but the resulting payload is
new. Reports separate queue waiting, Worker round trips, JSON parsing, paint and
forced pixel flush. Source/module hashes identify each compared build.

Diagnostic replay runs in a separate process/browser after ordinary samples,
which use the original Canvas modules and prototypes. Only diagnostic fields
are merged, after checking source/module hashes and browser/output dimensions.
Its nested scenes,
Canvas operations and yield time overlap; their inclusive times must not be
added together. Node stage timings describe the readable release bridge and
must not be compared directly with browser timing. PDF.js operator lists are
prepared with a fresh document after rendering measurements; these timings
exclude Canvas paint and DOM text layers.

Ordinary and freshly cloned Canvas plans also produce complete RGBA SHA-256
hashes. Before/after runs check identical input bytes, reference revision,
browser engine, DPR, output dimensions, reader pixels and reference pixels.
Cloning and hashing run outside the reported paint/flush measurements.

## First-page measurement

`first_load_benchmark.mjs` opens the unchanged packaged reader through its
ordinary file input, with a fresh browser context and Worker for every sample.
The reader shell and PDF.js module finish loading before timing. Both sides
start from a `File` read, with document parsing, Worker startup and the first
page's resource preparation included. Complete Canvas output is followed by
a one-pixel flush and two animation frames; full-page hashing happens afterwards.

When `PDF_BENCH_BASELINE_ROOT` is set, old and new artifacts run sequentially in
alternating order within each sample. The tool records module hashes, matching
Canvas dimensions, individual samples and medians. It rejects any changed
reader pixel, input or reference revision. The separate reader-ready marker
means the page, text, annotations and fonts have mounted and the reader is no
longer busy; document metadata may still be pending. PDF.js uses its Canvas API
without its viewer UI or text/annotation layers. These measurements assess
first-page Canvas visibility rather than complete reader feature parity or
cold OS/browser caches. They exclude downloading the input PDF and application
shell from a remote host.

Six paired fresh opens compare `87efa0c` with the font and image-row changes
below. These are medians from each browser's same sequential A/B batch, including
the first page's pixel flush and two animation frames.

| Browser | Before | After | Reduction | PDF.js Canvas API |
| --- | ---: | ---: | ---: | ---: |
| WebKit 26.0 | 1304.5 ms | 1185.5 ms | 9.1% | 330.0 ms |
| Chromium 145.0.7632.6 | 948.9 ms | 863.6 ms | 9.0% | 168.0 ms |

Every WebKit pair is faster; five of six Chromium pairs are faster. This input
still opens substantially slower than the PDF.js Canvas reference. The reference
does not mount reader UI, text or annotation layers. These results use pinned
Playwright engines, rather than the user's installed Safari. Complete before/
after first-page RGBA hashes match within each engine.

## Fixed: repeated font parsing and RGB pixel work on first open

Indirect fonts previously ran the recovery/Unicode reader again at every `Tf`
and ExtGState font binding. The page's existing resource context now shares
successful parsed fonts by indirect object number, capped at 128 entries and
discarded after the build. This also spans nested Forms, patterns, masks and
Type3 scenes. Each binding still resolves the current resource dictionary,
including after unmatched `Q` recovery; direct font dictionaries retain the
original reader path. Failed reads are not retained, and font, editing,
document and Range retries receive fresh page contexts.

On this input's first page, the expensive font recovery reader runs 57 times
instead of 148. Font sharing and RGB row copies alone did not produce a stable
first-page gain in paired browser runs; the reported speedup includes the
compact ICC loop below.

Opaque 8-bit identity RGB images already have exact display bytes. When the
horizontal source size is unchanged and process samples are not retained,
the image converter copies each row with the core byte primitive instead of
repeating coordinate arithmetic and channel stores for every pixel. Row
padding and the source row stride remain separate from PNG row filters.
Masks, changed Decode arrays, calibrated/ICC colours, horizontal resampling
and retained process components continue through their original sample rules.

The two large opaque ICC RGB images on the first page contain about 1.56 million
pixels. The existing colour cache already limited CMM calls to 2584, but every
pixel still traversed the generic image converter's coordinate, state and
component-key branches. A compact loop now keeps only exact packed output RGB
bytes for these unscaled 8-bit images. Its 4096-entry palette uses the same
Decode, source/ICC range clipping, LittleCMS and byte rounding. Failed transforms
use the same Alternate conversion without retaining it as a successful colour;
masks, alpha, retained components and resizing keep the general converter.
Both complete PNG bytes and all 13 page render payloads remain byte-identical.

## Fixed: semantic work repeated on cached pages

`accessibility_page_json` consumed the provenance captured by the initial page
parse. Later zooms reused `PdfPageModel` but collected the entire text stream
again for semantic mapping. On page 12 this repeated 186 font reads and 628 Flate
decodes in the Node profile.

The browser page cache now retains the semantic manifest alongside its page
model, with shared eviction, invalidation and memory accounting. In paired
WebKit runs, median Worker round trips for three new zoom payloads changed from
**154 ms to 25 ms**. On Node, cached bridge execution changed from **94 ms to
14 ms**, with no additional font reads, Flate decodes or content collection.
Cached Canvas and semantic hashes remain identical. This improves zoom payload
preparation; it does not measure the complete time until a zoomed page is drawn.

Regression checks cover original semantics across zoom/rotation, layer and font
invalidation, document close, metadata-only hydration and budget exhaustion.
The Range acceptance checks retain tagged semantics as new objects arrive.

## Fixed: unnecessary startup dependencies

Live acceptance also caught Worker startup timeouts before any PDF parsing on
both browser engines. The deployed parser bytes matched the local build. This
does not establish a specific CDN failure mechanism, but exposed avoidable work:
the Worker imported the complete display runtime and XFA engine for every PDF.

`pdf-graphics.mjs` now isolates the unchanged synchronous graphics initialization.
The Worker retains both ICC and JBIG2 readiness before accepting messages, while
ordinary startup fetches **8 resources instead of 22**, including the two Wasm
files. XFA binding and DOM rendering load on demand. The legacy runtime export
remains compatible, and an XFA DOM import completed after document replacement
returns an empty layer. The 15-second startup deadline is unchanged.

Subsequent live Chromium acceptance passed, while WebKit still timed out waiting
for secondary Worker module requests. The Pages build now uses the existing
locked esbuild to bundle the parser, Range loader and graphics adapters into
one Worker entry, followed by the two Wasm files. XFA remains an external dynamic
import; there are no shared chunks that import the entry again. Development
modules remain readable. JBIG2 resolves its Wasm URL from the root graphics
adapter, preserving repository subpath hosting after bundling.

Packaged acceptance rejects secondary startup JS requests and checks both
adapter readiness and actual JBIG2/ICC pixels, alongside XFA rendering, editing
and cancellation. The new startup request check fails against the previous
unbundled artifact. This removes the module fetch waterfall; recovery from the
observed live timeout needs separate evidence. After deployment, all eight live
WebKit checks passed. The first concurrent Chromium check still hit the startup
deadline; a fresh, separate Chromium run passed all eight checks. Published
Worker bytes match the local artifact. These checks verify the deployed build,
but do not establish that intermittent startup waiting has been eliminated.

## Fixed: rebuilding independent pattern bitmaps on every redraw

The per-render pattern painter discarded its colour and coverage bitmaps after
each page paint. The document image cache avoided decoding those photos again,
but nine opaque image patterns on page 12 still rebuilt about 3 MiB of repeating
surfaces on every redraw. Path construction was smaller: 878 `Path2D` calls took
about 1 ms in the diagnostic run.

The viewer now retains independent RGB cell bitmaps in a document-owned
16 MiB/32-entry pool. It reuses the existing raster pool's lease and eviction
logic, with the complete cell payload, raster dimensions, sampling/size policies
and host identities in the key. Newly parsed objects can reuse identical cells;
changed contents, limits and sampling policies cannot. Document, editing, font
and layer invalidation clear the pool. Concurrent pending builders stay separate
so cancelling one render cannot cancel another. Active consumers release retired
surfaces after their last lease. Transparent cells retain only their coverage
classification and preserve device-space replay; backdrop-dependent and proof
patterns keep the existing retained rendering.

Full-coverage shape masks now use an opaque rectangle instead of allocating and
uploading alpha-only pixel buffers. Partial-coverage masks retain their original
pixels. This also avoids creating repeating textures that transparent replay
immediately discarded.

The final sequential A/B runs compare the previous build `2aeac95` with this
change. Warm medians include forced pixel flush and use three ordinary samples;
the cloned-plan column is a separate replay at the same physical dimensions.

| Browser / page | Warm before | Warm after | Cloned plan before / after | PDF.js warm after |
| --- | ---: | ---: | ---: | ---: |
| Chromium / 12 | 54.9 ms | 26.8 ms | 52.3 / 28.0 ms | 24.8 ms |
| WebKit / 12 | 147 ms | 90 ms | 89 / 44 ms | 19 ms |
| Chromium / 2 | 19.7 ms | 22.3 ms | 19.5 / 19.8 ms | 22.5 ms |
| WebKit / 2 | 16 ms | 17 ms | 13 / 11 ms | 17 ms |

Every before/after reader and cloned-plan pixel hash matches exactly within each
engine, and differences from PDF.js are unchanged. On page 12 the ordinary pool
records 15 loads and 36 hits, with no active leases after replay. WebKit samples
vary substantially (117–162 ms before, 54–93 ms after); earlier paired runs also
showed 114 → 43 ms. These are repeated drawings at a matching raster size,
not complete open/zoom latency. The first page-12 paint recorded during these
navigation runs remains about 111 ms in Chromium and 171 ms in WebKit; this
change mainly benefits warm redraws.

Page-12 diagnostic traffic falls from **50 reads / 54 uploads to 24 reads /
36 uploads**. Read pixels fall from 798,298 to 31,636, and upload pixels from
812,236 to 47,454. The remaining transfers come from six shading-pattern scenes,
which still rasterize colour and coverage, convert Float32 components and create
scene bitmaps. The next drawing target is this retained shading path, especially
the cost of small repeated uploads in WebKit.

Focused checks cover affine placement, complete-cell content changes, sampling
changes, decoded-image limits, transparent coverage, bounded eviction, active
and pending document disposal, concurrent cancellation and failed builders.
Packaged Chromium/WebKit checks exercise the actual viewer loader across cloned
plans and document invalidation, preventing per-paint callback identity from
silently defeating reuse.

## Fixed: duplicate opaque shading passes and unused scene output

Six shading-pattern scenes still drew colour and coverage separately. Their
internal renders then encoded and uploaded RGBA targets that the caller
discarded, consuming only retained colour/shape buffers. The default renderer
now uses an opaque RGB source's clipped colour alpha as its coverage. Direct
shading and the existing pattern-carried representations share the proof.
Structured scenes additionally require one independent unit-opacity source
against transparency, with no scene annotations or soft-mask backdrop colour.
Custom adapters and unsupported colour/opacity cases keep separate coverage.
`fullShapeReplay: true` provides the original separate-pass comparison.

Scene, mask and backdrop-pattern callers now request retained samples without
encoding or uploading their unused RGBA targets. This request is consumed at
the call boundary; nested repeating tiles and native retained surfaces still
publish their Canvas output. Annotation-bearing scenes keep the existing Canvas
composition and RGBA result.

The final A/B runs compare `dd64f39` with this change, using **nine ordinary
replays per renderer** in separate sequential browser runs. Each run opens the
same local PDF through the actual packaged reader and captures its Worker plan
and host paint arguments. The tests add no PDF opening or parsing path.
Before/after reader, cloned-plan and reference hashes match exactly within
each engine; the differences from PDF.js are unchanged.

| Browser / page | Warm before | Warm after | First recorded paint before / after | PDF.js warm after |
| --- | ---: | ---: | ---: | ---: |
| WebKit / 12 | 56 ms | 34 ms | 157 / 141 ms | 18 ms |
| Chromium / 12 | 25.9 ms | 25.1 ms | 114.1 / 110.6 ms | 24.8 ms |
| WebKit / 2 | 12 ms | 12 ms | 10 / 9 ms | 17 ms |
| Chromium / 2 | 21.9 ms | 19.1 ms | 22.2 / 20.4 ms | 23.7 ms |

The page-12 WebKit warm median improves by about **39%**. Its samples range from
46–92 ms before and 27–44 ms after; a separate cloned-plan sample is 45 / 44 ms,
so that single measurement does not show the same speedup. These measurements
include forced pixel flush, exclude cloning/hashing, and are not complete
open/zoom latency. First-paint differences during navigation do not isolate
uncached image decoding. Chromium remains close to its previous speed.

Both engines reduce page-12 diagnostic traffic from **24 reads / 36 uploads to
12 reads / 18 uploads**. The 37 focused checks compare complete RGBA, coverage and
premultiplied/CMYK buffers, exercise both existing shading representations,
initial backdrops, group opacity/knockout, soft-mask BC, annotations, custom
adapters and nested Canvas publication. The same default production adapters
run in the benchmark; custom test callbacks are negative fallback checks.

## 2026-10-15: first-open follow-up

Six fresh-open A/B pairs per engine compare the preceding packaged build with
the following changes. Baseline and candidate run sequentially in alternating
order; Chromium and WebKit batches also run sequentially. Measurements retain
the first-page method and reference limitations described above.

| Browser | Before | After | Change | PDF.js Canvas API |
| --- | ---: | ---: | ---: | ---: |
| Chromium 145.0.7632.6 | 812.0 ms | 816.1 ms | +0.5% | 144.0 ms |
| WebKit 26.0 | 873.0 ms | 817.0 ms | -6.4% | 245.5 ms |

Five of six WebKit pairs improve. Chromium splits three faster and three slower
pairs and shows no measured first-open gain. Its baseline samples span
722–1246 ms and candidate samples 740–1139 ms. These local measurements do not
establish a portable speedup or first-open parity: the candidate is still about
5.7 times the Chromium reference and 3.3 times the WebKit reference.

- Type3 glyph lookup previously expanded all 256 character codes for every
  invocation, separately for the retained scene and compatibility outline.
  A page-owned table now shares bindings for at most 128 indirect fonts. The
  diagnostic input needs 57 table expansions instead of 530 on page 1.
  Direct dictionaries retain their original lookup. Graphics state, resources,
  clipping, placement and the actual CharProc paints remain invocation-local.
- Compatibility outlines share the page's existing font reader context.
- Bounded image Flate output uses bulk byte copies between the decoder and its
  result buffer. Limits, prefix handling and trailer validation are unchanged.
- Opaque ICC RGB runs reuse the preceding successful palette hit without a
  hash lookup. Failed transforms still retry, and the 4096-colour cap remains.
- Browser cache accounting counts the exact default JSON writer length without
  materializing a discarded serialized page. It keeps numeric spellings, string
  escaping, UTF-16 sizing, the 32 MiB budget and eviction decisions unchanged.

All 13 complete render payloads and their per-page cache statistics match the
baseline byte for byte. Both engines' fresh-open batches require identical
complete baseline/candidate RGBA hashes, stable reference hashes and matching
Canvas dimensions. Regression checks cover cache string escapes/Unicode/numeric
spellings, Type3 binding precedence and saturation, and nonuniform Flate output
across decoder windows. Existing ICC checks cover failed transforms and palette
saturation. Detailed local reports are under `_build/perf-2026-10-15/`.
The full default-target suite passes 715 tests and the JS suite passes 720;
packaged browser acceptance passes on Chromium and WebKit. `moon info` produces
no interface changes, and `moon fmt` completes successfully.

The next substantial first-open target is the image transport: colour-converted
pixels currently become compressed PNGs and base64 JSON in the Worker, then
become decoded images again in the host. A browser-specific typed-buffer path
could remove this encoding/decoding round trip; it still needs bounded ownership,
cancellation, masks, ICC, native/SVG compatibility and pixel validation. Worker
code loading/evaluation and the large per-viewport JSON payload are the other
remaining targets. This follow-up implements the local changes above and does
not claim those architectural changes are complete.

## Root-cause follow-up: image preparation before drawing

The earlier small improvements did not isolate the main first-open gap. A new
counterfactual records the exact results of one preparation stage, then reuses
those results while reopening the same document. The reusable diagnostic is:

```sh
node tools/pixels/profile_prepare_work.mjs /path/to/document.pdf _build/prepare-images.json 1 images
node tools/pixels/profile_prepare_work.mjs /path/to/document.pdf _build/prepare-png.json 1 png
node tools/pixels/profile_prepare_work.mjs /path/to/document.pdf _build/prepare-flate.json 1 imageflate
```

Stages also include `icc`, `fonts`, `type3` and `flate`. Each command runs seven
alternating ordinary/reuse pairs on fresh documents in one Node process, after
recording has warmed the JIT and adapters. It requires byte-identical complete
render payloads. These timings are diagnostic, overlap across stages, and must
not be added together or compared directly with browser latency.

The initial Node experiments measured the following medians on page 1:

| Previously computed results reused | Ordinary | Reused | Calls |
| --- | ---: | ---: | ---: |
| Complete image resources | 234.2 ms | 102.7 ms | 10 |
| Image Flate decoding | 236.0 ms | 155.9 ms | 12, including profiles |
| PNG encoding | 237.4 ms | 194.5 ms | 10 |
| Opaque ICC RGB rows | 235.4 ms | 220.0 ms | 2 |
| Font loading | 237.4 ms | 226.0 ms | 148 |
| Type3 scenes and compatibility outlines | 237.9 ms | 194.5 ms | 265 each |

The largest measured preparation component is the image pipeline, contributing
about 56% of ordinary warmed Node page preparation. Images are expanded through
the transport-oriented zlib streaming decoder, converted, compressed into PNGs,
and later decoded again for drawing. The streaming zlib wrapper checksums each
output byte separately and stages compressed input. A separate checksum-only
experiment reduces Node page preparation from 233.3 to 218.3 ms, so checksum
arithmetic explains only part of the image decoding cost.

An additional packaged-browser counterfactual substitutes the **same ten exact
image resources** prepared before measurement. The substituted resources contain
the original PNGs; output JSON, host image decoding, painting, reader UI and
Worker creation remain in the measured path. Its reconstructed baseline Worker
matches the `0e5f4da` build byte for byte. Six alternating fresh-open Chromium
pairs measure:

| Median phase | Ordinary | Images already prepared |
| --- | ---: | ---: |
| Worker startup | 135.7 ms | 135.5 ms |
| Document open RPC | 38.4 ms | 38.0 ms |
| Page preparation RPC | 369.5 ms | 181.4 ms |
| Host Canvas paint | 55.8 ms | 56.4 ms |
| First-page Canvas visible | 632.8 ms | 446.2 ms |

Every pair improves and complete first-page RGBA hashes match. First-page
visibility improves by **29.5%**, with almost the whole difference occurring in
the preparation RPC. This is an upper-bound diagnostic that moves image work
outside measurement, **not a production optimization or a new PDF cache**.
The same batch's PDF.js first-page median is 117.5 ms; its 62.0 ms render task
includes reference resource preparation as well as paint. Our image preparation
is a major component of the gap, while Worker startup and the remaining page
preparation also require attention. Removing image preparation alone does not
establish parity.

A compatible direct-Inflater prototype preserves all 13 payloads and passes
framing/output-limit differential checks against the original driver. Its actual
fresh-open improvement is only **2.1% in Chromium** (638.0 to 624.7 ms) and
**1.0% in WebKit** (695 to 688 ms), across six pairs per engine. This is too small
to resolve the identified pipeline cost, so that production change was reverted;
the prototype and its checks remain local under `_build/root-gap/`.

The counterfactual motivated the image codec change below. Native asynchronous
decompression and bounded pixel/bitmap transport remain possible later changes;
they need explicit ownership across page/render caches, cancellation,
colour/mask fidelity and native/SVG fallback. The ten captured image resource results serialize to
about 134,000 characters, including diagnostic result wrappers; most of the
roughly 1.87 million-character render payload is elsewhere, so large JSON
geometry is a separate problem. Worker
loading/evaluation must also be reduced: its 136 ms startup alone exceeds this
batch's complete 118 ms PDF.js first page.

## 2026-10-15: accelerate the image codec in the browser Worker

The Worker now installs a pinned pako 2.1.0 adapter for image Flate expansion
and PNG compression. Typed-array output avoids the portable zlib driver's
per-byte staging, and level-1 compression reduces the cost of recompressing
already available display pixels. Colour conversion, masks and PNG/SVG formats
remain unchanged. The portable engine remains the default on other hosts.

The host decoder stops at the first validated zlib trailer and uses output
chunks no larger than 32 KiB, with one excess byte to detect the caller's
output bound. It retains no cross-document decode cache. Invalid, truncated,
dictionary-dependent or oversized attempts fall back to the existing decoder,
preserving damaged-stream prefix recovery and error precedence. Empty results
also use the portable path. Source hashes, npm archive integrity, tool version
and license copying are pinned by the build.

ICC and JBIG2 fetch/compile attempts now run concurrently. Both still settle
before the Worker accepts document operations. This removes their serial
dependency, but does not materially reduce the dominant module evaluation cost
on this input.

Six alternating fresh-open pairs per engine compare the published candidate
against the byte-identical `0e5f4da` static baseline. The same private 13-page
input, browser versions, DPR 2, timing scope and pinned PDF.js reference from
the preceding measurements are used. No profiling or other test process runs
concurrently. These are this batch's medians, not comparisons across batches:

| Engine / median phase | Baseline | Candidate |
| --- | ---: | ---: |
| Chromium first-page Canvas visible | 679.6 ms | **568.8 ms (-16.3%)** |
| Chromium page preparation RPC | 392.3 ms | **289.4 ms** |
| Chromium Worker startup | 139.8 ms | 137.5 ms |
| Chromium host paint | 60.5 ms | 60.0 ms |
| WebKit first-page Canvas visible | 811.5 ms | **716.0 ms (-11.8%)** |
| WebKit page preparation RPC | 436.5 ms | **343.0 ms** |
| WebKit Worker startup | 134.5 ms | 134.5 ms |
| WebKit host paint | 87.5 ms | 78.5 ms |

Every pair improves, and all twelve complete first-page RGBA hashes match the
baseline. PDF.js Canvas first-page medians in the same batches are 127.8 ms
for Chromium and 212.5 ms for WebKit. This closes part of the preparation gap;
it does **not** establish PDF.js parity. Its measurement excludes reader UI,
selection and annotations as documented above.

Validation covers 715 default-target and 720 JS MoonBit tests; 1,396 actual
release-bridge inflate comparisons with/without the host (118 successful
nonempty fast decodes); RGB/RGBA PNG sample equality; all 13 complete page
payloads after canonicalizing PNG samples; the real Worker transport suite;
and all nine packaged-reader checks in each browser. Public `.mbti` interfaces
are unchanged. PNG compressed bytes can differ; their decoded samples match.

```sh
node tools/pixels/image_flate_test.mjs
node tools/pixels/image_flate_test.mjs /path/to/document.pdf
PDF_BROWSER=chromium PDF_BENCH_SAMPLES=6 PDF_BENCH_BASELINE_ROOT=/path/to/baseline \
  node tools/first_load_benchmark.mjs /path/to/document.pdf _build/chromium-first-open.json
PDF_BROWSER=webkit PDF_BENCH_SAMPLES=6 PDF_BENCH_BASELINE_ROOT=/path/to/baseline \
  node tools/first_load_benchmark.mjs /path/to/document.pdf _build/webkit-first-open.json
```

Local raw reports are `_build/root-gap/chromium-fast-flate-final.json` and
`_build/root-gap/webkit-fast-flate-final.json`; private inputs and ignored
artifacts are not published.

## 2026-10-15: reduce Worker module startup

Startup profiling places the main cost before the module-ready mark; the
ICC/JBIG2 attempt takes about 4 ms in the sampled Chromium trace. The bridge
contains large static character maps, and pdflite expands flat CMap tables into
lookup records at module initialization even when the document never uses
them. This follows the image codec change; the baseline here is **66cbcff**,
not the earlier image experiment's baseline.

The published build now compacts 53 integer arrays (473,004 values), defers 77
pure derived CMap initializers, and compresses 46 large resource strings inside
their existing lookup functions. Memoized getters preserve exact values,
ordinary array representations and shared table identity. Column-delta
varints or int32 bytes are compressed at build time and expanded synchronously
only on use. The trusted-data loader reuses the existing pako adapter; PDF
streams, colour algorithms, font/CMap contents and readiness semantics stay
unchanged. There is no parser prewarm, early-ready message, extra request,
runtime eval or feature removal.

The published Worker decreases from **7,831,732 to 5,201,779 bytes (-33.6%)**.
`tools/worker_startup_benchmark.mjs` measures nine alternating fresh-context
Worker pairs per engine without opening a PDF. These are loopback, no-store,
uncompressed HTTP measurements; profiling and other test processes are absent.
Its Worker-clock module phase is distinct from the main-thread ready timer:

| Engine / median phase | Baseline | Candidate |
| --- | ---: | ---: |
| Chromium Worker ready | 119.2 ms | **89.0 ms (-25.3%)** |
| Chromium module ready | 67.2 ms | 46.5 ms |
| Chromium graphics initialization | 50.6 ms | 40.9 ms |
| WebKit Worker ready | 113.0 ms | **72.0 ms (-36.3%)** |
| WebKit module ready | 106.0 ms | 64.0 ms |
| WebKit graphics initialization | 6.0 ms | 6.0 ms |

The graphics code is unchanged in this round. Its Chromium timings vary with
the isolated startup harness; they are not a new codec initialization claim.
For the actual file-input reader, six alternating fresh-open pairs per engine
use the same private 13-page fixture and full pixel checks as before:

| Engine / median phase | Baseline | Candidate |
| --- | ---: | ---: |
| Chromium Worker startup | 136.5 ms | **104.9 ms (-23.2%)** |
| Chromium first-page Canvas visible | 539.7 ms | **508.6 ms (-5.8%)** |
| Chromium page preparation RPC | 266.4 ms | 268.6 ms |
| WebKit Worker startup | 126.5 ms | **87.0 ms (-31.2%)** |
| WebKit first-page Canvas visible | 643.5 ms | **607.0 ms (-5.7%)** |
| WebKit page preparation RPC | 313.5 ms | 320.0 ms |

Every first-open pair improves, with complete RGBA hashes unchanged. In these
batches PDF.js first-page medians are 119.2 ms (Chromium) and 192.0 ms (WebKit),
under the earlier Canvas-only reference scope. Results compare within each
batch; machine load makes absolute values differ from prior sections.

First use of a needed CMap now includes its decode/unpack work. Three extra
Chromium pairs on `90ms_rksj_h_sample.pdf` check this cost: first-page visibility
improves from 232.3 to 214.1 ms with matching full RGBA. Thus the tested CJK
document also benefits after its first lookup. A separate `standard_fonts.pdf`
reference timing attempt hits the existing reader/reference dimension guard
and is excluded; no timing claim is made for that input. All 14 font programs
remain byte-identical, and the packaged-reader font checks pass.

Validation compares all 130 flat/derived tables and all 168 CMaps/14 fonts
against the untouched release bridge, checks that import expands none of the
transformed data and that repeat access reuses each array, and rejects unsafe
rewrite shapes/non-int32 data. All 13 complete private-document payload hashes
and cache statistics match the previous portable bridge. Default/JS MoonBit
tests pass (715/720), as do real Worker transport checks and all nine packaged
reader checks in both browsers. Public `.mbti` interfaces are unchanged.

```sh
moon run tools/build_pages.mbtx
node tools/compact_pdf_data_test.mjs
PDF_BROWSER=chromium PDF_BENCH_SAMPLES=9 PDF_BENCH_BASELINE_ROOT=/path/to/baseline \
  node tools/worker_startup_benchmark.mjs _build/worker-startup-chromium.json
PDF_BROWSER=webkit PDF_BENCH_SAMPLES=9 PDF_BENCH_BASELINE_ROOT=/path/to/baseline \
  node tools/worker_startup_benchmark.mjs _build/worker-startup-webkit.json
```

Local raw reports are `_build/worker-startup/{chromium,webkit}-startup-final.json`,
`{chromium,webkit}-first-open.json` and `chromium-cjk-first-open.json`. Private
documents and ignored diagnostic artifacts are not published.

## Fixed: unused source planes in nonisolated transparency groups

The image collector retained 16-bit component and opacity planes whenever any
ancestor group declared CMYK, an ICC profile or a calibrated space. The Canvas
compositor already implements the effective blending-space rule: nonisolated
groups inherit their parent's space; only isolated groups with an explicit
space change it. The collector now follows the same rule, including an inner
isolated RGB group switching off retention inherited from a CMYK parent.
Actual CMYK/profile/calibrated consumers keep their original source planes.

The pinned PDF.js fixture `test/pdfs/issue14200.pdf` exposes the cost: its
nonisolated CMYK Form paints an ICC RGB image and soft mask into an RGB page.
The unused planes added per-pixel component work, Base64 encoding, page-cache
accounting, JSON serialization and Worker transport. Removing them reduces
the first render payload from **4,603,360 to 940,063 characters (-79.6%)**.
This change does not remove the display PNG or approximate ICC conversion.

Six alternating fresh-context pairs compare the published `eba738b` baseline
with the collector fix, using the ordinary file-input benchmark above:

| Engine / median phase | Baseline | Candidate |
| --- | ---: | ---: |
| Chromium first-page Canvas visible | 650.7 ms | **458.9 ms (-29.5%)** |
| Chromium page preparation RPC | 388.6 ms | **211.8 ms (-45.5%)** |
| WebKit first-page Canvas visible | 623.5 ms | **493.0 ms (-20.9%)** |
| WebKit page preparation RPC | 354.0 ms | **215.5 ms (-39.1%)** |

All 12 pairs improve and all complete before/after RGBA hashes match within
each browser. The PDF.js Canvas-only medians in these batches remain 67.3 ms
and 137.0 ms respectively, so a substantial gap remains. This is a gain for
documents triggering unused ink retention, not a universal first-open gain.
The original private 13-page input does not trigger this redundant work; its
three Chromium check pairs retain identical pixels, with no large speedup.

Regression tests cover default/explicit nonisolation, isolated CMYK retention,
CMYK-to-RGB and RGB-to-CMYK nested isolated groups, inherited nonisolated spaces
and isolated groups without an explicit colour space. Experimental ICC batch
loops and skipped display-PNG generation remain outside the product: skipping
RGB for this nonisolated group changes pixels because the host consumes RGB.
All 13 complete private-document payload hashes and cache statistics remain
identical. Default/JS MoonBit tests pass (716/721), along with Canvas and real
Worker checks and all nine packaged-reader checks in each browser. Public
`.mbti` interfaces are unchanged.

```sh
PDF_BROWSER=chromium PDF_BENCH_SAMPLES=6 PDF_BENCH_BASELINE_ROOT=/path/to/eba738b-build \
  node tools/first_load_benchmark.mjs reference/pdf.js/test/pdfs/issue14200.pdf _build/effective-group-chromium.json
PDF_BROWSER=webkit PDF_BENCH_SAMPLES=6 PDF_BENCH_BASELINE_ROOT=/path/to/eba738b-build \
  node tools/first_load_benchmark.mjs reference/pdf.js/test/pdfs/issue14200.pdf _build/effective-group-webkit.json
```

Local reports are `_build/next-bottleneck/effective-group-{chromium,webkit}.json`.

## Preparation investigation: isolated Wasm GC prototype

Further checks on the original private 13-page input locate the largest
remaining first-open gap in preparation, rather than warm Canvas replay.
Five ordinary WebKit replays give median paint-plus-flush times of 15 ms on
page 1, 10 ms on page 2 and 24 ms on page 12. The corresponding warm PDF.js
medians are 17.5, 16.5 and 17 ms. The reader's initial page-1 preparation RPC
still takes 329 ms in this run. The independent diagnostic replay retains
the same reader pixels; its report is
`_build/render-benchmark-1792057865693/report.json`.

A local Wasm GC prototype builds the same MoonBit document reader, page model
and Canvas plan. It connects to the same pinned LittleCMS implementation via
primitive host imports, preserving ICC conversion rather than falling back to
Alternate. The JS control uses the existing ICC/pako adapters and published
static-table compaction/minification. Wasm GC uses the portable Flate path.
Both run in fresh browser contexts on the same pinned browser engine, with
five sequential alternating pairs per browser.

| Median phase | Chromium JS | Chromium Wasm GC | WebKit JS | WebKit Wasm GC |
| --- | ---: | ---: | ---: | ---: |
| Module loading/initialization | 42.6 ms | 23.1 ms | 53 ms | 21 ms |
| Document open + page model + Canvas JSON | 274.9 ms | 181.6 ms | 334 ms | 247 ms |
| Complete preparation path | **328.7 ms** | **234.2 ms (-28.7%)** | **404 ms** | **302 ms (-25.2%)** |

The complete path includes graphics initialization, module fetch and
initialization, Wasm input copying, JSON export and JSON parsing. Wasm input
copying costs about 7–9 ms and string export about 11–12 ms; JS consumes the
input Uint8Array and returns its JSON string directly. Every pair improves.
These are isolated preparation measurements, **not the complete reader's
first-page visibility**: Worker transport, scheduler and text/annotation DOM
mounting are excluded. The loopback server also does not represent remote
network latency or a cold OS cache.

Every normalized Canvas field matches, including each PNG's header and exact
decompressed scanlines; only PNG compression bytes differ. Both backends then
paint through the existing Canvas runtime at 2432 x 3436. All complete RGBA
hashes match each other and the packaged reader within each engine. Drawing
itself remains similar: Chromium medians 53 vs 55.8 ms, WebKit 69 vs 68 ms.

The prototype does not establish feature parity for the complete Worker API.
Range loading, editing, JS-only codec hooks, cancellation, cache accounting,
document lifetime and other inputs still need integration checks. Its binary
is also larger: 9,112,367 raw bytes versus 4,822,525 bytes for the JS probe;
offline gzip-9 sizes are 3,709,805 versus 2,530,512 bytes, and Brotli quality-5
sizes are 2,630,465 versus 2,432,784 bytes. These are compression comparisons,
not claims about production HTTP compression.

Production continues to use the existing JS Worker. The experimental ICC
imports and probe package are kept outside tracked product sources under
`_build/gap-followup/`, alongside the source snapshots and
`backend-browser-{chromium,webkit}.json` reports. A Type3 instruction cache
prototype saved only about 10 ms in warmed Node checks; scanline run filling
saved about 7–10 ms, with unstable fresh-open browser results. Neither was
included in production. A complete Wasm GC Worker adapter remains a candidate;
the following production changes first remove repeated glyph preparation and
a page-wide fallback from the existing JS path.

## Fixed: compiled glyph resources and single-image Type3 fallback

The browser previously interpreted a Type3 CharProc for every glyph invocation,
built a positioned retained scene and compatibility outline, then serialized
that geometry into every viewport response. The new opt-in Canvas projection
compiles eligible fill-only CharProcs once in font coordinates. Its bounded
document cache holds at most 512 resources and an estimated 8 MiB. Invocation
colour, clipping, FontMatrix/placement and groups remain separate. Unsupported
operators and colour/transparency requirements retain the existing interpreter.
The viewer expands each response once and reuses its normal Canvas plan;
the generic runtime expands before selecting native surface budgets or tiles.
Public page models, legacy bridge calls and printing retain version-1 plans.

The original private input uses 2,017 compiled glyph calls across 13 pages.
At scale 1, page 1's serialized response falls from 1,909,814 to 1,080,562
characters (-43.4%); page 2 falls from 2,130,838 to 1,059,751 (-50.3%).
Six sequential alternating fresh-context pairs compare the packaged baseline
`2ea5d33` with the candidate. Both use the ordinary file-input measurement above,
including a pixel flush and two animation frames:

| Median phase | Chromium baseline | Chromium candidate | WebKit baseline | WebKit candidate |
| --- | ---: | ---: | ---: | ---: |
| First-page Canvas visible | 529.8 ms | **482.7 ms (-8.9%)** | 626.5 ms | **563.0 ms (-10.1%)** |
| First-page preparation RPC | 275.5 ms | **231.1 ms (-16.1%)** | 329.0 ms | **262.5 ms (-20.2%)** |

All 12 pairs improve and all first-page RGBA hashes match within each browser.
PDF.js Canvas-only medians are 120.7 ms and 202.5 ms respectively; first-open
parity remains unresolved. These local results do not include remote downloads.

A separate capability gap was much larger: page 5 contains one 80 x 76 image
inside a Type3 CharProc. Rejecting that elementary scene forced the whole page
through retained transparency and tiled raster transfers. A one-image RGB
scene can now use the ordinary native image path, including decoded opacity,
when the enclosing text object has one glyph or explicitly sets TK=false.
Overlapping knockout glyphs, explicit knockout PDF groups and state requiring
retained shape/colour treatment keep their previous rendering boundaries.
`nativeImageGlyphs: false` disables the promotion for reference comparisons.

Nine warm paint-plus-forced-flush samples on each packaged artifact give:

| Page 5 / median | Baseline | Candidate | PDF.js in candidate run |
| --- | ---: | ---: | ---: |
| Chromium 145 | 937.7 ms | **22.9 ms (41x faster)** | 24.8 ms |
| WebKit 26 | 626.0 ms | **26.0 ms (24x faster)** | 17.0 ms |

Native image sampling changes some edge pixels on page 5. Against the same
full PDF.js output in each engine, mean absolute RGBA-channel error decreases
from 0.29545 to 0.28555 in Chromium and from 0.31934 to 0.28229 in WebKit.
This is not an assertion of exact PDF.js parity or universal first-open speedup.
Page 12 keeps its complete baseline RGBA hash. Its warm medians are 29.4 versus
31.5 ms in Chromium and 58 versus 56 ms in WebKit in the same batches; no stable
page-12 improvement or regression is established.

With image promotion disabled, all 13 complete diagnostic-input RGBA hashes
match before and after glyph compilation. Selection, editor, annotations and
accessibility payloads also match. Authored tests cover all text rendering modes,
affine placement, clipping, fill rules, degenerate paths, complex fallbacks,
cache budgets, real Worker transport and Range document hydration. Image-glyph
tests exercise alpha masks, overlapping knockout text, TK=false and retained
colour/state guards. MoonBit tests pass on default and JS targets (721/727),
144 compiled/legacy native and retained pixel comparisons pass, and all ten
packaged-reader checks pass in each browser. The public facade's `.mbti` stays
unchanged; the compiler entry points are confined to the internal engine package.

```sh
PDF_BROWSER=chromium PDF_BENCH_SAMPLES=6 PDF_BENCH_BASELINE_ROOT=/path/to/2ea5d33-build \
  node tools/first_load_benchmark.mjs /path/to/document.pdf _build/compiled-chromium.json
PDF_BROWSER=webkit PDF_BENCH_SAMPLES=6 PDF_BENCH_BASELINE_ROOT=/path/to/2ea5d33-build \
  node tools/first_load_benchmark.mjs /path/to/document.pdf _build/compiled-webkit.json
PDF_BROWSER=chromium PDF_BENCH_REPLAYS=9 node tools/render_benchmark.mjs /path/to/document.pdf 5,12
PDF_BROWSER=webkit PDF_BENCH_REPLAYS=9 node tools/render_benchmark.mjs /path/to/document.pdf 5,12
```

Local reports are `_build/canvas-compiler/acceptance-{chromium,webkit}.json`;
`replay-check-{baseline,candidate}-{chromium,webkit}.log` identifies each full
replay report. Private input bytes, text and rendered images remain unpublished.

## Fixed: saturated ICC runs and repeated image-buffer copies

Two preparation costs remained in the existing image pipeline. The opaque ICC
RGB row converter stopped updating its previous-colour entry when the separate
4096-entry palette filled. Later runs of one valid colour repeatedly called
LittleCMS. The previous-colour entry now remains useful independently of palette
capacity; failed transforms still retry and only successful conversions are
reused. On the private 13-page input, instrumented conversion counts decrease
from 504,453 to 275,923. Page 5 decreases from 263,170 to 114,068 calls and
page 6 from 198,483 to 119,125. These counts are work reductions, not latency
estimates; a palette-only Chromium batch did not establish a total-time gain.

A diagnostic readable release Worker CPU profile then found about 160 ms in
generic byte-by-byte array copies during a roughly 2.1-second preparation sweep.
Completed ICC/general RGB rows, alpha PNG rows and JPEG interleaved samples were
copied from a fresh `FixedArray[Byte]` into `Bytes`. Those four producers now
freeze their own completed array after its final write. No mutable alias escapes
or is retained for a later decode. Input samples and independent output buffers
remain separate; the change removes the copy and duplicate allocation on every
target without changing image arithmetic, codecs, PNG encoding or transport.

The focused browser comparison uses eight fresh pairs of documents and Workers
per engine. Both Workers finish opening before measurement. Each prepares pages
1 through 13 in order, alternating which Worker goes first at every page and
context. This keeps paired pages close in time when background load varies.
The unmodified packaged Workers include normal RPC transport and JSON parsing;
Canvas painting and text/annotation DOM mounting are excluded. Output is still
the complete ordinary display payload, at CSS width 1216 and DPR 2.

| 13-page preparation RPC + JSON / median | `55fc1f8` baseline | Candidate | Change |
| --- | ---: | ---: | ---: |
| Chromium 145 | 2359.6 ms | **2198.9 ms** | **-6.8%** |
| WebKit 26 | 2369.0 ms | **2025.0 ms** | **-14.5%** |

Page 5 preparation drops from 534.5 to 432.1 ms in Chromium and from 495 to
389.5 ms in WebKit (19–21%). Page 6 drops from 268.6 to 234.8 ms and from
257.5 to 227 ms (12–13%). Every paired complete payload SHA-256 matches on
all 13 pages. These are preparation measurements, not isolated Canvas redraws.

Separate six-pair full-document sweeps include File reading, Worker/graphics
initialization, document opening, all 13 page RPCs, Canvas painting and full-pixel
flushes; DOM mounting, remote downloads, hashing and teardown stay outside timing.
Chromium medians are 3589.7 to 2942.4 ms, versus 667.4 ms for the pinned PDF.js
Canvas API. WebKit gives 3246.5 to 2907.5 ms, versus 863 ms. Before/after full RGBA
hashes match on every page in every pair. These sweep medians show an 18%/10%
reduction in their batches; the interleaved preparation results above are the
stronger estimate under variable machine load. First-pass parity remains open.

Default and JS MoonBit tests pass (723/729), including retry after palette
saturation and independence of retained JPEG samples across subsequent decodes.
The Canvas, actual Worker and packaged-reader regressions pass; the public and
internal `.mbti` interfaces are unchanged. Node stage/counterfactual profilers
now install the same bounded pako hooks as the real Worker and recognize the
optional-argument render wrapper before interpreting stage results.

Local records are `_build/preparation-speed/paired-rpc-{chromium,webkit}.json`
and `final-{chromium,webkit}.json`, with `count-colours.json` and CPU profiles
for diagnostics. The raw-row transport experiment remains private: removing PNG
encoding alone did not establish a full-document gain because host pixel
conversion and transfer introduced other work. No raw transport or larger
colour palette was added to the product.

## Fixed: keep the bounded ICC palette useful for recent colours

The previous ICC row palette retained its first 4096 successful colours for an
entire image. Consecutive runs still reused the last colour, but photographs
with more distinct colours repeatedly reconverted later colours when a run
ended. The palette now keeps four recent exact colours in each hash bucket,
with at most 4096 entries overall. Hits are promoted and successful misses
replace the oldest entry in that bucket. Full 24-bit source keys distinguish
collisions; failed transforms neither evict successes nor become reusable.
Small images allocate fewer buckets. Decode, range clipping, LittleCMS intent,
rounding, PNG encoding and ordinary Worker transport remain unchanged.

Actual instrumented LittleCMS calls on the private 13-page input decrease from
275,923 to 89,645 (67.5%). Page 5 decreases from 114,068 to 16,299 and page 6
from 119,125 to 30,464. These are work reductions, not proportional latency
improvements. A diagnostic simulation compares one, two and four entries
per bucket and a full LRU with the same 4096-entry budget. Four entries recover
most of the full LRU's reuse and avoid its per-hit map mutations.
The simulator's call counts are diagnostic; only the implemented palette's
actual calls and packaged-browser timings are used below.

Sixteen fresh document/Worker pairs per browser use the same interleaved
per-page comparison described above, against the `e3076f0` rendering sources
(the `15f4330` CI-only commit has identical rendering sources). Both Workers
finish opening first, then prepare all 13 pages sequentially at CSS width 1216
and DPR 2 with ordinary RPC transport and JSON parsing. Canvas painting and
DOM mounting are excluded; hashing stays outside timing.

| 13-page preparation RPC + JSON / median | Baseline | Candidate | Change |
| --- | ---: | ---: | ---: |
| Chromium 145 | 1774.9 ms | **1712.4 ms** | **-3.5%** |
| WebKit 26 | 2089.5 ms | **1943.0 ms** | **-7.0%** |

Preparation totals decrease in all 16 Chromium pairs and 14 of 16 WebKit pairs.
Page 5 medians decrease from 389.2 to 345.2 ms and from 394 to 348 ms (11–12%).
Page 6 decreases from 204.9 to 176.6 ms and from 232 to 175.5 ms (14–24%).
Every complete payload SHA-256 matches across all 13 pages in all pairs.
The actual gain is modest compared with the conversion-count decrease: the
rest of image preparation and the page pipeline still execute. Absolute times
must not be compared with an earlier batch to claim additional gains.

Separate complete-document Canvas/flush sweeps verify exact RGBA hashes on
all 13 pages against the baseline and the packaged reader. Their timings vary
substantially with background load and do not establish a stable end-to-end
first-open speedup. The validated latency improvement here is preparation.

Regression coverage includes more than 4096 distinct samples followed by
nonconsecutive recent colours, exact output under deliberate bucket collisions,
and a failed fifth colour that must leave four successes available before
retry. Default/JS suites pass (725/731); the 17 image-colour regressions also
pass on Wasm, JS, Wasm GC and native. All 52 Canvas tests, actual Worker
regressions and all ten packaged-reader checks in each browser pass. Public
and internal interfaces are unchanged.

Local diagnostics are `_build/colour-speed/cache-probe.json`,
`count-colours.json`, `paired-rpc-{chromium,webkit}.json` and
`full-{chromium,webkit}.json`. Private input bytes, text and rendered images
remain unpublished.

## Fixed: sparse JPEG IDCT and invariant sample-packing work

JPEG decoding still accounted for about 267 ms in the previous diagnostic
readable-Worker CPU profile of a roughly 1.88-second preparation sweep. The
baseline decoder already recognized entirely DC-only blocks. On the private
input, 69,035 of 91,674 blocks take that shortcut; among the other 22,639 blocks,
about 84% of coefficients and 59% of columns are zero.

The separable IDCT now visits active frequencies and columns in ascending
order, hoists invariant scale products, and reuses one fixed scratch workspace
per decode across both baseline and progressive scans. It retains the original
multiplication, accumulation and rounding order for nonzero terms. Every
scratch value consumed by a block is overwritten by that block. Whole-block
DC handling stays separate. Block clearing uses the array fill primitive, and
component writes hoist the row addresses.

Three-component sample packing now keeps plane references, strides and each
sampled row outside the pixel loop. Integer sampling coordinates and the RGB
coding transform retain their existing arithmetic, including unusual 1–4
sampling factors that do not divide the maximum factor and partial edge MCUs.
The packing path adds no image-sized coordinate tables. Gray and CMYK/YCCK
retain the generic component loop and their existing transform policy.

Nine alternating warmed Node pairs over the ten actual JPEG decodes give
same-batch medians of 166.1 to 89.4 ms (46%). Complete decoded bytes match, as do all 13 complete
page payloads. All 12 authored JPEG fixtures also match for each of the three
ColorTransform settings (36 comparisons). Separate dense, sparse and DC-only
IDCT microbenchmarks check exact outputs and find no dense-case slowdown in
that diagnostic batch. These are decoder diagnostics, not browser latency.

Sixteen fresh document/Worker pairs per browser compare the unmodified
packaged Worker against `a58c715`. Both Workers finish opening before page
measurement. Pages 1–13 prepare sequentially in each Worker, alternating which
variant goes first at every page and context. Timing includes ordinary RPC and
JSON parsing at CSS width 1216 and DPR 2; Canvas, DOM and hashing are excluded.

| 13-page preparation RPC + JSON / median | `a58c715` | Candidate | Change |
| --- | ---: | ---: | ---: |
| Chromium 145 | 1723.9 ms | **1594.2 ms** | **-7.5%** |
| WebKit 26 | 1868.5 ms | **1775.0 ms** | **-5.0%** |

Every Chromium pair and 12 of 16 WebKit pairs improve. Page 5 preparation
medians decrease from 353.1 to 260.7 ms and from 342 to 281.5 ms (26%/18%).
Page 6 decreases from 179.3 to 149 ms and from 172 to 162 ms (17%/6%).
Every complete payload SHA-256 matches on all 13 pages in every pair.

Eight additional fresh paired documents use the shipped host to measure first
preparation plus Canvas painting and a full-pixel flush after both documents
have opened. The two document-owned image and pattern caches are independent:
every render asserts that its peer cache is untouched, and each page's resulting
cache accounting agrees between variants. Page order remains sequential within
each document and variant order alternates at every page/context. Hashing,
DOM mounting and document opening are excluded from these page totals.

| 13-page first preparation + Canvas/flush after opening / median | Baseline | Candidate | Change |
| --- | ---: | ---: | ---: |
| Chromium 145 | 2566.4 ms | **2445.4 ms** | **-4.7%** |
| WebKit 26 | 2509.5 ms | **2366.0 ms** | **-5.7%** |

All eight Chromium pairs and five WebKit pairs improve in this batch. Every
complete payload and full-page RGBA hash matches the independent ordinary
packaged-reader run on all 13 pages. This is an uncached first page pass after
opening, not a redraw of prepared pages.

Separate eight-pair ordinary complete-document sweeps include File reading,
Worker/graphics initialization, document opening, every page RPC, Canvas
painting and full-pixel flush. Chromium medians are 2488.4 to 2393.7 ms versus
562.1 ms for the pinned PDF.js Canvas API. WebKit is 2573.5 to 2641.5 ms versus
821 ms. Main-module loading, network PDF downloads, DOM mounting, hashing and
teardown remain outside this timing scope. The reader RPC still computes its
selection/editor/accessibility payload. All baseline/candidate RGBA hashes
match. Whole-document timing continues to vary with background load, so this
batch does not establish a cold-open improvement across both browsers; use the
interleaved preparation comparison for the stronger latency conclusion.

The default and JS suites pass (728/734); all 20 JPEG regressions also pass on
Wasm GC and native. A dense arithmetic reference checks every single-frequency
position at multiple amplitudes and 512 changing sparse/dense blocks while
reusing the same workspace. Sampling regressions cover ordinary and unusual
factors, both transform modes and partial MCUs. All 52 Canvas replay tests,
actual Worker regressions and all ten packaged-reader checks in each browser
pass. Public and internal interfaces are unchanged.

A separate lossless PNG filter probe was rejected. The standard
[Up/Sub filters](https://www.w3.org/TR/png-3/#9Filters) preserved all samples but
increased both encoding time and compressed bytes on this input: about
3.30 MB without filtering became 3.52 MB with Up or 3.70 MB with Sub. PNG
encoding and image transport are unchanged in the shipped JPEG optimization.

Local records are `_build/image-prepare-speed/jpeg-probe.json`,
`jpeg-bench.json`, `idct-density.json`, `paired-rpc-{chromium,webkit}.json`,
`paired-full-{chromium,webkit}.json` and `full-{chromium,webkit}.json`. Private input bytes, text and rendered images
remain unpublished.

## Fixed: packed PNG compressor hash sliding

The post-JPEG readable-Worker CPU sample locates about 272 ms in pako PNG
compression, including about 90 ms in its hash-table slide. The level-1
compressor updates 65,536 16-bit hash-chain positions each time its 32 KiB
window slides. Its original loop branches separately for every position.

After checking the pinned pako 2.1.0 source hashes, the asset build replaces
only that loop with a local equivalent. Each aligned 32-bit word updates two
16-bit positions with branchless saturating subtraction. The subtraction is
independent in each native lane, including on a big-endian host. Empty-chain
sentinels, hash positions, match selection, zlib bytes and checksums stay exact.
The build requires exactly one transformed source; the original license and a
local-modification notice accompany the generated adapter. The inflater and
its output bounds use the original upstream code.

Seven alternating warmed Node runs per variant over the actual large PNG scanlines give
encoding medians of 308.4 to 219.4 ms (28.8%). Every compressed byte matches the
original encoder, and independent Node zlib decoding recovers every scanline.
This is a compressor diagnostic, not a complete-reader latency estimate.
Compression options and the tested fflate alternative did not beat the current
encoder consistently on this input and remain outside the product.

Sixteen fresh document/Worker pairs per browser compare ordinary packaged
Workers against `9b47a11`. Both documents finish opening before timing. Pages
1–13 prepare sequentially, alternating variant order at each page and context.
Timing includes ordinary RPC and JSON parsing at CSS width 1216 and DPR 2;
Canvas, DOM, opening and SHA-256 computation are excluded.

| 13-page preparation RPC + JSON / median | `9b47a11` | Candidate | Change |
| --- | ---: | ---: | ---: |
| Chromium 145 | 1758.3 ms | **1657.0 ms** | **-5.8%** |
| WebKit 26 | 1918.5 ms | 1889.5 ms | -1.5% |

Thirteen of 16 Chromium pairs and ten WebKit pairs improve. Every complete
page payload SHA-256 matches across all pages and pairs. WebKit's smaller
change is close to the batch's scheduling variation.

Eight additional fresh document pairs use the shipped Canvas host after both
documents open, with independent document-owned image and pattern caches.
Page and variant ordering are the same. These totals include the first
preparation, RPC/JSON, Canvas painting and full-pixel flush, excluding opening,
DOM, hashing and teardown. Peer caches remain untouched by each render, and
all cache accounting agrees between variants.

| 13-page first preparation + Canvas/flush after opening / median | Baseline | Candidate | Change |
| --- | ---: | ---: | ---: |
| Chromium 145 | 2448.8 ms | **2283.5 ms** | **-6.8%** |
| WebKit 26 | 2440.5 ms | 2408.5 ms | -1.3% |

Seven of eight Chromium pairs improve; only four WebKit pairs do, so this
batch does not establish a stable WebKit end-to-end gain. Every full-page RGBA
hash matches the independent ordinary packaged-reader baseline and every
complete payload matches its paired Worker.

A separate six-sweep-per-variant cold-document batch includes File reading,
Worker/graphics initialization, opening, every page RPC, Canvas painting and
full-pixel flush. Main-module preloading, network PDF downloads, DOM mounting,
hashing and teardown stay outside timing. The PDF.js reference remains the
pinned Canvas API; the reader also computes its ordinary text/annotation/editor
and accessibility payload.

| 13-page cold-document total / median | `9b47a11` | Candidate | Pinned PDF.js |
| --- | ---: | ---: | ---: |
| Chromium 145 | 2557.9 ms | 2731.7 ms | 705.3 ms |
| WebKit 26 | 2822.0 ms | 2883.0 ms | 815.5 ms |

These complete-sweep medians increase in this batch. No cold-start improvement
is established. The validated latency benefit is Chromium's interleaved page
preparation after opening; the first-open gap to PDF.js remains substantial.
Every baseline/candidate RGBA hash matches on all pages in every sweep.
A later diagnostic readable-Worker CPU sample puts the modified hash slide at
about 37 ms self time; profiling samples do not replace ordinary latency checks.

Default and JS MoonBit suites pass (728/734), with unchanged interfaces.
The new CI regression exhausts all 65,536 values in each 16-bit lane for every
supported window size, including repeated slides, nonzero aligned offsets and
neighboring-buffer guards. It compares 105 complete zlib encodes byte for byte
with upstream pako over short, noisy, repeating and window-boundary inputs,
multiple levels, windows and memory settings. Independent Node zlib decoding
checks the samples and inputs remain unchanged. Existing 1,396 portable/host
Flate comparisons, all 13 private page payload/sample comparisons, 52 Canvas
tests, actual Worker checks and ten packaged-reader checks in each browser pass.

Local reports are `_build/png-prepare-speed/png-hash.json`,
`paired-rpc-{chromium,webkit}.json`, `paired-full-{chromium,webkit}.json`,
`full-{chromium,webkit}.json` and `worker-cpu.json`. Private source bytes, text
and images remain unpublished.

## Fixed: bounded ICC row traversal and component preparation

The opaque ICC RGB row loop still repeated array bounds checks and palette
writes, besides actual colour conversion. Decode, source clipping and ICC range
clipping are separable for its 8-bit components. Images with at least 4096
pixels now prepare three exact 256-entry component tables and reuse one sample
vector/view for synchronous CMM calls. Smaller images keep direct sample
preparation. Operation order, NaN handling, LittleCMS intent, fallback, rounding
and exact source-key palette policy remain the same.

A preflight before allocation proves positive dimensions, a representable RGB
stride, complete padded source rows and at most 64 MiB of output scanlines.
Divisions establish the bounds before any potentially overflowing products.
Every source offset is below `height * row_bytes <= bytes.length`; every output
offset is below `height * (width * 3 + 1)`. Palette capacity is a power of two
from 4 to 4096, and its mask ensures `bucket + 3 < capacity`. Component-table
indices are unsigned bytes. The internal loop uses these established bounds
instead of checking every channel access again. Public image validation still
precedes this specialized path.

The four palette probes and shifts are explicit, and a hit already at the
bucket head needs no palette writes. LRU order and which keys trigger CMM
conversion stay identical. Failed CMM results still neither enter the palette
nor displace successes, and repeated failed colours retry. The cache budget,
alpha/mask/scaled-image and retained-ink paths are unchanged.

Nine alternating warmed Node pairs over all 34 actual ICC RGB row conversions
give medians of 109.9 to 74.5 ms (32.2%). Every row byte and every complete page
payload matches the baseline. These are kernel diagnostics, not browser latency.
An eager-table prototype penalized tiny/flat icons. Seven further warmed pairs
across 1-pixel, flat/varied 16x16 and 256x256, and flat 64x64 inputs established
the final cutoff: tiny and flat 64x64 costs remain comparable, both 16x16 cases
and both large cases improve, and every output byte matches. Both variants warm
all shapes before measurement, avoiding an unseen-branch JIT comparison.

A separate valid-stream Flate diagnostic was rejected. Fixed 1 MiB output
chunks increased the warmed Node median from 116.6 to 144.8 ms over 547 actual
image streams; an adaptive chunk experiment gave 114.0 ms. Neither establishes
a useful complete-reader improvement, so the inflater remains unchanged.

Sixteen fresh pairs of ordinary packaged documents/Workers compare against
`84aa7fb`. Both documents open first, then prepare pages 1–13 in sequence,
alternating variant order at every page and context. Timing includes ordinary
RPC and JSON parsing at CSS width 1216 and DPR 2, excluding opening, Canvas,
DOM, hashing and teardown.

| 13-page preparation RPC + JSON / median | `84aa7fb` | Candidate | Change |
| --- | ---: | ---: | ---: |
| Chromium 145 | 1467.5 ms | **1400.7 ms** | **-4.6%** |
| WebKit 26 | 1504.5 ms | **1459.0 ms** | **-3.0%** |

Fifteen of 16 Chromium pairs and all 16 WebKit pairs improve. All complete
payload hashes match on every page in every pair.

Eight additional fresh pairs use the shipped Canvas host after both documents
open, with independent document-owned image and pattern caches. These totals
include first preparation, RPC/JSON, Canvas painting and full-pixel flush,
excluding opening, DOM, hashing and teardown. Variant order alternates at every
page and context; peer caches remain untouched and cache accounting agrees.

| 13-page first preparation + Canvas/flush after opening / median | Baseline | Candidate | Change |
| --- | ---: | ---: | ---: |
| Chromium 145 | 1975.3 ms | **1913.3 ms** | **-3.1%** |
| WebKit 26 | 1985.5 ms | **1933.5 ms** | **-2.6%** |

All eight pairs improve in each browser. Every complete payload and full-page
RGBA hash matches, including the independent ordinary packaged-reader baseline.

Six additional cold-document sweeps per variant include File reading,
Worker/graphics initialization, opening, all 13 page RPCs, Canvas painting and
full-pixel flush. Main-module preloading, network PDF downloads, DOM mounting,
hashing and teardown stay outside timing. PDF.js uses the pinned Canvas API;
the reader also computes its ordinary text/annotation/editor/accessibility data.

| 13-page cold-document total / median | `84aa7fb` | Candidate | Change | Pinned PDF.js |
| --- | ---: | ---: | ---: | ---: |
| Chromium 145 | 2128.0 ms | **2057.1 ms** | **-3.3%** | 533.9 ms |
| WebKit 26 | 2124.0 ms | **2086.5 ms** | **-1.8%** | 619.0 ms |

All six Chromium sweeps and five of six WebKit sweeps improve; baseline and
candidate RGBA hashes match on every page. These are modest same-batch gains
for this input, and a substantial first-open gap to PDF.js remains. Absolute
values must not be compared with earlier batches to infer cumulative gains.

Five new regressions pass on JS, Wasm, Wasm GC and native. Their general
Decode/clip reference covers every source byte, reversed/nonfinite Decode,
source and ICC ranges, padded rows, and both sides of the lookup cutoff.
Preflight panic cases cover short rows/inputs, overflowing width and zero
height. Existing collision, failed-CMM retry and cache-saturation tests retain
their exact outputs and conversion counts. Interfaces are unchanged.

Full default and JS suites pass (733/739), along with 52 Canvas replay tests,
ten actual Worker checks and ten packaged-reader checks in each browser.
Scope/dependency/license validation, `moon check`, `moon info`, `moon fmt`
and whitespace checks also pass.

Local reports are `_build/icc-loop-speed/rows-bench.json`, `density.json`,
`inflate-bench.json`, `paired-rpc-{chromium,webkit}.json`,
`paired-full-{chromium,webkit}.json` and `full-{chromium,webkit}.json`. Earlier
eager/256-pixel experiments are diagnostic records only. Private source bytes,
text and rendered images remain unpublished.

## Fixed: document-owned transferable raster resources

The browser previously used the image export format as its runtime protocol:
decoded pixels were PNG-compressed, Base64-encoded into JSON, transferred as
text, then decoded again before Canvas drawing. The shipped reader now opts
into a Worker-owned raster source catalog and transferable `ImageBitmap`
resources for eligible RGB/RGBA scanlines. The Canvas plan carries scoped IDs;
the bitmap transfers alongside the ordinary RPC result. Source decoding, ICC,
Decode/clipping, masks, rounding and sampling remain unchanged.

This is a source implementation, rather than a generated-JS transform.
Private JS hooks are enabled only during a synchronous compiled Canvas display
request and disabled in `finally`. Standalone bridge/Worker consumers retain
their PNG protocol by default. SVG embedding lazily calls the original encoder
to produce self-contained PNG URIs, including nested image masks. Print and
other non-Canvas exports remain self-contained. MoonBit interfaces are unchanged.

The Worker admits at most 256 source buffers and 64 MiB, charging full backing
buffers and per-entry overhead. Existing admitted IDs remain reproducible for
their document epoch. When admission is full, subsequent images take the
ordinary PNG path. This avoids dangling IDs in retained page/JSON caches.
Lazy SVG/legacy PNG strings have a separate 8 MiB/256-entry LRU. Both catalogs
clear with document close/reopen, font policy, layers and editing invalidation.

The main thread uses the existing 64 MiB decoded-image LRU and its render
leases. Prefetched bitmaps enter that pool directly; there is no additional
unbounded bitmap inbox. Each request advertises at most 256 resident IDs. After
eviction, a high-priority resource RPC recreates the bitmap from its retained
source rows. Cancellation, stale replies and reset close unclaimed transfers;
active leases survive cache disposal until their final release. Missing Canvas
support or a failed bitmap creation/transfer recovers to the original PNG
encoder, including already-cached plans containing raster IDs.

Six alternating fresh-context/document sweeps per variant compare the complete
reader against `c3f7bb1` in each browser. They include File reading,
Worker/graphics initialization, opening, all 13 preparation RPCs with JSON
parsing, Canvas drawing and full-pixel flushes at CSS width 1216 and DPR 2.
Main-module preloading, network PDF download, text/annotation DOM mounting,
hashing and teardown remain outside timing. The pinned PDF.js Canvas API's
render promise includes image/operator preparation; its `getPage` time alone
is not a comparable preparation stage.

| 13-page cold-document total / median | `c3f7bb1` | Candidate | Change | Pinned PDF.js |
| --- | ---: | ---: | ---: | ---: |
| Chromium 145 | 2454.6 ms | **2070.0 ms** | **-15.7%** | 637.0 ms |
| WebKit 26 | 2702.0 ms | **2353.5 ms** | **-12.9%** | 812.0 ms |

All six Chromium pairs and five of six WebKit pairs improve. Every full-page
RGBA hash matches the old reader and the independent packaged-reader baseline,
on all pages in every
run. Every complete non-Canvas payload field (text layer, editor, annotations,
accessibility, intent, SVG and page metadata) also matches. The ordinary wire
payload decreases from 11,390,119 to 6,886,378 characters. This input admits
64 resources covering 20,204,254 pixels: 60,670,914 charged source bytes, 64
initial bitmap transfers and no on-demand rebuilds during the first sweep.
Lazy self-contained fallbacks occupy 66,468 bytes. These are same-batch gains
for this input, not cumulative comparisons with earlier machine-load batches;
a substantial total-time gap to PDF.js remains.

Default/JS suites pass (733/740), along with 52 Canvas checks, ten actual
Worker checks, nine raster ownership/budget/transport checks and thirteen
packaged-reader checks in each browser. New browser coverage includes exact
native RGB samples, interpolated RGBA/transparent edges, equally warm full-page
replay, resource reconstruction after eviction, resident-ID reuse, active
cancellation, font/edit invalidation, close/reopen, unsupported hosts, failed
transfers and zero-budget PNG fallback. The high-frequency reading fixture has
an existing one-pixel difference between cold and warm Canvas rendering even
on the PNG path; its comparison warms both paths and separately checks native
decoded samples. The private 13-page cold sweeps retain strict exact hashes.

A separate Linux WebKit diagnostic also reproduces repeated vector coverage
on same-size Canvas replay with the PNG-only reader. Three distinct full-page
hashes share identical image-region pixels; differences occur in the outlined
text. Same-size native replays explicitly discard the backing store before
resetting dimensions. Initial, evicted and cancelled-transfer replays retain
strict full-page equality with PNG, including an equally reset reference pool.

The reader keeps the existing `pdf-client` singleton, so standalone bridge
functions still address the UI's open document. Full browser/print, editor,
layer and Chromium/WebKit text-interaction checks also pass. Linux browser CI
exposed an older bootstrap race: native file input could finish document/layout
RPCs before the first after-render callback created the page scheduler. All
open paths now wait for controller initialization before file I/O or publishing
state. A forced-delayed-frame regression reproduces the old scheduler unwrap
failure and validates opening, replacement and close during bootstrap on both
engines; generation tokens prevent superseded opens from resuming later.

Local reports are `_build/bitmap-production/full-{chromium,webkit}.json` and
the corresponding validation logs. The preceding disposable prototype and
counterfactual reports remain under `_build/structural-gap/`. Private source
bytes, text and rendered images remain unpublished.

## Remaining costs

| Phase | Observed cost | Next target |
| --- | --- | --- |
| Complex-page warm drawing | Page 12 still needs 12 Canvas pixel reads and 18 uploads; PDF.js warm drawing needs neither. | Reduce retained shading's source readback, Float32 conversion and required scene bitmap creation. |
| Cold image preparation | The latest six-pair Chromium batch still spends a median 201.8 ms preparing page 5. Source image decoding, colour processing and font preparation still execute. | Reuse decoded image/font resources across page builds with document/revision ownership. |
| New viewport payloads | The compiled page-12 response falls from 1,295,943 to 1,105,935 JSON characters after image transfer, but repeated clipping, font and retained-ink metadata remain inline. | Intern repeated clip/font metadata and reuse prepared plans between viewports. |
| Worker startup | An earlier reader batch measured about 105 ms in Chromium and 87 ms in WebKit after static-data compaction; the Worker is about 5.0 MiB. | Reduce remaining initial code evaluation and static initialization; retain first-use checks for CJK/fonts. |

The pixel traffic comes from the retained source colour/shape pass, pattern
shape surfaces, CPU shading output and retained scene bitmaps. The document
raster cache is effective: warm runs add no image decodes. It does not cache
these temporary colour/shape surfaces. WebKit spends much more time in pixel
reads/uploads than Chromium for the same calls. Prepared independent pattern
surfaces now have their own document pool; retained shading scenes remain
temporary.

Before the prepared-pattern change, one run had page-12 warm paint plus forced
flush medians of **134 ms versus 18.5 ms** for WebKit, and **69 ms versus 28.5 ms**
for Chromium. Page 2 remains
close to PDF.js. These are host-dependent samples; scheduling, raster flush and
background load explain variation between runs. The earlier semantic fix left
these drawing calls unchanged, so it did not close this part of the gap.

A diagnostic experiment bypassed the preliminary pattern colour/shape pass. It
removed many pixel transfers, but changed affine pattern coverage and some
pixels. That experiment remains outside the product. Further optimization must
retain transparent-edge coverage, group bounds, knockout shape and colour-space
semantics, including dense pattern lattices and cache eviction.

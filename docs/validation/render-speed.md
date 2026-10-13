# Render speed investigation

Measured on 2026-10-13 and 2026-10-14 against PDF.js revision
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

## Remaining costs

| Phase | Observed cost | Next target |
| --- | --- | --- |
| Complex-page warm drawing | Page 12 still needs 12 Canvas pixel reads and 18 uploads; PDF.js warm drawing needs neither. | Reduce retained shading's source readback, Float32 conversion and required scene bitmap creation. |
| Cold image preparation | Node page 12 takes about 409 ms overall: colour processing has 115 ms self time, PNG encoding 46 ms, font loading 51 ms and Flate decoding 37 ms. | Reuse decoded image/font resources and avoid encoding pixels that the host can consume directly. |
| New viewport payloads | Page 12 still sends about 2.13 million JSON characters. Its Canvas plan contains about 709,000 path characters and 138,000 clip-path characters. | Intern repeated immutable geometry/resources and reuse prepared plans between viewports. |
| Worker startup | A diagnostic WebKit run of the bundled entry spends about 150 ms loading/evaluating code and 10 ms initializing the colour/JBIG2 adapters. The Worker is about 7.4 MiB. | Reduce initial code evaluation; codec initialization is a smaller cost on this input. |

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

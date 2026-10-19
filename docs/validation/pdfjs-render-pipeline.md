# PDF.js and pdf-viewer: original-document CPU profiles

Captured on 2026-10-19 from pdf-viewer `7e7a98d8e300c597ba4012f983b4013ab787cf81` and PDF.js `89b500f5e1d98ed89bb90211e45b28730b2d99ac` (local generic build 6.5.1). This investigation changes no renderer behavior and claims no performance improvement.

The input is the original **14-page `tracemonkey.pdf`**, SHA-256 `3662ff519e485810520552bf301d8c3b2b917fd2f83303f4965d7abed367e113`. Other documents do not contribute to the findings below.

## Measurement and artifacts

Each sweep uses a fresh browser context, document and real dedicated parser Worker. Pages render sequentially at CSS width 1216 and DPR 2. Preparation, painting and a final full-page RGBA readback are included. Opening, module/Worker initialization, DOM construction, hashing and teardown are outside the page-sweep timing. The tool separately records opening time; localhost opening is not a production network-load benchmark.

Ours prepares Canvas, selection, accessibility, annotations and editor data. PDF.js prepares text content including marked content, annotations and structure. These semantic models differ: PDF.js content-order text is not our geometric reading-order/selection model. The measurements compare complete requested outputs in this harness, not exact feature equivalence between engines.

There are three paths:

- `ours`: `preparePage` followed by `paintCanvas`, using the unmodified published site frozen for `7e7a98d`.
- `reference`: the previous comparison shape, `getOperatorList` plus text/annotations/structure, then `render`.
- `reference-streaming`: `render` concurrently with text/annotations/structure, without the extra `getOperatorList` request. This exercises PDF.js's ordinary render streaming and optimizer path.

The old reference shape does additional work. `PDFPageProxy.getOperatorList` passes `isOpList=true`; `getRenderingIntent` adds `OPLIST` to the intent and cache key. `render` uses a different key, so the public operator-list request does not populate the render intent's operator list. `OperatorList` also selects `NullOptimizer` for the explicit `OPLIST` intent. Removing this extra request makes PDF.js faster and increases the measured gap.

Local artifacts, retained under ignored `_build/pdfjs-flow-next/`:

- [Interactive CPU heatmap and flame graphs](../../_build/pdfjs-flow-next/final/flamegraphs.html): variant, thread, page and phase filters; self-time table; hover locations; click to zoom; search highlighting.
- [CPU hotspot heatmap PNG](../../_build/pdfjs-flow-next/final/cpu-heatmap.png) and [per-page latency heatmap PNG](../../_build/pdfjs-flow-next/final/page-heatmap.png).
- [Raw profile run manifest](../../_build/pdfjs-flow-next/final/sampled.json), 18 adjacent `.cpuprofile` files and six `.folded` stack files with integer microsecond weights. Raw profiles can be imported into Chrome DevTools; they include the intervening harness/hash work. The HTML filters that work out using recorded page/phase windows, including page-setup gaps inside the timed page interval.
- [Resolved sampled stacks and summaries](../../_build/pdfjs-flow-next/final/analysis.json).
- [Five-sweep uninstrumented Chromium timings](../../_build/pdfjs-flow-next/final/timing.json), [three-sweep WebKit timings](../../_build/pdfjs-flow-next/webkit/timing.json), [separate Canvas operation counts](../../_build/pdfjs-flow-next/final/counts.json), and [combined summary](../../_build/pdfjs-flow-next/summary.json).
- [Verified Worker source-map manifest](../../_build/pdfjs-flow-next/pdf-worker.js.map.verified.json).

Chromium CPU sampling uses the [CDP Profiler](https://chromedevtools.github.io/devtools-protocol/tot/Profiler/) at a requested 1000 microsecond interval on **both** the main page target and the actual parser Worker target. Three fresh sweeps per path produced 39,098 raw samples across 18 profiles. Function wrappers and source replacement are absent from sampled and uninstrumented runs. The operation-count run separately wraps Canvas APIs and is not used for latency claims.

Source names are restored with a two-stage esbuild source map. Both minification stages must reproduce the published bridge and Worker byte for byte before the map is accepted. All 16 frozen artifact hashes were checked. The sampled Worker is 5,290,334 bytes, SHA-256 `e65a8e6fbc4b720d22f3673c1a6a0c49c0806f30be02ff2973979a5d242d6003`.

Sample weights estimate time at active JS stacks, including synchronous browser API work charged to its JS caller. They are not CPU-cycle measurements or C++/GPU stacks. Idle and unresolved `(program)` samples are reported separately. About 8–11 ms per main-thread sweep of hash-harness samples straddled phase boundaries and are separately excluded. Small differences below this granularity should not be interpreted. Inclusive parent/child times overlap. Main and Worker activity can overlap and must not be added as wall latency. Heatmap categories are disjoint classifications of sampled stacks; the actual call stacks remain inspectable.

## Full-document latency

These are independent medians of uninstrumented first sweeps; stage medians need not sum exactly to the total median.

| Browser and path | Sweeps | Prepare | Paint / combined render | Full page sweep |
| --- | ---: | ---: | ---: | ---: |
| Chromium, ours | 5 | 1772 ms | 1673 ms | **3568 ms** |
| Chromium, PDF.js extra OPLIST | 5 | 179 ms | 179 ms | 507 ms |
| Chromium, PDF.js streaming + semantics | 5 | overlapped | 312 ms | **437 ms** |
| WebKit, ours | 3 | 1708 ms | 1764 ms | **3573 ms** |
| WebKit, PDF.js extra OPLIST | 3 | 356 ms | 409 ms | 869 ms |
| WebKit, PDF.js streaming + semantics | 3 | overlapped | 508 ms | **639 ms** |

Median within-sweep ours/reference ratios are **7.04x / 8.22x** in Chromium (extra OPLIST / streaming) and **4.11x / 5.56x** in WebKit. These are paired ratios, not ratios calculated from the independent medians above. Host load during the Chromium timing batch was approximately 4.4–4.8; WebKit approximately 4.1–5.3. All heavy measurements ran sequentially.

Median localhost opening time was about 140–141 ms for ours and 59–72 ms for PDF.js. Including this opening interval gives median Chromium totals 3713 / 566 / 496 ms and WebKit totals 3710 / 936 / 707 ms for ours / extra OPLIST / streaming. The multi-second difference is in page processing, even with opening included. Opening was not CPU-profiled in this experiment.

Chromium ours page 13 produced two same-code pixel hashes across the five sweeps, with identical semantic hashes. This is retained as observed nondeterminism; no hash was added to a whitelist. WebKit ours was stable across all three sweeps. Each reference path was stable, and reference extra-OPLIST versus streaming pixels **and** semantics matched on every page in every pair. This is an analysis of an unchanged renderer, not a candidate pixel-acceptance or speedup result.

## The two pipelines

PDF.js keeps drawing as an operator program:

```text
PDF objects / content streams
  -> PartialEvaluator + font/image resource caches (parser Worker)
  -> fnArray + argsArray, streamed in chunks (nominal size 1000)
  -> CanvasGraphics.executeOperatorList (main thread in this harness)
  -> showText / paths / images / browser gradients

text extraction / annotations / structure -> independent request streams
```

Ours constructs a rich positioned page before it can send a complete render packet:

```text
PDF objects / content streams
  -> collected positioned glyph/paint entries
  -> PdfPageModel + shared compiled glyph resources
  -> geometric reading order and semantic projections
  -> model cache accounting
  -> Canvas v3 text runs + selection/accessibility/annotation/editor packet
  -> transfer and host decode
  -> whole-page native eligibility
       -> native outline runs, or
       -> expanded retained scene + tiled Float32 software compositor
```

We already share ordinary glyph programs and paint states and compute prepared reading order once. The remaining issue is the required sequence of rich intermediate forms and backend choice, not an assumption that every glyph recompiles its font or that selection and accessibility each sort the page again.

PDF.js can start consuming an operator chunk while later work continues. Ours currently waits for the complete page packet. Streaming can reduce the critical path and first visible paint, but changing request scheduling alone cannot explain or remove the much larger amount of active work sampled in our Worker.

## Main-thread hotspots: representation and backend choice

Mean sampled active main-thread time per sweep is approximately **1499 ms ours**, **292 ms PDF.js extra OPLIST**, and **243 ms PDF.js streaming**. Final RGBA readback is included in these numbers (roughly 142 / 138 / 102 ms sampled). It is a common measurement cost and is distinct from the internal readbacks below.

PDF.js's normal text path is `CanvasGraphics.showText -> ctx.fillText`. Its fallback `paintChar` path caches font-space `Path2D` objects through `FontFaceObject.getPathGenerator`. PDF.js still loops over individual glyph placements; it does not draw this entire document in one text call.

Our normal native text path is `nativePdfGlyphPath -> positioned SVG path string -> new Path2D(path) -> fill`. Shared numeric font outlines save compilation and packet size, but the host turns them into decimal path strings at every painted placement.

| Internal Canvas work, whole original document | Ours | PDF.js normal rendering |
| --- | ---: | ---: |
| `fillText` calls | 0 | 69,298 |
| `Path2D` constructions | 72,166–72,169 | 1,055 |
| String `Path2D` constructions | 72,166–72,169 | 0 |
| Cumulative input string length | approximately 112.5 million UTF-16 code units | 0 |
| Internal `getImageData` calls | 3,935 | 14 |
| Internal `getImageData` pixels | 12,519,452 | 1,400 |
| Internal `putImageData` calls | 144 | 0 |
| Browser linear gradients | 0 | 81 |

Counts exclude the harness's final 14 full-page readbacks. The reference's 14 internal readbacks are 10x10 subpixel-font capability probes. Counts are cumulative operation/input volume, not simultaneous memory retention. Two counting sweeps observed 112,502,500 and 112,502,835 path-string code units; minor operation-count variation is retained rather than treated as a deterministic fixture assertion. The first exploratory sweep is retained in `exploratory-counts.json`; its unverified `reference-outline` experiment is excluded from all comparisons. `final/counts.json` contains the repeated three-path count run.

`nativePdfGlyphPath` alone has approximately **203 ms self time** per sweep. The native `paint` callback containing `new Path2D` and `fill` has approximately **155 ms self / 159 ms inclusive**. PDF.js `showText` has approximately **54–57 ms self / 55–58 ms inclusive**. Synchronous Canvas work is included in those caller samples. This is direct evidence for an expensive positioned-outline representation; it is not evidence that replacing the text loop with fewer JavaScript `for` statements will close the gap.

The larger main-thread concentration is page 11:

| Page 11, uninstrumented median | Ours | PDF.js extra OPLIST | PDF.js streaming |
| --- | ---: | ---: | ---: |
| Prepare | 602 ms | 52 ms | overlapped |
| Paint / combined render | **919 ms** | **40 ms** | **67 ms** |
| Total including final readback | **1532 ms** | **106 ms** | **78 ms** |

This page accounts for about 43% of our entire sweep, and approximately 46% of the Chromium difference from streaming PDF.js when comparing the displayed medians. This is a concentration estimate, not an optimization forecast.

Both the compact native-program path and the expanded scene's native eligibility reject the standalone shading operations. `prepareNativeCanvasItems` only permits ungrouped paths/images at that point, and `prepareNativePdfProgram` also rejects shading raster-resource invocations. The compact text program expands, and the page goes through the tiled software compositor. Text shares that fallback even though most of it is ordinary opaque text. The page has 81 axial shading placements alongside thousands of glyphs.

On this page alone, ours performs **3,835 internal readbacks covering 12,487,052 pixels**. PDF.js performs one 100-pixel font probe and paints 81 browser linear gradients. Our sampled stacks show `raster`, `paintSource`, `PdfCompositor.paint`, `beginGroup`, `endGroup` and premultiplied-to-RGBA conversion; PDF.js has no corresponding repeated source readback/composition pipeline on this input. Across the entire document, the disjoint software raster/composition bucket accounts for about **505 ms** sampled active main-thread time, with another **103 ms** in shading/pattern stacks. Additional traversal/setup remains visible in the graph's `Other` bucket.

## Worker hotspots: more required work before painting

Mean sampled active parser-Worker time is approximately **1773 ms ours**, **240 ms PDF.js extra OPLIST**, and **190 ms PDF.js streaming**. Both reference paths also perform the independent text/annotation/structure requests.

| Selected Worker stack | Ours inclusive sampled time/sweep | Interpretation |
| --- | ---: | --- |
| `pdf_page_model` | 1247 ms | Rich prepared page construction dominates |
| `pdf_items_of_page` | 1064 ms | Contains collection and item/resource lowering |
| `pdf_collected_entries_of_ops` | 254 ms | Content interpretation and positioned entries |
| `pdf_items_of_collected` | 773 ms | Contains shading, image and outline lowering |
| Shading resource construction | 332 ms | Nested in item construction |
| Adaptive shading sampler | 257 ms | Nested in shading construction |
| Outline call lowering | 148 ms | Includes Type1/CFF preparation and placements |
| Image resource construction | 134 ms | Real Worker path, including raster-store behavior |
| Geometric text reading order | 146 ms | A single prepared ordering pass |
| Model cache accounting | 92 ms | Geometry/graph walk for bounded cache accounting |
| Canvas plan | 84 ms | Compact program projection |
| Accessibility projection | 59 ms | Additional complete semantic output |

These rows are nested and **must not be summed**. The graph exposes the nesting. A separate disjoint stack classification attributes approximately 334 ms to shading/pattern work, 239 ms fonts/glyph preparation, 227 ms text semantics/layout, 194 ms image-related stacks, 145 ms content interpretation, 142 ms Canvas/transport, 111 ms Flate decoding and 92 ms cache accounting. GC samples add approximately **172 ms**, versus **14 ms** in the extra-OPLIST reference or **9 ms** streaming. GC is not charged to a particular constructor without allocation evidence.

There are two concrete implementation differences beyond the rich page model:

- PDF.js radial/axial shading samples 840 inputs into typed buffers, simplifies color stops and delegates interpolation/rasterization to browser gradients. Our checked adaptive tree evaluates PDF color functions and transforms repeatedly, serializes its sampler and rasterizes through our own pixel pipeline. PDF.js shading parsing accounts for about 12–19 ms sampled inclusive time here, versus roughly 332 ms of our shading resource construction. Precision/validation policies differ; these outputs are not interchangeable merely because they are both gradients.
- PDF.js uses its asynchronous `DecompressionStream` path when supported, with its decoder fallback. Our content/font Flate path still uses the portable MoonBit decoder, while image Flate has the pako host path. The disjoint sampled decoding bucket is about 111 ms ours versus 6–7 ms reference. It is real but too small to explain the multi-second gap alone.

The Worker also samples about 50 ms self time in Unicode bidi range lookup, reached from control filtering, direction scoring and semantic separators. This is a useful bounded follow-up, not the largest architectural gap. `Array.push` samples are spread through sampler construction, packet construction, decoding and font work; they do not prove that MoonBit iteration as a language feature is inherently slow.

## Priorities supported by this evidence

1. **Page 11's coupled shading/whole-page fallback** is the largest concentrated target: expensive sampler preparation in the Worker followed by software replay of unrelated ordinary text on the main thread. Investigate a compact shading representation and a backend boundary that keeps eligible siblings out of the software pipeline. Preserve the existing Float32/backdrop/shape semantics and explicitly validate quantization at any boundary. Earlier direct native-shading promotion changed pixels; it is not an accepted implementation.
2. **Remove positioned path-string reconstruction** from ordinary text replay. PDF.js shows the reusable font-space representation to study. Our previous numeric-path prototype changed WebKit pixels, so direct numeric commands, transformed cached paths, or browser fonts must first demonstrate exact raster compatibility. Switching to `fillText` is a semantic/raster change, not an automatic drop-in fix.
3. **Build the browser program and semantic projections from a shared compact operation representation**, with lazy materialization of the public rich page model. This addresses model/geometry allocation, cache accounting, serialization and GC together. Preserve eager availability of the requested semantic features; moving them outside the timer is not an optimization. The earlier collector-pointer-sharing prototype did not establish a full-document gain and should not be treated as proof of this design.
4. Treat bidi lookup, Flate and smaller packet work as measured secondary targets. Even perfect removal of one such bucket cannot close the observed total difference.

## Reproduction

Build both sites first using the pinned project toolchain, then stop other heavy work. The following commands execute sequentially. A separately frozen site can be supplied through `PDF_PROFILE_ROOT`.

```sh
node tools/pixels/map_published_worker.mjs _build/pages _build/pdfjs-flow-next/pdf-worker.js.map
PDF_PROFILE_ROOT=_build/pages PDF_PROFILE_SAMPLES=3 PDF_PROFILE_MODE=sampled node tools/pixels/compare_cpu_profiles.mjs reference/pdf.js/test/pdfs/tracemonkey.pdf _build/pdfjs-flow-next/final
PDF_PROFILE_ROOT=_build/pages PDF_PROFILE_SAMPLES=5 PDF_PROFILE_MODE=timing node tools/pixels/compare_cpu_profiles.mjs reference/pdf.js/test/pdfs/tracemonkey.pdf _build/pdfjs-flow-next/final
PDF_PROFILE_ROOT=_build/pages PDF_PROFILE_SAMPLES=1 PDF_PROFILE_MODE=counts node tools/pixels/compare_cpu_profiles.mjs reference/pdf.js/test/pdfs/tracemonkey.pdf _build/pdfjs-flow-next/final
node tools/pixels/cpu_profile_report.mjs _build/pdfjs-flow-next/final _build/pdfjs-flow-next/pdf-worker.js.map
PDF_PROFILE_ROOT=_build/pages PDF_PROFILE_SAMPLES=3 PDF_PROFILE_MODE=timing PDF_PROFILE_BROWSER=webkit node tools/pixels/compare_cpu_profiles.mjs reference/pdf.js/test/pdfs/tracemonkey.pdf _build/pdfjs-flow-next/webkit
```

Read the actual source alongside the graphs:

- PDF.js [`src/core/worker.js:935`](../../reference/pdf.js/src/core/worker.js), [`src/core/evaluator.js:1670`](../../reference/pdf.js/src/core/evaluator.js), [`src/core/operator_list.js:653`](../../reference/pdf.js/src/core/operator_list.js).
- PDF.js [`src/display/api.js:1723`](../../reference/pdf.js/src/display/api.js), [`src/display/api.js:2705`](../../reference/pdf.js/src/display/api.js), [`src/display/canvas.js:730`](../../reference/pdf.js/src/display/canvas.js), [`src/display/canvas.js:2759`](../../reference/pdf.js/src/display/canvas.js), [`src/display/font_loader.js:484`](../../reference/pdf.js/src/display/font_loader.js).
- PDF.js [`src/core/pattern.js:168`](../../reference/pdf.js/src/core/pattern.js), [`src/display/pattern_helper.js:103`](../../reference/pdf.js/src/display/pattern_helper.js), [`src/core/flate_stream.js:164`](../../reference/pdf.js/src/core/flate_stream.js).
- Ours [`internal/engine/canvas_program.mbt:80`](../../internal/engine/canvas_program.mbt), [`internal/engine/collector.mbt:181`](../../internal/engine/collector.mbt), [`internal/engine/collector_items.mbt:2`](../../internal/engine/collector_items.mbt), [`cmd/browser/bridge.mbt:305`](../../cmd/browser/bridge.mbt), [`internal/engine/shading_sampling.mbt:185`](../../internal/engine/shading_sampling.mbt).
- Ours [`web/pdf-runtime.mjs:10`](../../web/pdf-runtime.mjs), [`web/pdf-canvas-program.mjs:155`](../../web/pdf-canvas-program.mjs), [`web/pdf-canvas-native.mjs:60`](../../web/pdf-canvas-native.mjs), [`web/pdf-canvas.mjs:112`](../../web/pdf-canvas.mjs), [`web/pdf-compositor.mjs:61`](../../web/pdf-compositor.mjs).

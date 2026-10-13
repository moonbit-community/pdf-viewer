# Render speed investigation

Measured on 2026-10-13 against PDF.js revision
`89b500f5e1d98ed89bb90211e45b28730b2d99ac` (generic build 6.5.1),
Playwright 1.58.2 and a local 13-page PDF. The input and detailed reports stay in
ignored `_build/`; no document text, images or input bytes are published here.

## Reproduce

Build the [pinned reference](../../reference/README.md) and the packaged viewer:

```sh
moon run tools/build_pages.mbtx
PDF_BENCH_PROFILE=1 node tools/render_benchmark.mjs /path/to/document.pdf 1,2,12
PDF_BROWSER=chromium PDF_BENCH_PROFILE=1 node tools/render_benchmark.mjs /path/to/document.pdf 1,2,12
node tools/pixels/profile_page_stages.mjs /path/to/document.pdf _build/stages.json 1,2,12
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

## Remaining costs

| Phase | Observed cost | Next target |
| --- | --- | --- |
| Complex-page warm drawing | Page 12 needs 50 Canvas pixel reads and 54 uploads; PDF.js warm drawing needs neither. | Avoid repeated colour/shape rasterization of independent pattern cells and shading scenes. |
| Cold image preparation | Node page 12 takes about 409 ms overall: colour processing has 115 ms self time, PNG encoding 46 ms, font loading 51 ms and Flate decoding 37 ms. | Reuse decoded image/font resources and avoid encoding pixels that the host can consume directly. |
| New viewport payloads | Page 12 still sends about 2.13 million JSON characters. Its Canvas plan contains about 709,000 path characters and 138,000 clip-path characters. | Intern repeated immutable geometry/resources and reuse prepared plans between viewports. |
| Worker startup | A diagnostic WebKit run spends about 132 ms loading/evaluating modules and 9 ms initializing the colour/JBIG2 adapters. The packaged bridge is about 7.5 MiB. | Reduce initial module evaluation; codec initialization is a smaller cost on this input. |

The pixel traffic comes from the retained source colour/shape pass, pattern
shape surfaces, CPU shading output and retained scene bitmaps. The document
raster cache is effective: warm runs add no image decodes. It does not cache
these temporary colour/shape surfaces. WebKit spends much more time in pixel
reads/uploads than Chromium for the same calls.

In one final run, page 12 warm paint plus forced flush has medians of **134 ms
versus 18.5 ms** for WebKit, and **69 ms versus 28.5 ms** for Chromium. Page 2 remains
close to PDF.js. These are host-dependent samples; scheduling, raster flush and
background load explain variation between runs. The semantic fix leaves these
drawing calls unchanged, so it does not close this part of the gap.

A diagnostic experiment bypassed the preliminary pattern colour/shape pass. It
removed many pixel transfers, but changed affine pattern coverage and some
pixels. That experiment remains outside the product. Further optimization must
retain transparent-edge coverage, group bounds, knockout shape and colour-space
semantics, including dense pattern lattices and cache eviction.

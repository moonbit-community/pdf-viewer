# Worker-backed Canvas integration

A2 integrates the upstream Worker host `eb4e017` and annotation/print-intent
entry `1f9db19` without replacing its task
queue, cache policy, text/source APIs or document generation ownership.
Parsing, image decoding and Canvas-plan construction remain in the Worker.
ICC/JBIG2 engines install before its `ready` message; Canvas replay installs a
separate main-thread ICC engine. Page, thumbnail and print Canvases are drawn
off-DOM and checked for cancellation before publication.

`tools/pixels/worker_canvas_test.mjs` runs the actual `web/pdf-worker.js` and
`web/pdf-client.js` over Node worker_threads transport. Its adapter supplies
browser-shaped Worker events and local file-URL asset fetch. It does not replace
the PDF bridge, decoders, CMM or Canvas renderer. [The report](worker-canvas.json)
records the fixture and original affine-text pixel hashes.

The deterministic 14-page PDF exercises real JBIG2 black/white pixels and ICC
conversion to `[61, 128, 193, 255]`, transferable document input, metadata-only
layout, off-screen selection and both LRU budgets/eviction. Transport tests cover
priority, pre-ready/queued/active cancellation, error recovery, invalidation,
reset/reopen and initialization failure. A second fixture verifies display-only,
print-only and Hidden appearance pixels at all rotations with CropBox/UserUnit,
separate display/print cache entries, safe annotation URLs and overlay geometry. The original 621-byte G01 fixture also
passes through the Worker: nonblank 240×160 pixels, empty diagnostics and exact
RGBA equality with the direct public bridge, without a native outline callback.

The test additionally invokes the real async scheduler and exact viewer
thumbnail/print functions with element doubles and delayed painting. Old
navigation/document results, warnings and errors cannot publish after cancellation.
These are lifecycle regression tests, not browser DOM QA. The updated
`tools/browser_test.mbtx` suite is compile-checked; historical upstream Chromium
measurements remain separately identified in `docs/validation.md`.

Run from the repository root after installing the Node Canvas host described in
[native Canvas setup](native-canvas-setup.md):

```sh
npm ci --prefix tools/web-assets --ignore-scripts --omit=optional
moon run tools/build_web.mbtx
moon run tools/text_host_pen.mbtx
PDF_CANVAS_PACKAGE=/absolute/path/to/host/package.json \
  node tools/pixels/worker_canvas_test.mjs
```

The common A2 check includes this command. Individual active-task cancellation
discards its result; closing/replacing the document terminates the Worker.
Synchronous Canvas replay is still main-thread work, and cache accounting is
not a whole-document or process peak-memory bound.

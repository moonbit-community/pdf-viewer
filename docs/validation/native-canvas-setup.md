# Native PDF plan to Canvas PNG: fresh-checkout setup

Run from the repository root. Install the MoonBit toolchain and Node 22.13.0+
with npm first.
The validation host used Node 24.19.0.
Linux native builds also need `g++` with C++20 support for the bundled JBIG2
adapter. Native ICC conversion uses the installed LittleCMS2 shared library
(`liblcms2.so.2` on Linux); when it is unavailable, the native colour path uses
its declared PDF Alternate capability rather than claiming profile conversion.
JPEG/JPX themselves need no external codec SDK.

A checkout does **not** contain the generated bridge or JS/Wasm dependency
assets. Install the locked asset dependencies and build the shared bridge and
deployment assets before using the Canvas host runner:

```sh
npm ci --prefix tools/web-assets --ignore-scripts --omit=optional
moon run tools/build_web.mbtx
npm install --prefix _build/canvas-host @napi-rs/canvas@1.0.10
moon run --target native cmd/main -- input.pdf page-1.canvas.json 1
PDF_CANVAS_PACKAGE="$PWD/_build/canvas-host/package.json" \
  node tools/render_canvas.mjs page-1.canvas.json page-1.png
```

The separate `_build/canvas-host` install supplies the local Canvas host. The
locked `tools/web-assets` dependencies supply LittleCMS and the standalone
JBIG2 Wasm asset from `pdfjs-dist`; the PDF.js renderer is not deployed or used
for product rendering. On a host where `@napi-rs/canvas` is already installed,
skip that Canvas installation and point `PDF_CANVAS_PACKAGE` at its absolute
`package.json` path. `PDF_VIEWER_BRIDGE` can optionally select another built Moon
JavaScript module exporting `process_cmyk_to_rgb`; otherwise the runner imports
`web/_generated/pdf.js`. The build script first runs
`tools/prepare_web_assets.mjs` to verify pinned package versions and asset
SHA-256 values, then builds the release JS bridge and stages local assets. It
does not install npm dependencies automatically. Generated LittleCMS JS/Wasm
and JBIG2 Wasm are ignored by Git; native C++ sources and text licenses remain
tracked. Deployed assets use same-origin URLs, including inside the Worker.

The native command parses and decodes the PDF once into the public Canvas JSON.
The Node runner replays that plan with local Canvas and the shared colour engine;
it does not parse the PDF again, upload it, or call a remote renderer. A one-based
page number is optional and defaults to 1. SVG output remains available by using
an `.svg` destination instead of `.canvas.json`.

This path is validated on Linux with a native Node Canvas API host. It is not a
DOM/browser interaction test. JBIG2 remains explicitly unavailable on untested
non-Linux native targets and standalone Moon Wasm/WasmGC; see the
[codec target matrix](../../codecs/jbig2/README.md). Per-image and Canvas limits
still apply, and the synchronous JS image path needs a worker boundary for hard
cancellation. See the [A2 acceptance record](../a2-acceptance.md) for the current
scope and [image entry measurements](image-sampling.md) for real-file evidence.

## Clean-build check

Before npm/build-copy delivery, a fresh archive of the integrated tracked
sources, with no generated web bridge or build outputs, was built in an
isolated directory. Cached Moon packages and an existing pinned Canvas host
installation were reused. Running the build script, native CLI and public Node
runner rendered the original `jpx_smaskindata.pdf` to 140x40 with empty
diagnostics and byte-exact
PDF.js pixels. This verifies the missing generated-bridge step and the external
Canvas package resolution at that baseline; it is not a test of the new npm
asset setup or a claim of a new network install test.

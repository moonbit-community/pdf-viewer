# Pattern-painted stencil images

`PdfVisualItem.pattern` retains a Pattern resource for an external or inline
`ImageMask`. Ordinary colour images ignore the current nonstroking Pattern.
The Canvas plan lowers this resource through the existing nested pattern plan,
including Type 2 shading patterns. The Canvas image branch paints that pattern
in page space and clips it to the decoded stencil coverage. Decode inversion,
clipping and constant alpha keep their normal image/paint semantics.

The resource uses the same stream-base `PatternInitialState` as ordinary paths.
Changing the image placement CTM does not scale the pattern lattice. Selecting
Pattern before or after a 20x placement transform produces the same 10-unit
cells as a same-stream path. This is checked at both model and final pixel
levels.

An unresolved stencil Pattern produces `PDF_IMAGE_PATTERN_RESOURCE`. The SVG
compatibility renderer reports `PDF_SVG_IMAGE_PATTERN`; it is not counted as a
Pattern-painted stencil implementation.

## Reproduce

From the checkout, with the documented MoonBit toolchain and C++ prerequisites:

```sh
npm ci --prefix tools/web-assets --ignore-scripts --omit=optional
moon run tools/build_web.mbtx
npm install --prefix _build/pattern-oracle @napi-rs/canvas@1.0.10 pdfjs-dist@6.4.299
python3 tools/fixtures/image_pattern.py _build/image-pattern.pdf
PDF_CANVAS_PACKAGE="$PWD/_build/pattern-oracle/package.json" \
  node tools/pixels/image_pattern_test.mjs web/_generated/pdf.js \
  _build/image-pattern.pdf _build/image-pattern-results
```

The generator creates only original deterministic PDF operators and packed
one-/two-pixel masks. It writes 21 pages and an adjacent case-name JSON file.
The harness invokes the release browser bridge and shipped `web/pdf-runtime.mjs`
with native Canvas API primitives. This is not a browser DOM test. It writes
actual/reference PNGs, exact page plans and a comparison report. Optional
`PDF_CANVAS_WEB` selects an integration checkout's web runtime without modifying
it. The harness does not download packages or upload PDFs.

## Results and oracle controls

The audit page is 20x20 points with a full one-pixel stencil, filled by a 10x10
red-left/blue-right pattern. Before the change the four interior points
(x=2,7,12,17; y=10) were all black, with no diagnostics. They now are red, blue,
red, blue. Poppler at 72dpi independently confirms those values.

The full producer suite passed 449 native, 441 JS, 442 Wasm and 442 WasmGC tests,
including five focused model/lowering regressions; all-target checking passed.
The Canvas harness has empty diagnostics for all 21 pages. Eighteen pages are
byte-exact against their applicable PDF.js reference/control, covering coloured
and inline stencils, both Decode directions, axial shading, translated pattern
matrices, alpha, clipping, normal colour images and CTM/path controls.

PDF.js 6.4.299 itself renders the eight fully opaque 1x1 stencil Pattern cases
as scalar black. Its `paintSolidColorImageMask` operation skips Pattern
materialization and calls `fillRect` with the existing Canvas fillStyle. The
harness records the actual operator selection. Each such page has an equivalent
fully opaque 2x1 control that takes PDF.js's general image-mask pattern path.
Our one-/two-pixel outputs are byte-identical. The applicable oracle is the
control output, not the erroneous black shortcut. Source attribution is the
pinned PDF.js revision `89b500f5e1d98ed89bb90211e45b28730b2d99ac`,
`src/core/image.js` (`isSingleOpaquePixel`), `src/core/evaluator.js` and
`src/display/canvas.js` (`paintSolidColorImageMask`).

The three uncoloured half-empty-cell cases retain a precise existing pattern
sampling difference: the renderer evaluates transparent cell coverage in
device space, while PDF.js filters a repeating alpha texture. Differences
above 8 occur only at the eight vertical edge columns 0,4,5,9,10,14,15,19;
maximum channel difference is 26, with zero interior pixels above 8. Both
stencil variants are byte-identical to an ordinary path using the same pattern.
The harness asserts those bounds only for these cases; other cases require
zero pixels above 8. No whole-page exactness is claimed for this policy
residual. Results and build/source hashes are in
[`tools/image-pattern-validation-results.json`](../../tools/image-pattern-validation-results.json).

# Canvas image sampling validation

The shared `web/pdf-image-sampling.mjs` applies the existing MoonBit/PDF.js
Float32 singular-value smoothing threshold and axis-aligned device-pixel
corner rounding. All image colour, component, shape and stencil draws use the
same decision.

The official ICC `version4pdf.pdf` has a separate DeviceRGB control: the colour
workstream replaced its seven images with the exact independently converted
pixels, leaving image placement unchanged. This separates CMM from sampling.
With the shared helper, the main image rectangle (108,144)-(491,433) agrees
with PDF.js 6.4.299 within one byte everywhere, MAE 0.001045 and zero pixels
above 8. Both upper quadrant interiors are byte-exact; lower quadrant interior
MAEs are 0.000277 and 0.000202. The small first example is within one byte too.
Captured PDF.js final drawImage transforms confirm matching corner rounding.

Against Poppler the same control still has main-image MAE 6.3878, including
10.8069/10.2096 in the lower quadrants. This is an independently reproduced
reference bitmap sampling/placement difference, not an ICC residual. Whole-page
PDF.js MAE 2.1764 includes text rendering outside the image rectangle and is not
counted as image acceptance. Per-crop results are committed in
`tools/image-sampling-validation-results.json`.

## Large scan minification

`pdfDrawImage` reduces each source axis by at most 2x per intermediate Canvas
draw before the final affine placement, matching PDF.js. Scratch pixel counts
are checked before each allocation, include both live temporary surfaces and
are limited to 16,777,216; surfaces are released on success and error. Alpha,
colour components and shape use the same helper.

The real `JBIG2Globals.pdf` has a 5188x6930 main scan. Captured PDF.js calls
reduce it to 649x867 then draw exactly (0,0)-(623,832). Both outputs put the
heading at y42; an earlier reported y8 placement discrepancy was incorrect.
With the exact full source bitmap, our iterative draw matches the entire
PDF.js page within one byte (MAE 0.00220, no pixels above 8). This independently
isolates the remaining normal-path difference to the image resource's bounded
nearest-neighbour pre-resize, rather than decode, placement or hidden OCR.

The production packed-source path now performs coverage-preserving binary
reduction before RGB allocation. For this fixture it emits 2594x3465 directly
from the 1-bit source. Replaying that actual resource in the original page plan
retains the same whole-page result: MAE 0.0021974, maximum 1, zero pixels above
8. No full 5188x6930 RGB/RGBA surface is allocated. Other oversized masked/colour
images retain the documented floor-nearest policy.

## Ten-case Canvas manifest

`tools/image_canvas_compare.mjs` runs `tools/image_cases.json` through the public
Canvas replay with the pattern/shading adapters and PDF.js 6.4.299. Set
`PDF_CANVAS_PACKAGE` to an installed oracle package.json; optionally set
`PDF_CANVAS_WEB` to the integrated web directory. The positional arguments are
an existing release `render_plan` bridge, fixture directory and output directory.
No dependency installation or PDF upload occurs. Results are stored in
`tools/image-canvas-validation-results.json`.

Seven complete pages are byte-exact: Lab `issue10339_reduced.pdf` at 0/90 degrees,
`colorkeymask.pdf` inside a tiling pattern at all four rotations, and
`issue4246.pdf` with its high-resolution mask. All ten have empty diagnostics.
The other cases retain their whole-page metrics, without widened tolerances:

- `smaskdim.pdf`: 14,144 pixels above 8, MAE 0.38360; visible annotation boxes
  account for the extra non-image output. Both decoded source RGBA images are
  independently exact, as recorded in the source-plane report.
- `issue17147.pdf`: 1,246 pixels above 8, MAE 0.02199, only on the rotated stencil
  perimeter. Every reference-uniform 3x3 black/white interior is byte-exact.
- `issue13931.pdf`: whole-page MAE 2.17642 includes text rendering differences.
  The stamp rectangle (880,145)-(1110,285) has MAE 0.02449, maximum error 2 and
  zero pixels above 8. The full source image alpha/matte checks remain separate.

These tests use @napi-rs/canvas 1.0.10 as the Canvas API host. They are not a DOM,
Chromium or interactive browser test. The release bridge used for these image
cases predates the final all-workstream aggregate build; shipped-entry checks
are recorded separately.

## Actual shipped entry

The final release `cmd/browser` bridge was consumed read-only through
`web/pdf-runtime.mjs`, with both LittleCMS and JBIG2 initialized through its
actual initialization function. The existing `tools/pixels/browser_entry_test.mjs`
was used with test-only PNG/timing capture. All three original PDFs have empty
runtime diagnostics; exact bridge hash and measurements are in
`tools/image-shipped-entry-results.json`.

- `JBIG2Globals.pdf`: 2.604 s bridge, 2.923 s including Canvas; all 7,012 text-layer
  items retained; whole-page maximum pixel error 1, zero pixels above 8.
- `jpx_smaskindata.pdf`: 79.6 ms including Canvas; whole page byte-exact.
- `issue13931.pdf`: bridge 6.287 s, total 12.051 s. The stamp crop has maximum
  error 2 and no pixels above 8; whole-page text differences remain recorded.

The last page also exposed a text replay resource issue: full-page end RSS was
2.409 GB, versus 588 MB when the same parsed plan replayed only its image. The
image-only Canvas phase took 163 ms, compared with 5.762 s for the full page.
This measured non-image issue was sent to the text workstream. These figures
are process measurements, not a peak-memory bound or a browser DOM result.

## Stencil Pattern paint

External and inline ImageMask Pattern capture, stream-base pattern matrices,
shading/uncoloured controls and the 21-page shipped Canvas regression are
recorded in [image-patterns.md](image-patterns.md). That report separates the
PDF.js one-pixel solid-mask shortcut defect from the existing transparent-cell
edge sampling policy.

# A2 affine text pen validation

Date: 2026-10-10. Implementation: `text_stroke.mbt`, the glyph-lowering hunk
in `pdf-viewer.mbt`, and the small browser-text consumer in `svg_text.mbt`.
No A1 font/CMap, charcode/CID/GID selection, FontMatrix, vertical origin,
text advance, extraction or actual Type 3 charproc implementation changed.

## What is retained and rendered

`PdfTextItem.stroke` retains the graphics CTM, width, dash array/phase,
cap, join, miter limit and stroke alpha separately from glyph placement.
For embedded CFF, Type 1 and TrueType, A1's existing glyph-transform helper
is called with an identity graphics CTM, followed by its existing outline
API. Thus the path includes font size, text matrix, horizontal scaling,
rise and vertical origin, while the **pen** is transformed only by the
original graphics CTM. This also avoids inverse-CTM cancellation and retains
local outlines when the graphics CTM is singular.

The SVG serializer strokes that local path under the complete CTM. The
Canvas plan retains the same local path and pen for native Path2D replay.
Modes 1/5 stroke; modes 2/6 fill and stroke. Existing clipping/soft-mask and
viewport wrappers remain outside that transform. Actual Type 3 charprocs
keep their own original paints and have no substituted text pen.

For unembedded/host fonts, an independent text transform that is a
similarity (uniform scale with optional rotation/reflection) has exact pen
compensation even under an arbitrarily sheared/nonuniform graphics CTM.
An independent nonuniform/sheared text transform still requires an outline
from A1 or a capable host. That boundary is explicit in both
`stroke.unresolved` and `data-pdf-text-stroke-unresolved`, with value
`affine-text-pen-requires-glyph-outline`. The visible fallback uses an
area-equivalent approximate pen rather than silently dropping the text.
This case is **not** claimed as affine stroke conformance. Host-created
legacy models lacking pen state have a separate `missing-pdf-pen-state`
SVG marker.

A subsequent capable-host integration resolves this boundary in the public
native Canvas tool using its existing SVG-to-outline API, with no new font
renderer. See [host-font text pen validation](host-text-pen.md) for the
minimal PDF, exact same-font controls, installed-font assumptions and the
still-explicit default browser/legacy-SVG boundary.

## Original embedded-font PDFs

`moon run tools/text_strokes.mbtx` creates `_build/text-strokes/`.
The two-glyph, unhinted TrueType font is original Apache-2.0 material; its
provenance and contours are described under `tools/fixtures/text-stroke/`.
The generated PDF has SHA-256
`595c0ba391a89b2901d582d4329934633ceeb7a13ec9cc01a259a04873e5446a`.

Comparisons use PDF.js 6.4.299 with `@napi-rs/canvas`, Resvg, and independent
Poppler 26.05.0. `tools/pixels/compare_text_strokes.mjs` compares the real
SVG and Canvas outputs at scales 1/2 and rotations 0/90/180/270. It writes
all four PNGs for each case, reports every difference, and fails on missing
references, inconsistent dimensions or blank output. It does not increase
thresholds or skip failing files. The `>8` count is a reported edge metric,
not a conformance tolerance.

At 1×, rotation 0, RGB mean absolute error on the 0–255 scale:

| PDF page | Pen case | SVG before vs Poppler | SVG after vs Poppler | SVG after vs PDF.js/Skia |
| --- | --- | ---: | ---: | ---: |
| 1 | Nonuniform CTM | 4.736953 | 0.413906 | 0.199818 |
| 2 | Sheared CTM, dashes and round joins | 4.022917 | 0.343698 | 1.019531 |
| 3 | Independent affine text matrix | 2.287161 | 0.390156 | 1.226875 |
| 4 | Reflection, fill and independent stroke alpha | 1.287925 | 0.127335 | 1.295391 |
| 5 | Miter limits | 9.014844 | 0.220130 | 0.135026 |
| 6 | q/Q pen restoration | 5.871927 | 0.403698 | 1.082188 |
| 7 | Page-space clipping | 8.517266 | 0.306719 | 1.693542 |

“Before” is commit `e0d6a8820092403d3443c57bd2b8d27394832980`.
Across all **56** page/scale/rotation combinations, SVG versus Poppler MAE
is **0.076706–0.413906**. PDF.js/Skia's visible dashed text differs from
Poppler and the explicit glyph paths; this is an observed reference-host
result, not a claim that every PDF.js/browser combination omits dashes.
The independent nonuniform text matrix and fill/stroke alpha cases also
show reference-renderer differences. PNG inspection confirms the new pen
geometry follows Poppler. Transparency compositing is a separate issue: the
combined fill/stroke case has a normative oracle split described below.

The pre-direct-Path2D Canvas fragment-image route had MAE
0.422691–1.961081 versus Poppler across those 56 combinations. Native
Path2D replay was then tested with the compositor workstream's actual
renderer and the same retained model: MAE is **0.105820–0.730920** versus
Poppler (mean 0.330966). At 1×, the seven page MAEs are 0.387031, 0.389557,
0.457813, 0.730920, 0.184661, 0.393177 and 0.351979. This also caught and
fixed a real integration error where direct text replay omitted the retained
stroke alpha.

The fourth page's remaining difference is intentional. Per
[ISO 32000-1 §11.7.4.4](https://opensource.adobe.com/dc-acrobat-sdk-docs/standards/pdfstandards/pdf/PDF32000_2008.pdf#page=365),
combined text modes 2/6 with unequal alpha use an implicit non-isolated
knockout group, independently of TK. Canvas follows that rule. Ghostscript
10.05.1 confirms the uniformly translucent stroke without compositing it
against the fill underneath. With 4-bit text/graphics antialiasing, Canvas
MAE versus Ghostscript is **0.345773**, compared with legacy SVG 0.961094,
Poppler 1.014974 and PDF.js/Skia 1.906120. The legacy SVG text fragment still
composites fill and stroke sequentially; its smaller Poppler error here is
**not** evidence of correct PDF transparency. The authoritative path for
this case is native Canvas replay.

Across all 56 variants, Canvas versus Ghostscript MAE is 0.227897–1.730156.
The larger cases have visibly continuous text strokes in Ghostscript where
Poppler and the retained-geometry path have dashes. Section 9.3.6 specifies
that text stroke state has the same effect as path stroke state in user
space; no reference mismatch is suppressed or converted into a wider test
tolerance.

Reproduce in an environment with the pinned Node packages:

```sh
moon run tools/text_strokes.mbtx
moon build --target js --release cmd/pixel_plan
cp _build/js/release/build/cmd/pixel_plan/pixel_plan.js _build/pixel-plan.mjs
PDF_CANVAS_PACKAGE=/absolute/path/to/node/package.json \
  node tools/pixels/compare_text_strokes.mjs \
  _build/pixel-plan.mjs _build/text-strokes/text-strokes.pdf
```

Optionally set `PDF_STROKE_BASELINE_BRIDGE` to the built baseline module.
`PDF_PIXEL_OUTPUT`, `PDF_PIXEL_SCALES` and `PDF_PIXEL_ROTATIONS` select output
and variant lists. `PDF_CANVAS_RENDERER` can select a candidate native
renderer module; `PDF_STROKE_GHOSTSCRIPT=1` enables the third reference with
4-bit text/graphics antialiasing. No private PDF bytes or browser login are required.

## Upstream embedded-CFF regression

Pinned PDF.js source revision:
`89b500f5e1d98ed89bb90211e45b28730b2d99ac`.
The unchanged upstream fixture `test/pdfs/text_clip_cff_cid.pdf` has SHA-256
`81aaf48f55c659d29d7a533cd913bd9d028ffad183b46580a2122eebe5187506`.
It uses rendering mode 7, so it is a genuine glyph/clip regression, **not**
an original stroked-text fixture. Its unchanged comparison is Canvas MAE
0.003006 (9 pixels above 8) and SVG MAE 0.139241 versus PDF.js/Skia.

A separately labelled derivative keeps that real embedded CID-CFF font and
replaces only page content with:

```text
q 1 .08 .2 1 5 0 cm 3 w [8 5] 3 d 1 J 0 j 3 M
BT 2 Tr 50 55 Td /F2 95 Tf <0044 0025 0026 0014 0015 0016> Tj ET Q
```

It exercises the actual CFF outlines with a sheared CTM, dashes and miter
limit. At scales 1/2 and four rotations, SVG MAE versus Poppler is
**0.227722–0.522603**, versus PDF.js/Skia **1.248121–1.338957**.
Native direct Canvas replay versus Poppler is **0.246166–0.528940**.
This derivative is not reported as an unmodified upstream PDF. It can be
recreated using `PdfWriter(clone_from=...)` from pypdf, replacing the first
page's decoded contents, then running the same comparison tool. The
upstream fixture is fetched through `git show` and is not redistributed by
this change.

## SVG-host boundary probe

`tools/pixels/text_pen_host_probe.mjs` tests a transformed rectangle against
an explicitly transformed outline with the correct independent pen, both
directly and as an isolated SVG image under an outer CTM. It uses the actual
native SVG image loader and Resvg; optional installed librsvg/Cairo is
loaded through its public C API. It does not download or install software.

Observed RGB MAE against the explicit-geometry control:

| Host | Direct non-scaling-stroke | Isolated nested SVG under CTM |
| --- | ---: | ---: |
| `@napi-rs/canvas` SVG image loader | 16.537600 | 10.002883; nested image blank |
| Resvg | 16.524000 | 5.372733 |
| librsvg/Cairo | 0.000000 | 1.072067; extra image rasterization blur |

Both `href` and `xlink:href` were also checked in the native host and the
nested SVG image remained blank. librsvg demonstrates that non-scaling
strokes **can** work in a capable host; Resvg's missing behavior is not
proof of a browser limitation. Chromium execution was unavailable in this
validation environment because its socket creation was denied. No browser
conformance is claimed from these probes, and the unresolved host-font
boundary remains explicit.

```sh
PDF_CANVAS_PACKAGE=/absolute/path/to/node/package.json \
  node tools/pixels/text_pen_host_probe.mjs
```

## Automated checks

Eight focused whitebox tests cover local A1 geometry, raw pen state,
restore, rendering modes, independent alpha, exact similarity fallback,
explicit anisotropic-fallback diagnosis, unchanged Type 3 charprocs and
singular graphics CTMs. `moon info`, `moon fmt`, all four target checks,
full target test suites, JavaScript syntax checks and `git diff --check`
passed for the delivery. Full suites: JS **320/320**, Wasm **321/321**,
Wasm-GC **321/321**, native **324/324**. Existing unrelated vendor warnings
are not reclassified as errors or hidden.

Whole-BT/ET object identity and TK compositing were subsequently integrated
without changing glyph geometry. See [text knockout validation](text-knockout.md)
for the six-page overlap corpus, native grouping, and explicit oracle splits.

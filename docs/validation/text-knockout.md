# BT/ET identity and text knockout

Date: 2026-10-10. This closes the collector/model gap that previously lost
whole-text-object identity after A1 emitted individual glyph entries.

`PdfTextItem.text_object_id` is a nullable string scoped to a particular
content invocation and BT operator. All Tj/TJ glyphs until the matching ET
share it. Reusing a Form XObject gives its text a new invocation prefix, so
two separate Form invocations cannot accidentally become one group.
`text_knockout` retains PDF TK, initially true. Hand-built legacy model
literals default to no object ID and TK true. SVG run joining also respects
the retained object boundaries. The change does not alter font decoding,
glyph placement, actual Type 3 charprocs or text clipping accumulation.

The native Canvas consumer groups consecutive text items sharing an ID
when TK is true. It establishes the implicit non-isolated knockout group
specified by [ISO 32000-1 §9.3.8](https://opensource.adobe.com/dc-acrobat-sdk-docs/standards/pdfstandards/pdf/PDF32000_2008.pdf#page=255).
Each glyph keeps its inherited alpha, blend mode and soft mask. The implicit
group's final composite uses Normal, alpha 1 and no soft mask. Graphics
state changes inside the text object persist after ET. TK false leaves
glyphs as separate elementary objects. The existing inner fill/stroke
implicit group for text modes 2/6 remains independent of this outer group.
The standard prohibits changing TK between BT and ET; this test set uses
valid state changes outside those operators.

## Tests and original PDF

Four whitebox tests cover:

- Shared identity across multiple Tj/TJ operations and separation at ET/BT
- TK false, q/Q restoration, and inherited alpha/blend changes persisting after ET
- Distinct identities for repeated Form invocations
- Retention without manufacturing explicit PDF transparency groups or resetting paints

`tools/text_knockout.mbtx` creates six original pages using the existing
original Apache-2.0 two-glyph embedded TrueType fixture. No extra font
implementation or third-party font asset is added. The PDF SHA-256 is
`cb7f5a6ffd4dfca15eb01365504dacd26133952852a582640ee10d3c866bf0f7`.

The existing three-reference pixel harness renders all six pages at scales
1/2 and rotations 0/90/180/270: **48 combinations**, with actual native
Canvas output and PNGs from PDF.js/Skia, Poppler 26.05.0 and Ghostscript
10.05.1. Ghostscript uses 4-bit text and graphics antialiasing. No mismatch
is hidden by skipping a page or enlarging a tolerance.

RGB MAE versus Ghostscript at 1×, rotation 0:

| Page | Case | Before TK replay | After TK replay |
| --- | --- | ---: | ---: |
| 1 | Default TK true; identical overlapping glyphs | 2.464566 | 0.057465 |
| 2 | Explicit TK false | 0.073385 | 0.073385 |
| 3 | Separate BT/ET objects | 0.092891 | 0.092891 |
| 4 | Same Form invoked twice | 2.393776 | 0.142821 |
| 5 | Inherited alpha and Multiply, persistent after ET | 2.277474 | 0.764514 |
| 6 | Inherited soft mask applied once | 0.039505 | 1.835538 |

Interior values give stronger evidence than a whole-page aggregate:

- Page 1: Canvas and Ghostscript both produce `(229,153,140)`, the later
  half-opacity red glyph composited with the original white backdrop.
  Poppler/PDF.js instead composite the two glyphs to approximately
  `(172,102,127)` even with TK true.
- Pages 2/3: the glyphs should composite; Canvas produces `(172,102,127)`.
- Page 4: each Form's internal text knocks out, then the two distinct Form
  invocations composite. Canvas `(216,102,83)` is within one channel level
  of Ghostscript `(217,101,82)`.
- Page 5: the glyph region is `(69,92,127)` versus Ghostscript
  `(68,92,125)`. Much of the page-wide error is the already-known RGB
  rounding of the large background, `(77,153,230)` versus `(76,153,229)`.
  The post-ET rectangle retains the same alpha and Multiply state.

### Explicit masked-text oracle disagreement

Page 6 is deliberately retained despite disagreement with all three
references. With AIS false, alpha `.5` and alpha soft mask `.5`, each glyph
has opacity `.25` and retains its full geometric shape. Whole-text-object
knockout therefore replaces the earlier glyph under the later glyph, and
Canvas produces `(242,204,198)`: the later red glyph at quarter opacity.
There is no duplicate mask application on the implicit group's final
composite.

Ghostscript, Poppler and PDF.js instead composite the masked glyphs,
producing approximately `(199,166,188)`. §9.3.8 provides no soft-mask
exception, and the group rules require glyph-local transparency parameters
with a final unit mask. The native implementation retains the normative
result; this reference mismatch is **not** represented as a pixel pass.
The unmasked TK true/false results independently distinguish knockout from
ordinary alpha accumulation.

The legacy SVG fragments still lack whole-BT/ET knockout compositing.
This retention plus native Canvas implementation does not claim that SVG
fragment serialization is a complete transparency backend. The separately
documented affine host-font/no-outline limitation is unchanged.

## Reproduction

```sh
moon run tools/text_knockout.mbtx
moon build --target js --release cmd/pixel_plan
cp _build/js/release/build/cmd/pixel_plan/pixel_plan.js _build/pixel-plan.mjs
PDF_CANVAS_PACKAGE=/absolute/path/to/node/package.json \
PDF_STROKE_GHOSTSCRIPT=1 \
PDF_PIXEL_OUTPUT=_build/text-knockout-validation \
  node tools/pixels/compare_text_strokes.mjs \
  _build/pixel-plan.mjs _build/text-knockout/text-knockout.pdf
```

`PDF_CANVAS_RENDERER` optionally selects a candidate compositor module.
Source retention passed `moon info`, `moon fmt`, `moon check --target all`,
all full target test suites and `git diff --check`; final counts are
JS **324/324**, Wasm **325/325**, Wasm-GC **325/325**, native **328/328**.

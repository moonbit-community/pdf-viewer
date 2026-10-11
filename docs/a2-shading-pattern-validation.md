# A2 shading-pattern transparency validation (2026-10-10)

## Retained state and replay

PatternType 2 now retains relevant `/ExtGState` transparency state, including
`/ca`, `/BM`, `/AIS`, overprint and a structured `/SMask`. Direct and indirect
ExtGState dictionaries are resolved on the **Pattern dictionary**, not the
Shading dictionary or the ExtGState resource-name map. Path-only entries such
as `/LW` do not change the outer painted path. Rendering intent and BG/UCR
continue through the shared shading colour evaluator.

The initial state comes from the resource-defining content-stream entry,
with transparency reset. Background retains its initial overprint state,
separately from the inner ExtGState; the reader also corrects pdflite 0.2.2's
`/op` versus `/OPM` lookup. `shading_pattern.mbt` lowers one implicit
nonisolated knockout scene at the enclosing page's dimensions. An optional
Background path precedes the `sh` item; the inner ExtGState applies to `sh`.
The existing Canvas compositor's `env.paintScene` replays that scene against
the live backdrop. Outer paint alpha, blend mode and clipping apply once.
The mask matrix includes the complete pattern transform. Pattern strokes
reuse the existing affine stroke mask. No second compositor is introduced.

This follows ISO 32000-1 sections 8.7.4 and 11.6.7: transparency defaults are
reset inside patterns, the shading pattern's ExtGState augments parameters
relevant to `sh`, and Background is painted before the shading in its implicit
knockout group. The result then supplies the colour, shape and opacity of the
outer paint. See the [official Adobe-hosted standard](https://opensource.adobe.com/dc-acrobat-sdk-docs/standards/pdfstandards/pdf/PDF32000_2008.pdf).

Scene and mask replay use the existing depth/surface budgets. The shading
adapter checks its pixel budget before creating any stroke surface. Invalid
SMask forms remain explicit unsupported-shading errors. Canvas-only lowering
omits redundant tiling-cell SVG and legacy shading mesh/stops when their
structured representation is present. The large sampled resource occurs only
on the inner `sh`; public resource geometry and SVG serialization are preserved.
Calibrated blend targets also invoke the actual source-to-target callback;
CalGray output is a one-component target.

## Complete-PDF evidence

`tools/pixels/shading_pattern_acceptance.mjs` generates nine original PDFs
with valid xref tables and nine equivalent control PDFs. Each original passes
through the MoonBit parser, retained Canvas plan and actual Canvas renderer.
Every RGB channel and alpha of all 90,000 pixels is checked against independent
blend equations, with maximum error at most 1 byte in this run (asserted limit
1.51 bytes). Source files, SHA-256 hashes, plans and PNGs are reproducible.

The control replaces each shading pattern with an ordinary transparency Form,
`/Group << /S /Transparency /I false /K true >>`, paints Background first, then
executes `/Inner gs /S sh`, preserving independent outer state. This isolates
the reader's Pattern dictionary handling from the actual transparency rules.

| Case | Max analytical byte error | Expanded Ghostscript mean | Expanded Poppler mean |
| --- | ---: | ---: | ---: |
| Inner Multiply, inner/outer alpha 0.5 | 0.60 | 0.3333 | 1.0000 |
| Indirect Pattern ExtGState | 0.60 | 0.3333 | 1.0000 |
| Inner Multiply, outer Screen | 0.88 | 0.6667 | 0.6667 |
| Default inner opacity reset | 0.00 | 0.0000 | 0.3333 |
| Knockout Background before sh | 1.00 | 0.9367 | 9.6000 |
| Pattern luminosity mask | 0.95 | 0.5000 | 0.6667 |
| Pattern matrix transforms mask | 0.95 | 0.1250 | 0.1767 |
| Background, mask and BBox | 1.00 | 0.5660 | 3.6440 |
| Pattern stroke with inner alpha | 0.60 | 0.0267 | 0.0800 |

These are not blanket reader-equivalence passes. Original Pattern PDFs differ
substantially from PDF.js 6.4.299, Poppler 26.05.0 and Ghostscript 10.05.1.
For the simple Multiply case, all three produce the result obtained by ignoring
the pattern's inner ExtGState. The
[pinned PDF.js reader](https://github.com/mozilla/pdf.js/blob/89b500f5e1d98ed89bb90211e45b28730b2d99ac/src/core/evaluator.js#L1645-L1659)
explicitly reads only Shading and Matrix in this branch. Direct and indirect
dictionaries behave alike. The ordinary `gs` plus `sh` controls recover the
expected effect, including the luminosity mask. Original discrepancies remain
in the report; the harness does not assert that they match.

The expanded controls still have residuals. Ghostscript's two Background
cases differ above 8 bytes only in the column x=24 immediately before the
shading's x=25 boundary: 100 pixels (maximum 69) and 60 pixels (maximum 81),
respectively. Poppler has broader knockout/Background differences: 5,100 and
3,120 pixels above 8, maxima 39 and 50. These maxima, counts, bounds and exact
means are retained in `tools/pixels/reports/shading-pattern.json`, together
with every original/control hash and reference version. The analytical test
does not exclude boundary pixels. Ghostscript control mean is additionally
bounded by 1.1 bytes; a missing optional external renderer is explicitly
recorded as unavailable, never reported as a pass.

## Validation and reproduction

- Full MoonBit JS suite: 403/403.
- Shading-pattern and existing pattern replay: 14/14 on native, wasm and
  wasm-gc; the same tests are included in the full JS suite.
- Node shading/Canvas/compositor/group-colour/ink suites: 49/49, including
  45 focused shading tests.
- `moon info`, `moon fmt`, `moon check --target all`, `git diff --check`.

```sh
moon build --target js cmd/pixel_plan
cp _build/js/debug/build/cmd/pixel_plan/pixel_plan.js _build/pixel-plan.mjs
PDF_CANVAS_PACKAGE=/path/to/package.json \
  node tools/pixels/shading_pattern_acceptance.mjs _build/pixel-plan.mjs
```

The package location supplies `@napi-rs/canvas` and pinned `pdfjs-dist`.
`pdftoppm` and `gs` supply optional diagnostic/control renders. Generated
artifacts default to `_build/shading-pattern-acceptance`.

SVG remains the documented approximate renderer; this change does not give
SVG the implicit scene's backdrop, knockout or structured-mask semantics.

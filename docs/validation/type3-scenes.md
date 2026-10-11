# Retained Type 3 paint scenes

Date: 2026-10-10. The Canvas producer reuses the existing A1 cached font,
Encoding/CharProcs selection and glyph transform, then runs the ordinary
content collector and graphics lowerer. No new font decoder is introduced.
`PdfTextItem.type3_scene` retains an enclosing-page-coordinate scene;
`type3_scene_unresolved` makes recursion/lowering failures explicit.
The Canvas plan exposes the scene as `type3_plan`, not a second SVG paint.

The CharProc inherits the caller's full graphics state. Internal alpha,
blend-mode and mask changes replace inherited state. Replay extracts the
scene source against the live backdrop, applying outer alpha/Normal/no-mask
only once. Invoking clips and enclosing group/TK identity remain intact.
Colored d0 paints retain their individual source colors and ICC catalog;
d1 preserves separate inherited fill/stroke colors even through Forms.
An absent Resources entry inherits the invoking resources. An explicit
empty dictionary does not. Recursive painted CharProcs are bounded at depth
8 and report `PDF_TYPE3_SCENE`; selection/source items remain available.

ISO 32000-1 section 9.3.6 says Tr=3 makes Type3 invisible. Other Tr modes
neither restroke the CharProc nor supply text clipping. The scene producer
implements that rule. The legacy SVG representation remains an explicit
`PDF_SVG_TYPE3_SCENE` compatibility approximation. Selection bounds are
not treated as conservative paint bounds: d0 can paint outside them, so
Canvas scene replay must retain the full-page fallback until actual paint
bounds are available.

## Reproduction

Use the configured MoonBit toolchain and installed Node pixel packages:

```sh
moon run tools/type3_scenes.mbtx
moon build cmd/pixel_plan --release --target js
cp _build/js/release/build/cmd/pixel_plan/pixel_plan.js _build/type3-scenes/bridge.mjs
PDF_CANVAS_PACKAGE=/path/to/pixel-packages/package.json \
  node tools/pixels/compare_type3_scenes.mjs \
  _build/type3-scenes/bridge.mjs _build/type3-scenes/type3-scenes.pdf
```

The generated PDF is original test content; its RGB profile is the existing
original `assets/icc/rgb-gamma22.icc`. Fourteen pages cover two internal colors,
CMYK/ICC groups, inherited/internal alpha and blend modes, inherited/internal
soft masks, d1, Tr1/3, affine reflection/shear, and equivalent ordinary-path
controls. PDF.js 6.4.299, Poppler and Ghostscript render actual reference PNGs.
The harness records every residual without expanding acceptance thresholds.

All 112 combinations (14 pages, scales 1/2, four rotations) completed. The
Type3 ICC and enclosing-CMYK cases are byte-identical to their equivalent
ordinary path controls at all eight viewports. The internal-CMYK Form case
has only a one-channel-level rounding difference from its ordinary Form
control (scale-1 MAE 0.0625). Process-color display conversion differences
are shared by the controls and are not a Type3 geometry fix.
At scale1/rotation0, cases 1,3,5,6,7,8,10 match PDF.js exactly. In the inherited
alpha case, Canvas red is (230,138,138), Poppler (229,137,137), while PDF.js
resets the inherited d0 alpha and yields (230,0,0). Ghostscript agrees with
inherited-state semantics. The implementation retains the normative result.

## Real fixtures and remaining differences

Read-only fixtures come from pdf.js commit
`89b500f5e1d98ed89bb90211e45b28730b2d99ac`, via `git show`:

- `simpletype3font.pdf`: Canvas/PDF.js MAE 0; Poppler 0.009872;
  Ghostscript 0.003738 at scale1/rotation0.
- `Type3WordSpacing.pdf`: separate red stroke/blue fill and positions retained.
  Canvas/PDF.js MAE 1.849861; Poppler 2.844528; Ghostscript 3.023861. PDF.js
  differs in subpixel stroke coverage; Poppler paints the d1 strokes blue,
  whereas PDF.js uses the separate inherited red stroke. Missing space
  CharProcs are also reported by reference engines. These are measured
  residuals, not a claim of exact reference parity.
- `ContentStreamNoCycleType3insideType3.pdf`: nested Type3 paints are retained,
  but its inner ordinary Helvetica glyphs require text pattern resources.
  This separate A2 handoff is explicitly diagnosed until retained resources
  are connected; the file is not counted as passing pixels.
- `ContentStreamCycleType3insideType3.pdf`: resource graphs are cyclic but
  the selected paints terminate. The authored self-invoking CharProc test,
  rather than this filename, verifies recursion handling.

Eight dedicated producer tests pass. Full suites: JS 409, Wasm 410,
Wasm-GC 410, native 417; `moon check --target all`, `moon info`, `moon fmt`
and `git diff --check` pass. Browser execution remains blocked by the
container's socket permission, as recorded in the text-stroke validation;
these are actual Node Canvas2D renders, not claimed Chromium runs.

# Native text fills and pattern handoff

Date: 2026-10-10. `text_paint.mbt` consumes the existing A1 CFF, Type1 and
TrueType geometry API once, retaining its page-SVG path as `fill_path` while
calling the same existing SVG paint helper. Glyph mapping, font selection,
advances, source text and selection remain A1's. The independent affine
stroke descriptor is unchanged. Type3 retains its own paint scene.

`PdfTextItem.pattern` and `stroke_pattern` use the existing pattern resource
builder with the content stream's initial pattern state, just like ordinary
paths. Both tiling and shading patterns retain their nested scenes, source
colors, target profiles and transparency. Canvas removes duplicate legacy
SVG/model resources from its paint object. Resolved fills need no SVG image.
Unresolved modes 2/6 receive separate `text_fill_svg`/`text_stroke_svg` produced
by the existing A1 serializer with modes 0/1, so unlike pattern paints and
fill/stroke knockout do not depend on parsing glyph semantics from SVG.

Legacy SVG still reports `PDF_SVG_TEXT_PATTERN`. An unavailable resource
reports `PDF_TEXT_PATTERN_RESOURCE`; unsupported affine host-font strokes
retain the existing explicit geometry diagnostic. Browser execution is not
claimed: the actual pixel host is native Canvas2D with the supplied adapter.

## Reproduction

```sh
moon run tools/text_paints.mbtx
moon build cmd/pixel_plan --release --target js
cp _build/js/release/build/cmd/pixel_plan/pixel_plan.js _build/text-paints/bridge.mjs
PDF_CANVAS_PACKAGE=/path/to/pixel-packages/package.json \
  PDF_PIXEL_OUTPUT=_build/text-paints/pixels \
  node tools/pixels/compare_type3_scenes.mjs \
  _build/text-paints/bridge.mjs _build/text-paints/text-paints.pdf
moon build cmd/browser --release --target js
cp _build/js/release/build/cmd/browser/browser.js _build/text-paints/browser.mjs
PDF_CANVAS_PACKAGE=/path/to/pixel-packages/package.json \
  node tools/pixels/profile_text_replay.mjs \
  _build/text-paints/browser.mjs /path/to/issue13931.pdf _build/text-paints/performance.json
```

The twelve-page original fixture covers embedded/native fill, stroke and
independent patterns, shading, uncolored tiling, alpha, affine reflection,
host-font fallback, and text clipping. It uses the same original two-glyph
TrueType asset as `text_strokes.mbtx`. The existing actual-PNG harness also
records the intentionally approximate SVG alongside PDF.js, Poppler and
Ghostscript; it never treats a successful export as pixel acceptance.

## Measured coverage

All 96 viewports (12 pages, scales 1/2, four rotations) completed. Embedded
native tiling fill/stroke, independent patterns, shading fill/stroke and
text clipping have PDF.js mean absolute RGB error below 0.056 at every
viewport. Scale 1 values are respectively 0.00950,0.02423, 0.02959, 0.02887,
0.03609 and 0.00994. Uncolored tiling is 0.39630. The transparent fill/stroke
case differs from PDF.js by 3.96243 and Ghostscript by 1.88039; affine dashed
patterns differ by 2.43385/4.74860. The full reported residuals are retained,
including larger Poppler pattern-placement differences. No tolerances were
expanded to hide them.

Standard 14 fallback uses A1 host substitution; its three scale 1 PDF.js
residuals are 2.90614, 7.47524 and 5.89979. The harness supplies PDF.js's bundled
standard fonts to avoid a missing-font reference. These host-outline and
raster differences remain visible rather than being described as exact.

The pinned real `ContentStreamNoCycleType3insideType3.pdf` retains all
six inner text patterns and six split fill/stroke pairs across five Type3
scenes, with no producer diagnostics. Initial replay hit the existing
pattern-cell budget, then native allocations; backend exact alpha-mask ROI
and bounded shared glyph caching resolved both without increasing limits.
The final actual PNG comparison completes under a 1,536 MiB JS heap cap:
PDF.js MAE 0.879373, Poppler 0.981475, Ghostscript 0.636775. The legacy SVG
PDF.js residual is 2.820769. Host-font and fine-pattern raster differences
remain measured; this is not a claim of exact cross-engine parity.

With fresh release browser bridges and the same latest Canvas adapter,
`issue13931.pdf` retains 512 visible text entries and byte-identical selection
and complete legacy SVG hashes. Native fill replay removes all 1,024 SVG
image loads. A sequential repeat measured bridge 7.806→7.822s (effectively
unchanged), Canvas 0.698→0.398s, peak RSS 682,564→554,060 KiB, and after-bridge
RSS 536,973,312→419,659,776 bytes. After-Canvas RSS varied between 505–565 MB
for native paths versus 699–700 MB for the latest fallback adapter across
two runs. The old 2.4 GB measurement also included the independently fixed
excessive SVG padding; it must not all be attributed to native paths.
The profiling tool records bridge hashes, both stages, memory,
source/SVG/pixel hashes and diagnostics for reproducible further checks.

Five dedicated producer tests pass. Full final suites: JS 441, Wasm 442,
Wasm-GC 442, native 449. `moon info`, `moon fmt`, `moon check --target all`,
JavaScript syntax checks and `git diff --check` pass.

A subsequent actual PDF.js render confirms `issue13931.pdf` native Canvas
MAE 0.0110535, maximum channel error 7, and zero pixels above 8. Its old
SVG-fragment Canvas result had MAE 1.2626277, maximum 152 and 15,402 pixels
above 8 against that same reference. Poppler/native MAE is 1.2379568 and
Ghostscript/native 2.4148892. The legacy SVG has a separately reported
595-pixel raster width versus the 596-pixel ceil viewport; the harness does
not rescale it or conceal that dimension mismatch. Fractional reference
pages are placed at their pixel origin on white paper, avoiding an accidental
half-pixel centering shift when one reference rounds its page width.

## Nested ICC catalogs

Type3 and soft-mask producers register profiles in the enclosing resource
context; the final page owns that complete catalog. Tiling pattern pages
already inherit the same scope. Canvas serialization now omits only
byte-identical catalog entries inherited by embedded Type3, mask and tiling
scenes. Standalone scene serialization keeps its catalog; a same-ID profile
with different bytes is not silently discarded. Shading-pattern masks pass
through the same catalog context. Tests cover two repeated mask/pattern
scenes, retained ICC group IDs, one profile payload, and standalone output.

The actual Altona page originally repeated a 7.3 MB ICC catalog in each of
43 Type3 scenes: 313,609,936 bytes in `type3_plan` values. The fresh native
producer with inherited catalogs emits a 21,272,700-byte complete plan;
those 43 Type3 scenes total only 98,216 bytes, while the root keeps all seven
profile registrations. No CharProc paints or profile references are omitted.

After the catalog changes, full suites pass JS 443, Wasm 444, Wasm-GC 444,
native 451, with all-target check and generated interfaces unchanged.
A fresh before/after catalog comparison on all fourteen authored Type3
pages is byte-identical at scale 1, including the ICC/group and mask cases.

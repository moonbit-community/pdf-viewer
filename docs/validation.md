# Validation baseline

The annotation baseline uses the local pdf.js checkout at revision
`89b500f5e1d98ed89bb90211e45b28730b2d99ac`, pdflite `0.2.2`, and the native SVG
CLI. It does not measure parity with pdf.js rendering.

The suite currently contains 75 tests on each of wasm, wasm-gc, JavaScript, and
native. It includes 13 annotation tests, 17 CFF tests, 4 text-geometry tests,
and 8 text-clipping tests. These results cover the MoonBit package and CLI;
they do not establish complete pdf.js compatibility.

## Reproduce

```bash
moon check --target all
moon test --target all
moon run tools/corpus.mbtx
moon run tools/corpus.mbtx reference/pdf.js/test/pdfs annotation
moon run tools/corpus.mbtx reference/pdf.js/test/pdfs cff
moon run tools/corpus.mbtx reference/pdf.js/test/pdfs text_clip
```

The corpus runner creates a new `_build/corpus-*/` directory every time. Each
entry in `report.json` includes the source filename, page number, status,
process exit code, diagnostic output, generated SVG path, and explicit
placeholder count. The runner also exercises the CLI's success, usage, invalid
PDF, missing file, invalid/nonpositive/out-of-range page, and output-write
failure paths. A failure or timeout makes the runner exit nonzero after saving
the full report.

## Annotation first-page run (2026-10-09)

- Files attempted: **31** (`annotation*.pdf`).
- First-page SVG created: **31**.
- Failed or timed out: **0**.
- Explicit placeholder markers in the produced SVGs: **0**.

The four files that previously failed page-tree parsing now render after the
viewer-side compressed-object/page-tree recovery was added:
`annotation-caret-ink.pdf`, `annotation-link-text-popup.pdf`,
`annotation-polyline-polygon.pdf`, and `annotation-square-circle.pdf`.

No placeholder only means the renderer did not emit an explicit missing-image
or missing-shading marker. It does **not** detect discarded unsupported
operators, incomplete fonts, approximate widgets, or incorrect appearance
geometry. Only page 1 is tested for these files.

## CFF outlines and text clipping

`cff_outline_wbtest.mbt` has 17 focused tests for raw CFF/OpenType CFF parsing,
Name-keyed and CID-keyed glyph mapping, Type 2 charstrings, and SVG outlines.
The corpus runner produced first-page SVGs with no explicit placeholders for
`cff_bluescale_small_zones.pdf`, `cid_cff.pdf`, `issue_cff_unsigned_bbox.pdf`,
and `text_clip_cff_cid.pdf`.

`text_clipping_wbtest.mbt` uses valid synthetic PDFs with embedded CFF and TrueType
outlines to check that one text object yields one clip path, later text objects
intersect it, modes 4–7 are honored, the clip activates after `ET`, `q/Q`
restores it, Forms inherit it without leaking local clips, Type 3 text does not
contribute to it, and captured glyph transforms survive later CTM changes.
It also distinguishes a valid empty outline (an empty clip) from an unavailable
outline (no fabricated clip), and verifies same-named CFF fonts resolve to
different programs inside page and Form resource scopes.

The `text_clip_cff_cid.pdf` SVG was opened in headless Chromium and visually
compared with Poppler's 72 dpi render. The blue clipped text matched in this
spot check. This is a manual browser comparison, not an automated pixel diff
or a pdf.js fidelity score.

## Focused annotation regressions

`annotations_wbtest.mbt` builds small PDFs with valid xref tables and runs the
public byte-reader/page/SVG path. It checks:

- RGB/gray/CMYK component handling and explicit transparent colors (CMYK still
  uses the renderer's approximate device conversion, not ICC color management);
- independent display and print decisions, raw annotation indices, popup
  parents, malformed siblings, and multiple markup quads;
- nonuniform fitting after rotation/shear, missing and degenerate BBoxes,
  clipping, appearance-state selection, and intentionally empty streams;
- distinct clip IDs across page content and multiple appearances;
- independent fonts in page, appearances, and nested Forms, plus embedded
  program transfer and CSS family isolation;
- outer appearance transparency-group metadata;
- PDFDocEncoding/UTF-16 text, radio-group selection, and checkbox `/AS` priority.

These assertions cover structure and resource selection. They do not establish
font rasterization, complete transparency compositing, full form layout, or
pixel equivalence to pdf.js. The standalone browser viewer and automated
pdf.js pixel comparisons remain future work.

## Text geometry and browser spot checks

`text_geometry_wbtest.mbt` verifies composed text transforms (CTM, shear,
horizontal scale and rise), a clipped FreeText baseline, vertical CID origin
and progression, and a minimal TrueType glyph at normal and rotated scales.
Glyph contour size must be independent of advance widths and font-wide BBox.

Two SVGs, `annotation-highlight.pdf` and `annotation-freetext.pdf`, were opened
in headless Chromium and inspected against Poppler `pdftoppm` PNGs at 72 dpi.
This exposed squeezed TrueType glyphs and a FreeText baseline falling below
its clip. After the transform fixes, text was legible, the blue FreeText
appeared, and placement was visually close in these two samples. This was a
manual spot check against Poppler, **not** an automated pixel comparison or a
pdf.js fidelity score.

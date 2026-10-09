# Validation baseline

The annotation baseline uses the local pdf.js checkout at revision
`89b500f5e1d98ed89bb90211e45b28730b2d99ac`, pdflite `0.2.2`, and the native SVG
CLI. It does not measure parity with pdf.js rendering.

The suite currently contains 112 tests on each of wasm, wasm-gc, JavaScript, and
native. It includes 13 annotation tests, 17 CFF tests, 23 Type 1 tests, 5 CID
layout tests, 9 variable-length CMap tests, 4 text-geometry tests, and 8
text-clipping tests. These results cover the MoonBit package and CLI; they do
not establish complete pdf.js compatibility.

## Reproduce

```bash
moon check --target all
moon test --target all
moon run tools/corpus.mbtx
moon run tools/corpus.mbtx reference/pdf.js/test/pdfs annotation
moon run tools/corpus.mbtx reference/pdf.js/test/pdfs cff
moon run tools/corpus.mbtx reference/pdf.js/test/pdfs text_clip
moon run tools/corpus.mbtx reference/pdf.js/test/pdfs issue15292
moon run tools/corpus.mbtx reference/pdf.js/test/pdfs issue18117
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

## Type 1 outlines

`type1_font_wbtest.mbt` covers eexec encryption, ASCII-hex eexec, direct-index
subroutines, `seac`, flex othersubrs, truncated PFB trailers, CID-keyed Binary/Hex
`StartData`, CIDMap/SubrMap offsets, page drawing, and text clipping. The parser
uses the embedded font's FontMatrix and keeps parsed outlines cached by font
object and glyph name. Additional cases cover signed-Int offset overflow,
huge counts, truncated tables, decimal-only StartData lengths, oversized and
incomplete hex data, binary whitespace preservation, no-op invalid subrs, and
rejection of multiple private dictionaries even when all FD indices are zero.
CID clipping tests distinguish visible notdef fallback from a valid empty
outline. `issue14462_reduced.pdf` produced
11 Type 1 outline paths on its first page; `tracemonkey.pdf` produced 812 on its
first page; `issue18548_reduced.pdf` produced 4 procedure-form Type 1 outline
paths. These pages were rendered as SVG and visually compared with Poppler at
72 dpi. The unit tests cover the single-FD CID-keyed parser; multiple FDArray
entries and complex predefined CMap recovery are still unsupported.

## External CMap widths and real CID Type 1 sample

`cid_layout_wbtest.mbt` uses a PDF with deliberately different character-code
and CID width entries. It verifies CID-indexed `/W`, `/DW` and notdef widths,
consecutive `Tj`/`TJ`, numeric `TJ` adjustments, quote operators, character
spacing, scale/shear/CTM, clipping positions, ToUnicode text, and preservation
of the original font's width table. The horizontal external-CMap path now
decodes variable-length strings, as described below.

The pdf.js fixture `issue15292.pdf` was downloaded from the URL in its `.link`
file. Its first-page SVG contains 1,041 Type 1 outline paths and no explicit
placeholders. A Chromium screenshot exposed overlapping text before the width
correction: character codes were used to look up CID-indexed widths. After the
correction the body and footer are legible, and their placement was visually
compared with Poppler at 72 dpi. Artifacts are in
`_build/corpus-1791554426187/`, with the prior output in
`_build/corpus-1791553607280/`. This is a manual spot check, not an automated
pixel diff or a pdf.js fidelity score.

The earlier CLI smoke run also passed for `cid*.pdf` (2/2), `cff*.pdf` (1/1),
and `tracemonkey*.pdf` (6/6). Together with `issue15292.pdf`, all 10 first pages
produced SVGs without explicit placeholders. This checks conversion only.

## Variable-length horizontal external CMaps

`cmap_text_wbtest.mbt` adds 9 tests through the decoder and public byte-reader/
page path. They cover mixed 1–4 byte codespaces, unsigned high-bit codes,
shortest-match segmentation, leading zeroes, local versus inherited Identity
codespaces, CID widths and outlines, multi-codepoint ToUnicode mappings,
consecutive operators, numeric TJ adjustments, quote line/spacing state,
source-length-sensitive Tw, invalid/truncated input, selection, and clipping.
All 112 tests pass on wasm, wasm-gc, JavaScript, and native.

The real PDF.js fixture `issue18117.pdf` contains an embedded SourceHanSansTC
TrueType font with a UTF-8 CMap, one-byte Latin text, a three-byte punctuation
code, and four-byte supplementary CJK codes. Its first-page SVG contains 86
TrueType outline paths and no explicit placeholders. The SVG was opened in
Chromium and visually compared with Poppler at 72 dpi; both lines, their spaces,
and the supplementary glyphs are visible with comparable placement. Artifacts
are in `_build/corpus-1791556855003/`, including `report.json`,
`issue18117-browser.png`, and `issue18117-poppler.png`. Poppler reports warnings
for this fixture's ToUnicode bfchar entries, so its extracted Unicode text is
not used as the oracle. This is a manual visual spot check, not an automated
PDF.js pixel comparison.

The regression conversion run also passed for `issue15292.pdf` (1/1),
`cid*.pdf` (2/2), and `cff*.pdf` (1/1). Those runs check first-page conversion,
not full-document visual conformance. A new Chromium screenshot of
`issue15292.pdf` was also inspected against the previous corrected screenshot;
its body and footer placement remain unchanged. The new artifacts are in
`_build/corpus-1791556939882/`.

Limits: the new path applies to horizontal external CMaps whose codespaces
survive pdflite's reader. Some four-byte ranges crossing the signed Int boundary
can be dropped by pdflite `0.2.2`, such as `<00000000> <FFFFFFFF>`; recovering
them, built-in CMaps, complex UseCMap inheritance, and vertical layout remain
TODO. Source bytes are retained during layout but are not exposed as stable
public byte-span metadata. Word spacing is corrected in this path; the other
font paths have not yet been fully aligned.

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

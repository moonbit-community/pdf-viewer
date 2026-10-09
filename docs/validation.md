# Validation baseline

The annotation baseline uses the local pdf.js checkout at revision
`89b500f5e1d98ed89bb90211e45b28730b2d99ac`, pdflite `0.2.2`, and the native SVG
CLI. That conversion baseline does not measure parity with pdf.js rendering.
The automated selected-page visual baseline below now measures actual output
against the same pinned PDF.js build.

The suite currently contains 149 tests on each of wasm, wasm-gc, JavaScript, and
native. It includes 13 annotation tests, 17 CFF tests, 23 Type 1 tests, 5 CID
layout tests, 9 variable-length CMap tests, 4 text-geometry tests, and 8
text-clipping tests plus one mixed-paint scaling regression. The latest addition has 8 predefined-CMap tests, 8 vertical
CID tests, 4 word-spacing tests and 1 missing-descriptor recovery test. The
browser/text-layer stage adds 4 geometry/range tests, 1 public-API test and
3 checked documentation examples, plus a separate Chromium interaction suite.
Seven additional pixel-classifier tests cover blank/identical images,
missing paint, small and large shifts, color differences, alpha compositing,
unequal viewport dimensions and allocation bounds. These results cover the
MoonBit packages and CLI; they do not establish complete pdf.js compatibility.

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
moon run tools/corpus.mbtx reference/pdf.js/test/pdfs vertical 1,2,3
moon run tools/corpus.mbtx reference/pdf.js/test/pdfs 90ms_rksj
```

For the independent browser, run `moon run tools/dev.mbtx 4312`, then in a
second terminal:

```bash
moon run tools/browser_test.mbtx http://127.0.0.1:4312 /path/to/chromium
```

`tools/build_web.mbtx` builds the MoonBit JS bridge and stages the static
`web/` deployment. No PDF.js renderer is loaded by the viewer.

The corpus runner creates a new `_build/corpus-*/` directory every time. Each
entry in `report.json` includes the source filename, page number, status,
process exit code, diagnostic output, generated SVG path, and explicit
placeholder count. A comma-separated final argument selects multiple pages;
page 1 remains the default. The runner also exercises the CLI's success, usage, invalid
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
entries remain unsupported. Predefined CMaps are now supported as described
below; complex external-stream CMap inheritance remains pending.

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
At that stage, all 112 tests passed on wasm, wasm-gc, JavaScript, and native.

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

Limits of that stage: the path applied to horizontal external CMaps whose codespaces
survive pdflite's reader. Some four-byte ranges crossing the signed Int boundary
can be dropped by pdflite `0.2.2`, such as `<00000000> <FFFFFFFF>`; recovering
them and complex external UseCMap inheritance still remain TODO. Predefined
CMaps, vertical layout and the other font paths' word spacing are now covered
by the following stage. Source bytes are retained during layout but are not
exposed as stable public byte-span metadata.

## Adobe predefined CMaps, vertical layout and word spacing

All **133/133 tests** pass on wasm, wasm-gc, JavaScript and native.
`builtin_cmap_wbtest.mbt` checks all 168 pinned binary assets decode, verifies
the PDF.js ETenms-B5 unit-fixture CID values and Japanese mappings, and checks
CID-to-Unicode collection data. It also covers truncated binary input, local
mapping priority, inherited codespaces/WMode, local WMode override and the
public page path joining named CMaps to CID widths and TrueType outlines.
The embedded assets contain mapping data, not font programs; Adobe's license
is retained in `assets/cmaps/LICENSE`, and regeneration checks the pinned
reference revision. Filtered CIDToGIDMap streams now decode before GID lookup.

`cid_vertical_wbtest.mbt` has 8 tests for CID-indexed W2, DW2 defaults and
origins, signed progression, source-length-sensitive Tw, Tc, numeric TJ,
consecutive operators, quote line matrices, q/Q, clipping, selection,
shear/scale/rise and negative font sizes. All CID paths now compute geometry
directly; the previous viewer-side quad-direction repair was removed.
`word_spacing_wbtest.mbt` has 4 additional tests for standard, simple and Type 3
fonts, and named UTF8/UTF16/UTF32 CMaps. A two- or four-byte encoding of code
32 does not receive Tw; changing a glyph's ToUnicode text does not change its
source-code word-spacing decision.

Real fixture runs on 2026-10-09:

- `vertical.pdf`: **3/3 pages** converted, no explicit placeholders; artifacts
  in `_build/corpus-1791560890434/`. Chromium and Poppler were compared at
  144 dpi for all three pages. The two Japanese columns on page 1 have
  comparable placement. Pages 2 and 3 are blank in both renderers, so they
  provide a blank-page regression rather than additional vertical-text cases.
- `90ms_rksj_h_sample.pdf`: **1/1 page** converted, no explicit placeholders;
  artifacts in `_build/corpus-1791560558842/`. The SVG contains
  `日本語テスト` at the CID-derived advances. Chromium and Poppler were
  visually compared at 144 dpi; both ASCII and Japanese lines are visible
  with comparable placement. The non-embedded CIDFont omits FontDescriptor:
  `font_recovery_wbtest.mbt` verifies recovery of text and widths without
  mutating the source object. Default metrics remain an explicit approximation,
  and the SVG's fallback font appearance depends on the host environment.
- First-page conversion regressions passed for `issue18117.pdf` (1/1,
  `_build/corpus-1791560967470/`), `issue15292.pdf` (1/1,
  `_build/corpus-1791560982581/`), `cid*.pdf` (2/2,
  `_build/corpus-1791560983718/`), `cff*.pdf` (1/1,
  `_build/corpus-1791560984996/`) and `text_clip_cff_cid.pdf` (1/1,
  `_build/corpus-1791560985460/`). No explicit placeholders were emitted.

These are structural regressions, conversion checks and manual Poppler spot
checks. They are **not an automated PDF.js pixel comparison or a visual
compatibility percentage**. Remaining CMap limits include reader-lost
unsigned four-byte ranges and local codespace priority in complex stream
UseCMap inheritance. General missing-ToUnicode/font recovery and diagnostics,
standard/system fonts and stable public source-byte spans remain pending.

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
pixel equivalence to pdf.js. The independent browser is now covered by the
following section; selected-page automated PDF.js comparisons are recorded
in the visual baseline below.

## Standalone browser and native cursor selection

On 2026-10-10, all **141/141** MoonBit tests passed on wasm, wasm-gc,
JavaScript and native. `text_layer_wbtest.mbt` verifies the layer matrix maps
all four corners onto the public viewport for every quarter rotation and
multiple scales, including nonzero page origins and affine shear. Cursor
tests verify sparse source item indices, partial ligatures, reversed ranges,
UTF-16 surrogate boundaries, rotated baselines and vertical columns.
`text_layer_test.mbt` exercises the public decoded-page/text-layer/range/SVG
surface; three checked API examples compile and run as documentation tests.

The Chromium DevTools suite passed **19 interaction checks** using
`90ms_rksj_h_sample.pdf`, `vertical.pdf` (3 pages), and `tracemonkey.pdf`
(14 pages). It verifies:

- actual mouse drag on ordinary, rotated/scaled and vertical CJK text;
- Shift plus arrow and keyboard initiation of cursor selection;
- DOM selection mapped to source item indices, quads and available file path;
- copied text, cross-page ranges and document-only select-all on all 14 pages;
- selection restoration and highlighter reprojection after zoom/rotation;
- actual browser file input, invalid-file reporting, retention of the prior
  preview and reopening after an error;
- absence of uncaught browser runtime exceptions during these checks.

Screenshots and the per-check report are saved in a fresh
`_build/browser-test-*/` directory. The initial complete 19-check run is in
`_build/browser-test-1791563539676/`; the final formatted rerun, including
all 19 check names and the passed count in `report.json`, is in
`_build/browser-test-1791563834238/`. The mouse-selection screenshot was
inspected: the Japanese line stays legible and the native highlight follows
its glyphs. The rotated screenshot places the selection on the rotated text;
the browser scrolls it into view instead of leaving it outside the viewport.
The 14-page screenshot confirms visible body text and selected glyphs.

Real dragging exposed a failure that programmatic Range tests had missed:
1px DOM fonts scaled up by CSS did not extend the mouse selection. The browser
now uses a normal font size, fits each text advance inside its source glyph
rectangle and applies a normalized affine basis. A repeated full-document
mount also exposed synchronous layout caused by computed-style reads mixed
with per-glyph writes; it now reuses inline styles and cached measurements.

Limits: these are Chromium interaction checks and structural geometry
assertions, **not automated PDF.js pixel parity** or an all-browser fidelity
score. The browser eagerly mounts all pages, so Worker scheduling,
virtualization, cancellation, memory limits and performance budgets remain
pending. The body layer uses source paint order plus a writing-direction
separator heuristic; general reading order/bidi and raw PDF byte spans are
not completed. Annotation appearances and readonly widgets still need their
own DOM interaction layer. Search, thumbnails and printing remain TODO.

## Automated PDF.js visual baseline

`moon run tools/visual_test.mbtx` builds the MoonBit bridge and the native
MoonBit pixel comparer, then measures every page/rotation in
`tools/visual_cases.json`. It needs Chromium and the generic build of the
pinned reference (`npx gulp generic` inside `reference/pdf.js`). The viewer
itself still loads no PDF.js code. This runner starts its own temporary
loopback HTTP server and isolated Chromium profile; it does not replace the
viewer on port 4312.

```bash
moon run tools/visual_test.mbtx tools/visual_cases.json /path/to/chromium
moon run tools/visual_summary.mbtx _build/visual-test-<run>/report.json
moon run tools/visual_contract_test.mbtx /path/to/chromium
```

The 2026-10-10 baseline in `_build/visual-test-1791566623303/` measured
**14/14 page/rotation combinations from 9 PDFs**, with **0 measurement
failures and 0 uncaught runtime exceptions**. PDF.js version `6.5.0`, build
`89b500f`, rendered in the same Chromium profile as MoonBit, at scale 2 and
deviceScaleFactor 1, on white. All 14 viewport dimension/matrix comparisons
matched within 1e-6; 11 text comparisons matched after removing whitespace.
**11 combinations had pixel or text differences; 3 were within the recorded
tolerance.** This is a selected corpus, not a visual compatibility percentage.

| Sample | Selected pages/rotations | Pixels above per-channel tolerance 8 | Main finding |
| --- | --- | ---: | --- |
| `90ms_rksj_h_sample.pdf` | page 1, 0/90° | 0 / 0 | Visible ASCII/Japanese control matches in this environment |
| `vertical.pdf` | pages 1/2/3, 0° | 2,569 / 1,497 / 1,497 | Page edges differ; pages 2/3 have no body text, not entirely blank pixels |
| `issue18117.pdf` | page 1, 0° | 11,268 | Text agrees; glyph/raster differences remain |
| `issue14462_reduced.pdf` | page 1, 0° | 1,578 | Type 1 glyph/raster differences remain |
| `issue18548_reduced.pdf` | page 1, 0° | 0 | CID Type 1 result is within tolerance; minor exact pixel differences remain |
| `text_clip_cff_cid.pdf` | page 1, 0° | 346 | Zoom clipping is corrected; residual pixel differences remain |
| `annotation-highlight.pdf` | page 1, 0° | 2,308 | Appearance differences remain |
| `annotation-freetext.pdf` | page 1, 0° | 585 | Appearance differences remain |
| `tracemonkey.pdf` | pages 1/7/14, 0° | 246,338 / 276,148 / 136,162 | Nimbus/Computer Modern fallback family improved; glyphs and normalized extracted text still differ |

The initial run `_build/visual-test-1791564786890/` exposed a concrete scale
bug: clip definitions used unscaled coordinates while text, paths, images
and shadings painted at the output scale. All clip-definition sites now
receive that scale, including each part of an intersected clip. The real
`text_clip_cff_cid.pdf` at scale 2 improves from **71,920 to 346** pixels
above tolerance, with mean absolute RGB error decreasing from **25.448 to
0.0147**. Its blue `ABC123` is fully visible in the inspected corrected
image. The mixed-paint MoonBit regression exercises explicit and text-clip
intersections on text/path/image/shading at scales 0.5/1/2 and all quarter
rotations. These improvements do not remove the remaining geometry/font
gaps in G-02/F-06.

The later baseline `_build/visual-test-1791566623303/` also includes the
Nimbus/Computer Modern family fallback correction. Tracemonkey's raw changed
pixels fell by 35,429 / 33,621 / 15,552 on pages 1/7/14 respectively. The
remaining Type 1 failures are per-glyph parser coverage and font metrics work,
not an excuse to mark F-06 or F-07 complete.

Each run retains PDF.js/MoonBit PNGs, raw RGBA, a heatmap, the original
run/glyph text geometry, viewport diagnostics, fixture SHA-256, browser build,
host font list, renderer options, warnings and viewer revision/worktree state.
`index.html` links the side-by-side images and `report.json`. Yellow heatmap
pixels have symmetrically matching colors within a 1px neighborhood; red
pixels do not. Yellow is a diagnostic candidate, **not proof of antialiasing**:
a shifted thin line can also be yellow. Raw differences, missing/extra ink,
error metrics and exclusive difference bounds remain in the report. Pages
are never resized to hide geometry mismatches.

The seven `tools/pixels` tests pass on all four backends. The independent
runner contract checks in `_build/visual-contract-1791565301945/` verify a
visible, nonblank control is accepted in strict mode, a deliberate 3px shift
is rejected after saving its report, and a missing fixture counts as one
failed selected page. The diagnostic shift is recorded explicitly and is
absent from the default manifest. These checks are separate from the 19
standalone viewer interaction checks.

After the zoom-clip correction, all **149/149** tests passed on wasm,
wasm-gc, JavaScript and native, and the standalone Chromium suite again
passed all **19** interactions. The latter report and screenshots are in
`_build/browser-test-1791565835505/`.

Normal mode exits successfully when measurement completes, including reported
differences. Appending `--strict` rejects pixel differences above tolerance,
viewport mismatches and text mismatches after removing whitespace. Input,
rendering and capture failures always fail the run and are counted in the
report. No missing file is counted as a matching blank page.

Limits: this baseline samples pages 1/7/14 of `tracemonkey.pdf`, not its entire
14-page document. It has not yet measured every decoder, color, pattern,
transparency, optional-content, form or XFA case in TODO. Text comparison
retains paint order and removes whitespace only; it does not normalize bidi
or ligatures. Automatic geometry comparison currently covers viewport
dimensions/matrices; per-run/glyph data is saved for further diagnosis,
without claiming a completed run-to-glyph correspondence. Raster captures
and their comparison union are bounded to 16M pixels / 8192px per side.

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

# Validation baseline

The annotation baseline uses the local pdf.js checkout at revision
`89b500f5e1d98ed89bb90211e45b28730b2d99ac`, pdflite `0.2.2`, and the native SVG
CLI. That conversion baseline does not measure parity with pdf.js rendering.
The automated selected-page visual baseline below now measures actual output
against the same pinned PDF.js build.

The suite currently contains 259 tests on each of wasm, wasm-gc, JavaScript, and
native. It includes 13 annotation tests, 17 CFF tests, 25 Type 1 tests, 5 CID
layout tests, 9 variable-length CMap tests, 4 text-geometry tests, and 8
text-clipping tests, one mixed-paint scaling regression, and one tiling-pattern
transform-scaling regression. Earlier stages added 8 predefined-CMap tests,
8 vertical-CID tests, 4 word-spacing tests, 1 missing-descriptor recovery
test, and 11 viewer-side external-CMap/ToUnicode recovery tests. The
browser/text-layer stage adds 4
geometry/range tests, 1 public-API test and 3 checked documentation examples,
plus a separate Chromium interaction suite. The search stage adds source-range
and diacritic-folding regressions plus browser toolbar checks.
Seven additional pixel-classifier tests cover blank/identical images,
missing paint, small and large shifts, color differences, alpha compositing,
unequal viewport dimensions and allocation bounds. These results cover the
MoonBit packages and CLI; they do not establish complete pdf.js compatibility.

The colour stage adds 11 colour-space/state tests, 8 original-image-sample
tests, 3 additional pattern regressions, 1 public independent fill/stroke
pattern test and 1 stream-comment reader recovery test. `moon test --target
all --diagnostic-limit 1` passed **209/209 on each backend**, and `moon check
--target all` passed. That earlier standalone Chromium run passed all **33**
interactions, with report/screenshots in `_build/browser-test-1791598489760/`.
The expanded selected-page baseline in `_build/visual-test-1791598324155/`
measured **57/57 combinations from 20 PDFs**, **0 failures**, and **55 with
pixel or text differences**. Its calibrated-colour interior samples below
are an additional diagnostic, not an exemption from full-page differences.

## A1 fonts, Unicode and reading order

The first batch adds 29 regressions: 7 Unicode-search, 6 mixed-direction/column,
7 TrueType-mapping/compound, 7 source/diagnostic and 2 CMap destination tests.
`moon test --target all --diagnostic-limit 1` passed **250/250 on
each backend**. `moon info && moon fmt` and the four-target check passed.
The 24 pre-existing deprecation warnings remain. Public interface changes are
additive: three text sidecar types and page/document inspection methods;
existing public records and source display-list indices are unchanged.

Pinned `bidi`, `normalization` and `ucd` 0.5.2 supply UAX #9,
Unicode 16 NFKD, lowercase and general-category data. Search preserves source
UTF-16 intervals through canonical mark ordering, compatibility expansions,
independent combining accents, supplementary scalars and case-sensitive
matching. Latin-specific ß/æ/œ policy remains explicit; this is not complete
locale-sensitive Unicode case folding.

Horizontal reading blocks separate persistent gutters, including a body below
a spanning heading and RTL columns. Bidi code-point permutations are collapsed
to complete glyph items and checked against visual geometry. Source order is
preferred when its forward projection agrees; ambiguous or split-glyph
permutations retain content order. Numeric runs, multi-scalar ToUnicode,
ligatures and surrogate selections share source identity across copy, search
and the DOM text layer. Complex tables, rotations, explicit bidi controls and
inferred spaces across directional run boundaries still need work.

TrueType selection now uses Encoding/Differences independently from ToUnicode;
symbol fonts also probe the F000/F100/F200 windows. PDF advances and text matrices
remain unchanged. Compound contours preserve shear, align unsigned parent/child
point numbers, transform scaled offsets and validate glyph-local records,
instructions, recursion and point count. These fixtures follow the
[OpenType composite-glyph description](https://learn.microsoft.com/en-us/typography/opentype/spec/glyf#composite-glyph-description).
The follow-up now uses the standalone `mizchi/font` cmap reader for formats
0/4/6/12; the whole-font parser and outline replacement remain separate work.

`text_sources()` exposes glyph-owned half-open ranges in the logical
`text_content().text`, font names and charcodes. Inferred separators have no
fake glyph owner. It does not claim raw PDF byte spans or complete CID/GID
provenance. Page diagnostics report observable replacement text, host fallback,
missing resources/outlines and missing clipping outlines; document diagnostics
also expose malformed/incomplete CMaps, cycles and unavailable source streams,
with resource path and immediate object number. Resource-level observations do
not prove that each associated glyph is damaged. Inspection is opt-in and can
rebuild a page; browser font-loading results and the bridge/UI are not included.
The recovery tokenizer now distinguishes 1–4-byte source codes from Unicode
byte-string destinations, permitting longer, whitespace-separated and empty
hex destinations. This avoids reporting valid multi-scalar ToUnicode values
as malformed and retains lazy range increments; oversized source codes remain
excluded.

### Standalone cmap integration

`mizchi/font` 0.7.4 is pinned in the root dependencies and used only for the
validated standalone cmap path. PDF selection prefers Windows Unicode/Symbol,
then MacRoman, with full-repertoire Unicode records for supplementary scalars;
directory order no longer merges conflicting records. MacRoman reverse lookup
reuses pdflite. Selected missing glyphs remain GID 0 instead of borrowing the
raw character code. Absent/unusable cmap tables retain the recovery branch.

Before calling the library, the adapter checks declared table/record lengths,
format 4 array/range offsets, format 12 group ordering, Unicode/GID bounds and
expansion limits. It corrects signed remainders to 16-bit glyph IDs and checks
maxp. A shared cache retains cmap bytes only, with limits of 8 entries, 1 MiB
input and 262,144 decoded mappings; each format 12 table can expand at most
131,072 codepoints. Other cmap formats, post-table glyph-name recovery and
broader damaged-font/host-loading behavior remain open.

Nine additional tests cover supplementary glyph painting and clipping with
independent ToUnicode, Unicode-platform format 12, conflicting/duplicate
platform records, Symbol high-byte lookup, MacRoman glyph-name conversion,
format 6 intervals, format 4 notdef holes/signed deltas, invalid GIDs,
truncation, oversized/wrapped ranges and cache isolation/eviction. The final
four-backend suite passed **259/259 on each backend**; `moon info && moon fmt`
and `moon check --target all` passed. The public `.mbti` interface is unchanged
by this follow-up. Probe output now records original cmap platform/encoding/
format triples, and font inventory includes subtype and PDF encoding.

The MacRoman adapter walks pdflite's existing encoding/forward extraction
instead of calling the generic CID-capable reverse lookup, which otherwise
links unrelated reverse CMap tables. Against the `100fc23` browser build,
the final generated JS grows from 12,227,920 to 12,248,518 bytes; `gzip -c`
grows from 2,782,919 to 2,785,682 bytes (**2,763 bytes**). This checks artifact
size, not page-load performance; no shared build/visual runner was changed.

### Font candidate probe

These commands extract original program bytes and call the candidate's public
GID/metrics interface; the fixture container itself is built with the candidate's
public sfnt writer. No font files are vendored.

```bash
moon run tools/font_inventory.mbtx reference/pdf.js/test/pdfs/issue14462_reduced.pdf _build/a1-font-issue14462
moon run tools/font_library_probe.mbtx _build/a1-font-issue14462/0.bin
moon run tools/font_inventory.mbtx reference/pdf.js/test/pdfs/ArabicCIDTrueType.pdf _build/a1-font-arabic
moon run tools/font_library_probe.mbtx _build/a1-font-arabic/0.bin
moon run tools/font_inventory.mbtx reference/pdf.js/test/pdfs/TrueType_without_cmap.pdf _build/a1-font-no-cmap
moon run tools/font_library_probe.mbtx _build/a1-font-no-cmap/0.bin
moon run tools/font_library_probe.mbtx --synthetic _build/a1-font-fixture.ttf
moon run tools/font_inventory.mbtx reference/pdf.js/test/pdfs/issue4800.pdf _build/a1-font-issue4800
moon run tools/font_library_probe.mbtx _build/a1-font-issue4800/0.bin
moon run tools/font_inventory.mbtx reference/pdf.js/test/pdfs/mixedfonts.pdf _build/a1-font-mixedfonts
moon run tools/font_library_probe.mbtx _build/a1-font-mixedfonts/3.bin
```

`mizchi/font` 0.7.4 returns None for all three selected programs:
`issue14462_reduced.pdf` embeds a PFB Type 1 program, while the other two
TrueType programs omit cmap. This does not measure all fonts in those files or
establish that the library rejects ordinary complete fonts. The authored sfnt
parses all 6 GIDs and returns advance 600 for each; the candidate's compound
bounds disagree with the expected raw-point transforms:

| Authored GID | Expected bounds | Candidate bounds |
| --- | --- | --- |
| 3: shear | [0, 0, 200, 200] | [0, 0, 100, 200] |
| 4: point attachment | [0, 0, 300, 400] | [0, 0, 200, 200] |
| 5: scaled offset | [50, 100, 100, 200] | [100, 200, 150, 300] |

Reports are in `_build/a1-font-library-*.json`. The candidate probe ran on
native; it is not a four-backend adoption test or a malformed-font fuzz result.
Current TrueType/CFF/Type 1 recovery remains in use while upstream extension is
evaluated. The new viewer tests exercise the same authored bytes/GIDs, plus
Encoding/ToUnicode disagreement, Differences, symbol mapping, truncation,
invalid point references and cyclic components.

### Real PDF comparison

The four-file `tools/text_cases.json` selection uses the pinned PDF.js
revision above, Chromium, white background and scale 2. The final A1 report
is `_build/visual-test-1791627482580/`; the isolated `7ab1cec` comparison
is `_build/a1-baseline/_build/visual-test-1791626838381/`. Both measured
**4/4 with 0 failures and 4 differences**. Matching SHA-256 values of each
before/after viewer screenshot confirm identical selected-page paint; this is
a comparison against the prior implementation, not pixel parity with PDF.js.

| Page 1 sample | Pixels above channel tolerance 8, before → after | Raw text outcome |
| --- | ---: | --- |
| issue14462_reduced.pdf | 1,389 → 1,389 | Equal to reference |
| tracemonkey.pdf | 199,680 → 199,680 | Columns no longer interleave; still differs |
| ArabicCIDTrueType.pdf | 11,566 → 11,566 | Still differs; no claim of Arabic parity |
| TrueType_without_cmap.pdf | 508 → 508 | Equal to reference |

`tracemonkey.pdf` now extracts the Abstract/Introduction left column before
the right column, instead of joining alternating columns into shared lines.
Its nonspace count is still 4,281 versus reference 4,295; the runner compares
raw sequences without ligature/Unicode normalization. First nonspace mismatch
moves from UTF-16 position 565 to 607, which alone is not a compatibility score.
Paragraph separators, ligatures and font/raster differences remain.

The cmap follow-up uses `tools/font_cmap_cases.json` at the same pinned
reference. The eight-file report `_build/visual-test-1791639147626/` and
isolated `100fc23` baseline
`_build/a1-cmap-baseline/_build/visual-test-1791639224260/` both measured
**8/8, 0 failures, 8 differences, 0 placeholders**. The additional simple-font
sample `issue4800.pdf` was measured separately in
`_build/visual-test-1791639404722/` versus
`_build/a1-cmap-baseline/_build/visual-test-1791639404712/`: **1/1, 0 failures**.
All nine before/after viewer screenshots have matching SHA-256 values.

```bash
moon run tools/visual_test.mbtx tools/font_cmap_cases.json /path/to/chromium
```

| Additional page 1 sample | Pixels above tolerance 8, before → after | Font coverage |
| --- | ---: | --- |
| complex_ttf_font.pdf | 72,427 → 72,427 | Two TrueType subsets without cmap retain recovery |
| Embedded_font.pdf | 16,368 → 16,368 | OpenType-CFF CID path remains usable |
| mixedfonts.pdf | 37,176 → 37,176 | Real DejaVuSans contains cmap 0/3/4, 0/4/12, 1/0/6, 3/1/4, 3/10/12 |
| pattern_text_embedded_font.pdf | 207,762 → 207,762 | Existing CFF/pattern path retains its differences |
| issue4800.pdf | 1,378 → 1,378 | Simple TrueType WinAnsi font uses Unicode 0/1 format 4 |

Triples above mean platform/encoding/format. `mixedfonts.pdf` binds DejaVuSans
as a CID font, so its unchanged rendering does not prove the simple-font cmap
selection path. `issue4800.pdf` exercises that path with a real program;
supplementary rendering and conflicting-platform behavior are covered by
authored fixtures. Raw text still differs for the same selected files; these
measurements do not establish PDF.js pixel parity or a performance score.


### Browser checks

The unchanged official `tools/browser_test.mbtx` run aborts at the
Shift+ArrowLeft assertion on this macOS Chrome host. The `7ab1cec` baseline
reproduces the same failure. A temporary diagnostic copy in
`_build/a1-browser-probe.mbtx` runs the same 33 assertions, records failures
instead of aborting at the first one, and still exits nonzero.

The current report `_build/browser-test-1791627557254/report.json` and
baseline report `_build/browser-test-1791627447829/report.json` both record
**31 passed, 2 failed**: Shift+ArrowLeft selection and mouse dragging on rotated,
scaled glyphs. Search, source ranges, copy, programmatic rotation/zoom
restoration, vertical text, multipage selection and file-reopen checks passed.
These two failures remain open browser/host work; this batch does not claim a
passing complete browser suite, and the official runner was not relaxed.

## Parallel-work baseline

The earlier eight-workstream split assigned each of the 33 remaining TODO IDs
exactly once; the 17 completed IDs were unchanged. It has been superseded by
the two core workstreams in [PARALLEL.md](PARALLEL.md).
Two agents audited the font/text and render/host boundaries read-only. No
feature implementation was delegated as part of this documentation split.
The unfinished JPEG parser is retained as `docs/drafts/jpeg-parser.mbt.txt`,
outside the compiled source set, and is not a completed decoder.

After parking that draft, `moon info`, `moon fmt`, `moon check --target all`
and `git diff --check` passed. Sequential tests on wasm, wasm-gc, JavaScript
and native each passed **221/221**, with 24 existing deprecation warnings.
This is a fresh build/test baseline for collaboration, not a new visual run;
the image and browser reports below retain their original dates and coverage.

The split moved font resources, Type 3 glyphs, SVG text output and text
selection unchanged into four dedicated files in the root package. No features
or dependencies were added, and the generated public interfaces are unchanged.
`moon info && moon fmt`, `moon test`, `moon check --target all` and
`git diff --check` passed. The existing deprecation warnings remain. This file
organization change has no new visual comparison run and does not change TODO
completion counts.

## Image interpolation, raw alpha masks and malformed simple-font recovery

`image_sampling.mbt` preserves `/Interpolate` and inline `/I`, uses the
affine transform's singular values with PDF.js-compatible Float32 rounding,
and selects image smoothing from the actual paint scale. Axis-aligned image
edges are rounded independently with a minimum one-pixel extent. Pattern
cells retain structured image parts so sampling is decided at page paint
scale rather than only at cell-local scale. Rotation and shear keep their
affine transforms.

`image_alpha.mbt` reads raw 1/2/4/8/16-bit SMask and explicit ImageMask samples,
including row padding, `/Decode` and malformed-size fallback to the parent.
SMask takes precedence over `/Mask`; only an ImageMask stream acts as an
explicit opacity mask. Image and mask are resized to their maximum dimensions
using floor nearest-neighbor indexing. Raw `/Matte` is converted in the parent
image colour space, then removed using clamped ties-to-even byte rounding;
fully transparent pixels become white. The result is one RGBA PNG, avoiding
a second alpha application through SVG.

Simple fonts with missing/invalid `/Widths`, `/FirstChar` or `/LastChar` can
now recover through a viewer-local shadow dictionary. Valid widths are
retained; `/MissingWidth` or Standard 14 AFM metrics fill missing entries.
The source dictionary is unchanged. `issue17147.pdf` consequently renders
instead of failing with `FontWidthsExpected`.

```bash
moon test image_alpha_wbtest.mbt
moon test image_sampling_wbtest.mbt
moon test font_recovery_wbtest.mbt
moon run tools/visual_test.mbtx tools/image_cases.json
```

The focused run `_build/visual-test-1791601213389/` measured **10/10 selected
page/rotation combinations**, **0 failures**, **7 with pixel or text
differences**, and **3 within recorded tolerance**. The image-alpha,
image-sampling and font-recovery suites passed 6/6, 4/4 and 3/3 respectively;
the complete suite passed **217/217 on each of the four backends**.

| Sample | Rotation | Pixels above per-channel tolerance 8 | Finding |
| --- | --- | ---: | --- |
| `issue10339_reduced.pdf` | 0/90° | 0 / 0 | Lab raw image conversion and enlarged sampling agree with PDF.js |
| `issue4246.pdf` | 0° | 0 | Higher-resolution raw alpha mask agrees with PDF.js |
| `colorkeymask.pdf` | 0/90/180/270° | about 3,220 / 3,499 / 2,969 / 2,690 | Integer edge placement improves the earlier 4,288-pixel result; mask/edge differences remain |
| `smaskdim.pdf` | 0° | about 5,130 | Includes annotation border/appearance differences; cannot attribute all errors to image masking |
| `issue17147.pdf` | 0° | about 1,001 | Malformed simple-font width recovery makes the page measurable; residual output differs |
| `issue13931.pdf` | 0° | about 38,378 | Encoded JPEG + SMask + Matte remains incorrect |

This run supplements the earlier 57-combination baseline below. It does not
replace its historical measurements or establish general visual compatibility.
Encoded JPEG/JPX/JBIG2 sample decoding, encoded-image masks/Matte, colour-key
edges, complete compositing and large-image scheduling keep I-04 open.

## Calibrated colours and original image samples

`colour.mbt` uses the declared PDF colour space for paths, text, images,
gradient/mesh colours, pattern bases and Form-mask path paints. The conversion
is adapted from the pinned PDF.js `colorspace.js`, with source/copyright
attribution. It includes PDF.js' SWOP CMYK polynomial, CalGray's tone curve,
CalRGB gamma/matrix/white-point/black-point handling and Lab's D50/D65 output
curve. The PDF CalRGB Matrix is read in primary XYZ columns, and Lab Range is
`[amin amax bmin bmax]`. Indexed lookup bytes expand into their base space's
ranges. Tint functions are parsed once before repeated image or mesh samples.
ICCBased still uses its alternate; no ICC profile/LUT engine is implemented.
Overprint and encoded JPEG/JPX/JBIG2 colour management remain open.

The viewer content adapter resolves named `CS/cs` in the current resource
scope and initializes PDF default samples, including K=1 for DeviceCMYK and
all tints=1 for Separation/DeviceN. Tests exercise path/text/shading colours,
q/Q restoration, resource shadowing in Forms, CalGray pattern bases and
calibrated fill/stroke in a Luminosity Form mask. Pattern cells and masks use
the viewer collector, so they also receive these state corrections. The
public `PdfPathItem.stroke_pattern` is separate from fill `pattern`, and the
black-box fixture paints a red tiling fill and blue tiling stroke together,
then a plain green fill without inheriting the active stroke pattern. Complex
pattern text, shading-pattern strokes and complete mask/compositor semantics
are still H/M work.

`image_colour.mbt` lets pdflite decode supported filters/predictors, then reads
original 1/2/4/8/16-bit samples with byte-aligned rows and big-endian 16-bit
components. `/Decode` maps samples into the declared colour-space ranges.
Colour-key `/Mask` compares the original integer components before either
mapping or conversion. The image tests inspect PNG IDAT pixels after the
PDF reader and filter path, including reverse Decode, CMYK, packed row
padding, 16-bit RGB, Indexed CalGray and spot-colour tint. Matte, interpolation,
encoded-image sample-space masks and large-image scheduling remain I-04.

The real CalGray/CalRGB fixtures initially rendered blank because pdflite
0.2.2 discards a stream with a legal comment between `endstream` and `endobj`.
The viewer recovery layer now skips that trivia, respects `/Length` and the
active xref chain, and does not recover raw encrypted content on this path.
The regression embeds the text `endstream endobj` inside the actual stream,
so scanning for those words cannot incorrectly terminate it. Dependencies
were not modified.

Reproduce the focused colour run and flat-colour diagnostic:

```bash
moon run tools/visual_test.mbtx tools/colour_cases.json
moon run tools/colour_samples.mbtx _build/visual-test-<run>
```

`tools/colour_cases.json` selects 26 pages from 7 PDFs, all of which are also
in the default manifest. `tools/colour_samples.mbtx` uses fixed coordinates
for the pinned fixtures at scale 2. Each swatch contributes a flat 16×16
interior, away from its labels and boundaries; dimensions and flatness are
recorded. In `_build/visual-test-1791598324155/colour-samples.json`, **1,432
swatches / 366,592 sampled RGB pixels** match PDF.js exactly, with zero
nonflat samples: 60 CalGray swatches, 1,360 CalRGB swatches and 12 Lab swatches.
This verifies the calibrated conversion path, not complete pages or all colour
spaces. It supports completion of C-02 within the pinned PDF.js behavior:
that reference ignores nondefault CalGray BlackPoint, Lab BlackPoint and
canvas rendering intent (`/ri`); the viewer also ignores them.

| Sample | Pages | Full-page pixels above tolerance 8 | Finding |
| --- | --- | ---: | --- |
| `calgray.pdf` | 1–3 | 20,886 / 22,805 / 20,736 | Swatch interiors exact; label/raster/text-order differences remain |
| `calrgb.pdf` | 1–17 | 79,358–85,961 per page | All 1,360 sampled swatches exact across white/black points, gamma and matrix variations; pages still differ |
| `issue10339_reduced.pdf` | 1 | 6,543 | Indexed Lab image interiors exact; upscaled boundaries are visibly smoothed instead of following `/Interpolate` |
| `devicen.pdf` | 1 | 946 | Tint conversion reaches the real fixture; alternate colour/raster differences remain |
| `devicen-none-zero-domain.pdf` | 1 | 25,600 | Visible differences in DeviceN/alternate colours; special-domain/colorant coverage and ICC conversion remain open |
| `colorkeymask.pdf` | 1 | 4,288 | Original-sample mask path is used; final resampling/mask output still differs |
| `function_based_shading_cmyk.pdf` | 1–2 | 149,598 / 8,639,970 | Function-based shading still has 3 / 6 placeholders; H-03 remains open |

Before stream recovery, the 3-page diagnostic
`_build/visual-test-1791597057764/` had **3,044,020** changed pixels for
CalGray page 1 and **3,175,619** for CalRGB page 1, with **viewer_ink=0**.
The corrected outputs are nonblank. That before/after measures recovery and
conversion together; it is not evidence for the colour conversion in isolation.
The swatch diagnostic above supplies the separate colour evidence.

## Text reading order and separators

`text_order_wbtest.mbt` exercises the page-level logical text index with a
synthetic PDF whose second line is emitted before the first in the content
stream. Public text content is ordered top-to-bottom, while the original paint
display list and each glyph's stable item index remain unchanged. A second
fixture places two glyphs on one baseline with a large geometric gap; copy,
search text and the DOM text layer all expose one synthesized word space.

The index detects strong Hebrew/Arabic ranges and orders a horizontal RTL line
from its right edge. This is a deterministic first step toward PDF.js' `bidi`
text chunks; it does not yet implement the full Unicode Bidirectional
Algorithm, mixed-direction run reordering, table/column inference, or
ligature/combining-character boundary metadata. The current suite reports
**209/209** on all four backends after the subsequent colour regressions.

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

## Page boundaries and UserUnit

The page-model regressions cover a non-zero MediaBox origin, a CropBox that
extends beyond it, disjoint and degenerate CropBox fallback, invalid UserUnit,
viewport offset inversion, and SVG dimensions after applying
`scale * user_unit`. The real PDF.js fixture `issue19176.pdf` declares an
8.5 by 11 page with `/UserUnit 72`; the native SVG has a 612 by 792 viewBox.
The selected PDF.js visual run `_build/visual-test-1791590079766/` measured
that page at scale 2 with matching 1224 by 1584 viewport dimensions, affine
matrix, text comparison, and **0 changed pixels**. This validates the page
unit and device-pixel sizing path; it does not claim that every malformed page
tree is recovered identically.

The same MoonBit tests generate encrypted fixtures for 40-bit ARC4, 128-bit
ARC4, and AESV2. Missing and wrong passwords fail with the stable viewer
authentication error, user and owner passwords both open the 128-bit fixture,
and successful reads expose the expected page text. Browser bridge and static
build checks pass; the prompt/retry loop is kept browser-only, and a dedicated
Chromium dialog test for an encrypted file remains a small follow-up.

## Destinations and document navigation

`pdf-viewer_test.mbt` builds a two-page navigation fixture containing a legacy
catalog `/Dests` entry, a `/Names` `/Dests` name-tree entry, an explicit page
destination and a remote destination. The regression checks local page-object
resolution, `XYZ` parameters, one-based page numbers, name lookup with and
without a leading slash, JSON serialization, outline navigation output and the
remote-page boundary. The destination model also covers the `Fit` family in the
viewer implementation (`Fit`, `FitH`, `FitV`, `FitR`, `FitB`, `FitBH`, `FitBV`).

This validates the reader/viewer API boundary. The standalone browser now
consumes local outline destinations in its directory panel and leaves remote
targets disabled; annotation links remain a separate A-04 layer. A remote
destination is reported with `remote: true` and is never used as a local scroll
target.

## Optional-content visibility

`pdf-viewer_test.mbt` builds a real `/OCProperties` document with an OCG listed
in `/OFF`, adds a `/Properties` alias and wraps the page content in `BDC /OC`.
The default viewer produces an empty page display list and no extracted text or
selection. `with_optional_content_state(pdf_optional_content_state(on=[object]))`
selects the same object number and restores the text, operator list and cursor
selection. The fixture is serialized and read again, so the check covers the
pdflite reader/writer boundary rather than only an in-memory state.

The content walk also covers common OCMD `/P` policies and nested `/VE`
`And`/`Or`/`Not` expressions, and a Form XObject's `/OC` is evaluated before
recursing into its operators. Usage dictionaries, radio-button groups, locked
layer controls and a browser layer panel are not claimed by this test.

## Inline image decode path

`pdf-viewer_wbtest.mbt` now exercises inline images through the page-model path:
each fixture is written into a PDF, read back, collected into a display list and
converted to the browser-facing image resource. The regression set contains
CCITT Group 4 with `K=-1`, CCITT Group 3 one-dimensional data with `K=0`, a
one-bit raw image with `/Decode [1 0]`, a serialized `ImageMask`, and a Flate
image whose `DecodeParms` uses PNG Predictor 12. The test reads the generated
PNG with pdflite, inflates its IDAT payload and checks dimensions, row lengths
and representative RGB/mask samples. This catches a missing filter parameter
even when a data URI is still produced.

The viewer keeps the `DecodeParms` value that pdflite attaches to
`Op_InlineImage` and adds it to the transient image stream before calling
the image adapter. That is the boundary needed for CCITT `/Columns`, `/Rows`
and `/K`; the viewer does not duplicate the CCITT or predictor decoder. The
four-backend suite at that stage was **182/182** on wasm, wasm-gc, JavaScript and native.
I-01/I-02 still cover JPX/JBIG2; the new original-sample path above expands
I-04's color-key coverage, while Matte, interpolation and encoded images remain open.

## Uncolored tiling pattern base colour

`pattern_wbtest.mbt` builds real PDF byte streams and checks that a
`PaintType 2` path tile inherits the invocation colour for both fill and
stroke. Synthetic cases cover DeviceGray, DeviceRGB and DeviceCMYK operands;
a `PaintType 1` case confirms that its cell colour remains independent of the
invocation colour. A scale-2 regression also checks that output scale is not
applied both by the page paint and again by the pattern transform. This checks
colour propagation and transform handling through the reader, content state
and SVG pattern resource, not only the final string helper.

The PDF.js fixture `tiling_patterns_variations.pdf` contains an uncolored P5
pattern with two path fills. The viewer's generated cell uses `#CC3333`, the
RGB base colour selected at the paint site. A scale-2 comparison exposed that
the page paint and `patternTransform` both applied output scale; the pattern
transform now retains PDF-to-page coordinates and lets the paint apply output
scale once. The P5 300-by-300 pixel region at `(840, 900)` changed from 61,094
to 4,176 pixels above tolerance 8 (the ROI includes the rectangle border).
In `_build/visual-test-1791590079766/`, all 31 selected pages/rotations measured
successfully; the full page has **27,076 pixels above tolerance 8**, down from
169,803. The remaining differences include pattern matrix, clipping and edge
cases; H-01 remains open until those are isolated and validated against PDF.js.

Recheck the P5 region by setting `run_dir` to a visual-run directory:

```bash
run_dir=_build/visual-test-1791590079766
sample=tiling_patterns_variations.pdf.page-1.rotation-0
moon run tools/pattern_roi.mbtx "$run_dir/$sample.reference.rgba" "$run_dir/$sample.viewer.rgba" 840 900 300 300 1200
```

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
72 dpi. The unit tests cover the single-FD CID-keyed parser; residual Type 1
operands at `endchar` and `setcurrentpoint` recovery now match the pinned
PDF.js behavior. Multiple FDArray entries remain unsupported. Predefined CMaps are now supported as described
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

Limits of that stage: the normal parsed-CMap path still depends on codespaces
surviving pdflite's reader, and source bytes are not always available to the
viewer recovery path. Predefined CMaps, vertical layout and the other font
paths' word spacing are now covered by the following stage. Source bytes are
retained during layout but are not exposed as stable public byte-span metadata.

## External CMap reader-loss recovery

`cmap_recovery.mbt` parses decoded external CMap streams independently when
pdflite has rejected part of the signed integer range. It keeps codespaces and
CID ranges as unsigned values, stores broad ranges without expanding them,
recursively composes indirect `/UseCMap` streams, and applies local mappings
before inherited mappings. `notdef` entries and WMode are recovered as well.
The recovered mapping is used by CID text segmentation, CID-indexed widths,
vertical layout, Adobe CID-to-Unicode lookup, and Type 1/CFF/TrueType outline
selection. For text extraction, a reader mapping wins; a matching mapping
recovered from the source ToUnicode stream is next; missing codes then use the
Adobe CID collection mapping before the reader's final fallback. Odd-length
UTF-16BE destinations are padded to match PDF.js decoding behavior.

`cmap_text_wbtest.mbt` covers a legal
`<F0000000> <FFFFFFFF>` codespace with a lazy four-byte `cidrange`, and a
public page path whose high-bit code is otherwise lost by the reader. Additional
tests cover high-range ToUnicode `bfchar`/`bfrange` and array mappings, lazy
lookup, reader-map precedence over collection fallback, partial ToUnicode
fallback, odd-byte destinations, and a synthetic PDF whose indirect child and
parent CMap streams disagree on a mapping. A further synthetic PDF resolves
named `/Adobe-Japan1-UCS2 usecmap` ToUnicode inheritance after the reader map is
removed. With the reader tables removed, the viewer resolves the parent
codespace and mapping, then correctly applies the child CID and ToUnicode
entries. The
selected corpus smoke run
`_build/corpus-1791571276960/report.json` converts pages 1, 7 and 14 of
`tracemonkey.pdf` with **3/3 rendered**, **0 failures**, and **0 placeholders**.
The real `cidfont_cmap_overflow.pdf` also converted with **1/1 rendered** and
**0 placeholders**. In `_build/visual-test-1791583678868/report.json`, its
viewport and text match PDF.js, while **4,620 pixels differ** and all fall
outside the diagnostic one-pixel neighborhood. This is an explicit unresolved
visual case, not a completed rendering claim. Real corpus fixtures for indirect
`UseCMap` inheritance, named ToUnicode inheritance, source streams unavailable
to the viewer and malformed-CMap diagnostics remain open. Named Unicode
fallback is currently demonstrated with a synthetic PDF only; it has no
real-corpus coverage yet.

The current recovery parser also has deterministic diagnostics for malformed
hex tokens, unclosed `codespacerange`/mapping sections, unavailable source
streams and indirect `UseCMap` cycles. When the source bytes cannot be decoded,
the recovery result is marked unavailable and the viewer keeps pdflite's reader
mapping instead of treating an empty local table as authoritative. Three new
white-box tests exercise these states. They make the fallback behavior explicit,
but the diagnostics are still internal and the real-corpus cases above remain
open.

### Corpus scan

`tools/cmap_corpus.mbtx` scans the local PDF.js test corpus through the same
pdflite reader boundary used by the viewer:

```bash
moon run --target native tools/cmap_corpus.mbtx reference/pdf.js/test/pdfs
```

The 2026-10-10 scan saw 990 PDF files. 976 documents were readable and 14 were
rejected before font inspection. It found 17 external CMap font resources, all
with decoded source streams, but no real text-body or dictionary `UseCMap` and
no reader-dropped CMap. The report includes each external CMap's file, page,
resource name and object number, plus the rejected file names. This is useful
coverage for source-stream access and regression selection, but it does not
replace a real indirect-inheritance sample; the synthetic parent/child,
missing-source and cycle cases therefore remain explicit F-03 tests.

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

On 2026-10-10, all **209/209** MoonBit tests passed on wasm, wasm-gc,
JavaScript and native. `text_layer_wbtest.mbt` verifies the layer matrix maps
all four corners onto the public viewport for every quarter rotation and
multiple scales, including nonzero page origins and affine shear. Cursor
tests verify sparse source item indices, partial ligatures, reversed ranges,
UTF-16 surrogate boundaries, rotated baselines and vertical columns.
`text_layer_test.mbt` exercises the public decoded-page/text-layer/range/SVG
surface; three checked API examples compile and run as documentation tests.

The Chromium DevTools suite passed **33 interaction checks** using
`90ms_rksj_h_sample.pdf`, `vertical.pdf` (3 pages), `tracemonkey.pdf`
(14 pages), `nested_outline.pdf` (9 pages), `labelled_pages.pdf` (11 pages),
and `attachment.pdf`. It verifies:

- actual mouse drag on ordinary, rotated/scaled and vertical CJK text;
- Shift plus arrow and keyboard initiation of cursor selection;
- DOM selection mapped to source item indices, quads and available file path;
- copied text, cross-page ranges and document-only select-all on all 14 pages;
- selection restoration and highlighter reprojection after zoom/rotation;
- actual browser file input, invalid-file reporting, retention of the prior
  preview and reopening after an error;
- document search toolbar options, source-match result counts, item-level
  highlights, active-result scrolling and previous/next result controls;
- document-info bridge output for outline destinations, Info fields, page
  labels, attachment metadata and XMP availability;
- outline click-to-scroll, thumbnail SVG previews, Info/attachment panel
  rendering, on-demand attachment/XMP downloads and the print entry point;
- continuous/single-page mode switching and `#page=N` browser history state;
- absence of uncaught browser runtime exceptions during these checks.

Screenshots and the per-check report are saved in a fresh
`_build/browser-test-*/` directory. The latest 33-check run is in
`_build/browser-test-1791598489760/`; its `report.json` records every check
name and the passed count. The mouse-selection screenshot was
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
pending. The body layer now uses the A1 block/line/bidi reading-order view;
complex layouts and raw PDF byte spans are not completed. Annotation
appearances and readonly widgets still need their own DOM interaction layer.
Search currently highlights complete source items; exact character-range
painting and complete locale/case-fold policy remain TODO.
Scale and rotation still rebuild all mounted pages even though the page models
are cached.

## Host font fallback policy

`PdfFontFallback` maps a PDF resource or `/BaseFont` name to a host CSS font
family. `PdfViewerDocument::with_font_fallbacks` applies the mapping when page
font resources are built; an embedded TrueType/OpenType program remains the
preferred source, so a host fallback cannot silently replace an embedded font.
The native API exposes the same value as the browser API. The browser bridge
accepts the JSON form through `set_font_fallbacks`, clears its page-model cache,
and returns the number of accepted mappings. This keeps font ownership with the
host and avoids bundling or redistributing font files.

The latest Chromium run includes the bridge acceptance check in
`_build/browser-test-1791598489760/report.json`. The white-box font test also
checks that a fallback changes an unembedded family and leaves an embedded
TrueType family on its document-local `@font-face` name.

## Standard 14 fonts and host fallback

Standard 14 resources now carry the AFM data needed by the viewer: the 1000-unit
em size, ascent, descent, cap height and character widths. BaseFont names with a
subset prefix are canonicalized before this lookup, so an unembedded
`/ABCDEF+Helvetica-Bold` still receives the Helvetica metrics. The page model
keeps the canonical face and metrics in `PdfFontResource` for native consumers
and browser diagnostics.

The SVG path uses host CSS families for unembedded Standard 14 faces. Times,
Helvetica and Courier prefer Nimbus/Liberation families with a generic fallback;
Symbol and ZapfDingbats prefer `Standard Symbols PS` and `D050000L`. An embedded
TrueType/OpenType program still wins and is emitted as a document-local
`@font-face`. The viewer does not bundle the PDF.js Foxit font programs or any
other font files, so the host remains responsible for licensing and installation.
`PdfFontFallback` lets an application provide a different local CSS family by
resource name or BaseFont name, and the browser bridge clears its page cache
when that mapping changes.

The white-box regressions verify AFM metrics, subset-name recognition, host family
selection and filtering of Standard 14 C0/undefined C1/`.notdef` display codes.
The `standard_fonts.pdf` fixture renders all 14 pages with no explicit control
characters in the SVG (`NUL_COUNT=0`). In the Standard 14 visual run,
`_build/visual-test-1791590079766/`, the Standard 14 pages differ from PDF.js by
129,822–169,878 pixels above channel tolerance 8. The remaining differences are
the expected host glyph outlines, rasterization and Symbol/ZapfDingbats coverage,
not a missing AFM advance path. A machine with different installed fonts will
produce different pixels; exact PDF.js parity would require a licensed,
deterministic font program or an outline renderer, so F-07 remains open.

## Text search

`PdfViewerDocument::search` searches the text already produced by each page
model, so optional-content visibility is respected without a second PDF parse.
Each result carries the one-based page number, the original matched text, a
UTF-16 source `index`/`length`, the union of matching glyph bounds and stable
source item indices. `PdfSearchOptions` supports case-sensitive, whole-word and
common Latin diacritic-insensitive matching. The implementation keeps a
normalized-code-unit to source-interval map; the regression for `Straße` and
`strasse` confirms that an expansion such as `ß` to `ss` still returns the
source range rather than the normalized range.

The browser bridge exposes the same operation as `search_pdf`. The standalone
toolbar adds the three options, displays the result count, scrolls to the active
page and highlights source text-layer items. The latest Chromium run is
`_build/browser-test-1791598489760/report.json`, with all 33 checks passing.
A1 now supplies Unicode NFKD source mapping and checked mixed-direction/column
ordering. Complex PDF.js reading-order cases, substring highlighting inside a
multi-character item and cancellable Worker search remain incomplete.

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

The latest 2026-10-10 baseline in `_build/visual-test-1791598324155/` measured
**57/57 page/rotation combinations from 20 PDFs**, with **0 measurement
failures and 0 uncaught runtime exceptions**. PDF.js version `6.5.0`, build
`89b500f`, rendered in the same Chromium profile as MoonBit, at scale 2 and
deviceScaleFactor 1, on white. All 57 viewport dimension/matrix comparisons
matched within 1e-6; 20 text comparisons matched after removing whitespace.
**55 combinations had pixel or text differences; 2 were within the recorded
tolerance.** This is a selected corpus, not a visual compatibility percentage.

| Sample | Selected pages/rotations | Pixels above per-channel tolerance 8 | Main finding |
| --- | --- | ---: | --- |
| `90ms_rksj_h_sample.pdf` | page 1, 0/90° | 1,098 / 956 | ASCII/Japanese are visible; recorded pixel differences remain |
| `vertical.pdf` | pages 1/2/3, 0° | 2,569 / 1,497 / 1,497 | Page edges differ; pages 2/3 have no body text, not entirely blank pixels |
| `issue18117.pdf` | page 1, 0° | 11,268 | Text agrees; glyph/raster differences remain |
| `cidfont_cmap_overflow.pdf` | page 1, 0° | 4,620 | Text and viewport agree; all changed pixels are outside the 1px neighborhood |
| `issue14462_reduced.pdf` | page 1, 0° | 1,578 | Type 1 glyph/raster differences remain |
| `issue18548_reduced.pdf` | page 1, 0° | 0 | CID Type 1 result is within tolerance; minor exact pixel differences remain |
| `text_clip_cff_cid.pdf` | page 1, 0° | 346 | Zoom clipping is corrected; residual pixel differences remain |
| `annotation-highlight.pdf` | page 1, 0° | 2,308 | Appearance differences remain |
| `annotation-freetext.pdf` | page 1, 0° | 1,032 | Appearance differences remain |
| `issue19176.pdf` | page 1, 0° | 0 | `/UserUnit 72`; exact viewport and pixels in this environment |
| `standard_fonts.pdf` | pages 1–14, 0° | 129,822–169,878 per page | Standard 14 fonts: AFM placement is wired; host glyph outlines, `.notdef`, Symbol and ZapfDingbats fallback remain visibly different |
| `tiling_patterns_variations.pdf` | page 1, 0° | 27,076 | Output scale is no longer doubled for tiling cells; P5 region has 4,176 changed pixels including its border; other matrix/clip/edge differences remain |
| `tracemonkey.pdf` | pages 1/7/14, 0° | 246,338 / 276,148 / 136,162 | Nimbus/Computer Modern fallback family improved; glyphs and normalized extracted text still differ |

The other 26 combinations are the seven colour/image fixtures listed in
[Calibrated colours and original image samples](#calibrated-colours-and-original-image-samples).
All of those pages still count as full-page differences, including the 21
pages whose sampled calibrated-colour interiors match exactly.

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

The Type 1 recovery change was checked with the full corpus smoke run and all
four MoonBit backends. The latest selected visual run above also completed in
Chromium with no measurement failures; its remaining pixel differences are
retained in the report rather than treated as matches.

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
absent from the default manifest. These checks are separate from the 33
standalone viewer interaction checks.

After the zoom-clip correction, CMap recovery, password paths, page-boundary,
destination, optional-content, search, ToUnicode fallback, Standard 14 font
metrics, pattern scale, inline-image decode, calibrated-colour conversion and
stream-comment recovery updates, all **209/209** tests passed
on wasm, wasm-gc, JavaScript and native, and the standalone Chromium suite
passed all **33** interactions. The latest report and screenshots are in
`_build/browser-test-1791598489760/`.

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

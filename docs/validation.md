# Validation baseline

The annotation baseline uses the local pdf.js checkout at revision
`89b500f5e1d98ed89bb90211e45b28730b2d99ac`, pdflite `0.2.2`, and the native SVG
CLI. That conversion baseline does not measure parity with pdf.js rendering.
The automated selected-page visual baseline below now measures actual output
against the same pinned PDF.js build.

The suite currently contains **379 tests on each of wasm, wasm-gc, JavaScript,
and native**; the browser host adds two lightweight page-layout regressions and
three annotation interaction/print regressions to the final A1 results below. Earlier stages included
13 annotation tests, 17 CFF tests, 25 Type 1 tests, 5 CID
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

## Readonly annotation interaction and print intent

Validated on 2026-10-11 with Chromium **145.0.7632.6** on macOS arm64.
Report: `_build/browser-test-1791698888406/report.json`, **78/78 checks pass**.
The 25 additional checks preserve the previous 53 browser interactions and
pressure checks. MoonBit passes **379/379** on each of wasm, wasm-gc, JavaScript
and native. This accepts the **A-04 main path** and brings the readonly
checklist to **29/50**; annotation appearance/form fidelity remains A-01–A-03.

`annotation_layer.mbt` adds `PdfViewerDocument::annotation_layer_json(n)`:
PDF-space rectangles/quads, original `/Annots` indices, display/print flags,
plain popup text and local/remote/URI/named-action targets. It reuses pdflite's
annotation and destination parsing without decoding AP streams. Named and
dictionary targets have a 32-step resolution bound; unresolved names do not
re-enter pdflite's recursive page resolver. Popup children and malformed
siblings are skipped without renumbering. Three new library tests cover
cyclic/unresolved/remote links, metadata with a corrupt AP, quads, and an
unchanged source model when selecting printable appearances.

`web/annotation-layer.js` mounts native links and keyboard-accessible comment
buttons over the same viewport matrix used by body/text paint. URI quad
regions remain separate. The popup displays author/subject/contents as text,
supports native Enter activation, Escape/close with focus return, and clears
on scrolling, repaint/unmount or document close. Markup mouse hits are handled
after a collapsed-selection click, allowing body text to retain native drag
selection. The visual SVG layer is inert, so only the DOM interaction controls
receive keyboard/link activation. `pdf-annotation-activate` carries the source
page/index/subtype/link. Local destination clicks apply page/history and
XYZ/Fit view parameters; supported named actions navigate pages/history.
Unknown/remote/unsupported actions are disabled. Native HTTP(S)/mailto/tel
links use `noopener noreferrer`; relative URIs require a fetched PDF URL base.

Real fixtures validate these paths:

| Fixture | Checked behavior |
| --- | --- |
| `annotation-link-text-popup.pdf` | HTTP link and comment controls, plain popup content and close |
| `annotation-text-without-popup.pdf` | Text comments work without an explicit Popup child |
| `widget_hidden_print.pdf` | Hidden cancels Print: the widget stays absent in both intents |

The authored two-page fixture `_build/browser-test-1791698888406/annotation-interactions.pdf`
has SHA-256 `a49171925da8be3623218be0edc0036713e76bf4342e129f83ec61f71d4fa7b7`.
It covers nonzero CropBox origins, UserUnit, intrinsic/requested rotation,
multiregion URI links, literal markup-looking popup text, malformed/unsupported
targets, source text selection, XYZ zoom, named NextPage, repaint and close.
Native pointer hits and DOM/paint bounding boxes pass at all four rotations;
the overlay also matches after rescaling. Screenshots are retained as
`annotation-rotation-{0,90,180,270}.png` in the report directory.

`PdfPageModel::with_print_annotations()` selects the independent Print flag
without mutating the display model. The bridge's `render_print_page` uses the
same body renderer and a separate render-cache key. The synthetic Print and
NoView/Print annotations are present in prepared print DOM; display-only and
Hidden annotations are absent. Print DOM contains no popup/link control layer.
The existing real 200-page print export still preserves all pages and physical
sizes. These are interaction and intent checks, not AP pixel parity. NoZoom/
NoRotate icon/AP fidelity, richer comment/attachment presentations and readonly
widget layout remain in A-01–A-03; editing/saving remains outside this baseline.

Reproduce with the development server running:

```sh
moon run tools/browser_test.mbtx http://127.0.0.1:4312 /path/to/chromium
moon test --target all
moon test --target native
```

## Browser host lifecycle, scheduling and pressure

Validated on 2026-10-11 using Chromium **145.0.7632.6** on macOS arm64.
The browser report is `_build/browser-test-1791696549159/report.json`:
**53/53 checks pass**, including the existing real-file interactions and 14
additional scheduling/lifecycle/pressure checks. All four MoonBit backends pass
**376/376**. This accepts the host main paths **P-02, U-05 and V-02** and brings
the readonly checklist to **28/50**. Rendering/annotation parity is unchanged.

`web/pdf-client.js` owns a native module Worker, a priority queue, startup
failure/timeout handling and AbortSignal cleanup. `web/pdf-worker.js` runs the
existing MoonBit bridge. Opening another file or closing the document
terminates the old Worker and rejects its queued/active tasks; stale results
cannot replace the new document. Cancelling an individual RPC rejects the
caller and removes queued work; an already running synchronous page/search
operation can finish before the Worker accepts another task. This is a host
task contract, rather than a copy of PDF.js loading/render task objects.

`PdfViewerDocument::page_viewport` resolves the same CropBox, origin, UserUnit
and rotation as rendering without interpreting page contents/fonts/images.
Its two tests compare geometry and preserve layout access with a corrupt page
stream. `web/page-scheduler.js` retains cheap page boxes and mounts paint/text
only near the viewport and selection endpoints. Thumbnails use a separate
visible-row observer. Scale/rotation cancels the previous layout generation.
Source selection/copy and search read unloaded pages through the Worker;
200-page Ctrl+A does not mount 200 text layers. Native selection text covers
mounted DOM; the rich selection event and clipboard contain the whole source
range. Existing drag, Shift-arrow, vertical-text, font and navigation checks
still pass.

The authored deterministic pressure fixtures and measured timings are:

| Fixture | Pages / input bytes | First page | Other observation |
| --- | ---: | ---: | --- |
| Simple text, varying Rotate/UserUnit | 200 / 56,204 | 635.2 ms | A requested 30 ms main-thread timer fires after 31.5 ms during Worker search |
| Independent 512×512 raw RGB images | 16 / 12,591,301 | 551.3 ms | All pages render; the visible page remains painted after eviction |

First-page time includes the file-input path, Worker startup and layout/font
readiness. The text fixture SHA-256 is
`cf9b2cb8c0569876f73aa66c80ff0fff3c2ef9767307e8689897fdcdb4075c02`;
the image fixture is
`a3ff2fa1be1b7203df98f28e290cae5b9eae8fb19a58b1915fe91cd1dcd14f3f`.
These are scheduling pressure fixtures, not a natural large-document corpus
or visual compatibility evidence. Cold/hot page rendering takes **4.4/0.2 ms**
in this run and returns identical content with a recorded render-cache hit.

| Retained cache | Budget | Final image-pressure sample |
| --- | --- | --- |
| Page models, including font/image assets | 8 pages and estimated 32 MiB | 8 pages, 17,566,298 estimated bytes, 8 evictions |
| Serialized SVG/text layer | 12 entries and 24 MiB | 11 entries, 24,020,794 bytes, 5 evictions |
| Main-thread font width measurements | 4,096 entries | Bounded independently of document length |

Oversized entries are returned without retention. Page-model estimates use
serialized UTF-16 size plus item/font overhead; they are cache accounting,
not object-heap measurements. Parsed input, temporary decoding, browser
font/image resources and the explicit whole-document print DOM are outside
these budgets. `runtimeDiagnostics()` reports mounted pages, queue/cancellation
counts and both caches. The final sample retains pages **1 and 2**, no queued
tasks and no active RPC. Twenty-seven CDP samples report main-thread/Worker JS
heap maxima of **33.71/127.60 MiB**; after explicit GC the retained heaps are
**1.28/36.72 MiB**. Backing storage and embedder fields are also in the report.
These are sampled JS heaps, not a continuous process peak or an RSS limit.

The print entry prepares every page at its physical point size, waits for
fonts/images, and releases temporary DOM on `afterprint`. A real Chromium
`Page.printToPDF` export is read back with pdflite: **200 pages**, with page 1
at **612×792 pt** and page 10 at **1188×918 pt**, preserving intrinsic Rotate
and UserUnit. Repeated print preparation cancels the old task without clearing
the new one. Use the toolbar or Ctrl/Cmd+P to prepare printing; a direct native
browser-menu print cannot asynchronously prepare unloaded pages and displays
that instruction. Screen/print annotation AP switching was subsequently accepted
in the [A-04 checks](#readonly-annotation-interaction-and-print-intent).

Reproduce with the development server running:

```sh
moon run tools/dev.mbtx 4312
# In another terminal:
moon run tools/browser_test.mbtx http://127.0.0.1:4312 /path/to/chromium
moon test --target all
```

## A1 completion validation

Validated on 2026-10-11 against the pinned pdflite **0.2.2**, `mizchi/font`
**0.7.4**, Unicode packages **0.5.2**, and PDF.js revision
`89b500f5e1d98ed89bb90211e45b28730b2d99ac` (build 6.5.1), using Chromium
154.0.0.0. The eight A1 main-path items **R-02, F-03, F-05, F-06, F-07,
T-01, T-02 and T-04 are complete** under the TODO acceptance rules. This is
font/text main-path acceptance, not complete PDF.js compatibility.

### Implementation and regression coverage

The final batch adds **29 regressions**, bringing the suite from 345 to 374:

| Area | New checks | Evidence |
| --- | ---: | --- |
| TrueType legacy tables | 4 | cmap 2 subheader aliases/relative offsets, post 2.5 signed names, truncated directories, valid later tables and damaged sfnt fallback; normalized input still uses the pinned cmap/post library |
| CFF/Type 1 programs | 6 | explicit missing CFF name selects `.notdef`; damaged strings/subroutines/programs retain copy and PDF advance; non-default FontMatrix; hint OtherSubrs and flex relative coordinates |
| Real text CMaps | 4 | named/indirect inheritance, absent local codespaces, WMode/local precedence, UTF32/surrogate source bytes, bounded large ranges and inheritance |
| Reader page trees | 5 | aliases/cycles/depth, inherited box/rotation/resources, retained good branches, unchanged original object store and lexical spans; serialized cyclic input also exercises password-aware opening |
| Text recovery | 10 | dictionary/Encoding/metrics/Unicode recovery, empty copied glyphs, missing Tf, cyclic descriptor/font-stream references, huge CID widths, literal U+FFFD and valid indirect Encoding/PostScript metadata |

`moon info && moon fmt`, `moon test --target native`, and sequential tests on
`wasm`, `wasm-gc` and `js` pass **374/374 on every backend**. `moon check
--target all` passes with the existing **24 warnings**, and `git diff --check`
passes. No new snapshot approval was needed.

The generated interface adds `PdfReaderDiagnostic`,
`PdfTextRecoveryDiagnostic`, `reader_diagnostics()` and
`text_recovery_diagnostics(n)`. Existing public record layouts stay unchanged.
Seven diagnostic enum cases add font stream/dictionary/encoding/metrics,
invalid-code, Unicode fallback and reader-CMap observations; consumers with
exhaustive matches must handle these additions. Old document text diagnostics
project records with a logical source range. Empty copied glyphs keep their
original operand bytes with no fabricated UTF-16 interval.

### Embedded programs and browser loading

The real `tracemonkey.pdf` exposed retained-argument failures in Type 1 hint
replacement. Following the pinned PDF.js OtherSubr handling and relative flex
operands reduces page 1's **1,549 missing embedded outlines and 1,549 host
fallbacks to zero**. The same 4,282 source glyphs and original font/program IDs
remain; the page has one `UnicodeMappingFallback` observation. Both page images
were inspected: title, superscripts, body contours and column placement are
present. Pixel differences still count in the report.

Chromium interaction checks pass **39/39**, including fresh mouse drags after
rotation/zoom, Shift-arrow extension, vertical/CJK copying, multi-page source
selection, five font-loading inputs and the cyclic-page-tree fixture. Report:
`_build/browser-test-1791658143102/report.json`.

| Input | FontFace result | Selectable glyphs / painted paths |
| --- | --- | ---: |
| `standard_fonts.pdf`, all 14 pages | 30 faces loaded | 5,788 / 12,664 |
| `complex_ttf_font.pdf` | 2 subset faces rejected | 616 / 1,143 |
| `TrueType_without_cmap.pdf` | 1 face rejected | 4 / 4 |
| `issue4800.pdf` | 1 face loaded | 12 / 12 |
| `issue14462_reduced.pdf` | Type 1 paths; no browser FontFace | 11 / 10 |

The rejected subset fonts are an observed browser decoder limitation. The
viewer still uses original-program outlines and selectable text; the check
does not claim that these font files became valid browser fonts. Normal host
fallback or missing ToUnicode observations do not prove PDF corruption.

### Original bytes, layout and located diagnostics

The final ten-font replay passes **10/10** with **5,409 logical/located glyphs,
6,252 captured bytes, 355 runs and 44 geometric paragraphs**. There are no
source/lexical/run/paragraph/diagnostic join failures. Rich diagnostic records
are checked against the same item/font/charcode and operand bytes. Its 783
observations include missing Unicode mappings, 74 host fallbacks in
`mixedfonts.pdf`, and 18 checksum-recovery observations across the nine glyphs
of `issue13316_reduced.pdf`; they are not 783 corrupt glyphs. Report:
`_build/text-provenance-1791658201943/report.json`.

The five-reader replay also passes **5/5**, with **2,525 logical glyphs and
2,525 captured bytes** across the four text-bearing pages. `bug1770750.pdf`
has no body text; its empty source list is checked without inventing glyphs.
The retained cyclic-tree page preserves 22 file-level lexical spans. Report:
`_build/text-provenance-1791658093293/report.json`.

Valid indirect simple-font Encoding dictionaries and real PostScript CMap
dictionary/literal headers no longer produce spurious CMap diagnostics.
Compressed/encrypted content still returns decoded lexical positions and
available whole encoded-stream spans, not invented character file offsets.
Rotated/sheared blocks, columns, compact tables and bidi controls use the
previously checked shared copy/search/selection order; untagged paragraphs
remain geometric inference.

### Reader and CMap corpus evidence

The isolated native reader scan processes all **989 locally present PDF.js
PDFs: 952 open, 37 fail**. Open/fail status is unchanged after using the strict
reader entry before bounded page-tree recovery. Among readable documents,
266 contain typed ObjStm streams, 6 XRef streams, 306 Metadata streams, 407
XObject streams and 18 typed CMap streams. These are document/stream-type
counts, not font CMap counts. Failure classes include 5 InvalidFlateData,
3 unsupported encryption authentications, 23 SoftError, 2 indirect-object
parse errors, 2 RootExpected, 1 XRefEntryExpected and 1 InvalidASCII85Data.
Each file retains its error and available startxref pointer; that pointer is
context, not a claim of the exact error byte offset. Report:
`_build/reader-corpus-1791658180369/report.json`.

`Pages-tree-refs.pdf` now retains its first readable page and reports the
original cycle path `/Root/Pages/Kids[1]/Kids[0]/Kids[0]/Kids[0]`, object 3.
The viewer reports **1 surviving page**. PDF.js reports **2 pages**, renders
page 1 and rejects page 2 lazily; the count difference is retained explicitly
in the visual report and browser check.

The matching pinned-reader CMap inventory sees **14 parsed external font
CMap resources**, **0 reader-dropped**, **0 body UseCMap** and **0 dictionary
UseCMap** across those inputs. Raw font inspection of the recovered cyclic
tree is skipped and recorded. Report:
`_build/cmap-corpus-1791658244622/report.json`. Earlier 990/976/17 inventory
numbers elsewhere are historical runs with a different standalone reader and
available-file set, not this pinned-root result.

Because the natural corpus has no external UseCMap sample, four **unmodified
Adobe Japan1 text CMaps** (`90ms-RKSJ-H/V`, `UniJIS-UTF32-H/V`) are pinned at
`f5cf3bca7fdfeaceb77aa82847e974f2306c20b4`, with hashes and Adobe BSD license
in `assets/cmaps/test-sources/`. Authored PDF wrappers test their real named
parents, indirect PDF parents, WMode and original multibyte origins. Additional
authored ranges/depth failures test limits and fallback. These wrappers are
not claimed as naturally occurring PDF.js PDFs. Runtime mappings remain the
existing Adobe assets and lazy viewer representation; no second reader or
stream decoder was introduced.

### Measured visual differences and retained branches

All selected comparisons use the same Chromium, scale 2, white background and
unmodified pinned PDF.js source. Ordinary completion means measured output;
`--strict` would reject the differences below.

| Manifest | Measured | Failures | With pixel/text differences | Report |
| --- | ---: | ---: | ---: | --- |
| `font_post_cases.json` | 10/10 | 0 | 10 | `_build/visual-test-1791657614581/report.json` |
| `standard14_cases.json`, `use_system_fonts=false` | 16/16 | 0 | 16 | `_build/visual-test-1791658043891/report.json` |
| `reader_cases.json`, `use_system_fonts=false` | 5/5 | 0 | 5 | `_build/visual-test-1791658014379/report.json` |

Standard-font pages retain **116,689–128,412** raw pixels over channel tolerance;
the whole-page grid includes known stroke/raster differences. Text comparison
also remains raw: pages 1–12 match after whitespace removal and NFKC (micro sign
versus Greek mu), Symbol retains Delta-codepoint differences, and Zapf copy
uses the dependency's dingbat Unicode mappings while PDF.js extraction retains
Latin codes. This is not concealed as a pixel-only difference. Neither report
normalizes away these mismatches. `tracemonkey.pdf` retains **182,901** raw
changed pixels (**163,751** outside the diagnostic 1px neighborhood) and text
order/normalization differences. `issue17147.pdf` retains **1,001** raw changed
pixels. The recovered cyclic page has **2,749**, CalGray **13,166**, CalRGB
**65,221**, checksum-recovered text **2,033**, and `bug1770750.pdf` **111**.

Rare cmap 8/10/13 and vendor post formats, font-library limitations on missing
tables/compound outlines, multiple-FD CID Type 1 and unrecoverable streams
retain documented recovery/error branches. Untagged ambiguous structures do
not recover author semantics automatically; unverifiable bidi retains content
order. Complete stroking/rasterization, image/colour/compositing and annotation
parity remain in A2 and later TODO items. At A1 acceptance the checklist was **25/50**;
editing, form saving and signatures are still outside that readonly baseline.

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
and the DOM text layer. The rotation/control/table follow-up below expands these cases while retaining
content order for ambiguous bidi permutations.

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

`mizchi/font` 0.7.4 is pinned in the root dependencies and used for validated
standalone cmap and post paths. PDF selection prefers Windows Unicode/Symbol,
then MacRoman, with full-repertoire Unicode records for supplementary scalars;
directory order no longer merges conflicting records. MacRoman reverse lookup
reuses pdflite. Selected missing glyphs remain GID 0 instead of borrowing the
raw character code. Absent/unusable cmap tables retain the recovery branch.

Before calling the library, the adapter checks declared table/record lengths,
format 4 array/range offsets, format 12 group ordering, Unicode/GID bounds and
expansion limits. It corrects signed remainders to 16-bit glyph IDs and checks
maxp. A shared cache retains cmap bytes only, with limits of 8 entries, 1 MiB
input and 262,144 decoded mappings; each format 12 table can expand at most
131,072 codepoints. Other cmap formats and broader damaged-font/host-loading
behavior remain open; post-table recovery is covered by the next batch below.

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

### Standalone post integration

The next batch reuses `mizchi/font.parse_post` for version 2 names. Version 1
supplies equivalent standard-name indices to that reader; version 3 supplies
no names. Deprecated 2.5 and vendor formats remain unsupported. The adapter
checks maxp counts, all name indices and Pascal-string reads within the declared
post table, following the [OpenType post specification](https://learn.microsoft.com/en-us/typography/opentype/spec/post).
The shared cache retains only post bytes/names, keyed by bytes and glyph count,
and is limited to eight entries, 1 MiB of input and 131,072 decoded names.
Post lookup preserves the first duplicate name and excludes .notdef, empty
glyphs and loca/glyf reads outside declared tables.

Valid Windows/Symbol cmap mappings take priority. Unicode-platform cmap
mappings use the original byte for BMP lookup, then prefer explicit PDF
Encoding/Differences post names. Supplementary glyphs retain Unicode lookup.
Missing cmap mappings and absent-cmap fonts can recover through post names.
Unknown PDF glyph names are distinguished from pdflite's raw-code fallback
using its existing glyph resolver. Only an unknown name with no usable post
names may use an explicit ToUnicode entry to find a cmap glyph; known names
remain independent of copied Unicode. PDF glyph-list and Macintosh name tables
are reused, not duplicated in the viewer.

Eleven new regressions cover custom-name painting/clipping/copy separation,
Windows and Symbol priority, Unicode-platform overrides and supplementary
glyphs, missing cmap, versions 1/2/3, the restricted ToUnicode fallback,
truncated strings, count/index bounds, duplicate/.notdef/empty glyphs,
loca/glyf/head bounds, cache isolation and input/decoded-name eviction.
The four-backend suite passed **270/270 on each backend**. The public `.mbti`
interface is unchanged. Against `deb27b1`, generated browser JS grows from
12,248,518 to 12,285,375 bytes; `gzip -c` grows from 2,785,682 to 2,790,651
(**4,969 bytes**). This is artifact size, not a load/performance measurement.

`tools/font_post_cases.json` measures the previous nine fonts plus
`issue13316_reduced.pdf`, at the pinned PDF.js revision, page 1, scale 2,
rotation 0. Current `_build/visual-test-1791641615896/` and detached `deb27b1`
baseline `_build/a1-post-baseline/_build/visual-test-1791641621559/` both
measured **10/10**, with **0 runtime failures**, **0 placeholders** and
**10 existing pixel/text differences from PDF.js**. Nine viewer PNG hashes
are identical between the builds. `TrueType_without_cmap.pdf` restores the
previously missing four-glyph word through post names: changed pixels above
tolerance fall from **508 to 355**, and missing-ink pixels from **449 to 59**.
Its extracted text remains equal to PDF.js; remaining edge/paint differences
are still counted, not waived.

At this post stage, `issue13316_reduced.pdf` remained at **3,771** changed pixels
and extracted `A C D E F`; the standalone font inventory raised
`InvalidFlateData`. The following checksum-recovery batch resolves this case.
The named Unicode-platform conflict is covered by authored regressions and the unchanged
`issue4800.pdf`; `issue13433.pdf` was not measured because downloading its
pinned `.link` target timed out. F-05/R-02 remain open.

### Font stream checksum recovery

`tools/font_stream_probe.mbtx` identifies an Adler-32 `ChecksumMismatch` in
`issue13316_reduced.pdf` object 12 (ToUnicode, 638 encoded bytes) and object 31
(FontFile2, 52,139 encoded bytes). Both strict pdflite decodes raise
`InvalidFlateData`; the pinned PDF.js Flate reader does not check that trailer
checksum. The viewer now directly pins pdflite's existing
`moonbit-community/flate` 0.8.1 engine instead of adding another decompressor.
After strict decoding fails, its streaming zlib decoder must identify a
complete checksum mismatch; its bounded raw DEFLATE decoder then retrieves
the complete body. Invalid headers, preset dictionaries, invalid/truncated
DEFLATE and missing checksum trailers remain failures. Only one Flate filter
with no transforming predictor is eligible. Recovery accepts at most 4 MiB
compressed input and 16 MiB output; its eight-entry byte-only cache retains
at most 8 MiB input and 16 MiB output. Normal pdflite decoding limits remain
unchanged.

Font programs, CIDToGIDMap and external/inherited CMaps share the adapter.
Recovered ToUnicode is retried in a shadow dictionary so simple-font glyph
recovery and copied text see the same descriptor. Metrics, PDF objects and
original encoded streams are preserved. Document `text_diagnostics()` adds
`FontStreamChecksumRecovered`, including the exact recovered parent's
resource path and immediate object number; checksum inspection walks up to
64 CMap streams and cuts cycles. This records a recovery decision, not proof
that the body equals the original producer's bytes. The sole public `.mbti`
change is the new diagnostic enum case; existing records are unchanged.

Fifteen new regressions cover complete checksum errors, every truncated
prefix, invalid headers/dictionary/reserved blocks, exact output limits and
final-step bytes, input larger than the decoder's window, trailing bytes,
indirect filters/parameters/lengths, predictor/filter-chain rejection on
cache hits, input/output/entry eviction, preserved source objects, valid-stream
semantics, unrecoverable-font fallback, and end-to-end TrueType, Type 1, CFF,
CIDToGIDMap and inherited CMap painting/clipping/copying/embedding. The suite
passed **285/285 on each of wasm, wasm-gc, JavaScript and native**.
`moon info && moon fmt`, script formatting and `moon check --target all` passed;
the same 24 pre-existing deprecation warnings remain. The stream probe also
ran against the real sample. Generated browser JS grows from 12,285,375 to
12,316,533 bytes; `gzip -c` grows from 2,790,651 to 2,795,296 (**4,645 bytes**).
This is artifact size, not a performance measurement.

The same ten `tools/font_post_cases.json` pages at scale 2/rotation 0 were
measured against the pinned PDF.js build. Current report
`_build/visual-test-1791645717953/` and detached `fe4d051` baseline
`_build/a1-flate-baseline/_build/visual-test-1791645527234/` both measured
**10/10, 0 failures, 0 runtime exceptions and 0 placeholders**. Nine viewer
PNG SHA-256 values are identical. `issue13316_reduced.pdf` now paints the five
Chinese glyphs and extracts **`开 票 通 知 单`**, exactly matching reference
text including spaces. Changed pixels above tolerance fall from **3,771 to
2,033**; missing-ink pixels fall from **2,226 to 527**, with **3** extra-ink
pixels. Viewport geometry matches. Stroke weight and raster edges still differ,
and all ten pages retain measured pixel/text differences; this is recovery of
this sample, not full font or PDF.js parity. Filter chains, predictors and
broader damaged-font/document recovery keep R-02/F-05/F-06/T-04 open.

```bash
moon run tools/font_stream_probe.mbtx reference/pdf.js/test/pdfs/issue13316_reduced.pdf _build/a1-stream-issue13316
moon test --target all --diagnostic-limit 1
moon run tools/visual_test.mbtx tools/font_post_cases.json '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
```

### Text byte and font provenance

`PdfViewerDocument::text_provenance(n)` adds an opt-in sidecar joining existing
logical UTF-16/item ranges to character-code bytes, half-open decoded-string
operand ranges, stream-reference scopes and repeated/nested Form invocations.
Operator indices address the existing parser's operations; TJ operand indices
retain numeric adjustments. Escaping, decompression and decryption precede
these byte offsets. A string may cross concatenated streams, so this API
retains the scope's entire stream-reference sequence and does not invent a
single stream or file lexical offset. Empty copied glyphs and inferred
separators have no logical source entry; omitted bytes do not renumber later
operand offsets.

CID/GID mapping reuses the existing CMap/TrueType/CFF/Type1 selectors and pinned
font library paths. The collector tracks the active PDF font object across Tf,
ExtGState, q/Q, inherited/shadowed Form resources and implicit Form frames.
Embedded programs are cached only within one inspection. GID 0 remains a valid
notdef selection; Type1/Type3 use available glyph names. Unknown mappings,
non-UTF8 Type3 names and host-font glyph IDs remain absent. Invalid or truncated
CMap codes preserve bytes without a CID/GID. This identifies PDF program
selection, not browser font-loading success or proof of matching rendered ink.

Twenty new regressions (17 whitebox and 3 public API) cover all text-showing
operators, PDF escapes and non-UTF8 operand bytes, 1–4-byte/unsigned and
predefined UTF8/UTF16/UTF32 CMaps, truncation, CIDToGIDMap/checksum recovery,
independent ToUnicode/GID selection, CFF/Type1/Type3 identities, Form invocation
and font-state scopes, concatenated/direct streams, empty/multi-scalar mappings,
bidi/ligature/surrogate search/selection, RC4/AESV2 decryption, optional-content
visibility and unchanged source objects/rendering. The final suite passed
**305/305 on each of wasm, wasm-gc, JavaScript and native**. `moon info && moon
fmt`, script formatting and `moon check --target all` passed; the same 24
pre-existing deprecation warnings remain. The public `.mbti` changes add three
sidecar types and one document method; existing public records are unchanged.

`cmd/text_provenance` exports JSON and checks public source relationships;
`tools/text_provenance_corpus.mbtx` reuses `tools/font_post_cases.json` at the
pinned reference revision. Report `_build/text-provenance-1791648236807/` passed
**10/10**, covering **5,409/5,409 logical glyphs**, **6,252 source bytes**,
**843 CID mappings**, **814 numeric GIDs** and **4,305 program glyph names**.
No invalid code or source-range/charcode mismatch occurred in these pages.
Counts can overlap; absent IDs include legitimate unembedded/host fonts.
These are provenance checks, not a comparison of PDF.js's rewritten font GIDs.

The selected-page visual replay in `_build/visual-test-1791647890679/` measured
**10/10 with 0 failures, runtime exceptions or placeholders**. All ten viewer
PNG SHA-256 values equal the `81b42d3` report in
`_build/visual-test-1791645717953/`; the existing ten pixel/text differences
from PDF.js remain. Generated browser JS grows from **12,316,533 to 12,334,904
bytes**, and `gzip -c` from **2,795,296 to 2,797,759 bytes** (**2,463 bytes**).
This is artifact size, not page-load performance. At that checkpoint file
lexical spans and run/paragraph structure were still pending; they are supplied
by the additional APIs below. Broader font/recovery parity remains in A1.

```bash
moon run --target native cmd/text_provenance -- input.pdf /tmp/page-1-text.json 1
moon run tools/text_provenance_corpus.mbtx tools/font_post_cases.json
moon run tools/visual_test.mbtx tools/font_post_cases.json '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
```

### File spelling, empty glyph origins and text structure

`text_lexical_sources(n)` returns paint-order glyph origins, including empty
copied glyphs. It reuses pdflite's lexer/parser and checks literal/octal/hex
spellings against the decoded charcode bytes. TJ member indices, quote
operators, concatenated streams and repeated Form invocation paths retain
their identity. Inline-image boundaries are validated with the resource-aware
parser, including a regression with `EI` inside actual image bytes.

The original input must match the lazy stream's backing bytes before exposing
an encoded payload range. Unfiltered/unencrypted streams additionally expose
exact file spelling ranges; compressed or encrypted streams expose decoded
spelling, with no fake per-glyph file offset. In-memory replacement streams
cannot masquerade as original file positions. Unverified locations and the
adapter's input/mapping/candidate limits return an explicit failure. These
are location limits, not a new rendering limit.

`text_structure()` groups the same logical sources into font/baseline runs and
geometric paragraphs. Run/paragraph ranges preserve UTF-16 ligatures and
surrogate pairs; inferred separator gaps remain without byte owners. The
existing logical provenance records and page/text records are unchanged.

Fifteen new regressions cover escaping, odd hex nibbles, variable-width codes,
Forms, cross-stream operators, empty copies, inline images, compression,
three password algorithms, optional-content visibility, replacement streams,
run/font boundaries, source joins and textless pages. All four backends pass
**337/337**, with the same 24 existing warnings; interface generation,
formatting and all-target checks pass. The native inspector now checks lexical
and run/paragraph joins as well as the existing byte/CID/GID relationships.
The final guarded ten-file replay in
`_build/text-provenance-1791653263952/` located **5,409/5,409 glyphs**, with no
invalid codes or source mismatch. This completes T-02's source/structure path without claiming
semantic paragraph recognition for arbitrary PDFs.

### Active font bindings in Forms and graphics state

TrueType/Type 3 paint, TrueType text clipping and CID ToUnicode recovery now
consume the active font object captured by the interpreter. An inherited Form
font is retained until a new Tf, even when its resource name is shadowed;
missing Tf resources, q/Q and ExtGState font arrays follow the same binding.
ExtGState font reads use the viewer's existing metrics/checksum recovery.
Page and annotation font resources register that binding instead of looking
the name up again. Page names remain unchanged unless two different active
font objects share a name, in which case the later binding gets a page-local
alias. Public records and item indices are unchanged.

Six new regressions cover painted GIDs and clip paths, Form shadowing and
restoration, host-font resource collisions, Type 3 missing/ExtGState bindings,
ExtGState metrics and ToUnicode checksum recovery, unchanged source objects,
and disabled string-byte capture during ordinary rendering. All four backends
passed **311/311**; interface generation/formatting and all-target checks passed
with the same 24 existing warnings. No public `.mbti` change was required.

The font manifest replay in `_build/visual-test-1791650411821/` measured **10/10**,
with no failures or runtime exceptions. All ten viewer PNG hashes match the
preceding `_build/visual-test-1791647890679/` baseline. These selected real files
retain their existing differences from PDF.js; the new scope defects are
demonstrated by the authored regressions, not presented as real-corpus fixes.

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
targets disabled; annotation links are now handled by the separate A-04 layer. A remote
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
score. The later [browser host checks](#browser-host-lifecycle-scheduling-and-pressure)
cover Worker scheduling, virtualization, cancellation and cache budgets. The
body layer uses the A1 block/line/bidi reading-order view; ambiguous untagged
layouts retain their documented limits. The later
[A-04 checks](#readonly-annotation-interaction-and-print-intent) cover comment
and link interaction; special annotation appearances and readonly widget
layout remain A-01–A-03.
Search currently highlights complete source items; exact character-range
painting and complete locale/case-fold policy remain TODO.
Scale and rotation now rebuild only wanted pages while retaining cheap page boxes.

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

The deterministic Standard 14 path now bundles the unmodified programs from
the pinned PDF.js reference: ten Foxit raw CFF programs and four Liberation
Sans TrueType programs. `assets/standard14/inventory.json` records byte lengths
and SHA-256 hashes; the Foxit and Liberation licenses are retained alongside it.
The existing CFF/TrueType outline readers paint and clip each selected glyph,
while PDF Widths and pdflite's AFM data retain responsibility for advances.
Embedded PDF programs win. An explicit `PdfFontFallback` continues to request
host text and carries the existing host/clip diagnostic when appropriate.

Runtime WinAnsi encodings fill the six undefined slots with `/bullet`, as the
pinned PDF.js table does. Explicit Differences override those defaults;
ToUnicode independently determines copied text, including Standard-font
ToUnicode streams that pdflite's Standard-font extractor does not consult.
The source font dictionary is unchanged. Copied control characters are retained
in the model; SVG labels omit characters disallowed by XML 1.0. Symbol and
ZapfDingbats use their face-specific implicit encodings and pinned CFF outlines.

Eleven new regressions cover all 14 programs, clipping, affine placement,
encoding/GID versus Unicode, embedded-program precedence, explicit fallback,
Symbol Differences, controls and the WinAnsi bullet defaults. The four-backend
suite passes **322/322**. Public interfaces are unchanged.

```sh
moon run tools/standard14_assets.mbtx
moon run tools/visual_test.mbtx tools/standard14_cases.json '<chromium>'
moon run tools/visual_test.mbtx tools/font_post_cases.json '<chromium>'
```

`_build/visual-test-1791652285671/` measured **16/16**, with no failures or
runtime exceptions. Its manifest sets `use_system_fonts: false` so both sides
use the pinned replacement programs, rather than allowing PDF.js to choose a
different installed font. The 14 Standard-font pages have **116,689–128,412**
pixels above tolerance 8; `issue17147.pdf` has **1,001**, and `tracemonkey.pdf`
has **199,680**. The viewport dimensions and transforms agree. Glyph ink and
table positions are visible on all pages; the comparison still exposes thicker
SVG table strokes and outline-versus-font rasterization. This completes the
deterministic font/AFM/encoding path for F-07, not whole-page pixel parity or A2's
stroke/raster work. The separate ten-file font replay in
`_build/visual-test-1791652385352/` measured **10/10** without failures and retains
its existing PDF.js differences.

The following records the earlier host-only implementation and its baseline.

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
not a missing AFM advance path. A machine with different installed fonts would
produce different pixels; exact PDF.js parity would require a licensed,
deterministic font program or an outline renderer. That path is now supplied
by the pinned programs described above.

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
ordering. Complex PDF.js reading-order cases and substring highlighting inside a
multi-character item remain incomplete. Search now runs asynchronously in the
Worker; cancelled or superseded results cannot publish, though a synchronous
search already running in that Worker may finish before the next RPC.

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

### Rotated blocks, tables and bidi controls

Eight authored regressions cover 90°/180° and sheared baselines, a rotated
heading over two columns, compact three-row tables versus long aligned columns,
RLO/PDF and RLI/PDI controls with remote zero-width geometry, supplementary
scalars, explicit newline glyphs and gaps between opposite-direction runs.
Reading order projects temporary geometry and returns the original paint items,
quads and indices. Copy, search, selection, DOM separators and source intervals
share the context-aware separator calculation. These are geometric heuristics
for untagged PDFs; ambiguous short columns and bidi permutations retain the
documented fallback instead of inventing document semantics.

All four backends pass **345/345**; interface generation/formatting and
`moon check --target all` pass with the existing 24 warnings. The ten-file
provenance replay is **10/10** with 5,409 logical glyphs, 6,252 captured source
bytes, and no source/lexical/run/paragraph join failures. Artifacts:
`_build/text-provenance-1791654528774/report.json`. Rendering still has the
previously recorded raster differences; these checks validate text identity.

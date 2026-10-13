# Readonly completion and continuous validation

The six remaining items in the 50-item readonly inventory are implemented.
This inventory measures delivered paths, not visual compatibility or the full
reader roadmap. [Annotation editing, form filling/saving and handwritten/image
signatures](editor.md) now have separate editor acceptance.
[Layer controls](layers.md) are implemented separately; cryptographic signing
and manual assistive-technology acceptance remain further work.

## Annotations and readonly fields

A-01 adds named note/file/sound icons, caret and stamp fallbacks, line endings,
interior colours, dashed borders, true squiggly geometry and anchored
NoZoom/NoRotate output and hit regions. Print output clears those screen-only
compensations. A supplied appearance stream, including an empty one, takes
precedence and owns its graphics-state opacity. Icons reuse the unmodified
Apache-licensed [PDF.js assets](../assets/annotations/UPSTREAM.json).

A-02 generates missing FreeText/Tx appearances through existing pdflite content
operations and the viewer font pipeline. It inherits DA/DR, encoding, CID widths
and font metrics; supports wrapping/CRLF, Q alignment, auto sizing, comb/MaxLen
and password masking. Password values are masked both in visible output and
SVG field metadata. The parsed field model still represents the source value.
Rich-text FreeText editing and every vendor-specific layout remain outside this
readonly implementation.

A-03 retains choice export/display pairs and selection indices, including
duplicate export values, list scrolling/selected colours and combo labels;
handles button captions, inherited values/defaults and radio identity through
Kids/Opt. These are readonly display paths; editable controls and the pdflite
writer are connected separately by the [editor](editor.md).

## Dynamic XFA

X-02 reuses the pinned PDF.js XFA XML parser, binder, paginator and XfaLayer DOM
renderer. [Vendored source and licenses](../vendor/xfa/README.md) are verified
before the pure-Wasm esbuild step. That bundle excludes the PDF parser, evaluator,
worker and PDF Canvas renderer; PDF objects and font programs still use pdflite
and this viewer. Scoped compatibility bindings do not patch global Map/WeakMap.

Dynamic documents use template/data binding, embedded/fallback font metrics,
generated pages, native controls, selection/search and whole-document
printing. Static XFA retains its PDF page appearances. XML text selections use
`source_kind: "xfa"` with empty PDF byte ranges. FontFace and image blob resources
are released on replacement/close. Controls are readonly until **Edit / Fill**;
bound controls then update datasets through the pinned binder/XML serializer.
Undo/redo, focused saving and fresh reopen are covered in Chromium and WebKit.
Document scripts remain disabled;
external XFA image references are not fetched. Packet input is capped at 32 MiB,
page count at 5,000 and page dimensions at 20,000 points.

Authored two-page binding/rotation/text tests and upstream `xfa_issue14315.pdf`
and `xfa_filled_imm1344e.pdf` cover real layout; the latter produces seven pages
and searchable bound values. This is not acceptance of every XFA template.

## HTTP Range

R-03 uses Fetch/ReadableStream with 64 KiB blocks. The transport adapter requests
the header, tail, xref sections and objects required by the page graph. pdflite
parses all PDF syntax, xrefs, streams and compressed members; there is no second
PDF parser. Newer/hybrid entries retain precedence, indirect stream lengths
are resolved before body parsing, and original byte spans remain available for
text provenance. Search hydrates one page at a time.

Both network blocks and retained encoded stream objects have 64 MiB budgets.
Requested-page resources stay pinned; prior streams are evicted and reloadable.
These budgets do not bound total process RSS, xref dictionaries or decoding peaks.
Servers must expose a valid Content-Range and stable strong ETag or Last-Modified.
Unsupported/malformed range responses and encrypted PDFs use a complete download
(512 MiB limit). A changed validator or length fails rather than combining document
revisions. Browser close/replacement terminates pending Worker downloads.

The authored 8,389,611-byte two-page PDF needs **132,075 bytes (1.57%)** for its
first page. Full and segmented page/Canvas models and lexical byte provenance
match. The second page hydrates its 8 MiB resource on demand. Tests also cover
actual classic/compressed xrefs, abort, truncated responses, changed sources,
full fallback, stream eviction/reload and cyclic revisions. Tagged PDFs hydrate
their structure tree before the first page render, without following structure
links into other pages' content or resources.

## Continuous checks

[Readonly validation](../.github/workflows/readonly-validation.yml) runs JS,
Wasm, Wasm-GC and native tests on Ubuntu plus native tests on macOS arm64. Linux
native tests require real LittleCMS and JBIG2 capabilities; unsupported hosts
assert their explicit fallback instead of unwrapping missing engines.
[Toolchain pins](../tools/ci/toolchain.json) include official archive checksums,
MoonBit/core, Node, Playwright, codec packages and the PDF.js source revision.
Standalone `.mbtx` tools also pin dependency imports to the project's versions;
the scope gate rejects missing pins and version drift. Script mode resolves its
own dependency graph, so an unversioned import can otherwise pick a newly
published library incompatible with the fixed compiler on a clean runner.
The official versioned MoonBit archives expire on 2026-11-20; update the pins
and checksums before that date. The installer rejects an existing destination.

CI verifies 28 [real corpus inputs](../tools/ci/corpus.json), four authored PDFs,
vendored source/license hashes and the 50-item gap table. It executes the actual
Worker/Canvas and browser entry, output density/alpha/pattern/ICC regressions,
XFA/Range checks, 200-page physical printing and cache pressure. The 32×16 gray
JPEG fixture is authored; its source and digest are in the
[provenance record](../tools/ci/provenance.json).

The fixed Canvas visual manifest measures 12 page/rotation combinations at scale
2, with system fonts disabled. All 12 currently have pixel differences; five also
have paint-order text differences. Viewport geometry matches in every case.
The raw PDF.js Canvas oracle omits no-AP HTML widget controls, so the authored
field fixture's extra ink is explicitly a comparison-scope difference. Browser
and typed-layout tests independently verify those controls' readonly appearance.
The [macOS baseline](../tools/ci/visual_baseline.json) and
[Linux baseline](../tools/ci/visual_baseline_linux.json) retain raw counts and
bounded tolerances independently, because the same source has different font
rasterization on these platforms. The initial Linux run also exposed a too-short
14-page full-selection harness deadline. Range hydration now preserves decoded
page snapshots, and the harness allows 55 seconds with explicit timeout state.
Gates reject missing inputs, viewport regressions,
increased differences/missing ink and lost viewer ink. They do not turn known
differences into pixel parity. CI uploads HTML/JSON, reference/viewer/diff PNGs,
text/geometry records, print PDFs and manifests even on failures.

The initial local macOS arm64 validation used Chromium 145.0.7632.6 and the pinned MoonBit
compiler: **668 JS, 669 Wasm, 669 Wasm-GC and 677 native** tests after the final
AP opacity regression, plus **104 browser checks**, 26/26 corpus reads and
12/12 successful visual measurements. Reports are build artifacts; rerun the
workflow to reproduce them on a clean checkout.

The subsequent [Rabbita frontend migration](frontend.md) passed **110 browser
checks**, retaining the original 104 and adding view/selection preservation,
cancelled thumbnail/print publication, repeated page clicks and dropped-file
capture and real host-font warning publication. The four backend suites still pass at **668 JS, 669 Wasm, 669 Wasm-GC
and 677 native**. Nine Worker/Canvas checks remain in the Node runner; the former
JavaScript function-extraction test now exercises the compiled MoonBit app and
real DOM through the browser suite.

The text/editing follow-up adds exact UTF-16 search ranges, original affine
selection highlights with cross-page batch undo, incremental saves, original-font
Unicode appearances and bound XFA editing. Namespace role mapping, Formula labels
and native MathML add automated semantic coverage. Six checks run in both
Chromium and WebKit; report gates require all six in each engine. They include
template access restrictions, unbound/multiselect controls, radio display/print
state and same-session highlight move/resize. Human
VoiceOver/NVDA and PDF/UA acceptance remain unverified by those checks.
The corpus now also includes `rotated_ink.pdf` and
`tracemonkey_with_annotations.pdf`. Four additional local Canvas comparisons
cover the ink page at 0/90 degrees and the annotated paper's first/last pages;
all rendered with matching geometry and recorded pixel differences. These
supplemental measurements do not replace or loosen the 12 fixed platform baselines.
The latest macOS run passes **703 JS, 704 Wasm, 704 Wasm-GC and 712 native**
tests, plus **110 reader, 25 editor and 11 layer checks** in Chromium and
**6 text-interaction checks each** in Chromium and WebKit. All 28 corpus inputs pass, and
the 12 fixed visual measurements remain within their platform's recorded gates.

The warning regression also runs in that browser suite: fresh page, thumbnail
and print sessions publish a real host-font diagnostic into the Rabbita alert
and retain nonblank pixels.

```sh
npm ci --prefix tools/web-assets --ignore-scripts --omit=optional
npm ci --prefix tools/test-host --ignore-scripts
export PDF_CANVAS_PACKAGE="$PWD/tools/test-host/package.json"
moon run tools/build_web.mbtx
node tools/pixels/write_readonly_fixtures.mjs
node tools/ci/prepare_corpus.mjs
node tools/ci/check_scope.mjs
moon test --target all
moon run tools/reader_corpus.mbtx _build/ci-corpus
moon run tools/visual_test.mbtx tools/ci/visual_cases.json /path/to/chromium
# Start tools/dev.mbtx on 4314 in a second terminal.
moon run tools/browser_test.mbtx http://127.0.0.1:4314 /path/to/chromium
node tools/editor_browser_test.mjs http://127.0.0.1:4314
node tools/layers_browser_test.mjs http://127.0.0.1:4314
node tools/text_interaction_browser_test.mjs http://127.0.0.1:4314
PDF_BROWSER=webkit node tools/text_interaction_browser_test.mjs http://127.0.0.1:4314
node tools/ci/check_reports.mjs
```

Clone/build the fixed reference first as described in [reference/README.md](../reference/README.md).

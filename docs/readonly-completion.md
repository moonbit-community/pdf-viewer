# Readonly completion and continuous validation

The six remaining items in the 50-item readonly inventory are implemented.
This inventory measures delivered paths, not visual compatibility or the full
reader roadmap. Annotation editing, form filling/saving, cryptographic signing,
layer controls and manual assistive-technology acceptance remain separate work.

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
Kids/Opt. These are display paths, not editable controls or a PDF writer.

## Dynamic XFA

X-02 reuses the pinned PDF.js XFA XML parser, binder, paginator and XfaLayer DOM
renderer. [Vendored source and licenses](../vendor/xfa/README.md) are verified
before the pure-Wasm esbuild step. That bundle excludes the PDF parser, evaluator,
worker and PDF Canvas renderer; PDF objects and font programs still use pdflite
and this viewer. Scoped compatibility bindings do not patch global Map/WeakMap.

Dynamic documents use template/data binding, embedded/fallback font metrics,
generated pages, readonly native controls, selection/search and whole-document
printing. Static XFA retains its PDF page appearances. XML text selections use
`source_kind: "xfa"` with empty PDF byte ranges. FontFace and image blob resources
are released on replacement/close. Document scripts and editing are disabled;
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
The official versioned MoonBit archives expire on 2026-11-20; update the pins
and checksums before that date. The installer rejects an existing destination.

CI verifies 26 [real corpus inputs](../tools/ci/corpus.json), four authored PDFs,
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

Local macOS arm64 validation used Chromium 145.0.7632.6 and the pinned MoonBit
compiler: **668 JS, 669 Wasm, 669 Wasm-GC and 677 native** tests after the final
AP opacity regression, plus **104 browser checks**, 26/26 corpus reads and
12/12 successful visual measurements. Reports are build artifacts; rerun the
workflow to reproduce them on a clean checkout.

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
node tools/ci/check_reports.mjs
```

Clone/build the fixed reference first as described in [reference/README.md](../reference/README.md).

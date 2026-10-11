# Host-font affine text pens

## Current default and host-fallback boundary (2026-10-11)

A1 source `a22a190` supplies fixed Standard 14 font programs. After integration,
the unchanged 621-byte Helvetica fixture below uses those A1 contours through
the shipped web bridge and `web/pdf-runtime.mjs`, without host font registration
or a native outline resolver. All 24 fill/stroke/fill-and-stroke viewport cases
have zero diagnostics and exact same-font embedded A1 RGB pixels. See the
[current Standard 14 validation](standard14-pen.md) and its
[portable evidence report](standard14-pen.json).

The remaining host-specific boundary applies to an **explicit host override**
and to nonstandard fallback text for which A1 has no usable glyph contours.
Family/style/weight and ordinary Canvas text metrics do not supply independent
pen outlines. Independent non-similarity strokes of such text still need a
capable `resolveTextOutline` callback; otherwise strict replay rejects
`PDF_TEXT_STROKE_GEOMETRY` and the viewer's warning policy retains a visibly
approximate preview. Resetting the explicit override restores the bundled
Standard 14 path and clears this diagnostic.
The override warning regression is documented at the end of this page.

This new evidence executes the shipped web code in a native Canvas host.
Chromium socket creation was denied with EPERM, so no browser DOM or interaction
pass is claimed. The Oct 10 adapter and SVG experiments below remain historical
measurements of their recorded baseline; they no longer describe the default
Standard 14 path.

## Historical native-host validation (2026-10-10)

Validated 2026-10-10 against a fresh release JS browser bridge, source
`a4db0d7` plus this native-host adapter. The bridge SHA-256 was
`064be16b07e44cf27928a237dc965e4c763eb0bd377d7e2cda48e95c8ec0f990`.
At that baseline, this closed the independent affine pen for capable native
hosts without changing A1 font mapping, glyph choice, text advance or source
selection.

### Public integration and font acquisition

`web/pdf-native-text.mjs` adapts the mature native host's
`convertSVGTextToPath` and serializable `Path2D` APIs. It converts the
**existing A1 SVG text primitive**, flattens the returned path matrices,
and returns page-space `fill_path` and graphics-pen-local `stroke_path` to
`renderPdfCanvas`'s optional `resolveTextOutline(svg, {paint, page})` hook.
The pen's retained width, CTM, dash, cap, join, miter and alpha are unchanged.
Successful resolution removes only that item's geometry diagnostic.
Type 3 charprocs are never sent through this adapter.

`tools/render_canvas.mjs` enables this adapter by default when its native
Canvas host offers these APIs. It uses the native host's installed or
already registered fonts and A1's existing family/style/weight selection.
There is no download, bundled font binary, test registration requirement,
PDF font decoding, new glyph mapper or font selection policy in the adapter.
The native host may substitute an installed fallback as it already does
when rasterizing SVG. The API does not expose the selected font identity,
so an exact requested-family match is not asserted merely from success.

The existing public A1 `set_font_fallbacks` family override remains usable.
A separate CLI process with **no font registration** rendered both the
normal `Nimbus Sans, Liberation Sans, Arial, sans-serif` list and an explicit
installed `Liberation Sans` override, with zero diagnostics and nonblank
output. The explicit family matched the registered control exactly; the
normal family list differed by MAE 1.159323 because its selected host font
was not constrained to the control. No particular platform's font inventory
is promised.

A missing host capability leaves `PDF_TEXT_STROKE_GEOMETRY` explicit.
Conversion errors, unsupported export structures, singular pen inverses,
oversized exports, and empty **non-whitespace** glyphs return `null`; they
do not silently certify blank output. A genuine serialized ASCII whitespace
glyph may resolve to empty paths. The real anisotropic stroked-space PDF
passes strict replay, paints nothing and retains its original source item.

The adapter accepts only flat exported SVG paths and matrix transforms,
not arbitrary SVG interpretation. It caches positive and negative results
by primitive plus pen matrix, with limits of 256 entries and 8 MiB of
conservatively accounted string storage. A 4,096-cell repeated-call test
performs one conversion. Create a resolver per render and keep the host
font configuration stable during that render; no font bytes are cached.

### Minimal valid PDF and controls

`tools/text_host_pen.mbtx` creates a **621-byte** unembedded Helvetica PDF,
SHA-256 `faf86fff67b17f2d78afcf5353341c85b5949e560a11c5271166432e5193a538`.
Its page is 240 by 160 points and its complete content is:

```text
q 1.1 .15 .2 .85 15 20 cm 3 w 0 J 0 j 4 M
BT /F1 60 Tf 1 Tr 2 .2 .4 .7 10 30 Tm (H) Tj ET Q
```

Both the graphics CTM and independent text matrix are anisotropic/sheared.
On that historical baseline, without the host callback, strict Canvas replay
reported the real missing geometry instead of certifying the scalar-width SVG
approximation. The current default Standard 14 path is validated separately
above; this historical failure now requires selecting the host branch.

For an exact shape oracle only, the harness registers the installed PDF.js
package's LiberationSans-Regular.ttf and selects that family through A1's
existing override. It generates a second PDF embedding those same bytes,
then renders its existing A1 TrueType outline pipeline unchanged. Font
SHA-256 is `f8ace1f892b2bd9dc1792ba7f097fa7588f84fed48321480e04de5390828221f`.
That font was external to the repository at this historical source baseline;
A1 `a22a190` subsequently added the licensed Standard 14 programs. A third
PDF replaces the text by the resolved H's explicit line contours and uses
the same raw graphics pen; independent Poppler and Ghostscript render it.

All eight viewports, scales 1/2 and rotations 0/90/180/270:

| Comparison | RGB MAE range (0–255) |
| --- | ---: |
| Native host vs same-font embedded A1 outline | **0.000000**, maximum difference 0 |
| Prior scalar-pen fallback vs same-font embedded outline | 2.085755–2.307552 |
| Native host vs explicit-path PDF / Poppler | 0.139427–0.276693 |
| Native host vs explicit-path PDF / Ghostscript | 0.287005–0.570234 |
| Legacy SVG / Resvg vs same-font embedded outline | 1.871914–1.927936 |
| Native host vs original Helvetica PDF / PDF.js | 2.013118–2.135417 |
| Native host vs original Helvetica PDF / Poppler | 6.100547–6.129688 |

The original unembedded-font references are retained honestly; their font
substitution and text rendering are not constrained to the same-font
control, and their larger residuals are not declared solved. The direct
path controls isolate geometry without relying on those choices. The
harness asserts exact same-font equality and a nonblank actual CLI result,
not an enlarged cross-renderer tolerance.

### Pen-local SVG alternative and browser boundary

A separate experiment rebases the **actual A1 text** into a pen-local SVG,
adds `vector-effect="non-scaling-stroke"`, rasterizes that separate image,
and applies the graphics CTM once in Canvas. This avoids the earlier nested
SVG-image limitation. It compares the same glyph's explicit local outline,
text with/without the vector effect, and its converted outline with the
vector effect. Native Canvas 1.0.10, Resvg 2.6.2, and installed librsvg/Cairo
were tested. No browser execution is inferred from these hosts.

| Host | Text NSS vs explicit path | Text NSS vs no NSS | Outline NSS vs explicit path |
| --- | ---: | ---: | ---: |
| Native SVG image loader | 173.222318 | **0** | 173.586641 |
| Resvg | 173.477109 | **0** | 173.477109 |
| librsvg/Cairo | 173.467266 | **0** | 0.000885 (maximum 1) |

The vector effect changes **zero pixels on actual text** in all three
hosts. librsvg's path support therefore does not establish text support.
The attribute is applicable to text in the
[SVG vector-effect specification](https://www.w3.org/TR/SVG2/coords.html#VectorEffectProperty),
but a specification is not an implementation test. The unverified SVG
strategy is not enabled automatically. Chromium could not execute because
socket creation was denied in this validation environment; this is an
evidence gap, not proof that browser text NSS fails.

On the Oct 10 baseline, `web/pdf-runtime.mjs` forwarded the optional outline
callback without importing native-only APIs. Its default Canvas path therefore
reported unresolved geometry for this minimal PDF unless a capable host
supplied that callback. The current default Standard 14 path no longer requires
it, but the host-only branch retains the same interface: either (1) an
outline of A1's already-selected SVG text in page and independent pen
coordinates, now expressible through `resolveTextOutline`, or (2) an
actually tested SVG text NSS raster interface in pen-local coordinates.
Ordinary `CanvasRenderingContext2D` text painting/metrics and A1's
family-only host fallback API do not provide glyph contours. No new browser
font renderer has been substituted to hide that boundary. Legacy standalone
SVG remains the explicit approximation described in [text strokes](text-strokes.md).

### Historical reproduction and checks

These commands and suite counts belong to the recorded Oct 10 source baseline,
not the merged tree. Use [the current Standard 14 recipe](standard14-pen.md#reproduction)
for default-path acceptance after A1 integration.

```sh
export MOON_HOME=/path/to/moon-toolchain
export PATH="$MOON_HOME/bin:$PATH"
export PDF_CANVAS_PACKAGE=/path/to/node/package.json
moon build --release --target js cmd/browser
mkdir -p _build/text-host-pen
cp _build/js/release/build/cmd/browser/browser.js _build/text-host-pen/browser.mjs
moon run tools/text_host_pen.mbtx _build/text-host-pen \
  /path/to/node/node_modules/pdfjs-dist/standard_fonts/LiberationSans-Regular.ttf
node --test tools/pixels/native_text_test.mjs
node tools/pixels/compare_text_host_pen.mjs \
  _build/text-host-pen/browser.mjs _build/text-host-pen
node tools/pixels/text_pen_nss_probe.mjs \
  _build/text-host-pen/public.canvas.json _build/text-host-pen/nss
PDF_VIEWER_BRIDGE=_build/text-host-pen/browser.mjs node tools/render_canvas.mjs \
  _build/text-host-pen/default.canvas.json _build/text-host-pen/default.png
```

The comparison tool writes every PNG, PDF control and JSON metric; the NSS
probe writes both candidate SVGs and actual host outputs. Ten adapter
regressions cover matrix rebasing, unsupported/missing capabilities,
errors, missing glyphs, valid whitespace, budgets and bounded caching.
`moon info && moon fmt`, full suites (JS 456, Wasm 457, Wasm-GC 457,
native 464), `moon check --target all`, JS syntax checks and
`git diff --check` passed on this source baseline.

## Current host-override warning regression

`tools/pixels/text_diagnostic_test.mjs` now deliberately selects the public
`set_font_fallbacks([{pdf_name: '/F1', family: 'Liberation Sans'}])` override
before rendering the unchanged 621-byte fixture. This distinguishes intentional
host text from the default bundled Standard 14 contours. It runs the shipped
`open_pdf` / `render_page` bridge and `web/pdf-runtime.mjs::renderPdfPage` with
**no** outline callback, verifies the requested host family, and checks that no
bundled `fill_path` or independent stroke outline silently replaces it.

Strict replay rejects `PDF_TEXT_STROKE_GEOMETRY`. The viewer's
`unsupported: 'warn'` policy paints a nonblank approximate preview and retains
the diagnostic's item index plus the human-readable message:
“Host font glyph outlines are unavailable; the affine text stroke is
approximate”. The source pen retains its machine-readable
`affine-text-pen-requires-glyph-outline` reason, and replay leaves the source
plan unchanged.

The test asserts that both full pages and thumbnails call the viewer's warning
function. It executes that exact function with a minimal element double and
checks that it unhides the `role="alert"` element and sets the warning text.
This verifies the runtime and visible-alert binding; it does **not** claim a
real DOM/browser session. The [Standard 14 regression](standard14-pen.md) also
checks that clearing the override invalidates the page cache and restores
strict, diagnostic-free bundled rendering.

```sh
moon run tools/text_host_pen.mbtx
PDF_CANVAS_PACKAGE=/absolute/path/to/canvas-host/package.json \
  node tools/pixels/text_diagnostic_test.mjs web/_generated/pdf.js
```

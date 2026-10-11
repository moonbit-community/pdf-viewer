# Invisible OCR lowering: actual-entry performance

## Scope

Non-Type3 text rendering mode 3 still creates every `PdfTextItem`, retaining its
source index, charcode, Unicode, advance, affine placement and selection quad.
It no longer requests an outline that cannot paint. The SVG fallback returns
without serializing invisible text, and Canvas omits those zero-paint entries.
Visible resolved glyph fragments also omit unused embedded `@font-face` data;
visible fallback text retains that data.

This changes graphics consumers, not A1 decoding, source mapping, glyph geometry,
font parsing or font caches. Type3 charproc lowering is left intact. Mode 7 still
resolves clipping geometry and applies the text clip to subsequent paint. No
public model/interface changes are required.

## Real PDF and stage evidence

Fixture: `JBIG2Globals.pdf`, recorded in `tools/jbig2/fixtures.json`; original
source is https://github.com/pdfminer/pdfminer.six/files/8399364/64.pdf .
SHA256: `19c9ab320b3effffd9d6761bd5eb377ea240346fc01f61474d89021953df28eb`.
The page has 7,012 invisible OCR glyphs, two painted images and three JBIG2 image
streams including the explicit mask. The large scan is 5188 × 6930 samples.

Before is `b05b874e521e64d43ed495316db8cd73504e175f`. Both before and after use
fresh `moon build --release --target js cmd/browser` output, actual `open_pdf`
and `render_page(1, 1, 0)`, and the registered Wasm JBIG2 decoder. Instrumentation
wraps generated JS functions without adding product logging. Times below are
single host runs, not a portable performance guarantee; nested timings are
inclusive and must not be added together.

| Actual bridge stage | Before | After |
| --- | ---: | ---: |
| Open PDF | 12.9 ms | 14.4 ms |
| Render page, including SVG/Canvas/text layer/JSON | 244.072 s | 3.818 s |
| Collect content operators | 121 ms | 141 ms |
| Lower collected page items | 242.317 s | 3.376 s |
| Type3 outline probe | 7,012 calls / 106.361 s | 0 calls |
| TrueType outline probe | 7,012 calls / 132.006 s | 0 calls |
| Font reader, nested in those probes | 14,024 calls / 213.097 s | 0 calls |
| Image-resource lowering | 3.082 s | 3.345 s |
| JBIG2 decode adapter | 270 ms | 227 ms |
| PNG encoding | 1.288 s | 1.426 s |
| Canvas plan serialization | 223 ms | 3.0 ms |
| Canvas paint entries | 7,014 | 2 |
| Response length, UTF-16 code units | 26,721,341 | 3,822,356 |
| Final process RSS | 1,198 MiB | 474 MiB |

The first actual-entry run improves **63.9×**. A second baseline run took
253.822 seconds and confirmed source retention below. This bottleneck was
pre-existing invisible outline probing: the new affine text-stroke function
already returns immediately for mode 3. General visible-text font caching remains
an A1 concern; this patch does not change it.

## Correctness and remaining pixel difference

- Complete before/after text-layer JSON is byte-identical: 7,012 entries, SHA256
  `77822e58995fe96b700864ab595ac2a5ca15f3449cad9aaf13430a58ce7bae1f`.
- Both non-text Canvas paint entries are structurally identical before/after,
  including resource data, placement, graphics state and masks.
- A control copied from the original page with **all text operators removed**
  retains its exact 622.559998 × 831.600037 page, image transforms and alpha.
  It renders in 3.306 seconds. Native Canvas output at 623 × 832 is byte-identical
  to the optimized original, including alpha. The control SHA256 is
  `657b96af4ecb36e839f0ded182aacfc4d85ab1336a3df83d53f32d0ccf4efd67`.
- An earlier codec-only no-text control changes page dimensions and image
  placement/alpha. It is useful for decode timing, not pixel-equivalence evidence.
- Whole-page reference differences remain: native Canvas RGB MAE is 20.8184
  against Poppler and 26.4826 against PDF.js 6.4.299 (with its `wasmUrl` configured).
  This performance fix does **not** claim image pixel acceptance or change image
  sampling. The original and its exact no-text control expose the same residual.

Five focused tests cover retained source/selection/search, mixed invisible and
visible text, unchanged Type3 lowering, mode-7 clips, and embedded-font payload
omission only for resolved outlines. Full suites pass: JS 365, Wasm 366,
Wasm-GC 366, native 373. `moon check --target all`, `moon info`, `moon fmt`,
`node --check tools/pixels/profile_text_lowering.mjs`, and `git diff --check` pass.
Unrelated pre-existing formatting changes from `moon fmt` were not retained.

## Reproduce

```sh
moon build --release --target js cmd/browser
PDF_PROFILE_RENDER=1 node tools/pixels/profile_text_lowering.mjs \
  _build/js/release/build/cmd/browser/browser.js \
  /path/to/JBIG2Globals.pdf _build/invisible-profile.json
```

The profiler emits inclusive stage counters, RSS samples, source-layer count and
hash, and the actual generated-bridge hash. `PDF_PROFILE_RENDER=1` additionally
saves the full rendered response for independent Canvas/SVG comparisons. It
creates a sibling `.profile.mjs` of the input bundle; use an ignored build path.
If MoonBit changes generated symbol naming, the profiler fails rather than
silently claiming an uninstrumented result.

For the exact image-only control, preserve the page and resources with `pypdf`
and remove text operators, not just naive `BT`…`ET` spans:

```python
from pypdf import PdfReader, PdfWriter
from pypdf.generic import ContentStream
reader = PdfReader("JBIG2Globals.pdf")
writer = PdfWriter()
writer.add_page(reader.pages[0])
page = writer.pages[0]
stream = ContentStream(page.get_contents(), writer)
text_ops = set(b"BT ET Tc Tw Tz TL Tf Tr Ts Td TD Tm T* Tj TJ".split()) | {b"'", b'"'}
stream.operations = [(args, op) for args, op in stream.operations if op not in text_ops]
page.replace_contents(stream)
with open("exact-no-text.pdf", "wb") as output:
    writer.write(output)
```

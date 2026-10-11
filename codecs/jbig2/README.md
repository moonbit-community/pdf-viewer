# JBIG2 samples adapter

`decode(data : Bytes, globals : Bytes?, width : Int, height : Int) -> Bytes?`
returns tightly packed, row-aligned, MSB-first, one-bit PDF luminance. Row stride
is `(width + 7) / 8`, with `0` black and `1` white. Padding bits are unspecified.
No colour conversion, `/Decode`, colour-key mask, ImageMask inversion, SMask,
Matte, or external alpha is applied here. The root wrapper remains
`pdf_jbig2_samples` so the existing image pipeline owns these operations.
`None` means unsupported/unavailable, malformed or a configured resource limit.

## Targets and integration

| Target | Actual support | Setup |
| --- | --- | --- |
| MoonBit JS in browser/Node | Tested, standalone PDFium Wasm decoder | Prepare the locked npm assets below. The shipped viewer awaits `initializePdfGraphics()`; direct codec consumers await `installJbig2Decoder()` from `decoder.mjs` |
| MoonBit native, Linux | Tested, vendored standalone PDFium C++20 | Installed `g++`, final executable/test link includes `-lstdc++` |
| Native macOS/Windows | Not implemented/tested | Native bridge deliberately returns failure without Linux process isolation |
| MoonBit wasm / wasm-gc | Typecheck only, returns `None` | No codec host-import bridge registered |

The use of a Wasm binary inside the JS backend does **not** implement the
MoonBit wasm/wasm-gc targets. A future host bridge can pass bounded byte chunks
through an imported opaque request handle (`begin`, `write`, `decode`, `read`,
`close`) to the same JS decoder. That also requires the consuming Wasm loader
to provide these imports; Moonrun does not supply them. No renderer replacement
is needed, and this is a remaining integration task rather than a proven
platform impossibility.

Root `moon.pkg` imports `moonbit-community/pdf-viewer/codecs/jbig2` as `jbig2`.
Native final-link packages, including root tests and `cmd/main`, need:

```text
options(link: { "native": { "cc-link-flags": "-lstdc++" } })
```

This package's `native-stub` build already selects C++20 and builds the exact
vendored dependency closure. It does not need a shared library installation,
PDFium SDK, network during build, or environment variable at run time. Source
includes are relative, so the stub works from another consuming module too.

The browser/Node Wasm asset is acquired from locked `pdfjs-dist@6.4.299`,
not stored in Git. From the repository root:

```sh
npm ci --prefix tools/web-assets --ignore-scripts --omit=optional
node tools/prepare_web_assets.mjs
```

Preparation verifies the pinned version and asset SHA-256, then copies
`wasm/jbig2.wasm` to the ignored `vendor/jbig2/jbig2.wasm` path used by Node
tests. `moon run tools/build_web.mbtx` invokes preparation and copies this asset,
`codecs/jbig2/decoder.mjs` and the tracked license notices into
`web/vendor/jbig2/`, preserving the same-origin relative layout. It does not
install npm dependencies automatically. No PDF.js renderer is loaded.
The initializer also accepts `{ wasmUrl }`; Node tests pass `{ wasmBytes }`.
Keep the vendor license files with redistributed assets. A missing/uninitialized
host fails explicitly. Native C++ sources remain tracked and do not need this
npm asset setup for native decoding.

## Limits and malformed input

Both bridges cap external dimensions at 32,768, pixels at 64 Mi, compressed page
plus globals at 16 MiB, output at 8 MiB, framing at 4,096 segments and 65,536
references, and aggregate region area at 256 Mi pixels. Sequential embedded
segments and file headers are supported; random-access files, multiple pages,
and unknown-length segments deliberately fail. Striped unknown page height can
use the PDF height. A bounded codec page width differing from PDF width is
allowed because real scanning PDFs can have padding columns.

JS additionally preflights symbol/text/pattern counts and caps the decoder's
linear heap at 128 MiB, with output callbacks checked before allocating. Every
decode gets a fresh instance and fresh output. This bounds allocation and avoids
stale-image/poisoned-state recovery. **The synchronous JS path has no hard
wall-clock interrupt**. Its malformed mutation suite runs in an externally
terminated worker; this test deadline is not a production timeout. A browser
worker around the calling renderer/decoder is needed for strict cancellation.

Linux native decodes in a short-lived child process with a 2-second CPU limit,
a 2.5-second parent-enforced wall timeout, no core dumps, and at most 128 MiB of
additional virtual address space above its inherited parent baseline. Packed
output uses a shared mapping and is copied only after successful exit. Native
OOM, abort and excessive entropy work cannot terminate the MoonBit parent.
Native resource limits can reject a valid exceptionally slow image. Process
creation must be available in the host sandbox. Other native platforms are not
silently run without equivalent isolation.

## Verification (2026-10-10)

- 8 JS unit tests: packed stride/polarity, clipping, file headers, dimension/input/
  heap limits, truncation, unknown lengths, duplicates, regions/symbol counts,
  stale-output recovery and host registration.
- Actual compiled MoonBit JS FFI probe: 10/10 real fixture hashes match after
  host installation; missing and malformed hosts map to MoonBit `None`.
- 2 native MoonBit package tests: real FFI, packed white/black, clipping,
  malformed/oversized input and subsequent recovery.
- 10 real encoded image streams from 8 PDFs: arithmetic and Huffman symbols/text,
  MMR, generic/refinement, halftone, compositing, file headers, separate globals,
  and a real 5188x6930 scanning image. All sample SHA-256 values match across the
  native and JS adapters. Nine rendered-image/packed-image comparisons against
  PDF.js 6.4.299's independent asm.js host path have zero differing bytes,
  including the scan and an explicit ImageMask `/Decode [0 1]` RGBA check.
- 2,000 deterministic truncated/mutated/random JS cases: 758 accepted, 1,242
  rejected, 477 ms total, maximum observed case 4.87 ms. Outer worker deadline
  10 seconds. Acceptance is permitted tolerant decoding, not proof of validity.
- Scan: JS cold 221 ms / warm median 211 ms, peak Wasm linear heap 17,891,328 B,
  one 4,497,570 B JS packed-output allocation; native median 162 ms including
  process isolation. Largest child RSS observed across native corpus: 28,292 KiB.
  These are observed isolated-codec figures, not full viewer peak memory.
- Native crafted huge-dictionary case rejected in 1.42 ms; next valid decode
  succeeds. Native corpus byte comparisons all exact.

The historical source/binary adapter bundle was about 0.8 MB raw / 0.18 MB gzip
before package documentation; that figure predates npm/build-copy delivery.
The browser needs only the roughly 102 KiB Wasm binary and 12 KiB adapter. Exact bytes/hashes and per-case timings are in the manifests
and `tools/jbig2/validation-results.json`.

Run from the repository root after the npm asset preparation above:

```sh
python tools/jbig2/prepare-fixtures.py _build/jbig2-fixtures
node --test tools/jbig2/decoder.test.mjs
node tools/jbig2/corpus.mjs _build/jbig2-fixtures <pdfjs-oracle-node_modules>
node tools/jbig2/fuzz.mjs _build/jbig2-fixtures/bitmap-mmr-5.jbig2
sh tools/jbig2/build-native.sh _build/jbig2-native.so
python tools/jbig2/native-corpus.py ./_build/jbig2-native.so _build/jbig2-fixtures
moon test -p moonbit-community/pdf-viewer/codecs/jbig2 --target native
moon build tools/jbig2/probe --target js
node tools/jbig2/moonbit-host.mjs _build/js/debug/build/tools/jbig2/probe/probe.js _build/jbig2-fixtures
```

Oracle node_modules needs pinned `pdfjs-dist@6.4.299` and `@napi-rs/canvas`.
Fixture preparation needs Python `pypdf`. PDF binaries are downloaded into an
ignored cache, hash-verified and not redistributed here. These codec-stage
counts and timings remain separate from the integrated viewer evidence below.

## Integrated image and shipped-entry acceptance

The dispatcher, native CLI, build-time browser asset copying and runtime host
initialization are now connected. Encoded masks and original Decode feed the
shared image pipeline; unsupported targets and strict synchronous-JS cancellation
remain the explicit limits in the target/limits sections above.

The original `JBIG2Globals.pdf` now runs through the actual release `cmd/browser`
bridge and `web/pdf-runtime.mjs`, preserving all 7,012 text-layer items. Its packed
5188x6930 scan is coverage-reduced to 2594x3465 before RGB allocation; the Canvas
replay uses bounded iterative minification. The final 623x832 page has maximum
pixel difference 1 and zero pixels above 8 against PDF.js, with no runtime
diagnostics. Observed bridge time was 2.604 seconds, 2.923 seconds including
Canvas, and end process RSS 547,958,784 bytes. Those are whole-entry observations,
not replacements for the isolated-codec measurements or hard memory ceilings.

See [image/entry evidence](../../docs/validation/image-sampling.md),
[exact shipped-entry results](../../tools/image-shipped-entry-results.json), and
[the image limits/alpha contract](../../docs/jpeg-decoder.md). The complete image
manifest includes explicit-mask and source-plane evidence separately from page
sampling differences. Current aggregate verification belongs to the
[A2 acceptance record](../../docs/a2-acceptance.md), rather than a historical
codec-stage suite total. Entry rendering uses a native Node Canvas host and is
not a DOM browser test. The
[fresh-checkout native setup](../../docs/validation/native-canvas-setup.md)
documents the public native plan-to-PNG path and its build prerequisites.

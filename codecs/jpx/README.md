# JPEG2000/JPX PDF adapter

Public API: `decode(Bytes, smask_in_data?=0, use_embedded_colour?=true,
limits?=default_limits()) -> Result[Samples,String]`.

`Samples.bytes` contains row-aligned, interleaved, unsigned, MSB-first integer
samples. Uniform colour precision is preserved for **every depth 1–16**, including
12-bit values and per-row padding. 16-bit output is big-endian. The upstream's
component planes are little-endian; signed values are normalized once to their
unsigned PDF range. Components may be subsampled; expansion follows their
reference-grid steps and origins. JPEG2000 MCT is already reversed by the codec.

`embedded_alpha` is a separate packed opacity plane with its own bits/stride;
0 is transparent. `/SMaskInData 0` ignores container alpha; 1 retains straight
opacity; 2 sets `embedded_alpha_associated` so the image pipeline unassociates
exactly once before PDF colour conversion. CDEF determines channel ordering.
The adapter never applies PDF `/Decode`, colour-key, external masks or Matte.

For a missing PDF `/ColorSpace`, JP2 `colr` supplies Gray/RGB/CMYK/sYCC, and sYCC
conversion matches the standalone OpenJPEG oracle. Palette/CMAP expansion precedes
channel interpretation. Embedded ICC bytes are returned as `embedded_icc_profile`
for the shared colour engine. If a PDF colour space exists, pass
`use_embedded_colour=false` so JP2 colour/ICC does not override it.

## Runtime matrix

The same pure MoonBit implementation runs on native, JavaScript, Wasm and
Wasm-GC. There is no native codec SDK prerequisite. JPEG2000 handling does not
rely on the JBIG2 or ICC host modules. ICC profile conversion is separate and
inherits the colour engine's actual target support.

## Bounds and explicit unsupported inputs

Before entropy decoding: input <=32 MiB, image <=4,194,304 pixels, total raw or
palette-expanded samples <=8,388,608, components <=32, tiles <=1024, quality
layers <=128, decomposition <=10, no precinct smaller than 8x8, and checked box,
marker and tile-part extents. Palette entries <=4096; embedded ICC <=4 MiB.
The public `Limits` can tighten budgets. No dimension multiplication is used
before its product is checked against the default budget.

Mixed colour precision, multiple/per-colour alpha, multiple codestreams and
unsupported upstream coding profiles return descriptive errors. Very small
precincts deliberately fail the synchronous work budget. The reused decoder
has partial HTJ2K coverage, not a claim of full JPEG2000 Part 15 support.
The adapter does not guarantee a wall-clock deadline for adversarial entropy
payloads; a host worker/process deadline is required for strict cancellation.

## Tests and measured performance

35 focused cases include all-prefix truncation, overflow/zero dimensions,
resource budgets, Gray/RGB/RGBA, reversible/irreversible MCT, tiles, wavelets,
uniform 1/2/3/4/7/8/9/12/15/16-bit and signed12/16-bit, subsampling, palette,
sYCC, embedded ICC handoff and the pinned PDF.js fixtures below. Full sample
buffers and alpha are asserted, not merely decode-success or first pixels.

- `bug_jpx.pdf`, object15: 128x64 Gray; repeated/empty tile-parts
- `jp2k-resetprob.pdf`, object6: 40x27 RGB, byte-exact with PDF.js/OpenJPEG
- `jpx_smaskindata.pdf`, objects5–8: exact colour and alpha, including missing
  PDF colour space and both SMaskInData 1/2

Reference revision: `mozilla/pdf.js@89b500f5e1d98ed89bb90211e45b28730b2d99ac`.
Reference standalone decoder: installed `pdfjs-dist@6.4.299` OpenJPEG module.
Extracted bytes are embedded in `samples_test.mbt`, under upstream Apache-2.0
attribution. Generated fixtures are original test data made with OpenJPEG via
Pillow or the small `tools/jpx/make_components.c` fixture encoder.

Observed Linux native 1024x768 RGB, 2,359,296 decoded bytes, exact OpenJPEG match:
- Debug: 25.116 s, observed peak RSS 43,458,560 bytes
- Release: 9.360 s, observed peak RSS 51,281,920 bytes

This reveals a real upstream throughput limitation. Memory is bounded at this
size, but this synchronous path should not be presented as interactive large-
image performance. Small 32x24 fixtures took 14–63 ms in the debug executable.
RSS is sampled every 2 ms; it is an observation, not a hard allocation ceiling.

Reproduce (Pillow with OpenJPEG; optional psutil for RSS):

```
moon test --target js -p codecs/jpx
moon test --target native -p codecs/jpx
moon test --target wasm -p codecs/jpx
moon test --target wasm-gc -p codecs/jpx
moon run tools/jpx_measure.mbtx
moon run tools/jpx_samples.mbtx -- input.jp2 output.raw 2
```

The precision fixture encoder accepts output path, bit depth, signed flag and subsample flag.
Build it against an official OpenJPEG development package. It is only a fixture
producer, not a runtime dependency.

Deterministic mutation smoke test (seed 31402, 250 one-to-three bit mutations of
the tiny RGB fixture): 86 accepted, 164 descriptive rejections, 0 crashes, 0 cases
reaching the external 2 s subprocess timeout; 0.478 s aggregate. This is limited
coverage, not a security certification. Reproduce with `tools/jpx/fuzz.py`.

The 35 focused JPX tests pass on native, JavaScript, Wasm and Wasm-GC.
The reused upstream sources retain deprecation/unused-code warnings under this
toolchain. Current integrated checks are recorded in the
[A2 acceptance record](../../docs/a2-acceptance.md); an earlier codec-stage
aggregate test count is not a current whole-project total.

## Integrated image and shipped-entry acceptance

The image dispatcher now consumes these original samples, applies PDF Decode,
colour-key, embedded/external masks and Matte, and registers source ICC profiles
with the shared colour engine. This is exercised beyond the standalone codec:

- All four real `jpx_smaskindata.pdf` RGBA resources match the independent
  sample oracle exactly, with embedded alpha applied once.
- Through the actual release `cmd/browser` bridge and `web/pdf-runtime.mjs`,
  that original 140x40 page is byte-exact against PDF.js, with no runtime
  diagnostics (79.6 ms observed including Canvas on the validation host).
- `bug_jpx.pdf` and `jp2k-resetprob.pdf` retain their separately recorded raw
  sample and image-resource checks.

See [image sampling/entry evidence](../../docs/validation/image-sampling.md),
[exact shipped-entry results](../../tools/image-shipped-entry-results.json), and
[the image sample/alpha contract](../../docs/jpeg-decoder.md).
The entry check uses a native Node Canvas host, not a DOM browser. It does not
supersede the 9.360-second 1024x768 release decode measurement above, establish
large-image interactivity, or add ICC/cancellation support to unavailable targets.
For the public native plan-to-PNG path, use the
[fresh-checkout setup](../../docs/validation/native-canvas-setup.md).

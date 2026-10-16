# Encoded image samples and JPEG alpha

## Reuse and ownership

The JPEG baseline/Huffman/IDCT implementation in `image_jpeg_decoder.mbt`
and `image_jpeg_idct.mbt` is adapted from **mizchi/image 0.4.3**,
`src/jpeg_decode.mbt` and the zigzag constant from `src/jpeg_tables.mbt`,
released under Apache-2.0:
<https://github.com/mizchi/image-mbt>.
The upstream module is fetched from Mooncakes for inspection; it is not a runtime
dependency. Its public RGBA-only result cannot retain the component samples that
PDF `/Decode`, colour-key ranges, calibrated colour spaces and CMYK need.

The focused progressive AC successive-approximation state machine in
`image_jpeg_progressive.mbt` is adapted from Mozilla PDF.js `src/core/jpg.js`,
Copyright 2014 Mozilla Foundation, Apache-2.0, pinned revision
`89b500f5e1d98ed89bb90211e45b28730b2d99ac`. PDF.js documents the earlier
notmasteryet/jpgjs origin. The repository's Apache-2.0 LICENSE applies.
The paused parser draft was not used.

Changes to the candidate include component output, CMYK/YCCK, PDF ColorTransform
and Adobe precedence, restart resets, noninterleaved/progressive scan decoding,
strict segment/table/index validation, bounded allocation, DC-only IDCT shortcut,
sparse separable IDCT with decode-owned scratch, hoisted three-component sampling,
rounding, and byte-sized component planes. Unsupported features retain the
existing encoded-resource fallback; budget violations are rejected rather than
handed to a browser decoder that could bypass the same limit.

For JS, three-component sample rows use a clamped byte view over the fresh
output buffer. This preserves the original YCbCr expressions and their
evaluation order while delegating saturation and ties-to-even rounding to the
host. Geometry and the last sampled offset in each padded plane are checked
before entering the native loop. Other targets use the original scalar rows.
An exhaustive JS test compares all 16,777,216 8-bit YCbCr tuples with the scalar
converter; existing sampling tests include non-dividing factors and partial
MCUs. The IDCT validates its fixed block/scratch sizes once before bounded
unchecked indexing, preserving accumulation order and dense-reference rounding.

## Sample contract

`PdfImageDecodedSamples` contains width, height, components, bits, explicit
`row_bytes`, and interleaved packed samples. Rows are byte-aligned, bit order is
MSB-first, and 16-bit values are big-endian. Encoded adapters may return uniform
1–16-bit samples; raw PDF images retain their 1/2/4/8/16-bit rules. No PDF Decode,
colour-key alpha, external soft mask or Matte has been applied at this boundary.
JPEG's coding-space YCbCr/YCCK transform happens before this boundary, yielding
Gray, RGB or CMYK components, never an unlabelled RGB conversion.

Optional embedded alpha is a separate plane with its own precision and stride.
Associated samples are unassociated once in sample space before conversion.
External mask samples never pass through a colour-space gamma transform. The
existing colour path handles PDF Decode, colour-key tests on original integer
samples, colour conversion, nearest-neighbour mask resize and Matte removal.
Its integrated PNG has straight RGBA, and the resource does not carry a second
alpha mask. Encoded grayscale mask fallbacks and encoded one-bit stencils use the
same sample reader, preserving Decode and stencil inversion.

## Supported JPEG branches

Pure MoonBit decoding is available on native, JS, Wasm and Wasm-GC:

- 8-bit sequential baseline, extended sequential and progressive Huffman DCT
- One, three and four components; Gray/RGB/CMYK and YCbCr/YCCK coding transforms
- Interleaved and noninterleaved scans; restart markers and predictor resets
- Sampling factors 1–4, including tested 4:4:4, 4:2:2 and 4:2:0
- PDF ColorTransform, Adobe APP14 precedence and explicit RGB component IDs
- PDF Decode, grayscale encoded SMask, original-component colour-key, Matte

Arithmetic coding, lossless JPEG and non-8-bit DCT are not claimed. Malformed
entropy/metadata and truncated input fail boundedly. Interleaved baseline and
progressive share colour/sample semantics while baseline avoids allocating full
coefficient planes. Noninterleaved sequential uses the multiscan path.

## Resource policy and remaining scope

Dimensions, multiplication, row stride and plane size are checked before the
viewer-owned allocations. JPEG limits are 16,777,216 pixels, 65,535 per side,
64 MiB input/sample planes and at most 256 MiB of progressive coefficient
storage. Scan count is bounded to 128. RGBA scanlines use one byte per channel
rather than an Int per channel; the filter byte adds one byte per row.
The real 12.75M-pixel issue13931 native debug export used 148,668 KiB peak RSS
and 14.08 seconds wall time on the validation host (a measurement, not a
performance promise). Bounded preceding filters, packed-source resizing and
resource diagnostics are described below.

These per-image limits do not bound aggregate document caches or host rendering
allocations. Unsupported JPEG variants can still use the encoded browser
fallback with an explicit warning, but that fallback does not promise
component-correct Matte. Total-document memory policy, colour-key raster edges
and compositor acceptance remain separately tracked. This change alone does
not complete I-01, I-02 or all of I-04.

## Validation

The self-contained `image_jpeg_wbtest.mbt` fixtures are original deterministic
17×13 Pillow/libjpeg-turbo patterns at quality 87, with PDF.js 6.4.299 sample
oracles. They cover baseline/progressive, subsampling, direct RGB, Gray, CMYK,
and baseline/progressive restarts. Per-channel decoder error is bounded to 3 and
mean absolute error to 1 without hiding any pixels. `image_encoded_wbtest.mbt`
additionally tests the actual PDF reader/resource/PNG path, Decode/ColorTransform,
colour-key, progressive SMask+Matte, CMYK, associated alpha, packed 12-bit samples,
all prefix truncations of three JPEG variants, malformed headers, allocation
limits and the exact 256-entry transfer table.

`issue13931.pdf` comes from the pinned PDF.js corpus. Its full 2996×4256 image
plane has 12,750,976 exact alpha samples and zero composited RGB pixels differing
by more than 8 from PDF.js. Unassociated RGB has 1,324 >8 differences only at low
alpha; mean absolute RGB difference across the plane is 0.00286. Source-image
acceptance must not be conflated with full-page fidelity: the scale 1 page
comparison still has 11,427/501,832 pixels above 8 versus 11,569 before, with
existing text/layout/rasterizer differences. Full-page MAE changes 1.319→1.156.

Reproduce the actual JS resource and source-image oracle (dependencies must be
installed separately):

```sh
moon run tools/jpeg_alpha.mbtx path/to/issue13931.pdf _build/jpeg-alpha path/to/node_modules
```

The tool writes the integrated PNG, viewer SVG, diagnostic page PNGs and a JSON
report. It requires exactly one RGBA XObject and one integrated PNG, failing
instead of skipping unsupported fixture structure. Canvas readback may round
unassociated low-alpha RGB, so that tool compares on a white backdrop and lists
alpha mismatch separately. The development raw-plane comparison decoded the PNG
without premultiplying and additionally measured the RGB statistics above.

## Follow-through: bounded filters and codec consumers

`image_limits.mbt` bounds preceding filters: the existing
`moonbit-community/flate@0.8.1` streaming zlib engine now checks the caller's
shape-derived output budget before appending output. LZW, RunLength and ASCII85
use length-only preflight checks before their existing pdflite decoder; CCITT
receives a bounded row count. Intermediate filter stages cap at 64 MiB, filter
chains at 32 stages, and predictor dimensions are checked before use. An optional
smaller `max_output` also permits a 16 MiB ICC-profile boundary. Failures retain
a `PdfImageResource.error` string rather than disappearing silently. Unsupported
encoded fallback resources carry an explicit warning.

Packed-source and RGB-surface limits are now separate. A uniformly packed image
may have up to 64M pixels subject to a 64 MiB sample-plane limit; before any RGB
allocation, output is reduced to at most 16M pixels and 16,384 per side. Unmasked
1-bit DeviceGray scans preserve coverage over power-of-two source cells; other
sample/colour-key/mask cases retain the existing floor-nearest sample rule. JPEG retains its narrower codec allocation
bound; the JPX adapter retains its own explicit entropy/coefficient limits.
Aggregate document/page caches remain the host's responsibility.

The JPX/JBIG2 dispatcher consumes the codec workstream's actual sample APIs:

- `jpx_smaskindata.pdf`: all four final 2×1 RGBA PNG resources are byte-exact
  against PDF.js, including associated alpha and `/SMaskInData` 1/2; no second
  mask remains on the resources. Additional tests distinguish nontrivial
  associated `/Matte` removal from simply dividing by alpha.
- `jp2k-resetprob.pdf`: final 40×27 RGB samples are byte-exact.
- `bug_jpx.pdf`: final 128×64 RGB samples and the 612×792 full-page Node/resvg
  raster are byte-exact.
- `JBIG2Globals.pdf`: actual native page output has no `image/jbig2` resources.
  The 5188×6930 packed scan now reduces by coverage to 2594×3465 before RGB
  allocation. With iterative Canvas sampling, the complete page matches PDF.js
  within one byte, MAE 0.00220 and zero pixels above 8. The earlier nearest-only
  3543×4733 reduction was byte-correct under its floor rule but lost thin strokes.
  Its 1034×204 explicit-ImageMask resource is byte-exact final RGBA. Native
  regressions cover both an explicit mask with reverse Decode and a standalone
  decoded stencil.
- ICC `version4pdf.pdf`, from <https://www.color.org/version4pdf.pdf>: native
  JPEG/ICCBased conversion produces the intended consistent four-quadrant image
  shown as the document's version 2 + version 4 success example. Poppler confirms
  the intended colours. The Node PDF.js run used for other tests has no working
  ICC backend and produces this document's illustrated green/purple failure
  example; those differences cannot be treated as a viewer regression or as
  an ICC pixel-fidelity pass. Remaining Poppler/page raster differences are
  retained rather than widening tolerance.

The exact tiny JPX source images still differ in resvg's page interpolation:
1,680/5,600 pixels exceed 8 on `jpx_smaskindata.pdf` despite byte-exact RGBA.
The SVG declares `image-rendering="crisp-edges"`; resvg smooths this case.
Changing only that attribute to resvg's `optimizeSpeed` produces zero differing
pixels, isolating the discrepancy to the rasterizer's sampling behavior.
A real Chromium check was attempted, including an approved escalated launch,
but the execution environment denied the browser's socket creation. Browser
sampling therefore remains unverified in this environment; it is not called
pixel-exact based on source-image agreement alone.

## Opt-in subtractive source planes

When the collector requests `retain_ink_samples`, image resources also carry
`PdfImageInkSamples`: normalized, interleaved big-endian 16-bit components,
a separate straight 8-bit opacity plane, dimensions/stride and source colour
metadata. Values come from the same entropy decode and resize pass as the PNG,
after PDF Decode, embedded unassociation and external Matte removal in the
source component space. They are not reconstructed from display RGB.
Ordinary RGB page collection leaves the field absent and allocates no extra
planes. The combined component and opacity byte buffers are limited to 64 MiB;
opt-in large images are resized before allocation. Base64 serialization adds
its explicit 4/3 representation overhead and belongs in host cache accounting.

Retained device RGB is converted directly to process CMYK with the active
compiled BG/UCR functions; device Gray becomes the K plane. The
`process_cmyk` flag identifies that representation while `source_colour.space`
keeps the original colour-space identity, including the sampled-image OPM
semantics. Direct CMYK is never subjected to BG/UCR again. The active rendering
intent is passed to both declared and embedded ICC transforms.

Final raw Flate images without predictors consume a bounded image-sized prefix,
matching PDF.js's requested-length image read; trailing unused samples need not
be expanded. This matters for `issue17147.pdf`, whose 1-bit stencil contains
24 times the declared sample length. Preceding encoded filters and profile
streams still reject expansion beyond their full-output limits. The legacy
image extractor receives the bounded, already-filtered stream, so a fallback
cannot accidentally decompress the original stream again without the limit.

Actual ICC target groups set `convert_ink_to_device_cmyk=false` and retain
original source channels instead of preconverting device RGB. Source ICC data
is registered once in the bounded page profile catalog via `resource_context`;
ink metadata carries its profile ID and component ranges. Embedded JPX ICC
uses the same byte-registration path only when the PDF has no overriding
ColourSpace, and remains ICC source data rather than inferred DeviceRGB.

## Whole-page performance attribution

`tools/image_stages.mbtx` instruments a release module only in its output
directory. It records inclusive function timings, codec calls, memory samples
and fixture SHA-256, without adding logging to product code:

```sh
moon run tools/image_stages.mbtx input.pdf _build/image-stages
```

On `JBIG2Globals.pdf`, the original page took 253.94 seconds: all three codec
calls plus the FFI boundary took 239 ms, two image resources 2.983 seconds,
PNG creation 1.219 seconds (Flate 1.158 seconds), base64 55 ms, content-op
collection 152 ms, font-resource lookup 6 ms and SVG serialization 20 ms.
Page item lowering took 253.56 seconds. A controlled PDF containing the same
three encoded streams, globals and image dimensions without OCR took 3.43
seconds, demonstrating that the large remaining cost is outside image decode
and assembly. The non-image lowering issue is tracked by the text workstream.
Original end RSS was 862.6 MiB; the no-text control's sampled peak was 318.6 MiB.
These are measured process figures, not a promised per-document bound.

JS image decoding is synchronous and cannot honor an AbortSignal mid-decode;
a worker boundary is required for hard production cancellation. Codec framing,
work and heap limits remain active. Native JBIG2 has a separate short-lived
process with CPU, wall-clock and address-space limits (see its codec README).

## Retained tint and calibrated source components

Retained image samples evaluate Indexed palettes and Separation/DeviceN tint
functions per pixel, after source Decode, associated-alpha removal and Matte.
The compiled image transform is reused; a zero-tint alternate is never used
for a whole bitmap. ICC terminal spaces keep their page profile ID and original
channels. `/None` no-paint and `/All` registration metadata survive terminal
conversion. This is display/process-group data, not a physical spot-plate proof.

CalGray/CalRGB terminals are retained as D50 `PCSXYZ`. Their three signed XYZ
ranges are calculated by the colour subsystem and serialized explicitly;
16-bit transport normalizes against those ranges, not an assumed unit cube.
Tests cover per-pixel Separation and DeviceN, Indexed CMYK, no-paint semantics,
and calibrated negative/out-of-unit XYZ reconstruction. The full local matrix
passes: native 333, JS 325, Wasm 326 and WasmGC 326 tests; `moon check --target
all` also passes. This slice depends on the calibrated PCS colour API.

`tools/image-validation-results.json` records the ten image-case manifest
runs with fixture hashes and final source-plane checks. Its page numbers are
SVG/resvg diagnostics, explicitly not Canvas/Chromium acceptance.

## Bounded binary scan coverage

Oversized unmasked DeviceGray 1-bit images use power-of-two coverage cells
before their first RGB allocation. Decode still applies after coverage; reversed
Decode and retained CMYK K-plane values are tested. Row padding is ignored and
partial edge cells use their actual sample count. Images with explicit/colour-key
masks, SMask, embedded alpha or colour profiles keep the original sample-domain
path, so averaging cannot corrupt integer colour-key tests or alpha semantics.

The actual JBIG2 exact-page no-text derivative converts in 2.218 seconds with
276.8 MiB end RSS on this host; it retains the original image CTMs and opacity.
Its generated main image is replayed in the original plan with all text-layer
items, producing the same within-one-byte complete-page result. Coverage tests
and the full matrix pass: native 337, JS 329, Wasm and WasmGC 330 tests each.

## Indexed DeviceN regression from the real printing page

Altona `/Im16` and `/Im36` are Indexed over a five-colorant DeviceN base with
a four-component CMYK alternate. pdflite's Indexed reader had used the alternate
arity, consuming four bytes per palette entry instead of five. The shared colour
reader now resolves Indexed first using the original base arity and a bounded
lookup-stream decode. Image retention correctly rejects an invalid tint arity
instead of silently rendering a constant alternate.

The image regression uses original arithmetic five-input sampled functions and
both string/stream palettes, with distinct first/fifth inputs. It checks exact
terminal CMYK bytes and distinct PNG colours. All 15 image-ink tests pass on
native, JS, Wasm and WasmGC with colour reader commit `d86b979`.

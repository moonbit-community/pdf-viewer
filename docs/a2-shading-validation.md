# A2 H-03 shading validation (2026-10-10)

## Implemented path

`shading.mbt` owns the shading-only resource reader formerly in
`pdf-viewer.mbt`. `mesh.mbt` now preserves the source components of type 4/5
vertices and the four source colour corners of type 6/7 patches, together
with their original geometry. Coons boundaries are converted to bicubic
tensor controls. Flags 1/2/3 reuse both geometry and unconverted components.
Type 4 byte alignment and type 5 bit-contiguous records have regressions.

`PdfShadingResource.raster` contains a bounded colour lookup, source triangles,
and unflattened patches. Function inputs/components are interpolated before
lookup. Lookup generation uses the shared `pdf_colour_eval_function` and
`pdf_colour_rgb_of_transform`, including the corrected sampled-function
interpolation, CMYK conversion and configured ICC engine. It never derives
CMYK or ICC samples from already-converted vertex RGB. `/None` colourants
produce neither colour nor shape. Missing functions and mismatching function
output arity are rejected.

The lookup is base64 RGB16LE, first input axis varying fastest. Each UInt16
is a straight, non-premultiplied channel in 0..65535; divide by 257 for an RGB
byte value. Packing loses at most 0.002 of a byte.

One/two-input functions now use error-checked adaptive binary cells, including
explicit type-3 stitching boundaries and nested/reversed Encode mappings.
Corner samples approach a cell boundary from its representable interior, so a
jump is not smoothed across cells. Exact boundary ownership follows the PDF
function, including reversed nested stitching. Seven fractions per axis,
including two irrational fractions, compare actual function/colour outputs
against interpolation. The checked error budgets are 0.35 RGB byte for 1D and
0.75 byte for 2D. CMYK output planes, when retained, are checked too.

Except for exact raw CalRGB sources described below, three/four-input colour
grids remain regular (25³/11⁴; two samples per axis for plain RGB/Gray), but
each cell is checked at its centre and two off-centre
points against the shared function/colour evaluator. A difference above 0.75
byte is unsupported, not silently accepted. These are deterministic numerical
checks, not a mathematical proof for arbitrary adversarial calculator programs.

A resource is capped at 80,000 RGB samples, 100,000 tree nodes, and 24 binary
levels. Exceeding sampling precision/depth/size, invalid arity, and more than
four source inputs produces a public `raster.error`; Canvas reports its text.
It no longer becomes an absent/black shading. There is no fallback from a
failed error check to the previous unchecked fixed lookup.

Adaptive cells greatly reduce simple gradients and preserve the original
checkerboard without boundary blur. The initial fixed table JSON was 5.55 MB
for the nine-shading type 1 fixture; the compact/adaptive path is bounded and
only refines the nonlinear portions. The current complete nine-shading plan is
1,677,416 bytes. Actual plan sizes are recorded with the fixture artifacts. The adapter also accepts numeric sample arrays for host
plans.

`web/pdf-shading.mjs` plugs into `renderPdfCanvas` through `paintShading`:

- Axial projection uses both coordinate axes, Function Domain, independently
  true/false Extend flags, full affine matrix and BBox.
- Radial sampling solves both quadratic roots, discards negative radii,
  respects Extend, and chooses the later covering circle. Concentric,
  eccentric, conic, shrinking and near-degenerate cases have pixel tests.
- Type 1 evaluates both input dimensions. Its own Matrix is separate from
  the shading/pattern/page matrix, so its Domain and the shading BBox remain
  in their correct coordinate systems.
- Gouraud triangles interpolate original components at each pixel center.
  Patches interpolate parameters across a device-adaptive bicubic mesh, then
  bilinearly interpolate source corner components before colour lookup.
- Adjacent triangles write a shared opaque bitmap. They do not alpha-blend
  against one another and do not use microtriangle edge strokes. The finished
  paint receives alpha exactly once. Curvature bounds in device space choose
  a common dyadic subdivision level, preserving shared patch edges at scale.
- Canvas provides surfaces, final clips, stroke masks and composition.
  Pattern Background applies only when `env.operation` identifies a pattern
  fill/stroke; direct `sh` ignores Background. BBox clips in shading space.

Canvas2D has no portable mesh primitive. The focused mesh bitmap strategy
was adapted from Mozilla PDF.js `src/display/pattern_helper.js` at
`89b500f5e1d98ed89bb90211e45b28730b2d99ac` (Apache-2.0, copyright notice in the
adapter). Pixel-center barycentrics replace its rounded scanlines; source
components/parameters replace endpoint RGB. The PDF.js renderer is used only
as a test reference, never to render the viewer's actual pages.

## Tests and independent pixel oracles

- 22 MoonBit shading tests on JS, native, wasm and wasm-gc.
- Full JS suite on the current A2 integration base: 454 tests.
- 46 Node Canvas shading tests: lookup dimension ordering, nonlinear samples,
  zero-width domains, RGB16LE, triangles, alpha/seams, patch curvature and scale,
  domain/BBox/matrices, radial roots/Extend, stroke masks, background, `/None`,
  malformed resources and explicit budget errors.
- Existing 33 Canvas replay tests also pass.
- `moon info`, `moon fmt`, `moon check --target all` and `git diff --check`.

`tools/pixels/shading_acceptance.mjs` generates ten complete PDFs and sends
all of them through the MoonBit parser, Canvas plan and actual Canvas pixels.
Every channel of all 100,000 pixels is checked against an independent formula,
not against a function copied from the renderer:

| Generated PDF | Max analytical byte error | PDF.js mean byte difference |
| --- | ---: | ---: |
| Type 4, t², two triangles, alpha 0.5 | 0.7482 | 22.2090 |
| Type 5, t² lattice | 0.4964 | 43.3493 |
| Type 6, t² Coons | 0.4964 | 40.9416 |
| Type 7, t² tensor | 0.4964 | 40.9416 |
| Type 1, two-input RGB sampled function | 0.4750 | 1.4784 |
| Axial, both Extend flags false | 0.3750 | 0 |
| Radial, both Extend flags false | 0.4959 | 0 |
| Axial N=10,000 at 100× zoom | 0.3826 | 2.4500 |
| Stitching band 0.00001 wide | 0 | 0 |
| Type 1 checkerboard discontinuities | 0 | 6.4733 |

The large nonlinear mesh differences are intentional and independently
resolved: at t=0.5 the t² function gives 0.25, not 0.5. PDF.js 6.4.299 converts
endpoint colours before mesh interpolation in these fixtures. ISO 32000-1
§8.7.4.5.7 requires interpolation of the parameter before Function evaluation.
No threshold was widened to hide this disagreement.

Source: [ISO 32000-1:2008](https://opensource.adobe.com/dc-acrobat-sdk-docs/standards/pdfstandards/pdf/PDF32000_2008.pdf).

## CMYK source-plane adapter

`paintShading` accepts `env.colourSpace='DeviceCMYK'` and `env.component=0..3`.
It uses `raster.process_samples`, a parallel four-channel UInt16LE table with
the same input interpolation/tree. Components remain actual DeviceCMYK values,
original DeviceRGB converted with the shared ISO BG/UCR helper, or DeviceGray
black; whole Separation/DeviceN tint alternates are evaluated before retaining
the four process components. Rendered display RGB is never inverted.
`process_background` preserves the same rule for a pattern Background.

The resource readers accept pre-parsed optional `black_generation` and
`undercolour_removal` functions so the collector can pass paint-site policy.
This path depends on the colour helper supplied by commit
`f7a6fa263b901f1c0de4f1b81852c8f97edde49d` (already integrated by the parent).
`env.shapeOnly` uses geometry independent of process conversion/alpha.

A complete type 4 PDF also checks all 40,000 CMYK plane pixels with alpha 0.5.
All alpha bytes are 128, including shared edges. RGBA8 Canvas stores
premultiplied channels internally; validation checks the compositor's actual
premultiplied input. Maximum error is below one premultiplied byte. The
unpremultiplied diagnostic maximum is 1.485 bytes because dividing by alpha
amplifies storage rounding; that value is retained in the report.

If adding CMYK checks exhausts the lookup budget while RGB still passes,
ordinary RGB remains usable and `raster.process_error` diagnoses the unsupported
component route. Raw RGB meshes can take that route when the default CMYK
min/max kink cannot fit the regular colour-grid error budget. No process colour
is guessed.

### Actual ICC group targets

The adapter accepts `env.iccProfileId` and a synchronous
`env.convertToGroup(source)` callback, supplied by the compositor's scoped ICC
catalog. `source_colour` retains the actual terminal ICC profile ID, intent,
component arity and ranges. DeviceRGB/Gray/CMYK and Lab source metadata are also
retained, because an ICC-RGB group cannot use already-rendered display RGB.
Whole Separation/DeviceN tints are evaluated before reaching this terminal
source. The page collector must pass its shared `resource_context` and the
paint-site `rendering_intent` to the shading resource reader.

Raw mesh source components bypass a source lookup entirely. Function/tint
outputs use a parallel `source_samples` UInt16LE table on the same adaptive
cells. Original-source interpolation is separately checked to 0.25 of a UInt16
unit before packing (which adds at most 0.5 unit); display-RGB equality cannot
hide source variations. A failed source budget yields `source_error` without
breaking ordinary RGB. The host CMM executes after source interpolation, using
the actual target profile, and never inverts display RGB. Target RGB is returned
in one pass; target Gray is replicated; CMYK uses the four component planes.
Pattern Background follows the same source conversion. Shape-only rendering
preserves the caller's AIS alpha and requires no target colour transform.

`shading_icc_acceptance.mjs` generates a complete PDF containing an ICCBased
axial shading and a nonlinear Function. It verifies the shared page profile
catalog, then compares 10,000 RGB and 40,000 CMYK output-plane pixels with the
real LittleCMS transformation of independently computed original components.
Maximum errors are 0.49937 and 0.49806 byte respectively. The CMYK test used the
system Ghostscript `default_cmyk.icc`, a genuine output-capable profile; profile
and PDF SHA-256 values are retained in `reports/shading-icc.json`. Hosts without
that profile must provide `PDF_CMYK_PROFILE`; absence is explicitly reported as
a skipped CMYK case, not a pass. No target-space error proof is claimed for
arbitrary profiles that amplify the finite source interpolation error.

Missing profiles, unsupported output profiles, unavailable source metadata and
failed source sampling raise descriptive errors. A source-only CMYK profile is
never fabricated into an output profile. CalGray/CalRGB sources use the shared calibration and black-point stages
followed by Bradford adaptation to D50 XYZ. Their `PCSXYZ` metadata preserves
signed and extended component ranges; XYZ is not clipped to the unit cube.
CalGray and Function/tint CalRGB samples retain evaluated PCS tables. Raw
CalRGB meshes retain original components plus their analytical calibration,
so the host applies gamma and the affine PCS conversion after interpolation.

The `--cal-gray` complete-PDF case combines a Function N2 with CalGray Gamma2
and checks another 10,000 RGB plus 40,000 CMYK target pixels against independent
D50 XYZ values. Maximum errors are 0.49635/0.50195 byte; the report is
`reports/shading-calibrated.json`. A separate real-CMM adapter test covers
negative and greater-than-one XYZ.

### Exact raw CalRGB meshes

Raw CalRGB type 4/5/6/7 meshes now use `source_direct` with original 0..1
components and `source_colour.calibration` (gamma, affine D50 PCS matrix and
offset). Their RGB/source tables are deliberately empty. The host interpolates
source components/patch parameters first, evaluates the shared exact descriptor,
and passes signed/extended XYZ to the actual CMM. Ordinary display explicitly
uses the initialized host CMM's sRGB destination. ICC and calibrated groups use
their existing scoped source-to-group transform. Pattern Background follows the
same source route. Shape-only replay needs no colour engine or sample table.

`PdfSourceColour.calibration` and `pcs_xyz` are mutually exclusive in these
produced source records: scalar paints retain their previously evaluated PCS;
raw CalRGB retains only its descriptor. Evaluated image/shading PCS records
explicitly clear the descriptor. Singular CalRGB source matrices are accepted
for forward conversion; the shared helper's default inverse requirement still
rejects them as destination group matrices.

`tools/pixels/shading_calrgb_acceptance.mjs` generates seven complete PDFs and
renders their public JS and native Canvas plans through `renderPdfCanvas`.
The 14 resulting cases check 140,000 pixels. Native and JS plans render exactly
the same bytes. Independent gamma/XYZ formulas and a Gaussian-solved Bradford
transform produce the oracle's D50 XYZ, followed by real LittleCMS target
conversion. The oracle never reads the retained calibration descriptor.
It covers fractional and nonlinear gamma, all four mesh types, ordinary sRGB,
actual RGB and CMYK output profiles, calibrated group targets, D65 adaptation,
and a valid singular source matrix. The signed-XYZ cases exercise 2,694 pixels
with negative XYZ and 50 pixels exceeding 1, without PCS unit-cube clipping.
Maximum group-component error is below 0.51 byte (including the half-byte
Canvas quantization); the D65 maximum is 0.50268 because the producer's Bradford
inverse uses rounded coefficients. Results and PDF/profile SHA-256 values are
in `tools/pixels/reports/shading-calrgb.json`.

The pre-fix producer rejected the five nonsingular source configurations with
`higher-dimensional colour grid exceeds 0.75-byte checked error`. This change
removes those grids only where conversion is represented analytically. It does
not loosen any checked RGB, process or source precision budget. CalRGB meshes
with a Function still interpolate its parameter before the original adaptive
Function/PCS lookup, and all prior nonlinear/stitching cases remain passing.

Standalone Canvas hosts must initialize the existing colour engine or provide
it to `createShadingPainter({iccEngine})`; absence produces the explicit
`raw CalRGB mesh requires an initialized colour engine` error. The shipped
runtime already initializes that engine. Native/wasm producers retain portable
metadata, not executable host state; actual pixels still require the Canvas
host. SVG remains the legacy endpoint/microtriangle approximation and is not an
exact calibrated-mesh rendering route.

The original-source route also retries without device process samples when
BG/UCR is too difficult for the process lookup, so an unavailable device-CMYK
approximation cannot disable a valid actual-profile conversion.

## Real fixture comparison

Fixtures are the unchanged PDFs at the pinned PDF.js revision above;
reference pixels use `pdfjs-dist` 6.4.299 with `@napi-rs/canvas`. Pixels with
any RGB channel differing by more than 8 are reported, not silently excluded.

| Fixture/page | Canvas MAE | Pixels >8 | Previous SVG MAE |
| --- | ---: | ---: | ---: |
| coons-allflags-withfunction / 1 | 0.4021 | 2,104 / 484,704 | 3.0995 |
| tensor-allflags-withfunction / 1 | 0.4031 | 2,290 / 484,704 | 3.0454 |
| function_based_shading / 1 | 1.3583 | 13,549 / 484,704 | 42.7685 |
| function_based_shading_cmyk / 1 | 2.2730 | 4,014 / 84,100 | 22.6477 |
| function_based_shading_cmyk / 2 | 0.5222 | 23,340 / 2,368,800 | 37.0853 |
| shading_extend / 1 | 0.9362 | 8,262 / 501,832 | dimension mismatch |
| radial_gradients / 1–5 | 2.0195–3.1789 | 15,480–25,547 / page | 2.1786–44.9274 |

The mesh fixtures contain no text. Eroding the union of their nonwhite masks
by three pixels classifies 2,042 of each fixture's >8 differences as outer
boundary pixels (97.1% of Coons differences; 89.2% of tensor differences).
The interiors have 62/248 pixels >8 and mean RGB errors 0.9571/0.9622.
These counts are reported separately, not removed from full-page results.

Independent numerical inversion of the bicubic tensor verifies examined large
interior disagreements: at device (329,295), the mathematical patch and viewer
both give [0,103,152], while PDF.js gives [0,136,118]; at (332,303), mathematical
patch/viewer give [0,115,140], while PDF.js gives [0,150,104]. Folded patch regions
have multiple parameter solutions; the examined viewer pixels match the later
parameter branch within one byte. Tightening flattening from 0.25 to 0.0625
pixels changes no channel by more than one byte in either fixture.

The type 1 reference has visible dashed internal mesh seams absent from the
viewer. Radial/Extend pages contain text, so their whole-page metrics include
A1/font differences; missing standard-font-data warnings occurred. Those pages
are diagnostics rather than proof of shading-only pixel equivalence. The
analytical axial/radial PDFs above give a separate exact reference comparison.

`axial_shading_many_inputs.pdf` is also attempted and rejected: it supplies an
18-input sampled function to a one-input axial shading. The viewer reports a
specific function input-arity diagnostic instead of accepting an empty/blank render.
It is not counted as a passing fixture.

## Reproduce

Use the official MoonBit toolchain and the repository's normal dependencies.
Install `pdfjs-dist@6.4.299`, `@napi-rs/canvas` and `@resvg/resvg-js` in an
isolated validation prefix and point `PDF_CANVAS_PACKAGE` to that prefix's
`package.json`. Generated PDFs/PNGs/reports stay under ignored `_build`.

```sh
moon build --release --target js cmd/pixel_plan
cp _build/js/release/build/cmd/pixel_plan/pixel_plan.js _build/pixel-plan.mjs
node --test tools/pixels/test_shading.mjs
node tools/pixels/canvas_test.mjs
node tools/pixels/shading_acceptance.mjs _build/pixel-plan.mjs
node tools/pixels/shading_icc_acceptance.mjs _build/pixel-plan.mjs
node tools/pixels/shading_icc_acceptance.mjs _build/pixel-plan.mjs --cal-gray
moon build --release --target native cmd/main
PDF_NATIVE_PLAN="$PWD/_build/native/release/build/cmd/main/main.exe" \
  node tools/pixels/shading_calrgb_acceptance.mjs _build/pixel-plan.mjs
```

Retrieve named real fixtures with
`git -C reference/pdf.js show 89b500f5e1d98ed89bb90211e45b28730b2d99ac:test/pdfs/NAME.pdf`.
Run the shared `tools/pixels/compare_canvas.mjs` with the shading adapter and,
for the Coons/tensor pattern fixtures, the pattern adapter installed. Source
fixture SHA-256 values are retained in its report.

## Host support, bounds and remaining gaps

- MoonBit parsing/model generation builds for all four targets. Actual pixel
  tests use the JS/Node Canvas host. Browser Canvas is the same adapter API but
  must be installed by the host. This is not a standalone native/wasm graphics
  renderer; those targets need a Canvas plan consumer. ICC availability retains
  the limitations documented in `a2-colour-validation.md`.
- Default limits are 16,777,216 surface pixels, 134,217,728 pixel visits,
  524,288 triangles, ten dyadic patch levels and 0.25-device-pixel flatness.
  Exhaustion raises a descriptive error. Plan geometry/source parsing still
  uses the viewer's existing limits; the adapter does not make arbitrary input
  sizes free of memory cost.
- Measured complete parse/plan/render time is roughly 0.48–0.50 s for the
  letter-size mesh fixtures, 12.28 s for the nine-shading type 1 page, 1.62 s for the 1880×1260 CMYK page and
  2.1–4.7 s for text-bearing radial/Extend pages in this environment. Whole
  renderer peak/transient memory includes multiple page-sized compositor
  buffers; observed RSS deltas can exceed 400 MB on the large page.
  Strict source-table attempts add measurable work even when their separate
  budget fails; source retention is not yet conditional on the target group.
  This is not yet a tiled/cached renderer, and no memory-performance acceptance is
  claimed from these one-process measurements.
- Adaptive/check-validated lookup cells are finite numerical approximations.
  Arbitrary oscillatory calculator programs could evade a finite set of
  probes; no mathematical all-input proof is claimed. Detected excess error,
  unresolved discontinuities and exhausted budgets are explicit diagnostics.
- More than four raw colour components produce a descriptive public error.
- Pixel-center mesh coverage avoids seams but does not implement analytic
  outer-edge area antialiasing. Canvas clips remain antialiased. PDF.js's
  differently filtered/expanded outer mesh footprint therefore differs.
- The SVG path remains an approximation: flat microtriangles, gradient Extend
  limitations, and no correct two-dimensional type 1 rendering. Canvas is the
  required path for these features. No H-03 completion claim is made for SVG,
  arbitrary adversarial functions, every host or unlimited zoom.

## Pattern transparency follow-up

PatternType 2 ExtGState now lowers to an implicit nonisolated knockout scene,
including ordered Background, inner blend/alpha/mask and independent outer
paint state. See [the dedicated evidence and reader discrepancy report](a2-shading-pattern-validation.md).
Canvas plans omit duplicate legacy mesh/stops and tiling SVG where retained
raster or structured cell plans are authoritative.

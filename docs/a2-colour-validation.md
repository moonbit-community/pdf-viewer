# A2 ICC and spot colour validation (2026-10-10)

## Implemented path

`pdf_colour_transform` compiles ICCBased to a cached LittleCMS transform,
clips samples to the PDF component `Range`, then converts to straight sRGB.
An unavailable engine, malformed profile, mismatching component signature or
failed transform uses a checked same-component alternate (or the PDF default
device space when the supplied alternate is illegal). Range clips; it does
not remap `[low high]` onto `[0 1]`. Indexed bases and the already shared
path/text/raw-image/pattern/shading/soft-mask consumers use this same path.
JPX can call `pdf_icc_transform(profileBytes, componentCount)` without making
a synthetic PDF stream. Encoded images must feed original samples through
this path, not convert already-RGB decoded pixels a second time.

The engine handles RGB/Gray matrix/TRC and CMYK LUT profiles. The PDF adapter
accepts ICC `RGB `, `GRAY`, `CMYK` signatures with N=3/1/4, caps profiles at
16 MiB, validates tag extents and caches up to eight transforms. Other ICC
input signatures intentionally use Alternate. LCMS chooses the profile's
matrix/LUT implementation; the viewer has not invented an ICC engine.
Output is sRGB with straight alpha. Relative colorimetric is the default;
per-paint intent and actual group/output-profile transport are described below. Untagged DeviceCMYK
keeps the existing PDF.js SWOP fitted fallback; no calibrated-colour fixture
or expected sample was changed to make these tests pass.

`pdf_colour_eval_function` reuses pdflite's parsed functions and calculator.
It fixes sampled-function interpolation (the dependency averaged just two
corners), degenerate domains, and internal stitching boundaries. It mirrors
the pinned PDF.js bounded simplex fallback above eight input dimensions.
`PdfSourceColour` retains original components and colourant names for the
compositor. Separation None and all-None DeviceN do not paint. A None channel
inside a mixed DeviceN still participates in the declared tint function.

## Target inventory and host hookup

- **native, Linux:** verified with installed `liblcms2.so.2` (LittleCMS 2.16).
  `colour_icc_native.c` dynamically loads the normal platform runtime and
  uses an explicit bounded transform LRU with reference-safe lazy reopening.
  Official LCMS declaration headers are vendored; no external development
  package or direct LCMS link flags are required. No installed LCMS means
  Alternate, not a silently invented transformation. macOS `liblcms2.dylib`
  and Windows `lcms2.dll` loader branches are present but unverified.
- **js, Node:** verified using the bundled MIT `lcms-wasm@1.0.5` / LCMS 2.16
  (309 KiB Wasm + 67 KiB module). Call `await installPdfIccEngine()` from
  `web/pdf-icc.mjs` before `open_pdf`. Profile input uses heap storage rather
  than the package's limited-stack array wrapper. Transforms retain reusable
  input/output buffers; per-sample conversion allocates no Wasm buffers.
- **js, browser:** the shipped `initializePdfGraphics()` runtime installs the
  same engine/assets before opening a PDF. Initialization failure emits an
  explicit `icc-engine-unavailable` diagnostic and uses PDF Alternate. The
  shipped `open_pdf`/`render_page`/`renderPdfPage` route is integration-tested
  with native Canvas; this is distinct from interactive browser visual QA.
- **wasm / wasm-gc:** compile and fallback tests pass; no ICC CMM host imports
  are supplied. They retain legal Alternate with explicit capability reporting;
  this is not four-target ICC-engine support.

The root `moon.pkg` change adds only the `colour_icc_native.c` native stub.
No Mooncakes dependency was changed. Profile and engine hashes and sources
are in `tools/colour_icc_cases.json`; licenses are adjacent to vendored assets.

## Historical initial validation and performance baseline

`moon test --target native colour_wbtest.mbt colour_icc_wbtest.mbt
colour_spot_wbtest.mbt`: 18 tests (includes native engine and page-consumer
checks). JS/wasm/wasm-gc run the 16 applicable portable tests. Existing colour
unit samples remain unchanged. A native page test covers ICC path, text,
raw-image PNG pixels, Indexed palette and shading output in one document.
`node tools/icc_engine_test.mjs` checks actual Wasm RGB/Gray/CMYK output;
`node tools/colour_planes_test.mjs` passes 10 plate-semantics cases.
`moon run tools/colour_icc.mbtx` is the combined diagnostic entry point.

Initial, pre-image-integration SVG raster comparisons used Node 24.19.0, PDF.js 6.4.299,
resvg 2.6.2, scale 1 and white background. Fixed upstream fixtures are from
PDF.js `89b500f5e1d98ed89bb90211e45b28730b2d99ac`:

| Page | Pixels | Any RGB change | Pixels with channel error >8 | Max error | Mean absolute RGB error |
| --- | ---: | ---: | ---: | ---: | ---: |
| devicen-none-zero-domain.pdf | 20,000 | 0 | 0 | 0 | 0 |
| colorspace_cos.pdf | 76,176 | 0 | 0 | 0 | 0 |
| devicen.pdf | 484,704 | 10,336 | 572 | 36 | 0.02331 |
| ICC version4pdf.pdf | 484,704 | 129,554 | 11,630 | 68 | 0.71039 |
| Altona technical 1v2 X3 | 1,004,360 | 491,196 | 359,754 | 255 | 13.85903 |

The first two match exactly. `devicen.pdf` exercises one real embedded ICC
transform, three samples. At that historical baseline the ICC version4 page bypassed shared
ICC in its encoded-image path on this isolated worktree (zero transforms),
so it is a deliberately failing integration diagnostic, not accepted ICC
coverage. The Altona baseline exercised six profiles and 2,050 samples before
actual PDF/X target selection and compositor integration. These figures are
historical only; current original-page and matched-policy results are below.
Both external PDFs are local diagnostic inputs, not redistributed. ECI allows
free use but requires written permission for redistribution.

One-million-sample host conversion benchmark (one run, no universal speed
claim): RGB 317 ms, Gray 278 ms, CMYK LUT 424 ms; engine initialization 6.9 ms;
profile open 1.1–2.6 ms. Measured RSS growth was 5.3 MiB / 0.28 MiB / 0.58 MiB
respectively, including runtime/JIT effects, not total peak page memory.

## Integrated overprint and display contract

`web/pdf-ink-compositor.mjs` retains original process components, premultiplied
ink planes, alpha and shape for CMYK groups. It implements OPM=0 and
DeviceCMYK-only zero suppression for OPM=1, group/knockout semantics, separable
and nonseparable blend modes, and actual-profile conversion at boundaries.
`web/pdf-colour-planes.mjs` supplies the separate explicit proof-plane helper.
Neither path attempts to reconstruct discarded inks from flattened RGB.

Ordinary additive display evaluates the complete Separation/DeviceN alternate
when the source colourants are unavailable; it does not invent combined physical
spot colours. DeviceRGB→unprofiled CMYK uses the declared BG/UCR policy;
actual ICC targets use the mature CMM. Physical spot proofing requires an
explicit complete-colourant transform and remains a separate opt-in capability.
The [compositor validation](a2-compositing-validation.md) covers mixed sources,
profiled/calibrated boundaries and non-normal overprint with actual parsed PDFs.
Six independently checked process-overprint probes from unchanged Altona,
including zero preservation and knockout, are reported below.

## Resource bounds and captured rendering intent

Active ICC resources now have explicit lifetimes. Both hosts retain at most
eight compiled transforms in an LRU. Eviction immediately deletes the CMM
transform and scratch buffers. Retained colour objects keep safe descriptors
and lazily reopen when reused. `clear_icc_transforms()` clears core cache and
active resources on document close; it does not invalidate retained objects.
The JavaScript engine additionally exposes `clearActiveTransforms`, `clearProfiles`
and `dispose`, without relying on FinalizationRegistry. Native uses LittleCMS's
public memory-handler plugin to cap aggregate CMM allocations at 64 MiB. The
bundled Wasm host rejects heap expansion before exceeding 64 MiB, conservatively
including the pinned Emscripten allocator's growth factor. Original source
profile bytes retained by live page objects are separate from active CMM memory.
Profile streams now use the bounded image-filter dispatcher with a 16 MiB
limit on every filter stage, before profile validation.

The shared colour helpers accept `rendering_intent` (default relative
colorimetric), mapping the four PDF names to the mature engine's intent.
The integrated path/text/image/pattern/shading collectors forward captured
graphics-state intent through the same optional parameter. Gray media-whitepoint tests
prove that relative and absolute intent produce different actual CMM output.
Host capability `icc_capability()` explicitly distinguishes `icc-engine`
from `alternate-only`; standalone Wasm/Gc remain legal Alternate paths.

For untagged DeviceRGB into DeviceCMYK groups, ISO 32000-1 10.3.4 is applied
to ORIGINAL RGB: complement RGB, choose k=min(C,M,Y), subtract UCR(k), use
BG(k) as black, and clamp process components. The declared reader-default
BG and UCR are identity; actual PDF functions override them, including negative
UCR values. Constant paints retain evaluated `process_cmyk` components. The
JavaScript `pdfDeviceRgbToCmyk` export accepts compiled BG/UCR callbacks for
pixel consumers. No inverse of the display-CMYK polynomial is used.

The JS engine also supports source-profile to actual output-profile transforms
with output N=1/3/4 and validated signatures. A supplied CMYK profile must have
a usable output direction: the bundled Compact CGATS001 input-only profile
correctly fails as a target, rather than inventing a reverse transform. A
full installed Ghostscript CMYK output profile is checked locally (not copied
into this repository). Registered profile catalogs are bounded to 32 MiB and
have immutable IDs. `sourceToProcess` uses original ICC inputs and actual
target profile IDs, or the declared untagged DeviceRGB policy when no target
profile is supplied. It never substitutes an arbitrary default ICC profile.

### Page-scoped profile transport

Canvas plans now carry one bounded `icc_profiles` catalog with
`{id, components, data_base64}` entries. Sources retain `icc_profile_id`,
original components, component ranges and (for Lab) `whitepoint_xyy`. A page's
`blend_profile_id` and each group's `icc_profile_id` identify actual profiles;
ICC N=4 still names its blend space `DeviceCMYK` for the existing ink pipeline.
Actual Group/CS profiles take precedence. A matching document OutputIntent
can characterize an untagged DeviceCMYK group. For PDF/X documents without
explicit page Group/CS, the embedded GTS_PDFX OutputIntent also selects the page
blending domain; ordinary PDFs do not acquire that PDF/X-only default. Profiles are deduplicated
within the page, at most 32 entries / 32 MiB; unsuccessful resource bookkeeping
is separately bounded. The catalog is useful even on Alternate-only targets.

JavaScript page replays use `engine.createProfileScope(plan.icc_profiles)` and
its source/group conversion callbacks, disposing that scope after asynchronous
replay finishes, including failure paths. Uniquely scoped registry IDs
prevent overlapping pages that both contain `icc-0` from using each other's
profiles. Do not globally clear another in-flight page's profile registry.
Five page tests cover source deduplication, page ICC blend space, nested Form
resource scope, actual OutputIntent selection and catalog limits, plus Lab
source transport. The initial catalog integration passed the then-current 342-test suite.

The group-profile API now also exposes `scope.sourceToGroup(source,
{profileId, components: 1|3|4, intent})` and `scope.groupToRgb(values,
{profileId, components, intent})`. The original `sourceToProcess` remains the
four-component alias. RGB/Gray ICC group components can therefore be blended
in their actual profile before their completed value is converted to sRGB.
Untagged DeviceRGB is assigned the viewer's declared sRGB device policy when
entering an actual profile; untagged CMYK has no invented source profile for
conversion into an RGB/Gray ICC group and returns an explicit unsupported
result. Raw source ICC values in the identical target profile bypass an
unnecessary reverse transform, including profiles with no output tables.
Embedded JPX ICC bytes register through `pdf_colour_register_icc_bytes` in the
same bounded, deduplicated page catalog as PDF ICC streams.
`sourceToGroup` with no target profile and `components: 3` denotes the existing
standard-sRGB display policy, so raw ICC/Lab/PCS sources can use the same CMM
forward conversion at a group boundary. It is not an implicit CMYK profile.

## Calibrated source-to-profile PCS bridge

CalGray/CalRGB sources now expose pre-display D50 XYZ through
`pdf_colour_calibrated_pcs`. Its final implementation starts from the original
gamma-adjusted matrix XYZ and adapts the actual source white to ICC D50 with
Bradford cone-response scaling. The black-point stage remains affine. It does
not reuse the legacy display-white approximation or invert display RGB. Existing calibrated RGB fixtures are unchanged. Scalar paints retain
`pcs_xyz`; image/shading terminal sources use `space: PCSXYZ` and actual XYZ
components. `pdf_colour_calibrated_pcs_ranges` bounds the monotone-gamma plus
affine stages from input-cube corners, retaining signed and >1 XYZ instead of
unit clipping. The CMM consumes XYZ double components and returns the actual
target profile's group components.

CalRGB/CalGray group targets retain their exact calibration descriptors and
use analytic inverse/forward conversion around blending, as described below.
Lab group targets remain explicitly unsupported rather than silently inheriting
DeviceRGB. Lab sources into supported group domains are supported.

## Actual ICC v4 image acceptance and printing-page resource evidence

The image-intent integration (`adc1fab`, including captured state forwarding)
was rerun through the public Canvas plan and actual Canvas renderer, with
Poppler/LCMS at 72 dpi as an independent page reference. For official
`version4pdf.pdf`, 5 LittleCMS transforms processed 339,879 samples with no CMM
failures or Canvas diagnostics. The displayed four-quadrant result is the
specified ICC-v2/v4-success appearance.

More importantly, the exact viewer JPEG component planes for **all seven**
embedded ICCBased images were independently transformed with installed system
LittleCMS 2.16, `TYPE_RGB_DBL`, the actual embedded profile, captured Perceptual
intent, and the viewer's final byte rounding. Every resulting image pixel
matches the image PNG in the actual Canvas plan exactly (maximum channel error
zero). `tools/colour_icc_image_check.py` reproduces this check from the decoded
plane manifest and Canvas plan; it does not reuse the viewer's ICC adapter.
The first three images also have ICC profiles, even though those profiles
behave as sRGB.

This check found and then verified the image-intent transport fix: the earlier
integration incorrectly applied RelativeColorimetric while retaining
Perceptual paint state. For the two v4 profiles, that defect caused mean byte
errors 3.141985 and 3.069728 (maximum 29) against the required transform. The
current Perceptual route has zero error for both.

Whole-page Poppler equality is **not** accepted: after the intent correction,
90,047 of 484,704 pixels exceed an 8-byte channel tolerance, with mean absolute
RGB error 6.414503 (before: 102,596 and 6.693303). A controlled PDF replacement
put the viewer's already-converted image pixels into DeviceRGB image objects
at the original PDF placements. Lower-quadrant residual means remained
13.976/11.434 versus 13.987/11.444 for the original ICC PDF, demonstrating that
those residuals are renderer placement/resampling rather than ICC conversion.
The analogous upper-quadrant controls reduced the original means 3.972/5.227
to 1.187/2.701, separating the previous intent error from raster differences.
Text also differs; none of these page-level discrepancies is waived merely
because the embedded image transforms are exact.

The historical pre-font-dedup Altona combined JS export exhausted Node's default
approximately 2-GiB heap before returning a plan. The native Canvas-only export
succeeded in 14.28 seconds with peak RSS 1,189,296 KiB and a 142-MiB JSON plan.
Its 6,521 items include 2,690 text paints; repeated `text_svg` payloads account
for 130,888,849 bytes, while all paint payloads total 11,925,115 bytes. It has
six actual ICC catalog profiles, RGB page blending, and no group target
profile. This isolates the primary export bloat from the bounded ICC CMM heap;
repeated font definitions were subsequently removed.
`tools/colour_canvas_compare.mjs` also accepts `PDF_CANVAS_PLAN` to test a native
plan without repeating the combined SVG/Canvas export. Current print-stage acceptance, remaining original-page pixels and bounded
replay measurements are recorded in the final section below.

## Calibrated group target descriptors

CalRGB and CalGray group/page targets now retain a compact
`PdfColourCalibration` descriptor (`gamma`, XYZ-column `pcs_matrix`, and
`pcs_offset`). It exactly represents the existing calibrated forward stage as
`PCS = matrix * components^gamma + offset`, including nonzero black-point
compensation. Original sources are transformed to D50 XYZ through LittleCMS,
then the analytic calibration inverse produces group components. Completed
group components use the forward descriptor and the mature XYZ-to-sRGB CMM.
No display-RGB inversion, sampled inverse or synthetic device profile is used.
Gray targets retain luminance through the descriptor's Y coordinate. Zero gamma,
singular/ill-conditioned matrices and nonfinite parameters reject explicitly.

The plan carries `blend_calibration` at page level and `calibration` on groups;
`sourceToGroup`/`groupToRgb` accept the same optional descriptor, and completed
calibrated source groups carry `source.calibration`. Original image inks are
retained inside these domains. `tools/icc_calibration_test.mjs` covers analytic
forward/inverse equality, CMM source-to-XYZ, authored RGB/Gray round trips,
same-domain source identity and malformed target rejection. This closes the
previous calibrated-target transport boundary. The independent parsed-PDF
Canvas/Ghostscript group tests cover path, image, pattern, shading, mask and
Form consumers, with their measured byte tolerances recorded in the linked
compositor validation; acceptance is not based on the helper test alone.

The later identical-DeviceRGB control against PDF.js attributes the remaining
ICC-v4 image raster differences more precisely: both upper quadrant crops are
byte exact, lower quadrants have mean errors 0.000277 and 0.000202, and the first
example 0.000101. Captured PDF.js image matrices and source canvases verify the
placement/downsampling match; Poppler's different bitmap policy accounts for
its substantially larger image-only residuals. Combined with the independent
zero-error CMM check, the seven actual embedded ICC image conversions are
accepted without waiving whole-page text or Altona differences.

## Scoped PDF device defaults

The shared colour-space reader and all six device colour operators now honour
`DefaultGray`, `DefaultRGB` and `DefaultCMYK`. Components pass unchanged into a
same-arity compatible replacement. Pattern bases, Indexed bases, and selected
whole Separation/DeviceN alternates use the same mapping; already-resolved ICC
sources are not retagged by a nested Form. Page initial gray is resolved once,
while a Form inherits the actual caller space until it explicitly selects a
new device space. Selecting DeviceCMYK through CS, including a resource alias,
still initializes 0001 black even when its default is ICCBased.

The reader checks colour-space graph depth and cycles before entering the
underlying recursive parser; default substitution tracks visited device spaces.
Wrong arity, cyclic aliases, and forbidden Lab/Indexed/Pattern defaults fall
back safely to the original device space. These rules follow ISO 32000-1
8.6.5.6, not a PDF/X-only heuristic. Seven focused default-space tests and the
full 398-test JS suite pass, with an all-target compile check. Actual OutputIntent
selection remains separate and gives these resource defaults priority.

Malformed or catalog-limited *explicit group* ICC profiles now retain an
`ICCBasedUnavailable` identity and a structured
`PDF_ICC_GROUP_PROFILE_UNAVAILABLE` diagnostic. They are not relabelled as
untagged device components. Strict Canvas replay rejects these plans; diagnostic
warning mode retains the warning. Ordinary ICC source paints still have their
separate legal Alternate route.

Printing-page oracle settings must be explicit: `PDF_PROOF=1` on
`colour_canvas_compare.mjs` enables Poppler overprint and supplies the exact
page target profile from the plan catalog as the reference device profile.
Ordinary-display comparisons remain available without that option.
`PDF_CANVAS_UNSUPPORTED=warn` is a labelled diagnostic-only run, never acceptance
of skipped unsupported paints.

## Indexed DeviceN palette regression found by the printing page

The first PDF/X-target Altona run exposed twelve failed paints of two images:
`Im16` and `Im36`. Their Indexed base has five DeviceN components
(`MyRed`, four `None` channels), while its alternate has four CMYK components.
The dependency's palette reader unwrapped the alternate before determining
entry size, consuming four bytes instead of five. That also silently changed
ordinary RGB output before retained ink samples made the arity error visible.

The viewer now parses Indexed tables before the dependency, using the original
base component count, and bounds lookup-stream decoding. String and compressed
stream tables share this path. Scalar Indexed paints resolve the selected
palette entry before retaining base colourants and samples; Indexed `None`
also retains its non-marking semantics. Two colour regressions plus the image
worker's end-to-end string/stream tests check the fifth component and distinct
palette entries. All twelve focused colour tests pass on native, JS, Wasm and
Wasm-GC; the full JS suite is 415/415 and the all-target compile check passes.

## Calibrated PCS correction found by the matched output-profile control

Altona's ECI CalRGB matrix has D50 white, so its gamma-adjusted matrix XYZ is
already ICC PCS. The first bridge reused the old PDF.js display normalization
(which scales LMS with XYZ white ratios), then applied a true Bradford inverse.
That was not the original calibrated XYZ: the flat CalRGB patch was
`[240,219,139]` versus its equivalent ICC/Ghostscript patch `[228,222,140]`.
The pre-CMM path now adapts original XYZ using actual white-point LMS ratios.
D50 needs no adaptation; D65 white and primaries have analytical controls.
Positive fractional CalGray gamma is also retained in this profile path.

This deliberately leaves the historical ordinary-display compatibility path
and its fixture expectations unchanged. It corrects source PCS and calibrated
profile-group descriptors, not the legacy PDF.js display policy. All 18 focused
PCS/legacy-colour tests pass on native, JS, Wasm and Wasm-GC; the full JS suite
is 417/417 and all-target compile passes.

## Final real-print colour-stage acceptance and remaining pixels

The original, unchanged Altona PDF/X-3 technical page completes strict replay
with all 6,521 items (2,690 text, 3,397 paths, 434 images), seven actual embedded
profiles, no graphics diagnostics, and zero CMM failures. Its actual CMYK
OutputIntent is 1,526,728 bytes, SHA256
`b58db54cc4df6ea2d4b8f9452cab4e881e8cc8e9f27b6c6bc026d7c400bbc571`.
The source PDF SHA256 remains
`06b980fa09cd45f35a1fc9a2b907911201e91c0fcc2ee5a67820f6bb7818e630`.

`tools/colour_print_stage_check.py` independently opens the original source
profiles in system LittleCMS 2.16, transforms original samples to the exact
OutputIntent CMYK, and transforms those components to sRGB. Both links use
relative colorimetric intent, flags 0, no black-point compensation and no
paper-white simulation. Five actual visible interior patches (ICC Gray, RGB,
CMYK, Lab and CalRGB) match the resulting RGB bytes **exactly**. The CalRGB
control computes XYZ from the original PDF matrix/gamma/white, not from the
viewer’s emitted PCS. This catches the old 12-byte CalRGB error and passes
after the correction. Six further original-page process-overprint probes also
match independently composed ink vectors and final RGB exactly. They cover
OPM=1 zero preservation, nonzero channels replacing the backdrop, Gray knockout
and white knockout. These are original-page results, not rewritten test paints.

A second reference renders the actual PDF using Ghostscript 10.05.1 `tiff32nc`:
72 dpi, exact embedded profile as both DefaultCMYK and OutputICCProfile,
RenderIntent=1, BlackPtComp=0, KPreserve=0, DeviceGrayToK=true and
Overprint=/enable. `colour_cmyk_raster_check.py` then converts that CMYK raster
with independent system LittleCMS and the same profile/intent/flags. The five
solid CMYK controls agree within one 8-bit ink level before display conversion.
The command-line meanings and device-dependent overprint distinction are
specified in [Ghostscript colour management](https://ghostscript.readthedocs.io/en/gs10.05.1/GhostscriptColorManagement.html)
and [its overprint documentation](https://ghostscript.readthedocs.io/en/master/Use.html#using-ghostscript-with-overprinting-and-spot-colors).

**The whole original page is not pixel-perfect or globally accepted.** These
are the native-fill Canvas results for its 1,004,360 pixels, preserving every
residual rather than substituting a derived control:

| Original-page reference policy | Pixels above 8 | Mean absolute RGB error |
| --- | ---: | ---: |
| Poppler normal PDF/X policy, actual DefaultCMYK profile | 443,871 | 18.5769 |
| Poppler overprint PDF/X policy, actual DefaultCMYK profile | 632,594 | 26.3129 |
| Matched Ghostscript CMYK→LCMS, default one-bit raster coverage | 279,247 | 12.5362 |
| Matched Ghostscript CMYK→LCMS, text/graphics AlphaBits=4 | 259,173 | 7.06356 |

In the last comparison, flat-reference interiors have 4,707 pixels above 8
among 328,868 pixels, MAE 0.83076. This mask only inspects the reference’s 3×3
neighborhood; it never selects pixels by viewer error. Both full-pixel and
interior results, including all 24 rows, are recorded in
[`tools/colour-print-validation-results.json`](../tools/colour-print-validation-results.json).
The targeted disjoint localization below accounts for all 4,707 of these
flat-reference residuals. Whole-page edge pixels remain included in the table;
localization does not turn their coverage differences into a pixel-perfect pass.

Poppler is not interchangeable with the matched two-link colour protocol:
three minimal solid PDFs retain the original ICC samples/profiles, with and
without only the PDF/X OutputIntent. Its ICC Gray result changes from
`[175,175,175]` to `[162,163,166]`; ICC RGB changes from `[229,222,140]` to
`[217,221,121]`. The original source→OI→sRGB controls above distinguish this
output-policy difference from source-tagging errors. All six isolation-PDF
hashes are in the report; none of those PDFs is redistributed.

The separately labelled **derived colourant-availability control** renames
only seven process-named Separation/DeviceN entries to unavailable names.
It preserves `None`, `All`, ordinary DeviceCMYK paints, every function, and all
59 encoded content/image/profile streams byte-for-byte. A recursive semantic
graph comparison verifies no other changes. This makes the CMYK oracle use
the same whole-alternate policy as the additive display for those names;
it does not simulate unknown physical spots. Its SHA256 is
`f28b5275b1b322c2db2b6b411b36a09b096ae1eafd6adcb276ec75a031251434`.
With AA4, this derived control has 229,528 pixels above 8, MAE 5.43667;
flat-reference MAE is 0.45188. These numbers never replace original-page
acceptance. `colour_print_alternate_control.py` records every changed name,
source/control hashes and the unchanged stream hashes.

The exact same saved Altona plan and renderer also verify the compositor’s
performance optimization: dirty-region and full-surface replays have **zero
changed RGBA pixels**, while replay time falls from 173.60 to 32.37 seconds.
The earlier 283.98-second parse+replay used different SVG glyph padding and
is not a byte-identical comparison. Native text fill geometry and Type3/mask/pattern catalog deduplication are
integrated. The fresh corrected-colour plan is 21,272,647 bytes, with zero pixel
changes from the previous native-fill replay. The pre-scratch-reuse backend baseline (root d1820f7), using a fresh saved-plan
replay, measured 47.52 seconds and 3,203,760,128 bytes RSS growth (parse+replay:
88.22 seconds and 3,307,982,848 bytes). This isolates a remaining compositor
allocation-churn problem after catalog deduplication; this measurement is
explicitly **not** a bounded-page resource acceptance. The compositor workstream
tracks and validates its resource fix independently. The final public saved-plan
runner now completes in 10.62 seconds at 783,416 KiB peak process RSS with
identical RGBA bytes; see [allocation validation](a2-allocation-validation.json).
This does not retroactively turn the earlier allocation baseline into a pass.

Colour acceptance is therefore specific: native/JS mature-CMM source and
actual-profile target conversion, real v2/v4 image conversion, calibrated PCS,
and the checked ordinary-display/process-overprint cases are verified. Wasm
and Wasm-GC still explicitly use legal Alternate rather than an ICC engine.
No complete unknown-spot physical proof system or pixel-perfect whole-page
printing result is claimed.

## Unavailable ICC source Alternate in actual profile groups

The retained source record now carries the same checked, range-clipped legal
Alternate as the ordinary display transform. A missing/unusable **source**
profile can therefore recover inside a valid ICC group. A separate source→sRGB
probe distinguishes failed input conversion from an unusable target; invalid
actual group profiles still produce the explicit group diagnostic/error.

Image and shading metadata is reusable: the Alternate receives the current
sample, never the metadata record's initial zero components. CalGray/CalRGB
Alternates retain their analytical calibration for this dynamic path. Raw ICC
meshes use exact interpolated components and the page-owned profile scope,
just as raw calibrated meshes do, rather than requiring an unused nonlinear
25³ display table to pass a precision test before actual target conversion.

`tools/pixels/icc_alternate_acceptance.mjs` checks nine complete authored PDFs
(9,216 pixels): malformed/header-valid unusable sources, varying RGB/CalRGB
axial shading, raw meshes, images, actual RGB/CMYK targets, and valid ICC meshes
in ordinary RGB and DeviceGray display pages. All compare within one RGB byte with direct
Alternate/CMM controls; eight cases are byte-exact. The valid profile display case
is byte-exact against direct CMM conversion and has 576 channel values differing
from DeviceRGB Alternate, proving scoped ICC IDs are actually resolved. Results:
[`tools/pixels/reports/icc-alternate.json`](../tools/pixels/reports/icc-alternate.json).
Focused MoonBit tests pass JS/Wasm/Wasm-GC 36 each, native 40; full JS 458,
all-target compile and host lifecycle checks pass.


## Disjoint original-page residual localization

`colour_print_residuals.py` always starts from the original AA4 reference mask:
4,707 pixels above 8 among 328,868 flat-reference pixels. Each pixel is assigned
once. The name-only control is used to establish cause, never to replace the
original acceptance result. Boxes below are half-open screen pixel coordinates
at 72 dpi. Full per-paint clusters, exact edge positions and sample values are
in [`colour-print-residuals.json`](../tools/colour-print-residuals.json).

| Original residual category | Pixels | Bounding box | Source/evidence |
| --- | ---: | --- | --- |
| Available process names versus whole display Alternate | 1,908 | [45,219,433,801] | Exact original-mask pixels resolved by the verified seven-name-only control |
| Adjacent opaque shape coverage | 859 | [59,141,637,1146] | 145 original CMYK K/Gray paint pairs, including 2187/2188, 3813/3814 |
| Forced oracle intent | 321 | [186,18,220,77] | ICC logo paints 189 and 222–225; 307 red and 14 turquoise solid pixels |
| GS CID0 glyph selection | 451 | [347,14,590,25] | Original glyph paints 6296–6335 |
| GS CID2 glyph selection | 613 | [348,45,591,56] | Original glyph paints 6475–6518 |
| Partial text coverage | 280 | [11,80,753,1170] | Original glyph paths, including 2339/2342, 3779/3782, 6471/6474 |
| Partial path/stroke coverage | 116 | [44,475,434,1103] | Original affine strokes 2171/3611 and fills 2027/3467 |
| Partial image-quad coverage | 143 | [108,226,424,786] | Original images including 2531/3971 (/Im7), 2675/4115 (/Im28) |
| Reference-font bitmap sampling | 16 | [629,13,835,91] | Original image 6520 (/Im0), independently sampled and transformed |
| **Disjoint total** | **4,707** | | **Zero unlocalized flat-reference pixels** |

The shared-edge case is reproduced independently by the compositor's
`tools/pixels/coverage_seams.mjs`: two adjacent full-opacity fills have separate
fractional coverages, so source-over does not make their shared pixel fully
opaque. At the original x=81.221 edge, actual `[175,177,178]` and direct host
Canvas `[175,176,177]` differ by at most one byte; a combined path and GS yield
`[158,160,161]`. The equations and CMM are correct. Blindly merging the original
CMYK/Gray paints would change OPM=1 channel marking, so geometry expansion or
unsafe paint batching is not used to conceal the raster-policy difference.

The remaining 539 text/path/image-edge pixels (280+116+143) have strictly
partial coverage, 1–254, when `colour_print_coverage.mjs` independently rasterizes
the original outlines, affine stroke pens and image quads. This establishes
source/region/coverage localization rather than claiming a complete numerical
proof of every edge. Several zero-tint Separation edges also combine the named
plate policy with AA. None is an unlocalized flat solid ICC conversion patch.

The two CID header lines visibly select different glyphs in GS (`2ULA…` and
`7\SH…`). Both the viewer and independent Poppler preserve the intended
`Type 0 (CID)…` / `Type 2 (CID)…` outlines. The other text rows do not share that
reference selection failure. The 16 /Im0 samples are separately verified in
[the printing bitmap audit](validation/print-bitmap-sampling.md): exact decoded
gray planes, independent two-stage bilinear sampling and system-LCMS final RGB
all agree with the viewer; isolated GS reproduces the different reference
point-sampling result. The original residual counts remain unchanged.

`colour_print_intent_check.py` uses the original /Cs9 profile and original logo
components in two local 20×20 isolation PDFs. Source intent remains Perceptual,
BPC is off, and the same exact OutputIntent and relative-colorimetric display
link are used. Independent system LCMS gives the viewer's red `[231,75,56]` and
turquoise `[0,162,170]` **exactly**. GS with forced output RI=0 differs by at most
one byte after its 8-bit CMYK raster; RI=1 gives the original reference values
`[231,72,41]` and `[39,167,172]` exactly, even with OverrideRI=false. This directly
verifies the installed GS 10.05.1 output-intent override behavior rather than
assuming all paints were relative colorimetric. Original/control/profile hashes
and exact options are in
[`colour-print-intent-controls.json`](../tools/colour-print-intent-controls.json).

The colour-stage acceptance is therefore supported by actual original-page
solids, process-overprint probes, per-paint intent controls, and localized
remaining differences. The whole-page pixel-match flag stays false; the
remaining raster-policy differences and resource measurements are not hidden.

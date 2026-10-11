# Bounded shading reuse and conservative replay

Measured on the A1-integrated A2 source `f51e6ba`, using the pinned PDF.js
`tracemonkey.pdf`, page 11 (612 × 792). [Machine-readable measurements](shading-reuse.json)
retain fixture and output hashes. These are local timing observations, not
latency or peak-memory guarantees.

- Page-local sampler reuse reduces JS `render_plan` from 15.206 s to 4.217 s.
  The complete 38,296,184-byte result, including SVG, and the 30,728,188-byte
  Canvas JSON are byte-identical to the uncached result.
- Conservative clipping reduces saved-plan Canvas replay from 11.243 s to
  2.790 s. Shading sample visits fall from 78,522,048 to 34,446 across 162 calls.
  Full replay, clipped replay and the previously saved PNG have identical RGBA.
- Full-size working surfaces remain. An independent replay still used roughly
  1.15 GB RSS; same-process before/after RSS endpoints must not be called a
  peak-memory improvement.

The page-local sampler cache admits at most 16 entries and 8 MiB of conservatively
accounted tables/function storage. Resolved colour space, function bodies,
domain, intent, BG/UCR and actual profile capabilities participate in identity.
Paint geometry, matrices and names remain per use. Returned arrays are copied.
Failures, partial process/source sampling, meshes and over-budget entries are
not cached. Nine Moon regressions cover these boundaries.

The Canvas optimization only bounds direct axial/radial/function sample loops.
Explicit absolute M/L/C/Z clip geometry is transformed into a conservative
control-point hull, padded for antialiasing and intersected. Pixel centers and
evaluation order stay global. Unknown syntax, meshes, path paints and retained
PatternType2 scenes retain full replay. Seven focused host tests cover transforms,
Extend/BBox, ICC conversion, knockout, masks, CMYK and fallback geometry.

## Reproduce

Install the pinned host packages described in [the common check](../a2-acceptance.md#common-reproduction) and set
`PDF_CANVAS_PACKAGE` to their package manifest. Build with `moon run tools/a2_check.mbtx`.
Download the fixture from the revision recorded in the JSON file, then run:

```sh
PDF_PIXEL_SVG=0 PDF_PIXEL_OUTPUT=_build/shading-real \
  node tools/pixels/compare_canvas.mjs _build/pixel-plan.mjs /path/to/tracemonkey.pdf
PDF_SHADING_REAL_PLAN=_build/shading-real/tracemonkey-11.plan.json \
PDF_SHADING_BASELINE_PNG=_build/shading-real/tracemonkey-11.canvas.png \
PDF_SHADING_PROFILE_OUTPUT=_build/shading-real/replay.json \
  node tools/pixels/shading_region_test.mjs
```

The optional real-page test compares full and clipped replay in the same process;
the ordinary aggregate explicitly skips that optional fixture unless supplied.
The final Worker-integrated rerun (`84079e0`) passed all eight tests including
the real page: full replay 10.938 s, clipped replay 2.762 s, with the same exact
RGBA hash as the pre-change baseline. The comparator records reference pixel
differences, not fidelity pass counts.
`PDF_PIXEL_SVG=0` explicitly records the SVG renderer as skipped. The default
comparator still runs SVG; Resvg did not finish Tracemonkey page 13 in this
environment, while the Canvas route completed. No SVG performance pass is claimed.

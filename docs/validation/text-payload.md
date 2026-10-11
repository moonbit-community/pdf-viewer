# Canvas glyph payload and Altona memory

The Canvas plan is a per-source-paint display list. Its A1 SVG glyph fragments
must not duplicate the entire page's embedded font programs. The companion
[invisible OCR change](invisible-text.md) omits font definitions for resolved
outlines. The follow-up makes two additional consumer-only reductions:

- Real fallback text receives only its matching PDF font resource, not every
  font on the page. A regression includes an unrelated embedded resource and
  verifies it never enters the glyph fragment.
- A text item with a resolved `stroke.svg_path`, including an empty outline,
  emits `text_svg: null`. The Canvas adapter already paints that path directly;
  its separate SVG page serializer remains unchanged. Type3/fallback fragments
  without a native pen path remain present.

No font decoding, glyph geometry, source indices, selection or public model
fields change.

## Actual Altona page

Private diagnostic fixture: ECI `altona_technical_1v2_x3.pdf`, SHA256
`06b980fa09cd45f35a1fc9a2b907911201e91c0fcc2ee5a67820f6bb7818e630`.
The PDF is not redistributed. Measurements use its complete first page, not a
synthetic subset: **6,521 paint items and 2,690 glyph entries**. Of those glyphs,
2,687 already have resolved A1 outlines and only three use fallback fragments.

| Measure | Before | After |
| --- | ---: | ---: |
| Native Canvas plan bytes | 148,034,623 | 20,765,343 |
| Sum of raw `text_svg` string lengths | 130,795,395 | 3,526,115 |
| Embedded-font fragments | 2,690 | 0 |
| Native generation elapsed | 14.28 s | 13.01 s |
| Native peak process RSS | 1,189,296 KiB | 252,212 KiB |
| Actual JS `render_plan`, default heap | OOM near 2 GiB | completes |

The current release JS bridge also completes under
`node --max-old-space-size=1536`, with the actual LittleCMS host installed:
42.22–42.68 seconds for `render_plan` across two runs, peak process RSS
1,038,152–1,055,000 KiB, and 26,703,362 UTF-16 code units in the full SVG + Canvas response. These are single-machine
measurements, not portable time or memory guarantees. The 1,536 MiB option caps
V8's heap, not all native/Wasm process allocations.

The native before/after **complete glyph paint objects are structurally equal**,
not merely equal glyph counts. The refreshed JS plan with LittleCMS is also
structurally equal to the native plan. Its source identity/geometry hash is
`8b6cddc0adb610060c6d683720468a5e2ffaa174bd96a9f743750a0b5b891000`.
Only the redundant fragment resources change.
This resolves the measured plan-serialization OOM. It does not claim that all
large-document font parsing or Canvas raster replay is now inexpensive; those
stages must be measured separately.

## Checks and reproduction

Six focused tests pass. Full suites: JS 366, Wasm 367, Wasm-GC 367, native 374;
all-target checking passes. `moon info && moon fmt` introduces no interface
change. Unrelated existing formatting edits were not retained.

The seven real authored affine-text PDF pages were replayed through the native
Canvas host at scale 1, rotation 0 after dropping the unused native-pen SVGs.
Every output pixel matches the previous TK-integrated capture. Poppler and PDF.js
comparisons retain the documented AA/implicit-knockout reference differences;
see [text-strokes.md](text-strokes.md).

Build a fresh release bridge rather than reusing an old generated file:

```sh
moon build --release --target js cmd/pixel_plan
cp _build/js/release/build/cmd/pixel_plan/pixel_plan.js _build/pixel-plan.mjs
PDF_PROFILE_RENDER=1 node --max-old-space-size=1536 \
  tools/pixels/measure_plan_payload.mjs _build/pixel-plan.mjs \
  /path/to/altona_technical_1v2_x3.pdf _build/altona-payload.json
```

The diagnostic installs the production ICC/JBIG2 hosts and records bridge/PDF
hashes, source identity/geometry hash, payload counts, ICC counters, elapsed time,
heap statistics and peak RSS. `PDF_PROFILE_RENDER=1` additionally saves the actual
Canvas plan beside the report. It does not redistribute the input PDF.

For a native plan:

```sh
moon build --release --target native cmd/main
_build/native/release/build/cmd/main/main.exe \
  /path/to/altona_technical_1v2_x3.pdf _build/altona.canvas.json 1
```

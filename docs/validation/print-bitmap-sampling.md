# Original Altona bitmap sampling residuals

All 16 remaining original-page flat-reference residuals assigned to item 6520
are numerically explained by the existing PDF.js-compatible image sampling
policy. This establishes no new raw-sample, Decode, alpha, or CMM-ordering bug.
The original Ghostscript differences remain in acceptance; no threshold or
reference mask is relaxed, and this does not establish whole-page equality.

## Source, sampling and colour checks

The original PDF's object 201 is a 947×301 8-bit DeviceGray Flate image, without
Decode, mask, or Interpolate entries. All 285,047 decoded source bytes match
retained 16-bit samples exactly after multiplication by 257; all retained alpha
bytes are 255. Original PDF, decoded-stream, profile, plan and reference hashes
are recorded in [the sampled evidence](../../tools/colour-print-bitmap-samples.json).
The output profile read directly from the original PDF equals the plan profile.

The top-origin device transform is
`[245.2755,0,0,78.56151,591.54287,13.17]`. The adapter rounds both axis-aligned
corners to `[245,0,0,79,592,13]` and enables smoothing for minification even
though Interpolate defaults to false. The bitmap is reduced to 474×151 before
the final draw. This is the documented PDF.js-compatible host policy, not a
claim that every PDF renderer must make the same sampling choice.

For destination pixel `(x,y)`, the second-stage bilinear position is
`((x+0.5−592)*474/245−0.5, (y+0.5−13)*151/79−0.5)`. An integer first-stage
sample `(i,j)` is the rounded bilinear value of the raw image at
`((i+0.5)*947/474−0.5, (j+0.5)*301/151−0.5)`. Independent evaluation reproduces
all 16 adapter grayscale bytes exactly, as does PDF.js 6.4.299 on the same
@napi-rs/canvas 1.0.10 host.

A2 converts Gray to group CMYK with C=M=Y=0 and K=1−Gray, samples the component
planes, then applies the final output-profile-to-sRGB transform. It does not
minify already CMM-converted RGB. At all 16 pixels, A2's K equals
`(255−PDF.js gray)/255`. Independent system LittleCMS 2.16, relative colorimetric
intent and flags 0, converts those K values to the exact final A2 RGB bytes.

| Page pixel | PDF.js / independent bilinear gray | A2 K byte | A2 / independent LCMS RGB | Original GS K byte |
|---|---:|---:|---|---:|
| 828,13 | 191 | 64 | 207,209,210 | 0 |
| 830,16 | 151 | 104 | 177,179,180 | 244 |
| 743,76 | 188 | 67 | 205,206,208 | 0 |
| 812,83 | 74 | 181 | 112,113,114 | 0 |
| 813,83 | 73 | 182 | 111,112,113 | 0 |
| 814,83 | 73 | 182 | 111,112,113 | 0 |
| 635,90 | 237 | 18 | 242,242,242 | 0 |

The same original image and its four clipping rectangles are isolated in a
270×100 PDF, with an integer translation preserving device alignment. Replaying
only this paint reproduces all 16 original-page A2 RGB values. Ghostscript
10.05.1 on the isolated PDF reproduces all 16 original CMYK TIFF values, which
also equal nearest sampling under the original unrounded transform:
`floor((x+0.5−591.54287)*947/245.2755)` and
`floor((y+0.5−13.17)*301/78.56151)`.

Thus a reference-flat 3×3 neighborhood can still correspond to source-image
structure discarded by its sampling. Twelve residuals are internal image
pixels, and four touch the image's top edge. The conclusion does not depend on
calling every residual a quad edge. The supplementary whole isolated crop
adapter/PDF.js comparison has 24 perimeter pixels differing by one byte and
none by more than one; all 16 audited pixels are exact.

## Reproduction

[The checker](../../tools/colour_print_bitmap_check.py) requires the existing
Node validation dependencies, Python numpy/Pillow/pypdf, Ghostscript, and system
LittleCMS. Supply the original PDF, emitted plan, final A2 PNG and matched GS
CMYK TIFF; it renders only the isolated image, never the whole original page.

```sh
python tools/colour_print_bitmap_check.py \
  "$PRIVATE_PDF" "$PRIVATE_PLAN" "$ACTUAL_PNG" "$GS_CMYK_TIFF" \
  _build/bitmap-samples.json --canvas-package "$CANVAS_PACKAGE_JSON"
```

The GS TIFF must use 72 dpi, TextAlphaBits=4, GraphicsAlphaBits=4,
RenderIntent=1, BlackPtComp=0, KPreserve=0, DeviceGrayToK=true, Overprint=enable,
and the original output profile as both DefaultCMYKProfile and
OutputICCProfile. The checker uses those settings for its isolated reference.
Its default source object/index are 201/6520. This is a narrowly scoped
fixture check; unsupported geometry or source semantics fail explicitly.

Temporary raster/PDF/profile assets are removed automatically; optional
`--keep-artifacts` retains them locally for diagnosis. Never publish that
directory: the ECI-licensed PDF, image and profiles are not redistributed.
Only small sampled values, hashes and original sampling math are committed.
The checker asserts every exact relationship above and exits nonzero on
failure. No implementation code changed for this audit.

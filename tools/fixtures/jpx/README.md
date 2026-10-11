# Original JPX fixtures

These four tiny lossless files were generated for this project with Pillow's
OpenJPEG encoder (`irreversible=False,num_resolutions=1`) on 2026-10-10.
They are original test data under the repository Apache-2.0 license.

- gray.jp2: 4x3 Gray8, samples [0,64,128,255,255,128,64,0,30,90,150,210]
- rgb.jp2: 3x2 RGB8,  red/green/blue, [80,160,220], [30,50,70], white
- rgba.jp2: 2x2 RGBA8, [255,0,0,255],[0,255,0,128],[0,0,255,0], [30,60,90,200]
- gray16.jp2: 4x2 Gray16, [0,65535,32768,1,256,4660,32767,65534]

The fixture bytes and expected pixels are embedded into MoonBit tests so tests
run unchanged on all four target runtimes without filesystem access. Larger
original fixtures are reproducible with `tools/jpx/generate.py`; signed,
non-byte and subsampled codestreams use `tools/jpx/make_components.c` with an
official OpenJPEG development library. Real PDF.js samples are attributed in
`codecs/jpx/README.md` and use the pinned source revision.

# Original affine text pen fixture

`affine-pen.ttf` is an original, unhinted 1000-units-per-em TrueType font,
created for this repository and licensed Apache-2.0. It contains `.notdef`
(empty), `A` (a sharp polygon), and `B` (quadratic curves), mapped to U+0041
and U+0042. Both glyph advances are 650 units. No third-party font data is
included. The deliberately simple contours isolate graphics-state pen
geometry from font hinting, shaping, fallback and glyph-selection differences.

`tools/text_strokes.mbtx` embeds this font in seven original PDF pages covering
nonuniform/sheared/reflected CTMs, independent text matrices, caps/joins/dash
phase, miter limits, fill/stroke alpha, q/Q restoration and page-space clipping.

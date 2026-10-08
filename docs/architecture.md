# Renderer architecture

The project is split around the same boundary that makes pdf.js testable:

```text
PDF bytes
  │
  ▼
pdflite reader/content entries
  │
  ▼
PdfViewerDocument ── page(n) ── PdfPageModel
                                  ├─ PdfViewport
                                  ├─ PdfTextContent
                                  ├─ PdfPageItem display list
                                  └─ selection mapping
  │
  ▼
SVG renderer / future Canvas renderer / host adapter
```

`pdflite` owns PDF syntax, xref recovery, resources, font decoding, content
operators, and image decoding primitives. The viewer package owns the stable
host-facing model and coordinate conversion. This keeps an OpenSeek adapter (or
a future Rabbita browser shell) from depending on `pdflite` internals.

The first renderer deliberately serializes a display list instead of drawing
directly while parsing. That gives us three independently testable results:

1. page geometry and rotation;
2. positioned text and selection order;
3. SVG paint output.

Text items retain the original `pdflite` quadrilateral in addition to their
axis-aligned bounds. This lets SVG preserve a glyph run's direction while the
bounds remain convenient for cursor selection. Path items likewise carry the
PDF line cap, line join, and dash state needed by an SVG host.

Text paint mode and source fill/stroke colours are retained as part of each
text item. Path line widths and dash spacing are scaled by the affine paint
CTM before serialization; this is exact for uniform transforms and uses the
mean basis-vector scale for shears and non-uniform transforms.

`PdfPageModel::viewport` follows pdf.js' `PageViewport` affine matrix,
including nonzero media-box origins. The SVG renderer uses the equivalent
relative transform after subtracting the page origin from display-list
coordinates, so the public viewport matrix and rendered page stay in the same
coordinate convention.

The current renderer has several concrete compatibility improvements: it emits the pdf.js-style
full viewport matrix, lowers path-only coloured tiling patterns to SVG `pattern` definitions,
and applies a retained `/Matrix` at the paint site. Explicit clipping paths are serialized as
nested clip paths so each additional path narrows the previous clip instead of becoming a union.
PDF ImageMask, colour-key `/Mask`, image `/SMask`, and common Form soft-mask resources are lowered
to browser-ready mask images. A nested SVG applies image masks before the outer affine transform,
while page-space soft-mask definitions retain their `/BBox`, backdrop sample, and transfer-map
output. Adjacent items with the same soft mask are now emitted inside one SVG compositor group,
so the mask is applied to the accumulated source paint. Form XObject transparency dictionaries
are also read into each flattened item, preserving the source group id and its isolated/knockout
flags, including a `group_path` for nested Forms. SVG maps isolated groups to
`isolation:isolate`; a future canvas/WebGL compositor can use the data attributes for
non-isolated backdrops and knockout. Exact backdrop and knockout pixel compositing remains
outside the current SVG lowering.

The remaining implementation stages are ordered by the visible compatibility gap:

1. CTM-preserving path/image geometry, complete group-level mask compositing, and mesh shading;
2. embedded fonts and font metrics with a system-font fallback policy;
3. complete annotation appearance and form/widget layers;
4. Canvas/WebGL output and incremental page loading for large documents.

The current SVG path already handles image XObjects and inline images. Inline payloads
are collected with `parse_content_ops_with_resources`, including images nested in Form
XObjects, then passed through pdflite's colour-space/filter decoder. Axial, radial, and
function shading resources are sampled into SVG gradients. Basic alpha and blend mode
state is tracked in a parallel content walk because the compact pdflite JSON entry does
not expose those fields.

Each stage should add a narrow fixture from the pinned pdf.js corpus under
`reference/pdf.js/test/pdfs` and a MoonBit test that checks the structural
output before adding pixel or browser-level assertions. The current fixture run
uses the native CLI for inspection; a browser pixel-diff harness has not been
claimed or added yet.

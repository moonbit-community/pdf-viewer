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

Embedded TrueType fonts have a second rendering path. The viewer reads the
`head`, `maxp`, `loca`, and `glyf` tables, resolves a CID through
`CIDToGIDMap`, and lowers simple or composite glyph outlines into SVG paths.
This is needed for CID fonts whose embedded program has no browser-usable
Unicode `cmap`; the original font data is still emitted as a resource for
hosts that can use it. Vertical writing quads are corrected at the viewer
boundary because PDF vertical advance is negative in user space while the
current pdflite layout helper stores its positive magnitude.

Text paint geometry is carried separately as `glyph_transform`: a one-em,
y-up glyph coordinate system mapped to PDF page coordinates, including CTM,
the per-glyph text matrix, font size, horizontal scale, rise, and vertical
origin. TrueType contours use this matrix and units-per-em normalization.
Fitting a font-wide BBox to a glyph's advance rectangle incorrectly squeezes
narrow letters. SVG fallback text uses the same matrix at font-size 1 and an
alphabetic baseline, so font selection/selection metrics cannot move a
FreeText appearance below its own clipping box. Host-built items may omit
the matrix and retain the older quad-based fallback.

Embedded CFF fonts are decoded into glyph outlines as well. The parser handles
raw CFF and OpenType `CFF ` tables, standard and expert encodings, Name-keyed
and CID-keyed charsets, FDArray/FDSelect, private dictionaries and subroutines,
and the Type 2 charstring operators used by the tested fonts. Parsed outlines
are cached per embedded font and glyph. Single-byte Type 1 programs are also
decoded in the viewer: eexec and PFB framing, ASCII-hex eexec, charstring
encryption, direct-index subroutines, `seac`, and common flex othersubrs are
supported. Single-FD CID-keyed Type 1 programs are also decoded from Binary/Hex
`StartData`, including CIDMap, SubrMap, `lenIV`, and empty-CID fallback.
Multiple FDArray entries and complex CMap-to-CID recovery remain on the text
fallback path.

Text rendering modes 4–7 collect glyph outlines while a text object is read;
the combined path becomes active at `ET`. Later text-object clips are
intersected, and the collector saves/restores them with `q/Q`. Form XObjects
inherit the active clip while keeping their local text clips inside the Form.
Each text-object clip is resolved once and shared by subsequent page items.
The current path reconstruction covers CFF, single-byte Type 1, and embedded
TrueType outlines;
when a glyph outline cannot be decoded, the renderer leaves that clip
unavailable instead of treating the missing glyph as an empty path. Type 3
fonts do not contribute to this clip, as required by PDF text semantics.

`PdfPageModel::viewport` follows pdf.js' `PageViewport` affine matrix,
including nonzero media-box origins. The SVG renderer uses the equivalent
relative transform after subtracting the page origin from display-list
coordinates, so the public viewport matrix and rendered page stay in the same
coordinate convention.

The current renderer has several concrete compatibility improvements: it emits the pdf.js-style
full viewport matrix, lowers path-only coloured tiling patterns to SVG `pattern` definitions,
and applies a retained `/Matrix` at the paint site. ShadingType 4/5/6/7 streams are decoded into
`PdfMeshTriangle` records; PatternType 2 resources are clipped to their source path, while the
SVG fallback uses barycentric microtriangles and leaves per-vertex colours available for a future
Canvas/WebGL Gouraud renderer. Explicit clipping paths are serialized as
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

1. Multiple-FD/complex-CMap CID-keyed Type 1 outlines, complete font metrics and system-font fallback policy;
2. CTM-preserving path/image geometry, complete group-level mask compositing, and pixel-level
   Gouraud interpolation for mesh triangles;
3. complete annotation appearance and form/widget layers;
4. Canvas/WebGL output and incremental page loading for large documents.

Annotation parsing and SVG lowering live in `annotations.mbt` and
`annotations_svg.mbt`. The viewer reads the original `/Annots` array: popup
children and malformed annotations are skipped without renumbering valid source
indices. PDFDocEncoding/UTF-16 strings, normalized `/C` components, quads, lines,
vertices, ink paths, and display/print flags are retained independently of the
fallback drawing.

Normal appearance streams reuse the content collector with their own resource
dictionary and BBox. The fragment is clipped to its source box, then mapped
through `/Matrix` into `/Rect`; a zero-area transformed BBox uses the PDF
translation fallback. Item IDs are allocated after page content and preceding
appearances, avoiding SVG reference collisions. Appearance fonts are resolved
at each text paint site, including nested Form scopes, and embedded programs
receive appearance-specific CSS family names. The outer transparency group
preserves isolation/knockout metadata with the same compositing limits as page
Forms. A valid empty stream suppresses geometry fallback.

Widget metadata distinguishes inherited field values from each radio/checkbox
on-state and checked state. The current fallback is a simple read-only display;
it does not implement `/DA`/`/DR` layout, multiline/comb/password formatting,
choice selection or export mappings, editing, or JavaScript actions.

Document navigation/metadata JSON methods adapt pdflite reader outputs without
claiming the pdf.js JSON schema. Page labels provide a decimal fallback even
when pdf.js would return null. Reading optional-content configuration does not
yet filter the display list by layer visibility.

The current SVG path already handles image XObjects and inline images. Inline payloads
are collected with `parse_content_ops_with_resources`, including images nested in Form
XObjects, then passed through pdflite's colour-space/filter decoder. Axial, radial, and
function shading resources are sampled into SVG gradients. Basic alpha and blend mode
state is tracked in a parallel content walk because the compact pdflite JSON entry does
not expose those fields.

Each stage should add a narrow fixture from the pinned pdf.js corpus under
`reference/pdf.js/test/pdfs` and a MoonBit test that checks the structural
output before adding pixel or browser-level assertions. `tools/corpus.mbtx`
builds and runs the native CLI with per-file timeouts and fresh artifact paths,
checks error exit codes and SVG creation, and writes a JSON report. These are
first-page conversion checks, not visual conformance tests. The measured result
and known failures are recorded in `docs/validation.md`; a browser pixel-diff
harness has not been claimed or added yet.

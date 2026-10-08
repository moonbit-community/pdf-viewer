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

The next implementation stages are ordered by the visible compatibility gap:

1. image XObject decoding to browser data URLs, then inline images;
2. graphics state (fill/stroke colors, line width, alpha, clipping and blend);
3. embedded fonts and font metrics with a system-font fallback policy;
4. annotations and form/widget layers;
5. Canvas/WebGL output and incremental page loading for large documents.

Each stage should add a narrow fixture from the pinned pdf.js corpus under
`reference/pdf.js/test/pdfs` and a MoonBit test that checks the structural
output before adding pixel or browser-level assertions.

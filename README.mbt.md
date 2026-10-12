# PDF Viewer

A PDF viewer, editor and rendering library written in [MoonBit](https://www.moonbitlang.com/),
built on [`moonbitlang/pdflite`](https://mooncakes.io/docs/moonbitlang/pdflite).
The browser interface uses the MoonBit [Rabbita](https://mooncakes.io/docs/moonbit-community/rabbita)
framework; its views and reader controller are in [`cmd/viewer/`](cmd/viewer/).
The project provides a standalone browser application, structured document and
page APIs, a Canvas2D pixel backend, and SVG compatibility output for native applications.

The root package exposes the public API through [`api.mbt`](api.mbt).
PDF implementation and whitebox tests live in [`internal/engine/`](internal/engine/),
generated CMap/font resources in their own internal packages, and public consumer
tests in [`tests/api/`](tests/api/). See [package boundaries](docs/architecture.md#package-boundaries).

## Features

- Open local PDF files through the file picker or drag and drop.
- Navigate documents with page controls, thumbnails, outlines, and page labels.
- Toggle PDF layers and configurations, respecting radio groups, locks and display/print usage.
- Follow PDF links and open readonly annotation comments with mouse or keyboard.
- Read tagged headings, lists, tables, and alternative text through a page-local DOM/ARIA layer.
- Zoom, rotate, select and copy text, and search across pages.
- Decode in a browser Worker, mount nearby pages/thumbnails, and retain bounded page/render caches.
- Print the complete document at its original page sizes using the toolbar or Ctrl/Cmd+P.
- Create text annotations, highlights and ink; move, resize, delete, undo and redo edits.
- Fill AcroForm text, choice, checkbox and radio fields, then download and reopen the edited PDF.
- Add handwritten or image signatures with portable PDF annotation appearances.
- Open password-protected documents and inspect document information and attachments.
- Export native page plans for Canvas rendering, or SVG compatibility output.
- Access page geometry, text, display lists, and selection data through MoonBit APIs.
- Inspect text sources, original character bytes, lexical spans, runs/paragraphs, and recovery diagnostics.

Rendering support and compatibility limitations are documented in
[Implementation and Development Notes](docs/development.md).

## Getting Started

Install the [MoonBit toolchain](https://www.moonbitlang.com/download/) and
Node 22.13.0 or newer with npm, then clone the repository:

```sh
git clone https://github.com/moonbit-community/pdf-viewer.git
cd pdf-viewer
moon install
npm ci --prefix tools/web-assets --ignore-scripts --omit=optional
moon run tools/dev.mbtx 4312
```

Open [http://127.0.0.1:4312/](http://127.0.0.1:4312/) and select a PDF file.
Local files are read and decoded in the browser. The locked npm dependencies
provide the LittleCMS and standalone JBIG2 assets; the build verifies and copies
them locally. Generated JS/Wasm assets are ignored by Git, and opening a PDF
does not fetch them from npm or a CDN.

Select **Edit / Fill** to fill fields or use the annotation/signature tools, then
**Download** (Ctrl/Cmd+S) to save the edited PDF. See [editing and saving](docs/editor.md)
for controls, supported fields and limitations. Handwritten/image signatures are
visual annotations; certificate signing is separate work.

Select **Layers** to change layer visibility or restore a configuration. Display and
print usage can differ; layer choices remain viewing preferences when saving.
See [layer controls](docs/layers.md).

## Command-Line Usage

Render the first page of a document as SVG:

```sh
moon run --target native cmd/main -- input.pdf page-1.svg
```

Provide a one-based page number to render another page:

```sh
moon run --target native cmd/main -- input.pdf page-3.svg 3
```

For the structured pixel path, export a page plan and replay it in a Canvas host:

```sh
moon run --target native cmd/main -- input.pdf page-1.canvas.json
node tools/render_canvas.mjs page-1.canvas.json page-1.png
```

The host runner requires `@napi-rs/canvas` and the built web bridge; follow the
[fresh-checkout setup](docs/validation/native-canvas-setup.md) first.
See the [A2 acceptance and target matrix](docs/a2-acceptance.md) for setup,
codec/CMM availability, resource bounds, and remaining rendering limitations.
SVG emits diagnostics for semantics that need the pixel backend.

## Static Hosting

The web viewer can be published at
[moonbit-community.github.io/pdf-viewer](https://moonbit-community.github.io/pdf-viewer/).
The [GitHub Pages workflow](.github/workflows/pages.yml) builds and checks the site
on every `master` push. Enable **Settings → Pages → Source: GitHub Actions**, then
run the workflow once to publish it. Until Pages is enabled, builds still produce
a verified site artifact. See [website setup and deployment](docs/pages.md).

Install the locked asset dependencies (once per checkout or lockfile change),
then build the browser application:

```sh
npm ci --prefix tools/web-assets --ignore-scripts --omit=optional
moon install
moon run tools/build_pages.mbtx
```

Serve the generated `_build/pages/` directory with a static HTTP server. It includes
the Worker modules, both generated MoonBit applications, XFA and codec assets,
and their licenses, while excluding development test PDFs. The deployed application
runs without a native PDF process or a PDF.js renderer. `pdfjs-dist` supplies only the standalone JBIG2
Wasm asset to the product build; its renderer is not deployed. The build does
not install npm dependencies automatically.

## Documentation

- [Implementation details, API reference, and development commands](docs/development.md)
- [Architecture](docs/architecture.md)
- [Editing, form filling, signatures and saving](docs/editor.md)
- [MoonBit/Rabbita browser interface](docs/frontend.md)
- [Web viewer and GitHub Pages deployment](docs/pages.md)
- [Compatibility roadmap](docs/TODO.md)
- [Validation methodology and results](docs/validation.md)
- [Contributor workstreams](docs/PARALLEL.md)


The standalone viewer supports readonly annotation/field fallbacks, HTTP Range
loading, and dynamic XFA pages. XFA layout and native controls reuse the pinned
Apache-licensed PDF.js XFA components; the PDF reader and Canvas pipeline remain
this project's pdflite/MoonBit implementation. See [readonly acceptance and
CI limits](docs/readonly-completion.md) and [editor acceptance](docs/editor.md).
Authenticated encrypted PDFs can be edited and saved with their original
passwords and permissions. Dynamic XFA editing and certificate signatures remain
unsupported, and known visual differences prevent a claim of full PDF.js parity.

## License

Licensed under the [Apache License 2.0](LICENSE).
Bundled CMap data retains its [upstream attribution and license](assets/cmaps/README.md).
Image codecs and colour engines retain their respective notices in
[`codecs/jpx`](codecs/jpx/README.md), [`codecs/jbig2`](codecs/jbig2/README.md),
and [`web/vendor/lcms-wasm`](web/vendor/lcms-wasm/README.md).
Bundled Standard 14 replacement fonts retain their [font licenses and provenance](assets/standard14/README.md).

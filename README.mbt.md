# PDF Viewer

A read-only PDF viewer and rendering library written in [MoonBit](https://www.moonbitlang.com/),
built on [`moonbitlang/pdflite`](https://mooncakes.io/docs/moonbitlang/pdflite).
The project provides a standalone browser application, structured document and
page APIs, and SVG output for native applications.

## Features

- Open local PDF files through the file picker or drag and drop.
- Navigate documents with page controls, thumbnails, outlines, and page labels.
- Zoom, rotate, select and copy text, and search across pages.
- Open password-protected documents and inspect document information and attachments.
- Export pages as SVG through the native command-line interface.
- Access page geometry, text, display lists, and selection data through MoonBit APIs.

Rendering support and compatibility limitations are documented in
[Implementation and Development Notes](docs/development.md).

## Getting Started

Install the [MoonBit toolchain](https://www.moonbitlang.com/download/), then clone
the repository:

```sh
git clone https://github.com/moonbit-community/pdf-viewer.git
cd pdf-viewer
moon run tools/dev.mbtx 4312
```

Open [http://127.0.0.1:4312/](http://127.0.0.1:4312/) and select a PDF file.
Local files are read and decoded in the browser.

## Command-Line Usage

Render the first page of a document as SVG:

```sh
moon run --target native cmd/main -- input.pdf page-1.svg
```

Provide a one-based page number to render another page:

```sh
moon run --target native cmd/main -- input.pdf page-3.svg 3
```

## Static Hosting

Build the browser application:

```sh
moon run tools/build_web.mbtx
```

Serve the `web/` directory, including the generated `web/_generated/pdf.js`,
with a static HTTP server. The deployed application runs without a native PDF
process or a PDF.js runtime.

## Documentation

- [Implementation details, API reference, and development commands](docs/development.md)
- [Architecture](docs/architecture.md)
- [Compatibility roadmap](docs/TODO.md)
- [Validation methodology and results](docs/validation.md)
- [Contributor workstreams](docs/PARALLEL.md)

## License

Licensed under the [Apache License 2.0](LICENSE).
Bundled CMap data retains its [upstream attribution and license](assets/cmaps/README.md).

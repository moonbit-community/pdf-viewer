# Standalone JBIG2 decoder provenance

The tracked source in this directory contains only JBIG2 and its fax primitive
dependencies. It does not contain or call a whole-PDF renderer. The Wasm asset
is copied from an npm dependency and ignored by Git.

- Browser binary: `jbig2.wasm`, copied unchanged from
  `pdfjs-dist@6.4.299/wasm/jbig2.wasm` on npm,
  SHA-256 `466f45c2a61a698152fb5400c27e56ff2ceb73dcb71fde3fc366a502308eaab0`.
- Native source: PDFium revision
  `bb1f9f71e7b15afdd5937adf8cfe5807522b882f` from
  https://pdfium.googlesource.com/pdfium.
- Standalone build header definitions: Mozilla `pdf.js.jbig2` revision
  `15f6f9357c5e5e30285eb83aa08e5fe1a16ab77a` from
  https://github.com/mozilla/pdf.js.jbig2.
- Native closure: 97 dependency/source files, 601,304 upstream bytes, found with
  `g++ -std=c++20 -DNDEBUG -MM` over Mozilla's 24 listed translation units.
  The two upstream repository licenses are also retained.

`SOURCE_MANIFEST.json` pins every upstream and vendored file hash. The only
source adjustment rewrites quoted `core/...` and `build/...` include paths to
relative paths, for source-tree-independent package builds. No decoder
algorithms are changed. `tools/jbig2/vendor-native.py` reproduces the closure
from checkouts at these exact revisions and verifies all hashes.

PDFium's BSD-style terms and the Apache-2.0 terms are retained in
`LICENSE_JBIG2`, `LICENSE_PDFJS_JBIG2`, `pdfium/LICENSE`, `mozilla/LICENSE`,
and `LICENSE_CHROMIUM` (the two Chromium build headers).
This is not Artifex `jbig2dec`; no AGPL decoder is included.

## Asset delivery

From the repository root:

```sh
npm ci --prefix tools/web-assets --ignore-scripts --omit=optional
node tools/prepare_web_assets.mjs
```

`tools/web-assets/package.json` pins the exact package version; its lockfile pins
the archive integrity and dependency tree. Preparation checks the package
version and Wasm SHA-256 before copying to this directory. The web build runs
that preparation and copies the binary, adapter and tracked license notices to
`web/vendor/jbig2/`; it never installs npm dependencies itself. Only the
standalone decoder is deployed, not the PDF.js renderer or optional Canvas
package. This pins acquisition of the published binary; it does not establish
a bit-identical local C/C++-to-Wasm build. Native source provenance and build
remain independent of the npm asset.

Only the 103,671-byte Wasm binary and the JS adapter are needed by the browser;
native source is not shipped to browser clients. Native builds use the vendored
source and an installed C++20 compiler, never an installed system PDFium.

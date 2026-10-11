# LittleCMS Wasm runtime

Build-generated copies of unmodified `dist/lcms.js` (renamed `.mjs`) and
`dist/lcms.wasm` from npm `lcms-wasm@1.0.5`:
https://www.npmjs.com/package/lcms-wasm/v/1.0.5 .
The two generated assets are ignored by Git; this README and license notices
remain tracked.
Upstream adapter: https://github.com/mattdesl/lcms-wasm .
The shipped engine identifies its LittleCMS version as 2.16 (`LCMS_VERSION=2160`).
Both upstreams are MIT; license texts are retained alongside the assets.
The adapter is implemented in `../../pdf-icc.mjs`, not patched into the bundle.

This Wasm module is a JavaScript-hosted engine and does not make the MoonBit
`wasm` or `wasm-gc` targets ICC-capable by itself. Those targets currently use
PDF Alternate; browser/Node MoonBit `js` uses this runtime after initialization.

## Provenance and repeatable asset acquisition

From the repository root:

```sh
npm ci --prefix tools/web-assets --ignore-scripts --omit=optional
node tools/prepare_web_assets.mjs
```

The exact version and dependency tree are pinned in
`tools/web-assets/package.json` and its lockfile. Preparation checks the version
and both asset SHA-256 values before copying them here. The normal web build
invokes preparation too, but never installs npm dependencies automatically.
Install scripts are disabled; the wrapper's declared Tape dependency stays in
local `node_modules` and is not deployed.

- Registry archive: https://registry.npmjs.org/lcms-wasm/-/lcms-wasm-1.0.5.tgz
- npm archive integrity (SHA-512/base64):
  `bQpBF4BvoHY//Gq7k67VD9l+BEk6dmaROAB+ci83ZajOurOUPAcwfi3z5VzzAf27qccIE867kYc+jk6/wPelcA==`
- `lcms.wasm` SHA-256:
  `dbcbee3fb3a49459a60bb6b29d6ab25fe7c219b0cc0c2b9579c0cc78f7390ddd`
- `lcms.mjs` SHA-256:
  `1a5c8f81186211856ba7c5d6841e35fe3fa901b857a247f72318e1652c5e1cec`

The runtime assets are byte-identical to that archive's `package/dist/lcms.wasm`
and `package/dist/lcms.js` (the latter is renamed for ESM hosting). The archive
also includes the wrapper sources `lib/` and `build.sh`. The build script uses
LittleCMS C sources from https://github.com/mm2/Little-CMS and Emscripten, disables
filesystem/pthreads, and targets web, workers and Node. The published module
reports engine version 2.16. The upstream package does not pin its Emscripten
compiler, so we claim reproducible acquisition of verified release assets,
not a locally proven bit-identical rebuild from C. No runtime asset is fetched
from npm or a CDN when opening a PDF; it is served from the local web build
using the existing same-origin URLs in the Worker and Canvas host.

Both LittleCMS and the wrapper are MIT licensed (the two adjacent license
files). This asset is required for actual ICC colour conversion in the JS
viewer; it contains no application credentials or private data. Adapter bounds
and explicit lifecycle are implemented in `web/pdf-icc.mjs`.

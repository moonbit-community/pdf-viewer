These 36 unmodified modules come from Mozilla PDF.js revision
`89b500f5e1d98ed89bb90211e45b28730b2d99ac`, under Apache-2.0.
`UPSTREAM.json` records every source SHA-256. The XML parser, XFA template,
data binding, pagination and DOM presentation are reused as a component.

`tools/prepare_xfa_assets.mjs` verifies the files and bundles only the XFA
factory and XfaLayer with locked esbuild-wasm. Its dependency check rejects
the PDF reader, document, evaluator, Worker and Canvas renderer. PDF objects,
streams and fonts remain the responsibility of pdflite and this project's
existing font pipeline.

The small injected Map adapter supplies the upstream collection API inside
the bundle on older JavaScript hosts. It leaves the upstream files and the
application's global Map unchanged. Generated output and the license are
copied to `web/vendor/xfa/`; builds require no network access after npm ci.

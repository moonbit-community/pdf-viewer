# Browser image Flate adapter

The browser Worker uses [pako 2.1.0](https://github.com/nodeca/pako/tree/2.1.0)
for bounded zlib image expansion and level-1 PNG compression. Its source is
licensed under MIT and Zlib; the complete notice is copied to `LICENSE` beside
the generated `pako.mjs` module in the static build.

`tools/web-assets/package-lock.json` pins the npm archive and integrity.
`tools/ci/pako-assets.json` pins individual source and license SHA-256 hashes.
After the normal locked npm install, `tools/prepare_flate_assets.mjs` verifies
these inputs and bundles `tools/pako_adapter.mjs` with pinned esbuild 0.25.12.
Both generated files are ignored, and no npm/CDN fetch occurs at viewer runtime.

The adapter uses pako's single-stream zlib driver to retain the PDF reader's
trailing-data behavior. It validates the header and Adler-32 trailer and bounds
retained output. Invalid, truncated, dictionary-dependent and oversized streams
fall back to the portable decoder, including its prefix recovery and error
precedence. Other MoonBit targets and standalone bridge consumers retain their
existing codec unless the JS host is explicitly installed.

`node tools/pixels/image_flate_test.mjs` compares the actual release bridge with
and without the host. An optional PDF path additionally checks every page's
complete payload after canonicalizing lossless PNG samples.

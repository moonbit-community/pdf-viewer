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

After verifying upstream hashes, the build applies the local
`tools/pako_deflate_transform.mjs` optimization to `slide_hash`. The aligned
16-bit position tables are updated two entries at a time, using branchless
saturating subtraction. Hash positions, match choices and compressed bytes
remain identical to upstream; source and license attribution are retained.
The build fails if the pinned source marker or transform application changes.
`node tools/pixels/pako_deflate_test.mjs` exhausts all 16-bit positions for each
supported window size and compares complete zlib bytes against upstream pako
and decoded samples against Node zlib.

The same verified build applies `tools/pako_inflate_transform.mjs` to the
low-level inflater's direct output match loop. Distance-one matches repeat
the preceding output byte, so a native typed-array fill replaces their scalar
copies. Window-backed matches and all header, distance, trailer and budget
checks retain the original code. The transform requires one exact source block
and the build requires one application. `node tools/pixels/pako_inflate_test.mjs`
compares low-level output, input positions, bit state, checksum and status with
the pinned original driver across input/output splits and window boundaries.

The adapter uses pako's single-stream zlib driver to retain the PDF reader's
trailing-data behavior. It validates the header and Adler-32 trailer and bounds
retained output. Invalid, truncated, dictionary-dependent and oversized streams
fall back to the portable decoder, including its prefix recovery and error
precedence. Other MoonBit targets and standalone bridge consumers retain their
existing codec unless the JS host is explicitly installed.

`node tools/pixels/image_flate_test.mjs` compares the actual release bridge with
and without the host. An optional PDF path additionally checks every page's
complete payload after canonicalizing lossless PNG samples.

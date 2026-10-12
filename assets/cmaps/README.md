# Adobe CMap data

The generated [`internal/cmap_assets/assets.mbt`](../../internal/cmap_assets/assets.mbt) embeds the binary CMaps from
[PDF.js](https://github.com/mozilla/pdf.js/tree/89b500f5e1d98ed89bb90211e45b28730b2d99ac/external/bcmaps).
Their Adobe redistribution terms are preserved in `LICENSE`.

These assets provide character-code/CID and CID/Unicode mappings. They contain
no font programs. The MoonBit binary decoder is based on PDF.js's Apache-2.0
`src/core/binary_cmap.js` at the same revision.

To reproduce the generated data with that reference checkout:

```bash
moon run tools/cmap_assets.mbtx
```

# Standard 14 font programs

The generated `standard14_assets.mbt` contains the unmodified font bytes from
[the pinned PDF.js reference](https://github.com/mozilla/pdf.js/tree/89b500f5e1d98ed89bb90211e45b28730b2d99ac/external/standard_fonts).
The ten Foxit faces originate in PDFium and retain `LICENSE_FOXIT`. Their `.pfb`
filenames contain raw CFF programs; the generator preserves those bytes.
Original code copyright 2014 Foxit Software Inc.; font data copyright 2014
PDFium Authors. See `LICENSE_FOXIT` for the redistribution terms.
The four Helvetica replacements are Liberation Sans 1.07.4 and retain
`LICENSE_LIBERATION` (GPL v2 with its font exception). These licenses apply to
the font assets; the viewer's source remains Apache-2.0.

`inventory.json` records original filenames, byte lengths and SHA-256 hashes.
The existing CFF/TrueType readers build outlines from those bytes; pdflite's
AFM data and PDF widths still determine text positioning. No host-installed
font is needed for this path. Embedded PDF programs take precedence.

Regenerate with the exact reference checkout:

```bash
moon run tools/standard14_assets.mbtx
```

For redistribution, preserve both license files and the inventory/reference
link. The generator makes no changes to the original font programs.

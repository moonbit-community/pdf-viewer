# Pinned JPEG2000 decoder reuse

This directory contains the dependency closure of `trkbt10/jpeg2000@0.2.0`
(Apache-2.0), fetched from Mooncakes. The original decoder is by trkbt10:
<https://github.com/trkbt10/jpeg2000_mbt>. The original license is `LICENSE`.
`UPSTREAM.json` records every imported source file's SHA-256 before adaptation.
No upstream specifications, reference C libraries or unrelated corpus were copied.

Changes from the fetched package:

- Rename the module prefix to `moonbit-community/pdf-viewer/vendor/jpeg2000`.
- Omit unused top-level diagnostic/audit decoder wrappers; the PDF adapter calls only the all-component orchestration entry.
- Omit upstream executable/test source and remove their imports and clang-only
  compiler overrides; use the consuming project's compiler instead.
- Add `components.mbt`, a genuinely public all-component API that preserves each
  component's dimensions, precision, signedness and little-endian sample layout.
  It uses the copied package's internal orchestration legally within this module.
  The viewer never imports another module's `internal` package.
- Reject upstream placeholder `zero_recon` outputs rather than silently presenting
  an undecoded colour image as valid grayscale/black.
- Format with the current project MoonBit formatter and generate fresh interfaces.

The entropy, packet, quantization, MCT and wavelet implementation is reused, not
rewritten. `codecs/jpx` adds PDF/JP2-facing bounds, box metadata, channel/alpha,
palette and packed-sample adaptation. No browser JP2 image element, whole-PDF
renderer, system OpenJPEG runtime or separate Wasm payload is needed to decode.

Packaging measured after public API/interface generation: 114 files, 802,916 bytes
uncompressed (about 146,096 bytes gzip concatenated). This is source packaging,
not a browser bundle size claim; the MoonBit linker removes unused codec paths.

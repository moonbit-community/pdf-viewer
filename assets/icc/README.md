# Small ICC fixtures

- `CGATS001Compat-v2-micro.icc`: 8,464-byte CMYK v2 LUT profile by
  Compact ICC Profiles, copied unchanged from `pdfjs-dist@6.4.299/iccs/`.
  Its CC0 license is retained as `LICENSE-CGATS001`.
  Upstream: https://github.com/saucecontrol/Compact-ICC-Profiles
- `gray-gamma22.icc`, `rgb-gamma22.icc`, `srgb-matrix.icc`: original tiny test
  profiles generated with LittleCMS 2.14 (`cmsCreateGrayProfile` with D65 and
  gamma 2.2; `cmsCreateRGBProfile` with D65, sRGB primaries and gamma 2.2;
  `cmsCreate_sRGBProfile`). Their profile copyright tag is "No copyright,
  use freely". Creation timestamps are fixed to 2024-01-01 00:00:00 for
  reproducibility. The two explicit-gamma fixtures use x/y/Y whitepoint
  (0.3127, 0.3290, 1), primaries R(0.64,0.33,1), G(0.3,0.6,1), B(0.15,0.06,1).

The base64 copies in `colour_icc_fixtures_wbtest.mbt` are byte-identical and
allow the same tests to build without filesystem access on all targets.
These test profiles do not change the device-CMYK fallback policy.

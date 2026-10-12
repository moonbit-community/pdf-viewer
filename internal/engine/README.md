# PDF engine

This package owns PDF implementation and its whitebox tests. The root
`moonbit-community/pdf-viewer` package exposes the supported public entry point.

Shared model types and their methods stay in this package because MoonBit public
methods belong to the package that defines their type. Content collection also
shares private resource contexts with fonts, patterns, masks and accessibility.
Moving those helpers into separate packages would require new interfaces and
visibility changes; filesystem cleanup should not introduce those changes.

The central files have separate responsibilities:

- `model.mbt`: page, item, geometry and resource data.
- `document.mbt`: opening and document-level APIs.
- `page_api.mbt`: viewport conversion and page-level APIs.
- `collector.mbt`: content-state interpretation and page-item lowering.
- Feature files: font, text, image, colour, annotation and editor implementation.
- `deprecated.mbt`: compatibility promotions for derived public types.

Pinned CMap and Standard 14 bytes are loaded from the independent
`internal/cmap_assets` and `internal/font_assets` packages. Their generators are
`tools/cmap_assets.mbtx` and `tools/standard14_assets.mbtx`.

`*_wbtest.mbt` files exercise private implementation. Tests in `tests/api/`
exercise the root facade as a consumer; documentation examples also use that
public entry point.

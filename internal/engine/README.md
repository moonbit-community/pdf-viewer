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
- `collector.mbt`: page-model assembly and page geometry.
- `collector_entries.mbt`: collected entry types and content-operator interpretation.
- `path_builder.mbt`: owned buffers for consecutive path construction, frozen at interpreter boundaries.
- `collector_items.mbt`: lowering collected entries into paths, text, images and shading.
- `canvas_program.mbt`: prepared browser paints, reading order and bounded glyph resource ownership.
- `canvas_outlines.mbt`: shared Type1/CFF fill geometry keyed by PDF font encoding and character code.
- `collector_state.mbt`: Form groups, graphics-state resolution and paint attributes.
- `svg.mbt`: SVG page wrapper and source-order item traversal.
- `svg_groups.mbt`: transparency-group and masked-run traversal.
- `svg_paths.mbt`: vector paths, stroke styles and geometry serialization.
- `svg_images.mbt`: image placement and image-local mask serialization.
- `svg_shading.mbt`: gradients, meshes and pattern definitions.
- `svg_clip.mbt`: clipping and soft-mask definitions and scopes.
- `svg_text.mbt`: text runs, font declarations and text serialization.
- `type1_font.mbt`: Type 1 font model, loading and PDF glyph-outline entry points.
- `type1_parser.mbt`: Type 1 tokens, encrypted programs, PFB containers and procedures.
- `type1_charstring.mbt`: glyph/subroutine execution and outline commands.
- `type1_encoding.mbt`: mapping PDF character codes to Type 1 glyph names.
- Feature files: font, text, image, colour, annotation and editor implementation.
- `deprecated.mbt`: compatibility promotions for derived public types.

These are file boundaries within the same package. Helpers retain package-private
visibility and callers use the same names. Keep the operator interpreter,
page-item lowering and CharString interpreter intact when reorganizing files;
changes to those state machines should be reviewed separately from file moves.

Pinned CMap and Standard 14 bytes are loaded from the independent
`internal/cmap_assets` and `internal/font_assets` packages. Their generators are
`tools/cmap_assets.mbtx` and `tools/standard14_assets.mbtx`.

`*_wbtest.mbt` files exercise private implementation. Tests in `tests/api/`
exercise the root facade as a consumer; documentation examples also use that
public entry point.

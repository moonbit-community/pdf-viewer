# PDF layers

The layer panel uses MoonBit and Rabbita. PDF objects, names, usage states,
alternate configurations, radio groups and locks come from pdflite's OCG model.
Nested `/Order` labels are projected from its resolved objects with a depth limit
of 10 and a 10,000-entry budget; omitted groups remain available in the panel.

Select **图层** when the document contains optional content. Check a layer to
show it; enabling a member of `/RBGroups` disables its peers. `/Locked` controls
are disabled. Enabling a radio member that would disable an enabled locked peer
fails without changing the current state. The configuration selector offers the
default `/D` and alternate `/Configs`. **恢复此配置** resets user toggles.

Display applies `/Usage /View /ViewState`; printing independently applies
`/Usage /Print /PrintState`. A layer with `/OFF` usage is hidden in that intent.
Base-state and configuration `/OFF` still hide it even if usage says `/ON`.
An explicit user toggle overrides usage for both display and print, matching
the pinned PDF.js reader. Hints beside the controls show differing print states.

Layer changes rebuild page paint, text, annotation targets and native field
metadata. They clear old selection, search results and prepared print pages,
cancel stale thumbnail work and invalidate both render caches. An active form
input commits before the change. Editing undo/redo retains the chosen layers;
Range hydration and completion before editing retain them as well. Late replies
cannot update a replacement document. The sidebar shares the reader's CSS grid
row, so wrapped reader/editor toolbars remain usable on narrow windows.

These choices are viewing preferences. Downloading the source or an edited PDF
preserves its original `/OCProperties`; layer toggles do not mark it unsaved.
The selector creates a fresh configuration state, including `/Unchanged`
initialization, rather than retaining a previous configuration's overrides.
Environmental `/AS` rules for zoom, language and user identity are not applied.

## MoonBit and Worker interfaces

`with_optional_content_visibility(object_number, visible)` returns an immutable
document and validates radio/locked constraints. `with_optional_content_config`
selects `None` for the default or a zero-based alternate index and resets toggles.
The existing `with_optional_content_state` remains a low-level host override.

`page(number, optional_content_intent=Print)` and
`pages(optional_content_intent=Print)` collect print-visible content. The default
is `Display`. `Export` also applies `/Usage /Export /ExportState` for library
consumers. Hidden content is filtered before text selection and display-list
collection, including nested Forms, OCMD predicates and layer-bound annotations.

`optional_content_layers_json()` returns `None` without `/OCProperties` or a
manifest with `config_index`, `configs`, `groups`, `order` and `radio_groups`.
Group IDs are PDF indirect object numbers; names decode PDFDocEncoding/UTF-16.
The browser bridge exports `optional_content_info`,
`set_optional_content_visibility` and `set_optional_content_config` (`-1` selects
the default). The Worker returns `layers: null` or the manifest object and clears
render caches only after successful changes. Display and print retain separate
cache keys and the same page-specific embedded-font namespace.

## Validation

Eight core regressions cover immutable state, display/print/export usage,
configuration resets, locked radio failure atomicity, Unicode/nested order,
bounded cyclic order, hidden Form/path/annotation/widget content, OCMD predicates
and save/reopen preserving the original layer configuration.

`tools/layers_browser_test.mjs` has 11 Chromium checks using actual native clicks,
Canvas output, field input, undo/redo, downloads, Range loading and replacement
races. Printed colour samples agree with the pinned PDF.js print intent. The
real `issue17679.pdf` and `issue17679_2.pdf` fixtures also compare 15 colour
samples in three visibility states, including nested Forms and transparency.
The real-fixture samples allow and record a maximum one-byte RGB rounding
difference (the fixture's `0.3` green component becomes 77 versus PDF.js's 76).
These sampled comparisons do not establish whole-document pixel parity.
CI checks every named case and retains reports/PDFs/screenshots in
`_build/layers-test-*/` alongside the reader and editor reports.

```sh
moon test internal/engine/optional_content_layers_wbtest.mbt --target js
moon run tools/build_web.mbtx
moon run tools/dev.mbtx 4315
# In another terminal:
node tools/layers_browser_test.mjs http://127.0.0.1:4315
```

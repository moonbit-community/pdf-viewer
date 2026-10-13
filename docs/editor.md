# Editing, form filling and signatures

The browser editor is implemented in MoonBit and Rabbita. PDF edits reuse
pdflite's object model, content operations and writer. Native input/select
controls, Pointer Events and Canvas pixel acquisition provide browser primitives.

## Using the editor

Open a PDF and select **Edit / Fill**. AcroForm and dynamic XFA fields become native controls; readonly
fields remain disabled. Text changes commit when the field loses focus. Download
and print also flush the active field.

The tools add text boxes, rectangular highlights, ink, handwritten signatures
and image signatures. Enter text, choose a colour/size, then drag on the page.
To highlight existing text, select it and choose **Highlight selected text**.
The annotation retains the selected glyph quadrilaterals, including shear and
rotation. A selection spanning pages creates one annotation per page and one
undo step for the whole selection.
Select an annotation to edit its text/style, drag to move it, or drag the lower
right handle to resize it. Delete, undo and redo are available in the toolbar;
Ctrl/Cmd+Z, Ctrl/Cmd+Shift+Z and Ctrl/Cmd+Y work outside native inputs. Consecutive
ink/signature strokes on the same page and tool form one annotation; each stroke
can be undone.

**Download** or Ctrl/Cmd+S saves a new PDF with the current edits. Downloading records
the saved snapshot, so undoing away from it marks the document as unsaved.
Downloading after undoing every edit records the original PDF as the saved snapshot.
Replacing a document with unsaved edits asks whether to discard them; closing
the browser also uses its native unsaved-change prompt. A host calling
`loadFile`/`closeDocument` directly controls replacement itself.

## Supported data and persistence

- FreeText, Highlight, Ink and image Stamp additions write explicit normal
  appearance streams. Existing unlocked annotations can be selected, moved,
  resized or deleted; text/style appearance regeneration is supported for the
  editor's four annotation types. Rich-text FreeText edits replace `/RC` with
  plain-text contents.
- AcroForm Tx, Ch and non-pushbutton Btn fields persist `/V`, choice `/I`, and
  button `/AS`. Inherited field values and all widgets of a shared field update
  across pages. Choice controls retain export/display pairs and duplicate-value
  selection indices. Readonly and MaxLen constraints are enforced; radio groups
  requiring a selection cannot be cleared.
- Text/choice appearance generation reuses the existing DA/DR and font pipeline.
  The existing font and encoding take precedence when they represent the entered
  text, including non-Latin characters. FreeText style changes retain the DA font
  name. When the font cannot encode browser-entered text, the browser supplies a
  raster appearance using its available fonts. Unicode
  field/annotation values remain PDF strings, while the saved pixels render
  without requiring those fonts on another machine. This fallback does not
  promise the original font, precise typography, or searchable text inside the
  raster appearance itself.
- Image signatures embed RGB pixels and a soft alpha mask. Handwritten signatures
  are Ink annotations. Both remain visible when another reader opens the PDF.
  They do not create or validate a cryptographic signature.
- Password-authenticated PDFs support annotation editing and form filling. Saved
  files retain the original RC4/AES encryption settings, file ID, both passwords,
  metadata-encryption flag and permission mask. User credentials enforce
  annotation/form permissions; an authenticated owner can edit supported content.
  Files with an empty user password open without a password prompt.
- Dynamic XFA bound text inputs, textareas, checkboxes, radio groups and single-choice controls update their datasets
  through the pinned XFA binder and XML serializer. Undo restores the original
  dataset snapshot; download and print flush the active control. Templates,
  unrelated packets and PDF objects remain available after saving and reopening.
  The current editing session retains its original layout; reopening can paginate
  differently when values affect layout. XFA scripts remain disabled.
  Unbound controls, inherited template readonly/protected controls and
  unsupported multiselect controls remain readonly. The Worker also rejects
  snapshots targeting these IDs; edits cannot appear saved while being discarded
  by the upstream dataset serializer.

Saving appends an incremental revision through
`pdflite.pdf_write_document_incremental_update`, retaining the original byte
prefix and writing changed objects and a new xref. Recovered sources without a
validated original xref fall back to the complete-document writer, including
an in-bounds startxref that points at non-xref data.
Preserving original bytes does not establish a preexisting certificate
signature's validity. For an HTTP Range
document, enabling editing completes and validates the source download before
the writer can run, including objects on unvisited pages.

## Library and Worker interfaces

`PdfViewerDocument::editor_page_json(page)` returns stable annotation/widget IDs,
PDF-space bounds, contents, editability, field values/options and ink paths.
Page numbers are one-based. Indirect objects retain their object IDs; additions
use UUID-based IDs, and edited direct dictionaries retain an extension ID.

`with_editor_changes(changes)` applies a snapshot to a copy and returns a new
document. Failure leaves the source unchanged. Snapshot entries have unique IDs
and a `kind` of `add`, `update`, `delete` or `field`. Geometry is expressed in PDF
coordinates, independently of CropBox, UserUnit and viewer rotation:

```json
[
  {
    "kind": "add",
    "id": "new:example",
    "page": 1,
    "subtype": "FreeText",
    "bounds": [40, 80, 200, 120],
    "contents": "A note",
    "size": 14,
    "color": [0.1, 0.2, 0.7]
  },
  {
    "kind": "field",
    "id": "object:6",
    "page": 1,
    "values": ["Selected export value"],
    "indices": [1]
  }
]
```

`indices` is optional for Ch fields and resolves duplicate export values.
Highlight additions can supply `quads`, with PDF-space `p0` through `p3` points
inside `bounds`. Saving preserves these points rather than replacing them with
axis-aligned rectangles; moving/resizing maps the original quads to the new bounds.
Ink additions require `paths` containing arrays of `[x, y]` points. Stamp
additions require `image: {width, height, rgba}` with base64 RGBA bytes.
`editor_permissions()` reports whether annotations and forms can be edited.
`with_xfa_packets(replacements)` applies host-serialized dataset/XDP packets to
an immutable document copy, enforcing form permissions and the 32 MiB packet
budget. `save_bytes()` returns an incremental PDF by default;
`save_bytes(incremental=false)` requests a full rewrite. For an authenticated AES document,
pass `aes_iv_provider`, which must supply fresh, cryptographically secure 16-byte
IVs. The browser uses `crypto.getRandomValues`; deterministic pdflite providers
are used only in test fixtures. Credentials remain private to the parsed document
and are omitted from JSON/status/diagnostics. Image input is limited to four
million pixels; snapshots are limited to 10,000 entries.

The browser bridge exports `editor_info`, `prepare_editor`, `apply_edits`, `apply_xfa_packets` and
`save_pdf`. It keeps the original document as the baseline and applies full
undo/redo snapshots against it. Page/thumbnail caches clear after edits.
The app checks document generations before publishing async replies or errors,
including preparation and image-decoder failures from a replaced document.
Layer changes flush active fields and retain visibility through editing snapshots
and undo/redo; hidden layer fields/annotations are omitted from editor controls.
Saving retains the document's original layer configurations, as described in
[layer behavior](layers.md).

## Validation and remaining work

Core tests cover save/reopen, immutable sources, explicit APs, popup
removal, stable direct IDs, locks, inherited fields, choice/radio state, duplicate
exports and transparent image signatures. Encryption cases cover six security
settings, user/owner authentication, permission enforcement, empty user passwords,
AES IV validation and failure atomicity.
Additional regressions verify incremental byte prefixes and revision chaining,
affine highlight geometry, invalid-quad atomicity, original-font Unicode
appearances, XFA datasets, missing dataset packets and encrypted XFA roundtrips.

The 25 Chromium editor checks use actual native inputs and pointer gestures.
They reopen downloaded bytes with the pinned PDF.js reader, render saved Chinese
text and signature APs, verify two physical printed pages, and exercise a real
PDF.js choice fixture. Six encrypted variants are saved, reopened with both
passwords and rendered by PDF.js; AES saves must differ, and permissions/file IDs
must remain unchanged. Restricted and owner-protected documents also exercise
native controls and the Worker boundary. Reports, downloaded PDFs, printed output and appearance
screenshots are retained under `_build/editor-test-*/`.
The pinned `issue6010_1.pdf` and `issue6010_2.pdf` fixtures also cover saved
annotations, actual PDF.js rendering and ASCII/non-ASCII password reopening.
Six additional checks run in Chromium and WebKit through
`tools/text_interaction_browser_test.mjs`. They verify exact search ranges,
single/cross-page selected highlights and batch undo, XFA Unicode undo/redo,
focused saving/reopening, unbound/locked/multiselect restrictions, radio remount
and print state, and namespace/MathML accessibility semantics. Selected highlights
also move and resize before the first save, with their affine geometry retained.

```sh
moon test --target js --warn-list '-a' -f '*editor*'
moon run tools/build_web.mbtx
node tools/pixels/write_readonly_fixtures.mjs
moon run tools/dev.mbtx 4315
# In another terminal, with the pinned tools/test-host dependencies installed:
node tools/editor_browser_test.mjs http://127.0.0.1:4315
node tools/text_interaction_browser_test.mjs http://127.0.0.1:4315
PDF_BROWSER=webkit node tools/text_interaction_browser_test.mjs http://127.0.0.1:4315
```

Encrypted saving requires successful authentication and an AES IV provider when
applicable. XFA controls without dataset bindings and template-readonly controls
remain readonly. Pushbuttons, field
calculation/validation JavaScript, certificate
signing and arbitrary rich-text editing are not implemented. The existing
visual-baseline differences and manual assistive-technology
acceptance remain separate work. These editing paths do not establish complete
PDF.js parity.

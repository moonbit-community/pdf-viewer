# Editing, form filling and signatures

The browser editor is implemented in MoonBit and Rabbita. PDF edits reuse
pdflite's object model, content operations and writer. Native input/select
controls, Pointer Events and Canvas pixel acquisition provide browser primitives.

## Using the editor

Open a PDF and select **编辑**. AcroForm fields become native controls; readonly
fields remain disabled. Text changes commit when the field loses focus. Download
and print also flush the active field.

The tools add text boxes, rectangular highlights, ink, handwritten signatures
and image signatures. Enter text, choose a colour/size, then drag on the page.
Select an annotation to edit its text/style, drag to move it, or drag the lower
right handle to resize it. Delete, undo and redo are available in the toolbar;
Ctrl/Cmd+Z, Ctrl/Cmd+Shift+Z and Ctrl/Cmd+Y work outside native inputs. Consecutive
ink/signature strokes on the same page and tool form one annotation; each stroke
can be undone.

**下载** or Ctrl/Cmd+S saves a new PDF with the current edits. Downloading records
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
  When browser-entered text contains characters outside the simple Latin range,
  the browser supplies a raster appearance using its available fonts. Unicode
  field/annotation values remain PDF strings, while the saved pixels render
  without requiring those fonts on another machine. This fallback does not
  promise the original font, precise typography, or searchable text inside the
  raster appearance itself.
- Image signatures embed RGB pixels and a soft alpha mask. Handwritten signatures
  are Ink annotations. Both remain visible when another reader opens the PDF.
  They do not create or validate a cryptographic signature.

Saving writes a complete PDF through `pdflite.pdf_write_document`, retaining the
document's objects and explicit appearances. It does not use incremental updates
or preserve a preexisting certificate signature's validity. For an HTTP Range
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
Ink additions require `paths` containing arrays of `[x, y]` points. Stamp
additions require `image: {width, height, rgba}` with base64 RGBA bytes.
`save_bytes()` returns the serialized PDF. Image input is limited to four
million pixels; snapshots are limited to 10,000 entries.

The browser bridge exports `editor_info`, `prepare_editor`, `apply_edits` and
`save_pdf`. It keeps the original document as the baseline and applies full
undo/redo snapshots against it. Page/thumbnail caches clear after edits.
The app checks document generations before publishing async replies or errors,
including preparation and image-decoder failures from a replaced document.

## Validation and remaining work

Ten core tests cover save/reopen, immutable sources, explicit APs, popup removal,
stable direct IDs, locks, encryption rejection, inherited fields, choice/radio
state, duplicate exports and transparent image signatures.

The 22 Chromium editor checks use actual native inputs and pointer gestures.
They reopen downloaded bytes with the pinned PDF.js reader, render saved Chinese
text and signature APs, verify two physical printed pages, and exercise a real
PDF.js choice fixture. Reports, downloaded PDFs, printed output and appearance
screenshots are retained under `_build/editor-test-*/`.

```sh
moon test --target js --warn-list '-a' -f '*editor*'
moon run tools/build_web.mbtx
node tools/pixels/write_readonly_fixtures.mjs
moon run tools/dev.mbtx 4315
# In another terminal, with the pinned tools/test-host dependencies installed:
node tools/editor_browser_test.mjs http://127.0.0.1:4315
```

Encrypted PDFs remain readable but cannot be edited/saved. Dynamic XFA controls
remain readonly. Pushbuttons, field calculation/validation JavaScript, certificate
signing and arbitrary rich-text editing are not implemented. The existing
visual-baseline differences, OCG control panel and manual assistive-technology
acceptance remain separate work. These editing paths do not establish complete
PDF.js parity.

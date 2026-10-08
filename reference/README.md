# PDF viewer references

The local `pdf.js` checkout is intentionally ignored by Git because its test
corpus is large. It was cloned for feature and fixture comparison only.

- Upstream: <https://github.com/mozilla/pdf.js>
- Pinned revision: `89b500f5e1d98ed89bb90211e45b28730b2d99ac`
- Checkout date: 2026-10-07

Useful comparison areas:

- `src/display/api.js`: document/page/viewport contracts;
- `src/display/display_utils.js`: viewport transforms;
- `src/display/text_layer.js`: positioned text and selection behavior;
- `test/pdfs/`: compatibility and regression corpus;
- `test/unit/`: focused parser/display utility tests.

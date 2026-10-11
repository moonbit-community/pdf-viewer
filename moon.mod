// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "moonbit-community/pdf-viewer"

version = "0.1.0"

readme = "README.mbt.md"

repository = ""

license = "Apache-2.0"

keywords = [ ]

preferred_target = "wasm"

description = ""

import {
  "moonbitlang/pdflite@0.2.2",
  "moonbitlang/async@0.22.4",
  "moonbitlang/x@0.5.5",
  "moonbit-community/bidi@0.5.2",
  "moonbit-community/normalization@0.5.2",
  "moonbit-community/ucd@0.5.2",
  "moonbit-community/flate@0.8.1",
  "mizchi/font@0.7.4",
}

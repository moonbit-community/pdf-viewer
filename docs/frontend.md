# Browser interface

The browser application uses [Rabbita](https://mooncakes.io/docs/moonbit-community/rabbita)
0.16.4, pinned in `moon.mod`. The application source is MoonBit; the build compiles
it to an ES module for the browser. No separate JavaScript application controller
or handwritten virtual DOM is used.

`cmd/viewer/view.mbt` and `sidebar.mbt` define the toolbar, document panels and
status with Rabbita HTML. `model.mbt` holds typed view snapshots and message types;
Rabbita state and commands connect them in `main.mbt`. The async reader session
tracks document generations, abort controllers and page/selection lifetimes in
MoonBit. Navigation and page/text mounting live in `pages.mbt`, search and native
selection in their corresponding files, and file/print lifecycle in `document.mbt`
and `print.mbt`. Native browser events are connected in `events.mbt`.

Rabbita owns the application DOM. The empty `#pages`, `#print-pages` and thumbnail
preview containers retain their identity across view updates; rendering adapters
own their contents. This preserves Canvas pixels, native selection endpoints and
annotation focus. Code that needs the new view waits for Rabbita's `AfterRender`
command before observing or measuring it.

`web/viewer.js` loads the generated module and exposes the existing host helpers
(`loadFile`, search, selection, close, print and diagnostics). `web/viewer-host.mjs`
connects existing Canvas, Worker, annotation, accessibility and XFA engines.
`platform.mbt` contains narrow FFI for native APIs and opaque render plans. DOM
operations use Rabbita's DOM package where available; Selection/Range and PDF
engine calls use native bindings. Worker transport, page scheduling and rendering
modules remain adapters rather than application views or navigation controllers.

`tools/build_web.mbtx` builds both `cmd/browser` and `cmd/viewer`. Static hosting
must include both generated modules and the existing codec/XFA assets. Develop
with `moon run tools/dev.mbtx 4312` after installing MoonBit and web dependencies.

`tools/browser_test.mbtx` passes 110 checks against the compiled application in Chromium. It
checks all existing reader behavior plus view updates preserving Canvas/native
selection, stale thumbnail/print draws suppressing publication and warnings,
selections outside the PDF text layer,
repeated page clicks, files captured during native drop events, and real warnings
published by page/thumbnail/print rendering.
These checks replace the former test that extracted JavaScript controller
functions into a VM; Worker/Canvas and scheduler tests remain separately runnable.

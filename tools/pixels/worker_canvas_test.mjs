#!/usr/bin/env node
// The shipped Worker module and client run over real worker_threads transport.
// Only browser Worker events and local file-URL fetch are adapted for Node.
// Canvas pixels use the same shipped runtime with the caller's native host.
// Scheduler checks use element doubles; this does not claim browser DOM QA.
import assert from 'node:assert/strict';
import { Worker as NodeWorker } from 'node:worker_threads';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { PdfWorkerClient } from '../../web/pdf-client.js';
import { PageScheduler } from '../../web/page-scheduler.js';
import { annotationRects, annotationURL } from '../../web/annotation-layer.js';
import { installPdfIccEngine } from '../../web/pdf-icc.mjs';
import { renderPdfPage } from '../../web/pdf-runtime.mjs';
import { process_cmyk_to_rgb } from '../../web/_generated/pdf.js';

const require = createRequire(process.env.PDF_CANVAS_PACKAGE || import.meta.url);
const { createCanvas, Path2D, loadImage } = require('@napi-rs/canvas');
const wrapper = `
  import { parentPort, workerData } from 'node:worker_threads';
  import { readFile } from 'node:fs/promises';
  const networkFetch = globalThis.fetch;
  globalThis.fetch = async (url, options) => String(url).startsWith('file:')
    ? new Response(await readFile(new URL(url))) : networkFetch(url, options);
  globalThis.self = {
    addEventListener(type, callback) {
      if (type === 'message') parentPort.on('message', data => callback({ data }));
    },
    postMessage(data, transfer) { parentPort.postMessage(data, transfer); },
  };
  await import(workerData.moduleURL);
`;
class BrowserWorker {
  constructor(url) {
    this.thread = new NodeWorker(new URL(`data:text/javascript,${encodeURIComponent(wrapper)}`), {
      workerData: { moduleURL: String(url) },
    });
  }
  addEventListener(type, callback) {
    if (type === 'message') this.thread.on(type, data => callback({ data }));
    else this.thread.on(type, error => callback({ message: error.message, preventDefault() {} }));
  }
  postMessage(data, transfer) { this.thread.postMessage(data, transfer); }
  terminate() { return this.thread.terminate(); }
}
globalThis.Worker = BrowserWorker;
const checked = serialized => {
  const value = JSON.parse(serialized);
  assert.equal(value.ok, true, value.error);
  return value;
};
const stream = (dict, bytes) => {
  bytes = Buffer.isBuffer(bytes) ? bytes : Buffer.from(bytes);
  return Buffer.concat([Buffer.from(`<< ${dict} /Length ${bytes.length} >>\nstream\n`), bytes, Buffer.from('\nendstream')]);
};
function makePdf(objects) {
  const chunks = [Buffer.from('%PDF-1.7\n')], offsets = [0];
  let size = chunks[0].length;
  for (const [index, object] of objects.entries()) {
    offsets.push(size);
    const chunk = Buffer.concat([Buffer.from(`${index + 1} 0 obj\n`), Buffer.from(object), Buffer.from('\nendobj\n')]);
    chunks.push(chunk); size += chunk.length;
  }
  chunks.push(Buffer.from(`xref\n0 ${objects.length + 1}\n0000000000 65535 f \n` +
    offsets.slice(1).map(offset => `${String(offset).padStart(10, '0')} 00000 n \n`).join('') +
    `trailer << /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${size}\n%%EOF\n`));
  return new Uint8Array(Buffer.concat(chunks));
}
const u32 = value => [value >>> 24, value >>> 16 & 255, value >>> 8 & 255, value & 255];
function blankJbig2(black) {
  const payload = [...u32(8), ...u32(8), ...u32(72), ...u32(72), black ? 4 : 0, 0, 0];
  return Buffer.from([...u32(1), 48, 0, 1, ...u32(payload.length), ...payload]);
}
const profile = readFileSync(new URL('../../assets/icc/rgb-gamma22.icc', import.meta.url));
const objects = [
  '<< /Type /Catalog /Pages 2 0 R >>',
  `<< /Type /Pages /Kids [${Array.from({ length: 14 }, (_, i) => `${8 + i * 2} 0 R`).join(' ')}] /Count 14 >>`,
  stream('/Type /XObject /Subtype /Image /Width 8 /Height 8 /BitsPerComponent 1 /ColorSpace /DeviceGray /Filter /JBIG2Decode', blankJbig2(true)),
  stream('/Type /XObject /Subtype /Image /Width 8 /Height 8 /BitsPerComponent 1 /ColorSpace /DeviceGray /Filter /JBIG2Decode', blankJbig2(false)),
  stream('/N 3 /Alternate /DeviceRGB', profile),
  '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  '<< >>',
];
for (let number = 1; number <= 14; number++) {
  objects.push(`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 32 32] /Resources << /XObject << /Black 3 0 R /White 4 0 R >> /ColorSpace << /ICC [/ICCBased 5 0 R] >> /Font << /F1 6 0 R >> >> /Contents ${9 + (number - 1) * 2} 0 R >>`);
  objects.push(stream('', number === 1
    ? 'q 16 0 0 32 0 0 cm /Black Do Q q 16 0 0 32 16 0 cm /White Do Q'
    : number === 2 ? '/ICC cs .25 .5 .75 scn 0 0 32 32 re f'
      : `0 0 1 rg 0 0 32 32 re f 0 g BT /F1 6 Tf 1 16 Td (Worker page ${number}) Tj ET`));
}
const fixture = makePdf(objects);
// Intent regression fixture: filled APs make the four flag combinations
// independently measurable after CropBox, UserUnit and intrinsic rotation.
const annotationFixture = makePdf([
  '<< /Type /Catalog /Pages 2 0 R /Dests << /chapter [3 0 R /XYZ 30 100 1.25] >> >>',
  '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
  '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 140] /CropBox [10 20 190 120] /UserUnit 1.5 /Rotate 90 /Contents 4 0 R /Resources << >> /Annots [9 0 R 10 0 R 11 0 R 12 0 R 13 0 R 14 0 R] >>',
  stream('', 'q Q'),
  ...['1 0 0', '0 0 1', '0 1 0', '0 0 0'].map(colour =>
    stream('/Type /XObject /Subtype /Form /BBox [0 0 20 20] /Resources << >>', `${colour} rg 0 0 20 20 re f`)),
  ...[4, 36, 0, 6].map((flags, index) =>
    `<< /Subtype /Square /Rect [${30 + index * 40} 50 ${50 + index * 40} 70] /F ${flags} /AP << /N ${5 + index} 0 R >> >>`),
  '<< /Subtype /Link /Rect [30 85 50 100] /Dest /chapter >>',
  '<< /Subtype /Text /Rect [70 85 90 100] /T (Reviewer) /Contents (<b>Plain</b>) >>',
]);
const output = resolve(process.env.PDF_WORKER_OUTPUT || '_build/worker-canvas');
mkdirSync(output, { recursive: true });
const report = {
  scope: 'Actual web/pdf-worker.js and web/pdf-client.js over Node worker_threads; shipped Canvas runtime with native Canvas API host; scheduler element doubles, not browser DOM',
  fixtureSha256: createHash('sha256').update(fixture).digest('hex'),
  pages: 14, tests: [],
};
const client = new PdfWorkerClient();
const engine = await installPdfIccEngine();
const options = { createCanvas, Path2D, loadImage, convertProcess: values => process_cmyk_to_rgb(...values) };
try {
  client.reset();
  const beforeReady = new AbortController();
  const cancelledStartup = client.call('cache_info', [], { signal: beforeReady.signal });
  beforeReady.abort();
  await assert.rejects(cancelledStartup, { name: 'AbortError' });
  const bytes = fixture.slice();
  const opened = checked(await client.call('open_pdf', [bytes], { transfer: [bytes.buffer], priority: 100 }));
  assert.equal(opened.pages, 14);
  assert.equal(bytes.byteLength, 0, 'The source buffer must cross the real transfer boundary');
  report.graphics = client.diagnostics().graphics;
  assert.deepEqual(report.graphics, { icc: true, jbig2: true, diagnostics: [] });
  const layouts = checked(await client.call('page_layouts')).layouts;
  assert.equal(layouts.length, 14);
  assert.equal(checked(await client.call('cache_info')).pages, 0, 'Geometry-only layout must not decode page models');
  report.tests.push('ready gates ICC/JBIG2 hooks, transferable input, metadata-only layout');

  for (const number of [1, 2]) {
    const result = checked(await client.call('render_page', [number, 1, 0]));
    const canvas = createCanvas(1, 1);
    const painted = await renderPdfPage(canvas, result.canvas, options);
    assert.deepEqual(painted.diagnostics, []);
    const pixel = (x, y) => [...canvas.getContext('2d').getImageData(x, y, 1, 1).data];
    if (number === 1) {
      assert.deepEqual(pixel(4, 16), [0, 0, 0, 255]);
      assert.deepEqual(pixel(24, 16), [255, 255, 255, 255]);
    } else {
      const transform = engine.open(profile, 3, 1), expected = new Float64Array(3);
      assert(transform.convert(.25, .5, .75, 0, expected)); transform.close();
      const actual = pixel(16, 16);
      for (let c = 0; c < 3; c++) assert(Math.abs(actual[c] - Math.round(expected[c] * 255)) <= 1);
      assert(actual.slice(0, 3).some((value, c) => Math.abs(value - [.25, .5, .75][c] * 255) > 2), 'ICC pixels cannot silently use DeviceRGB Alternate');
      report.iccPixel = actual;
    }
    writeFileSync(`${output}/page-${number}.png`, canvas.toBuffer('image/png'));
  }
  report.tests.push('Worker-decoded JBIG2 black/white pixels and ICC profile pixels through shipped Canvas');
  const selected = checked(await client.call('select_page_text', [3, -1, -1, -1, -1]));
  assert.match(selected.selection.text, /Worker page 3/);
  for (let page = 3; page <= 14; page++) checked(await client.call('render_page', [page, 1, 0]));
  const cold = await client.call('render_page', [14, 1, 0]);
  assert.equal(await client.call('render_page', [14, 1, 0]), cold);
  const cache = checked(await client.call('cache_info'));
  assert(cache.pages <= cache.max_pages && cache.estimated_bytes <= cache.budget_bytes && cache.evictions > 0);
  assert(cache.render.entries <= cache.render.max_entries && cache.render.bytes <= cache.render.budget_bytes && cache.render.evictions > 0 && cache.render.hits >= 2);
  report.cache = cache;
  report.tests.push('off-screen text selection and bounded decoded/serialized LRU caches');

  const order = [];
  const active = client.call('render_page', [1, 1.1, 0]).then(() => order.push('active'));
  const low = client.call('render_page', [2, 1.1, 0], { priority: -5 }).then(() => order.push('low'));
  const abort = new AbortController();
  const cancelledQueued = client.call('render_page', [3, 1.1, 0], { signal: abort.signal });
  abort.abort();
  await assert.rejects(cancelledQueued, { name: 'AbortError' });
  const high = client.call('render_page', [4, 1.1, 0], { priority: 20 }).then(() => order.push('high'));
  await Promise.all([active, low, high]);
  assert.deepEqual(order, ['active', 'high', 'low']);
  const activeAbort = new AbortController();
  const cancelledActive = client.call('render_page', [5, 1.2, 0], { signal: activeAbort.signal });
  activeAbort.abort();
  await assert.rejects(cancelledActive, { name: 'AbortError' });
  checked(await client.call('cache_info'));
  await assert.rejects(client.call('not_a_pdf_operation'), { code: 'invalid-operation' });
  checked(await client.call('set_font_fallbacks', ['[]']));
  assert.equal(checked(await client.call('cache_info')).render.entries, 0);
  report.tests.push('priority ordering, pre-ready/queued/active cancellation, bad-operation recovery and cache invalidation');

  const annotationBytes = annotationFixture.slice();
  checked(await client.call('open_pdf', [annotationBytes], { transfer: [annotationBytes.buffer] }));
  const appearances = [
    [[255, 0, 0, 255], [255, 0, 0, 255]],
    [[255, 255, 255, 255], [0, 0, 255, 255]],
    [[0, 255, 0, 255], [255, 255, 255, 255]],
    [[255, 255, 255, 255], [255, 255, 255, 255]],
  ];
  for (const rotation of [0, 90, 180, 270]) {
    for (const [intentIndex, method] of ['render_page', 'render_print_page'].entries()) {
      const result = checked(await client.call(method, [1, 1.25, rotation]));
      assert.equal(result.intent, intentIndex ? 'print' : 'display');
      assert.deepEqual(result.canvas.viewport, result.layer.viewport);
      assert.equal(result.annotations.length, intentIndex ? 0 : 6);
      const canvas = createCanvas(1, 1);
      const painted = await renderPdfPage(canvas, result.canvas, options);
      assert.deepEqual(painted.diagnostics, []);
      for (let index = 0; index < appearances.length; index++) {
        const m = result.layer.viewport.matrix, x = 40 + index * 40, y = 60;
        const actual = [...canvas.getContext('2d').getImageData(
          Math.floor(m[0] * x + m[2] * y + m[4]),
          Math.floor(m[1] * x + m[3] * y + m[5]), 1, 1).data];
        assert.deepEqual(actual, appearances[index][intentIndex], `${result.intent} annotation ${index}, rotation ${rotation}`);
      }
      if (!intentIndex) {
        assert.deepEqual(result.annotations.slice(0, 4).map(a => [a.visible, a.print]),
          [[true, true], [false, true], [true, false], [false, false]]);
        assert.equal(result.annotations[4].link.destination.page, 1);
        assert.equal(result.annotations[4].link.destination.zoom, 1.25);
        assert.equal(result.annotations[5].contents, '<b>Plain</b>');
        for (const annotation of result.annotations) {
          const [rect] = annotationRects(annotation, result.layer.viewport);
          const sideways = (rotation + 90) % 180 !== 0;
          const bounds = annotation.bounds;
          assert.equal(rect.width, (sideways ? bounds.max_y - bounds.min_y : bounds.max_x - bounds.min_x) * 1.5 * 1.25);
          assert.equal(rect.height, (sideways ? bounds.max_x - bounds.min_x : bounds.max_y - bounds.min_y) * 1.5 * 1.25);
          assert(rect.left >= 0 && rect.top >= 0 && rect.left + rect.width <= canvas.width && rect.top + rect.height <= canvas.height);
        }
      }
      if (!rotation) writeFileSync(`${output}/annotations-${result.intent}.png`, canvas.toBuffer('image/png'));
    }
  }
  const display = await client.call('render_page', [1, 1.25, 0]);
  const printing = await client.call('render_print_page', [1, 1.25, 0]);
  assert.equal(await client.call('render_page', [1, 1.25, 0]), display);
  assert.equal(await client.call('render_print_page', [1, 1.25, 0]), printing);
  const annotationCache = checked(await client.call('cache_info')).render;
  assert.equal(annotationCache.entries, 8);
  assert.equal(annotationCache.misses, 8);
  assert.equal(annotationCache.hits, 4);
  assert.notEqual(display, printing);
  assert.equal(annotationURL('javascript:alert(1)'), null);
  assert.equal(annotationURL('data:text/html,x'), null);
  assert.equal(annotationURL('file:///tmp/x.pdf'), null);
  assert.equal(annotationURL('next.pdf'), null);
  assert.equal(annotationURL('next.pdf', 'https://example.com/files/book.pdf'), 'https://example.com/files/next.pdf');
  report.annotationIntent = { fixtureSha256: createHash('sha256').update(annotationFixture).digest('hex'),
    rotations: [0, 90, 180, 270], scale: 1.25, userUnit: 1.5, cache: annotationCache };
  report.tests.push('actual Worker separates display/print caches; Canvas preserves print-only, display-only and Hidden appearance pixels at all rotations; overlay geometry and safe URLs retained');

  const original = readFileSync(resolve('_build/text-host-pen/text-host-pen.pdf'));
  assert.equal(original.length, 621);
  assert.equal(createHash('sha256').update(original).digest('hex'), 'faf86fff67b17f2d78afcf5353341c85b5949e560a11c5271166432e5193a538');
  const source = new Uint8Array(original);
  checked(await client.call('open_pdf', [source], { transfer: [source.buffer] }));
  const workerPlan = checked(await client.call('render_page', [1, 1, 0]));
  const directBridge = await import('../../web/_generated/pdf.js');
  checked(directBridge.open_pdf(new Uint8Array(original)));
  const directPlan = checked(directBridge.render_page(1, 1, 0));
  directBridge.close_pdf();
  const workerCanvas = createCanvas(1, 1), directCanvas = createCanvas(1, 1);
  const workerPaint = await renderPdfPage(workerCanvas, workerPlan.canvas, options);
  const directPaint = await renderPdfPage(directCanvas, directPlan.canvas, options);
  assert.deepEqual(workerPaint.diagnostics, []);
  assert.deepEqual(directPaint.diagnostics, []);
  assert.deepEqual(workerPaint.data, directPaint.data);
  assert(workerPaint.data.some((value, i) => i % 4 !== 3 && value < 240));
  report.originalTextFixture = {
    bytes: original.length,
    sha256: createHash('sha256').update(original).digest('hex'),
    width: workerCanvas.width, height: workerCanvas.height,
    rgbaSha256: createHash('sha256').update(workerPaint.data).digest('hex'),
    diagnostics: workerPaint.diagnostics, exactDirectBridgePixels: true,
    nativeOutlineCallback: false,
  };
  writeFileSync(`${output}/original-text-pen.png`, workerCanvas.toBuffer('image/png'));
  report.tests.push('unchanged 621-byte text-pen fixture through actual Worker and default Canvas is nonblank, diagnostic-free and exact to direct bridge RGBA');

  const glyphFixture = makePdf([
    '<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 80 80] /Contents 4 0 R /Resources << /Font << /F 5 0 R >> >> >>',
    stream('', '0 .2 .8 rg BT /F 24 Tf 10 10 Td (AAA) Tj ET'),
    '<< /Type /Font /Subtype /Type3 /FontBBox [0 0 600 900] /FontMatrix [.001 0 0 .001 0 0] /FirstChar 65 /LastChar 65 /Widths [600] /Encoding << /Differences [65 /A] >> /CharProcs << /A 6 0 R >> /Resources << >> >>',
    stream('', '600 0 0 0 600 900 d1 0 0 600 900 re 100 100 400 700 re f*'),
  ]);
  checked(await client.call('open_pdf', [glyphFixture], { transfer: [glyphFixture.buffer] }));
  const compact = checked(await client.call('render_page', [1, 1, 0, true, true]));
  assert.equal(compact.canvas.version, 2);
  assert.equal(compact.canvas.glyph_resources.length, 1);
  assert.equal(compact.canvas.items.filter(item => item.glyph).length, 3);
  const packetArgs=[1,1,0,true,true,true];
  const packetExpected=checked(await client.call('render_page',packetArgs));
  const packetFirst=await client.callPage(packetArgs);
  assert.deepEqual(packetFirst,packetExpected,'Real transferred packet preserves every semantic and paint field');
  packetFirst.canvas.items[0].draws[0]=999;
  packetFirst.layer.items[0].quad.p0.x=999;
  const packetAgain=await client.callPage(packetArgs);
  assert.deepEqual(packetAgain,packetExpected,'Cache-hit transfers retain independent buffers and metadata');
  assert.equal((await client.callPage([1,0,0,true,true,true])).code,'invalid-scale');
  const packetAbort=new AbortController();
  const cancelledPacket=client.callPage([1,1.01,0,true,true,true],{signal:packetAbort.signal});
  packetAbort.abort();await assert.rejects(cancelledPacket,{name:'AbortError'});
  checked(await client.call('cache_info'));
  assert.deepEqual(await client.callPage(packetArgs),packetExpected,'A discarded transferred packet cannot detach a cached owner');
  const packetCache=checked(await client.call('cache_info')).render;
  assert(packetCache.hits>0&&packetCache.bytes<=packetCache.budget_bytes);
  report.tests.push('Float64 page packets transfer real buffers, preserve every field, survive repeated cache hits and cancellation, and keep cache owners attached');
  const selection = checked(await client.call('select_page_text', [1, -1, -1, -1, -1]));
  assert.equal(checked(await client.call('cache_info')).compiled_resources.entries, 1);
  const legacy = checked(await client.call('render_page', [1, 1, 0, true]));
  assert.equal(legacy.canvas.version, 1);
  assert.deepEqual(checked(await client.call('select_page_text', [1, -1, -1, -1, -1])), selection);
  const compactPaint = await renderPdfPage(createCanvas(1, 1), compact.canvas, options);
  const legacyPaint = await renderPdfPage(createCanvas(1, 1), legacy.canvas, options);
  assert.deepEqual(compactPaint.data, legacyPaint.data);
  assert.deepEqual(compactPaint.diagnostics, []);
  report.tests.push('actual Worker transports deduplicated glyph programs, keeps legacy call arity and selection, and reproduces legacy Canvas pixels');

  const pending = client.call('render_page', [1, 1.3, 0]);
  client.reset();
  await assert.rejects(pending, { name: 'AbortError' });
  const reopened = fixture.slice();
  assert.equal(checked(await client.call('open_pdf', [reopened], { transfer: [reopened.buffer] })).pages, 14);
  assert.equal(checked(await client.call('cache_info')).render.entries, 0);
  assert.equal(checked(await client.call('cache_info')).compiled_resources.entries, 0);
  client.close();
  await assert.rejects(client.call('cache_info'), { code: 'document-closed' });
  assert.equal(client.diagnostics().queued, 0);
  assert.equal(client.diagnostics().graphics, null);
  report.tests.push('reset terminates stale work, fresh engines/document reopen, and close releases queued work');

  for (const source of [
    'throw new Error("worker startup failed");',
    'self.postMessage({type:"startup-error",error:{message:"graphics startup failed"}});',
  ]) {
    const failing = new PdfWorkerClient({ workerURL: new URL(`data:text/javascript,${encodeURIComponent(source)}`) });
    try {
      failing.reset();
      await assert.rejects(failing.call('cache_info'), { code: 'worker-error' });
      assert.equal(failing.diagnostics().worker, false);
    } finally { failing.close(); }
  }
  report.tests.push('real transport forwards module and explicit graphics startup failures without a timeout');
} finally { client.close(); engine.dispose(); }

// Exercise the actual scheduler with an async Canvas mount that finishes after
// a replacement layout or navigation. Detached stale output must never publish.
const element = () => ({
  childNodes: [], dataset: {}, style: {}, attributes: {},
  querySelectorAll() { return []; },
  replaceChildren(...nodes) { this.childNodes = nodes; },
  setAttribute(name, value) { this.attributes[name] = value; },
});
const page = element(); page.dataset.page = '1';
const pages = { children: [page], replaceChildren() { this.children = []; }, querySelectorAll: () => page.dataset.rendered === 'true' ? [page] : [] };
const viewer = { dataset: {} };
let releaseMount, startedMount, currentDuringMount, mounts = 0, unloads = 0;
const mountStarted = () => new Promise(resolve => { startedMount = resolve; });
const scheduler = new PageScheduler({
  pages, viewer, render: async () => ({ page: 1 }), pinned: () => [], singlePage: () => true,
  onError: error => { throw error; }, onMount: async () => { mounts++; },
  onUnload: target => { assert.equal(target, page); unloads++; },
  mount: async (_result, current) => {
    currentDuringMount = current; startedMount();
    await new Promise(resolve => { releaseMount = resolve; });
    return { childNodes: ['fresh Canvas'], style: { width: '32px', height: '32px' } };
  },
});
for (const cancellation of ['epoch', 'navigation']) {
  const started = mountStarted();
  const task = scheduler.ensure(1);
  await started;
  assert(currentDuringMount());
  if (cancellation === 'epoch') scheduler.cancel();
  else scheduler.update(2);
  assert.equal(currentDuringMount(), false);
  releaseMount();
  await assert.rejects(task, { name: 'AbortError' });
  assert.deepEqual(page.childNodes, []);
  assert.equal(mounts, 0);
}
const started = mountStarted();
const fresh = scheduler.ensure(1);
await started; releaseMount(); await fresh;
assert.deepEqual(page.childNodes, ['fresh Canvas']);
assert.equal(page.dataset.rendered, 'true');
assert.equal(mounts, 1);
scheduler.unload(page);
assert.equal(unloads, 2, 'navigation also unloads unfinished Canvas output');
assert.deepEqual(page.childNodes, []);
scheduler.clear();
assert.equal(unloads, 3);
assert.deepEqual(pages.children, []);
report.tests.push('actual async PageScheduler discards old epoch/navigation Canvas mounts and mounts a fresh result; unloading/clearing invokes annotation cleanup');
// Thumbnail/print publication is checked against the compiled Rabbita app
// and real browser DOM in tools/browser_test.mbtx.
writeFileSync(`${output}/report.json`, JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report));

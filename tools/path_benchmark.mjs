// Authored scaling probe for path construction, through the packaged Worker.
// Build both site directories before running; do not build while timing.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {resolve, dirname, extname, sep} from 'node:path';
import {makePdf} from './pixels/readonly_fixtures.mjs';

const baseline = process.env.PDF_BENCH_BASELINE_ROOT;
assert(baseline, 'Set PDF_BENCH_BASELINE_ROOT to an independent packaged site');
const output = resolve(process.argv[2] || '_build/path-benchmark/report.json');
const engine = process.env.PDF_BROWSER || 'chromium';
assert(['chromium', 'webkit'].includes(engine));
const samples = Number(process.env.PDF_PATH_SAMPLES || 3);
assert(Number.isInteger(samples) && samples >= 3 && samples <= 15);
const roots = {
  baseline: resolve(baseline),
  candidate: resolve(process.env.PDF_BENCH_VIEWER_ROOT || '_build/pages'),
  reference: resolve('reference/pdf.js/build/generic'),
};
const sizes = [512, 2048, 8192, 16384];
const fixtures = new Map(sizes.map(n => {
  const content = '0 0 m\n' + Array.from({length: n}, (_, i) =>
    `${i % 256} ${Math.floor(i / 256) % 256} l`).join('\n') + '\nf';
  return [n, makePdf([
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 256 256] /Resources << >> /Contents 4 0 R >>',
    `<< /Length ${content.length} >>\nstream\n${content}\nendstream`,
  ])];
}));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const report = {
  scope: 'Authored single-path scaling diagnostic, not corpus latency. Fresh context, document and Worker per sample, CSS width 256 / DPR 2. Timed work includes preparation, painting and complete RGBA flush; opening/startup, hashes, DOM and teardown are excluded. PDF.js render time includes its Worker/operator preparation. Only baseline/candidate RGBA and full semantic equality are required; cross-engine hashes are reported separately.',
  engine, samples, sizes,
  workerSha256: Object.fromEntries(await Promise.all(
    Object.entries(roots).map(async ([variant, root]) => [variant,
      hash(await readFile(resolve(root, variant === 'reference' ? 'build/pdf.worker.mjs' : 'pdf-worker.js')))]),
  )),
  rows: [],
};
const mime = {'.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm'};
const server = createServer(async (request, response) => {
  const url = new URL(request.url, 'http://localhost');
  if (url.pathname === '/probe.html') {
    response.writeHead(200, {'Content-Type': 'text/html'}).end('<!doctype html><body>');
    return;
  }
  if (url.pathname === '/fixture.pdf') {
    const bytes = fixtures.get(Number(url.searchParams.get('segments')));
    response.writeHead(bytes ? 200 : 404).end(bytes);
    return;
  }
  const [, variant, ...parts] = url.pathname.split('/'), root = roots[variant];
  if (!root) { response.writeHead(404).end(); return; }
  const file = resolve(root, parts.join('/'));
  if (!file.startsWith(root + sep)) { response.writeHead(404).end(); return; }
  try {
    const bytes = await readFile(file);
    response.writeHead(200, {'Content-Type': mime[extname(file)] || 'application/octet-stream'}).end(bytes);
  } catch { response.writeHead(404).end(); }
});
await mkdir(dirname(output), {recursive: true});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const browser = await createRequire(resolve('tools/test-host/package.json'))('playwright')[engine].launch({headless: true});
try {
  for (const segments of sizes) {
    for (let pair = 0; pair < samples; pair++) {
      const order = pair % 2 ? ['reference', 'candidate', 'baseline'] : ['baseline', 'candidate', 'reference'];
      for (const variant of order) {
        const context = await browser.newContext({deviceScaleFactor: 2});
        try {
          const page = await context.newPage(), errors = [];
          page.on('pageerror', error => errors.push(String(error)));
          await page.goto(`http://127.0.0.1:${server.address().port}/probe.html`);
          const result = await page.evaluate(async ({segments, variant}) => {
            const bytes = new Uint8Array(await (await fetch('/fixture.pdf?segments=' + segments)).arrayBuffer());
            const canvas = document.createElement('canvas');
            let api, task, documentHandle;
            if (variant === 'reference') {
              api = await import('/reference/build/pdf.mjs');
              api.GlobalWorkerOptions.workerSrc = '/reference/build/pdf.worker.mjs';
              task = api.getDocument({data: bytes, useSystemFonts: false, isEvalSupported: false});
              documentHandle = await task.promise;
            } else {
              api = (await import('/' + variant + '/viewer-host.mjs')).viewerHost;
              api.pdf.reset();
              const opened = JSON.parse(await api.openDocument(new File([bytes], 'path.pdf'), bytes, null));
              if (!opened.ok) throw Error(opened.error);
            }
            let payload, prepareMs = null;
            const start = performance.now();
            if (variant === 'reference') {
              const page = await documentHandle.getPage(1), viewport = page.getViewport({scale: 1});
              canvas.width = Math.ceil(viewport.width * 2); canvas.height = Math.ceil(viewport.height * 2);
              await page.render({canvasContext: canvas.getContext('2d'), viewport, transform: [2, 0, 0, 2, 0, 0], background: 'rgb(255,255,255)'}).promise;
            } else {
              payload = JSON.parse(await api.pdf.call('render_page', [1, 1, 0, true, true]));
              if (!payload.ok) throw Error(payload.error);
              prepareMs = performance.now() - start;
              const painted = await api.paintCanvas(canvas, payload, 2, () => true, () => { throw Error('Unexpected host CMM'); });
              if (painted.diagnostics.length) throw Error(JSON.stringify(painted.diagnostics));
            }
            const paintEnd = performance.now();
            const pixels = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
            const end = performance.now();
            if (!pixels.some((value, index) => index % 4 !== 3 && value < 250)) throw Error('Blank path render');
            const digest = async bytes => [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))]
              .map(n => n.toString(16).padStart(2, '0')).join('');
            const rgbaSha256 = await digest(pixels);
            const semanticSha256 = payload ? await digest(new TextEncoder().encode(JSON.stringify(
              Object.fromEntries(['ok', 'page', 'svg', 'layer', 'editor', 'annotations', 'accessibility', 'intent'].map(key => [key, payload[key]])),
            ))) : null;
            if (variant === 'reference') await task.destroy(); else api.pdf.close();
            return {prepareMs, paintAndPrepareMs: paintEnd - start, totalMs: end - start, rgbaSha256, semanticSha256};
          }, {segments, variant});
          assert.deepEqual(errors, []);
          const row = {segments, pair, variant, ...result};
          report.rows.push(row);
          console.log(JSON.stringify(row));
          await writeFile(output, JSON.stringify(report, null, 2) + '\n');
        } finally { await context.close(); }
      }
    }
    for (const field of ['rgbaSha256', 'semanticSha256']) {
      const rows = report.rows.filter(row => row.segments === segments && row.variant !== 'reference');
      assert.equal(new Set(rows.map(row => row[field])).size, 1, `${field} ${segments}`);
    }
  }
} finally {
  await browser.close();
  await new Promise(resolve => server.close(resolve));
}
console.log(output);

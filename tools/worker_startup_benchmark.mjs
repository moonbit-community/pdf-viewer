// Fresh Workers/contexts; no PDF, parser warm-up or document work before ready.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {resolve, dirname, extname, sep} from 'node:path';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';

const engine = process.env.PDF_BROWSER || 'chromium';
assert(['chromium', 'webkit'].includes(engine));
const samples = Number(process.env.PDF_BENCH_SAMPLES || 9);
assert(Number.isInteger(samples) && samples >= 3 && samples <= 30);
const root = resolve(process.env.PDF_BENCH_VIEWER_ROOT || '_build/pages');
const baselineRoot = process.env.PDF_BENCH_BASELINE_ROOT ? resolve(process.env.PDF_BENCH_BASELINE_ROOT) : null;
const output = resolve(process.argv[2] || '_build/worker-startup/report.json');
const require = createRequire(resolve('tools/test-host/package.json'));
const mime = {'.js': 'text/javascript', '.mjs': 'text/javascript', '.wasm': 'application/wasm'};
const server = createServer(async (request, response) => {
  const path = new URL(request.url, 'http://localhost').pathname;
  if (path === '/') { response.setHeader('Content-Type', 'text/html'); response.end('<!doctype html>'); return; }
  const baseline = path.startsWith('/baseline/');
  const directory = baseline ? baselineRoot : root;
  const file = directory && resolve(directory, path.slice(baseline ? 10 : 1));
  if (!file || !file.startsWith(directory + sep)) { response.writeHead(404).end(); return; }
  try {
    response.writeHead(200, {'Content-Type': mime[extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store'});
    response.end(await readFile(file));
  } catch { response.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
let browser;
try {
  browser = await require('playwright')[engine].launch({headless: true});
  const report = {engine, browserVersion: browser.version(), samples, root, baselineRoot,
    scope: 'Each sample uses a fresh browser context and module Worker. Timer starts before construction and ends at ready; no PDF or parser preload. HTTP responses use no-store, without gzip. Module/graphics phases use the Worker clock. Samples run sequentially in alternating variant order.',
    timestamp: new Date().toISOString(), ours: [], baseline: [], builds: {}};
  for (const [name, directory] of [['ours', root], ['baseline', baselineRoot]]) {
    if (!directory) continue;
    const bytes = await readFile(resolve(directory, 'pdf-worker.js'));
    report.builds[name] = {bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex')};
  }
  for (let pair = 0; pair < samples; pair++) {
    for (const variant of baselineRoot ? pair % 2 ? ['ours', 'baseline'] : ['baseline', 'ours'] : ['ours']) {
      const context = await browser.newContext();
      try {
        const page = await context.newPage();
        await page.goto(`http://127.0.0.1:${server.address().port}/`);
        const result = await page.evaluate(prefix => new Promise((resolve, reject) => {
          const start = performance.now(), worker = new Worker(prefix + 'pdf-worker.js?profile=startup', {type: 'module'});
          const timeout = setTimeout(() => { worker.terminate(); reject(Error('Worker startup timed out')); }, 15000);
          worker.onerror = event => { clearTimeout(timeout); worker.terminate(); reject(Error(event.message)); };
          worker.onmessage = event => {
            clearTimeout(timeout);
            const readyMs = performance.now() - start;
            worker.terminate();
            event.data.type === 'ready' ? resolve({readyMs, ...event.data.benchmark, graphics: event.data.graphics})
              : reject(Error(JSON.stringify(event.data)));
          };
        }), variant === 'baseline' ? '/baseline/' : '/');
        assert.deepEqual(result.graphics, {icc: true, jbig2: true, diagnostics: []});
        report[variant].push({pair, ...result});
      } finally { await context.close(); }
    }
  }
  const median = values => { values.sort((a, b) => a - b); return (values[Math.floor((values.length - 1) / 2)] + values[Math.ceil((values.length - 1) / 2)]) / 2; };
  report.medians = {};
  for (const variant of ['ours', 'baseline']) if (report[variant].length)
    report.medians[variant] = Object.fromEntries(['readyMs', 'moduleReadyMs', 'graphicsMs'].map(key => [key, median(report[variant].map(sample => sample[key]))]));
  await mkdir(dirname(output), {recursive: true});
  await writeFile(output, JSON.stringify(report, null, 2));
  console.log(JSON.stringify({engine, medians: report.medians, builds: report.builds}));
  console.log('REPORT ' + output);
} finally { await browser?.close(); server.close(); }

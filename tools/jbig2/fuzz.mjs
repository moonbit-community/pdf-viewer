// The deadline lives outside the synchronous Wasm call and can terminate it.
import { Worker } from 'node:worker_threads';
import fs from 'node:fs';
const fixture = process.argv[2];
if (!fixture) throw new Error('Usage: node tools/jbig2/fuzz.mjs <399x400.jbig2>');
const start = performance.now();
const result = await new Promise((resolve, reject) => {
  const worker = new Worker(new URL('./fuzz-worker.mjs', import.meta.url), { workerData: [...fs.readFileSync(fixture)] });
  const timeout = setTimeout(() => { worker.terminate(); reject(new Error('JBIG2 fuzz worker exceeded 10 second deadline')); }, 10000);
  worker.once('message', result => { clearTimeout(timeout); worker.terminate(); resolve(result); });
  worker.once('error', error => { clearTimeout(timeout); reject(error); });
});
console.log(JSON.stringify({ ...result, elapsedMs: performance.now() - start, deadlineMs: 10000 }, null, 2));

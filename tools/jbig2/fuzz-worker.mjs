import { parentPort, workerData } from 'node:worker_threads';
import fs from 'node:fs';
import { createJbig2Decoder } from '../../codecs/jbig2/decoder.mjs';
const decoder = await createJbig2Decoder({ wasmBytes: fs.readFileSync(new URL('../../vendor/jbig2/jbig2.wasm', import.meta.url)) });
let accepted = 0, rejected = 0, maxMs = 0;
let seed = 0x24681357;
function random() { seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; return seed >>> 0; }
const base = new Uint8Array(workerData);
for (let i = 0; i < 2000; i++) {
  const data = i < 1000 ? base.slice() : new Uint8Array(random() % 256);
  const changes = 1 + random() % 8;
  for (let j = 0; j < changes; j++) if (data.length) data[random() % data.length] = random() & 255;
  const start = performance.now();
  try { decoder.decode(data, null, 399, 400); accepted++; } catch { rejected++; }
  maxMs = Math.max(maxMs, performance.now() - start);
}
parentPort.postMessage({ accepted, rejected, maxMs });

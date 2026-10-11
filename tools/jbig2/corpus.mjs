import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
import { createJbig2Decoder } from '../../codecs/jbig2/decoder.mjs';
const [cache, nodeModules] = process.argv.slice(2);
if (!cache || !nodeModules) throw new Error('Usage: node tools/jbig2/corpus.mjs <fixture-cache> <oracle-node_modules>');
const manifest = JSON.parse(fs.readFileSync(new URL('./fixtures.json', import.meta.url)));
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const decoder = await createJbig2Decoder({wasmBytes: fs.readFileSync(new URL('../../vendor/jbig2/jbig2.wasm', import.meta.url))});
const canvas = await import(pathToFileURL(path.resolve(nodeModules, '@napi-rs/canvas/index.js')));
for (const n of ['DOMMatrix', 'ImageData', 'Path2D']) globalThis[n] = canvas[n];
const pdfjs = await import(pathToFileURL(path.resolve(nodeModules, 'pdfjs-dist/legacy/build/pdf.mjs')));
assert.equal(pdfjs.version, manifest.pdfjs_version);
const records = [];
const decoded = new Map();
for (const image of manifest.images) {
  const data = new Uint8Array(fs.readFileSync(path.join(cache, image.name + '.jbig2')));
  const globals = new Uint8Array(fs.readFileSync(path.join(cache, image.name + '.globals')));
  const samples = decoder.decode(data, globals, image.width, image.height);
  assert.equal(hash(samples), image.samples_sha256, image.name);
  const cold = decoder.lastStats;
  const timings = [];
  for (let i = 0; i < 3; i++) { decoder.decode(data, globals, image.width, image.height); timings.push(decoder.lastStats.elapsedMs); }
  timings.sort((a,b) => a-b);
  records.push({ name: image.name, ...cold, warmMedianMs: timings[1], sampleSha256: hash(samples) });
  decoded.set(image.name, samples);
}
const comparisons = [];
for (const pdf of new Set(manifest.images.map(x => x.pdf))) {
  const task = pdfjs.getDocument({ data: new Uint8Array(fs.readFileSync(path.join(cache, pdf))),
    useWasm: false, wasmUrl: path.resolve(nodeModules, 'pdfjs-dist/wasm') + '/', isEvalSupported: false });
  try {
    const doc = await task.promise, page = await doc.getPage(1), ops = await page.getOperatorList();
    for (let i = 0; i < ops.fnArray.length; i++) {
      if (ops.fnArray[i] !== pdfjs.OPS.paintImageXObject) continue;
      const ob = await new Promise(resolve => page.objs.get(ops.argsArray[i][0], resolve));
      const image = manifest.images.find(x => x.pdf === pdf && x.width === ob.width && x.height === ob.height && !x.mask);
      assert.ok(image, `No matching image: ${pdf}`);
      const samples = decoded.get(image.name);
      if (ob.kind === 1) {
        assert.equal(hash(samples), hash(ob.data), `${image.name} vs PDF.js asm.js`);
        comparisons.push({ name: image.name, comparedBytes: samples.length, differingBytes: 0 });
      } else if (pdf === 'JBIG2Globals.pdf' && ob.kind === 3) {
        // Real image object 11 and explicit /ImageMask object 12 share the
        // same bits. PDF Decode [0 1] means zero paints, one is transparent.
        const mask = decoded.get('JBIG2Globals-12'), row = Math.ceil(image.width / 8);
        let different = 0;
        for (let y = 0; y < image.height; y++) for (let x = 0; x < image.width; x++) {
          const bit = 7 - (x & 7), byte = y * row + (x >> 3), off = (y * image.width + x) * 4;
          const value = ((samples[byte] >> bit) & 1) * 255;
          for (let c = 0; c < 3; c++) different += ob.data[off + c] !== value;
          different += ob.data[off + 3] !== (1 - ((mask[byte] >> bit) & 1)) * 255;
        }
        assert.equal(different, 0, `${image.name} Decode/ImageMask polarity`);
        comparisons.push({ name: image.name + '+explicit-mask', comparedBytes: ob.data.length, differingBytes: different });
      } else throw new Error(`Unexpected PDF.js image kind ${ob.kind}`);
    }
  } finally { await task.destroy(); }
}
console.log(JSON.stringify({ pdfjsVersion: pdfjs.version, runtime: process.version, records, comparisons }, null, 2));

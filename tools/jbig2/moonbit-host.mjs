import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
import { installJbig2Decoder } from '../../codecs/jbig2/decoder.mjs';
const [modulePath, cache] = process.argv.slice(2);
if (!modulePath || !cache) throw new Error('Usage: node tools/jbig2/moonbit-host.mjs <compiled-probe.js> <fixture-cache>');
const { decode_image } = await import(pathToFileURL(path.resolve(modulePath)));
assert.equal(decode_image(new Uint8Array([1]), new Uint8Array(0), 1, 1), undefined);
await installJbig2Decoder({ wasmBytes: fs.readFileSync(new URL('../../vendor/jbig2/jbig2.wasm', import.meta.url)) });
assert.equal(decode_image(new Uint8Array([1]), new Uint8Array(0), 1, 1), undefined);
const manifest = JSON.parse(fs.readFileSync(new URL('./fixtures.json', import.meta.url)));
for (const image of manifest.images) {
  const bytes = decode_image(new Uint8Array(fs.readFileSync(path.join(cache, image.name + '.jbig2'))),
    new Uint8Array(fs.readFileSync(path.join(cache, image.name + '.globals'))), image.width, image.height);
  assert.ok(bytes instanceof Uint8Array, image.name);
  assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'), image.samples_sha256, image.name);
}
console.log(`MoonBit JS host FFI: ${manifest.images.length}/${manifest.images.length} fixture hashes match`);

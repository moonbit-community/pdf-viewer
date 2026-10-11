import assert from 'node:assert/strict';
import { test } from 'node:test';
import fs from 'node:fs';
import { createJbig2Decoder, inspectJbig2, stripJbig2FileHeader, installJbig2Decoder } from '../../codecs/jbig2/decoder.mjs';
const wasmBytes = fs.readFileSync(new URL('../../vendor/jbig2/jbig2.wasm', import.meta.url));
const decoder = await createJbig2Decoder({ wasmBytes });
const u32 = x => [x >>> 24, x >>> 16 & 255, x >>> 8 & 255, x & 255];
function segment(id, type, bytes, page = 1) {
  return [ ...u32(id), type, 0, page, ...u32(bytes.length), ...bytes ];
}
function blank(width = 9, height = 2, black = false) {
  return new Uint8Array(segment(1, 48, [...u32(width), ...u32(height), ...u32(72), ...u32(72), black ? 4 : 0, 0, 0]));
}

test('tight rows and PDF luminance polarity, no Decode or mask inversion', () => {
  assert.deepEqual([...decoder.decode(blank(), null, 9, 2)], [255, 255, 255, 255]);
  assert.deepEqual([...decoder.decode(blank(9, 2, true), null, 9, 2)], [0, 0, 0, 0]);
  assert.equal(decoder.lastStats.outputBytes, 4);
  assert.equal(decoder.lastStats.outputAllocatedBytes, 4);
});

test('PDF dimensions can clip a bounded codec padding column', () => {
  assert.equal(decoder.decode(blank(10, 2), null, 9, 2).length, 4);
});

test('sequential file headers with known and unknown page counts', () => {
  const magic = [151, 74, 66, 50, 13, 10, 26, 10];
  for (const head of [[...magic, 3], [...magic, 1, 0, 0, 0, 1]]) {
    const data = new Uint8Array([...head, ...blank()]);
    assert.deepEqual(stripJbig2FileHeader(data), blank());
    assert.equal(decoder.decode(data, null, 9, 2).length, 4);
  }
  assert.throws(() => stripJbig2FileHeader(new Uint8Array([...magic, 2])), /Random-access/);
  assert.throws(() => stripJbig2FileHeader(new Uint8Array(magic)), /Truncated/);
});

test('dimensions, compressed bytes, output and initial heap limits', async () => {
  for (const dims of [[0, 1], [1, -1], [32769, 1], [32768, 32768], [NaN, 1]])
    assert.throws(() => decoder.decode(blank(), null, ...dims), /dimensions/);
  const bounded = await createJbig2Decoder({ wasmBytes, limits: { maxInputBytes: 16 } });
  assert.throws(() => bounded.decode(blank(), null, 9, 2), /input/);
  const heap = await createJbig2Decoder({ wasmBytes, limits: { maxHeapBytes: 65536 } });
  assert.throws(() => heap.decode(blank(), null, 9, 2), /initial heap/);
  await assert.rejects(() => createJbig2Decoder({ wasmBytes, limits: { maxHeapBytes: 2 ** 30 } }), /Invalid/);
});

test('truncated framing, unknown lengths, duplicates and global-page confusion', () => {
  for (let n = 0; n < blank().length; n++)
    assert.throws(() => decoder.decode(blank().slice(0, n), null, 9, 2));
  const unknown = blank(); unknown.fill(255, 7, 11);
  assert.throws(() => inspectJbig2(unknown, null, 9, 2), /Unknown-length/);
  assert.throws(() => inspectJbig2(new Uint8Array([...blank(), ...blank()]), null, 9, 2), /Duplicate/);
  assert.throws(() => inspectJbig2(blank(), blank(), 9, 2), /page association/);
});

test('bounded regions, symbol counts and segment/reference counts', () => {
  const region = segment(2, 39, [...u32(0x7fffffff), ...u32(2), ...u32(0), ...u32(0), 0, 1]);
  assert.throws(() => inspectJbig2(new Uint8Array([...blank(), ...region]), null, 9, 2), /region dimensions/);
  const symbols = segment(2, 0, [0, 1, ...u32(0xffffffff), ...u32(0)]);
  assert.throws(() => inspectJbig2(new Uint8Array([...blank(), ...symbols]), null, 9, 2), /symbols/);
  assert.throws(() => inspectJbig2(new Uint8Array([...blank(), ...segment(2, 49, [])]), null, 9, 2,
    {...decoder.limits, maxSegments: 1}), /Too many JBIG2 segments/);
});

test('failed streams cannot reuse stale image data or poison the next decode', () => {
  assert.equal(decoder.decode(blank(), null, 9, 2)[0], 255);
  assert.throws(() => decoder.decode(new Uint8Array(11), null, 9, 2));
  assert.equal(decoder.lastStats, null);
  assert.equal(decoder.decode(blank(9, 2, true), null, 9, 2)[0], 0);
});

test('MoonBit host adapter registration returns bytes or null', async () => {
  await installJbig2Decoder({ wasmBytes });
  assert.equal(globalThis.__pdf_viewer_jbig2_decode(blank(), null, 9, 2)[0], 255);
  assert.equal(globalThis.__pdf_viewer_jbig2_decode(new Uint8Array(0), null, 9, 2), null);
  delete globalThis.__pdf_viewer_jbig2_decode;
});

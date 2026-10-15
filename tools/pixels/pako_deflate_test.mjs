import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {inflateSync} from 'node:zlib';
import {pakoSlideHash, optimizePakoDeflate} from '../pako_deflate_transform.mjs';
import {deflate} from '../../web/vendor/pako/pako.mjs';

// Exhaust both 16-bit lanes and every supported window size, then slide the
// same tables again. Include nonzero aligned offsets and independent tables.
for (let bits = 9; bits <= 15; bits++) {
  const windowSize = 1 << bits;
  const backing = new Uint16Array(65540).fill(0xbeef);
  const head = backing.subarray(2, 65538);
  const prev = new Uint16Array(65536);
  for (let i = 0; i < 65536; i++) { head[i] = i; prev[i] = 65535 - i; }
  for (let slide = 1; slide <= 3; slide++) {
    pakoSlideHash({w_size: windowSize, head, prev});
    for (let i = 0; i < 65536; i++) {
      assert.equal(head[i], Math.max(0, i - slide * windowSize));
      assert.equal(prev[i], Math.max(0, 65535 - i - slide * windowSize));
    }
    assert.equal(backing[0], 0xbeef);
    assert.equal(backing[1], 0xbeef);
    assert.equal(backing[65538], 0xbeef);
    assert.equal(backing[65539], 0xbeef);
  }
}
assert.throws(() => optimizePakoDeflate(''), /source changed/);
assert.throws(() => optimizePakoDeflate('const slide_hash = (s) => {'), /source changed/);
assert.throws(() => optimizePakoDeflate('const slide_hash = (s) => {\n};\nconst slide_hash = (s) => {\n};'), /source changed/);

const require = createRequire(resolve('tools/web-assets/package.json'));
const upstream = require('pako');
let seed = 123456789;
const random = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed >>> 24; };
const noise = Uint8Array.from({length: 300003}, random);
const pattern = Uint8Array.from({length: 300003}, (_, i) => (i * 13 + (i >>> 8)) & 255);
const repeated = new Uint8Array(300003);
for (let i = 0; i < repeated.length; i++) repeated[i] = noise[i % 32761];
const inputs = [new Uint8Array(), noise.subarray(0, 7), noise.subarray(0, 65535),
  noise, pattern, repeated, new Uint8Array(300003)];
let comparisons = 0;
for (const input of inputs) for (const level of [0, 1, 3, 6, 9]) {
  for (const windowBits of [9, 12, 15]) {
    const options = {level, windowBits, memLevel: level === 3 ? 9 : level === 6 ? 1 : 8};
    const before = input.slice();
    const expected = upstream.deflate(input, options);
    const actual = deflate(input, options);
    assert.deepEqual(actual, expected, JSON.stringify(options));
    assert.deepEqual(new Uint8Array(inflateSync(actual)), input);
    assert.deepEqual(input, before);
    comparisons++;
  }
}
console.log(`Pako hash slide: exhaustive 16-bit lanes and ${comparisons} byte-identical zlib encodes passed.`);

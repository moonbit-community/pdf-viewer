// Compare every low-level stream transition with the original pinned inflater.
// The shipped adapter is separately exercised by image_flate_test.mjs.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {deflateSync, constants} from 'node:zlib';
import {optimizePakoInflateFast} from '../pako_inflate_transform.mjs';

const directory = resolve('tools/web-assets/node_modules/pako/lib/zlib');
const require = createRequire(directory + '/inflate.js');
const original = await readFile(directory + '/inffast.js', 'utf8');
assert.throws(() => optimizePakoInflateFast(''), /source changed/);
assert.throws(() => optimizePakoInflateFast(original + original), /source changed/);
const modified = {exports: {}};
new Function('module', optimizePakoInflateFast(original))(modified);
const driverModule = {exports: {}};
new Function('module', 'require', await readFile(directory + '/inflate.js', 'utf8'))(
  driverModule, name => name === './inffast' ? modified.exports : require(name));
const drivers = [require('./inflate'), driverModule.exports];
const ZStream = require('./zstream');
let seed = 123456789;
const noise = Uint8Array.from({length: 8192}, () => {
  seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
  return seed >>> 24;
});
const inputs = [new Uint8Array(), noise, ...[1, 2, 3, 17, 258, 32749].map(period =>
  Uint8Array.from({length: 70003}, (_, index) => noise[(index % period) % noise.length]))];
const configurations = [[7, 259], [1021, 32768], [Infinity, 65536]];
let comparisons = 0, fillCalls = 0;
const fill = Uint8Array.prototype.fill;
try {
  Uint8Array.prototype.fill = function(value, start, end) {
    if (arguments.length === 3 && end - start >= 3) fillCalls++;
    return fill.call(this, value, start, end);
  };
  for (const input of inputs) for (const options of [{level: 1}, {level: 6}, {strategy: constants.Z_FIXED}]) {
    const compressed = deflateSync(input, options);
    for (const [inputStep, outputStep] of configurations) {
      const streams = drivers.map(driver => {
        const stream = new ZStream();
        assert.equal(driver.inflateInit2(stream, 15), 0);
        stream.input = compressed;
        return stream;
      });
      let available = 0, length = 0, finished = false;
      for (let step = 0; step < compressed.length + input.length + 10; step++) {
        available = Math.min(compressed.length, available + inputStep);
        const results = drivers.map((driver, index) => {
          const stream = streams[index];
          const backing = new Uint8Array(outputStep + 10).fill(0xa5);
          stream.output = backing.subarray(5, 5 + outputStep);
          stream.avail_in = available - stream.next_in;
          stream.next_out = 0;
          stream.avail_out = outputStep;
          const status = driver.inflate(stream, 0);
          assert(backing.subarray(0, 5).every(byte => byte === 0xa5));
          assert(backing.subarray(5 + outputStep).every(byte => byte === 0xa5));
          return {status, nextIn: stream.next_in, availIn: stream.avail_in,
            nextOut: stream.next_out, availOut: stream.avail_out,
            mode: stream.state.mode, hold: stream.state.hold, bits: stream.state.bits,
            check: stream.state.check, output: stream.output.slice(0, stream.next_out)};
        });
        assert.deepEqual(results[1], results[0]);
        const result = results[1];
        assert.deepEqual(result.output, input.slice(length, length + result.nextOut));
        length += result.nextOut;
        comparisons++;
        if (result.status === 1) { finished = true; break; }
        assert.equal(result.status, 0);
      }
      for (let index = 0; index < streams.length; index++) drivers[index].inflateEnd(streams[index]);
      assert(finished);
      assert.equal(length, input.length);
    }
  }
} finally {Uint8Array.prototype.fill = fill;}
assert(fillCalls > 100, 'Distance-one native expansion must actually run');
console.log(`Pako inflate: ${comparisons} identical stream transitions; ${fillCalls} native fills; input/output splits, overlapping matches and window boundaries passed.`);

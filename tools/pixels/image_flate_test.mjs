// Exercise the actual release bridge with and without its optional image host.
import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {deflateSync, inflateSync, constants} from 'node:zlib';
import {inflateBounded} from '../../web/vendor/pako/pako.mjs';
import {installPdfFlate} from '../../web/pdf-flate.mjs';

const directory = resolve('_build/image-flate-test');
await mkdir(directory, {recursive: true});
const source = await readFile(resolve('web/_generated/pdf.js'), 'utf8');
const names = [...source.matchAll(/^function ([$\w]+)\(/gm)].map(match => match[1]);
const find = suffix => {
  const name = names.find(name => name.endsWith(suffix));
  assert(name, 'Compiler names changed: ' + suffix);
  return name;
};
const generated = resolve(directory, 'bridge.mjs');
await writeFile(generated, source + `\nexport {${find('pdf__image__inflate__limited_2einner')} as inflate, ${find('pdf__png__of__scanline__bytes')} as png};\n`);
const bridge = await import(pathToFileURL(generated));
installPdfFlate();
const fast = globalThis.__moonbit_pdf_image_inflate;
let accepted = 0, comparisons = 0;
function compare(data, limit, prefix) {
  delete globalThis.__moonbit_pdf_image_inflate;
  const expected = bridge.inflate(data, limit, prefix);
  globalThis.__moonbit_pdf_image_inflate = (bytes, bound) => {
    const output = fast(bytes, bound);
    if (output?.length) accepted++;
    return output;
  };
  assert.deepEqual(bridge.inflate(data, limit, prefix), expected, `limit=${limit}, prefix=${prefix}`);
  comparisons++;
}
let seed = 123456789;
const random = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed >>> 24; };
const noise = Uint8Array.from({length: 70003}, random);
for (const pixels of [new Uint8Array(), Buffer.from('small image'), Buffer.alloc(100003, 0x5a), noise]) {
  for (const options of [{level: 0}, {level: 1}, {level: 6}, {strategy: constants.Z_FIXED}]) {
    const compressed = deflateSync(pixels, options);
    assert.deepEqual(inflateBounded(compressed, pixels.length), new Uint8Array(pixels));
    for (const limit of [0, 1, 32767, 32768, pixels.length, pixels.length + 1])
      for (const prefix of [false, true]) compare(compressed, limit, prefix);
    for (const suffix of [Buffer.from([0, 255, 78]), Buffer.from('trailing'), deflateSync(Buffer.from('second stream'))]) {
      const data = Buffer.concat([compressed, suffix]);
      assert.deepEqual(inflateBounded(data, pixels.length + 100), new Uint8Array(pixels));
      compare(data, pixels.length + 100, false);
    }
    for (const cut of [1, 2, 3, compressed.length >> 1, compressed.length - 4, compressed.length - 1]) {
      for (const prefix of [false, true]) {
        compare(compressed.subarray(0, Math.max(0, cut)), 17, prefix);
        compare(compressed.subarray(0, Math.max(0, cut)), pixels.length + 1, prefix);
      }
    }
    for (let mutation = 0; mutation < 24; mutation++) {
      const data = Buffer.from(compressed);
      const position = Math.floor((random() / 256) * data.length);
      data[position] ^= random() || 1;
      for (const prefix of [false, true]) compare(data, pixels.length + 1, prefix);
    }
  }
}
// Fixed output buffers stop expansion before retaining the full attacker input.
assert.equal(inflateBounded(deflateSync(Buffer.alloc(8 * 1024 * 1024)), 1024), null);
for (const data of [Buffer.from([0x78, 0x20, 0, 0, 0, 1]), Buffer.from([0x88, 0x1c, 3, 0, 0, 0, 0, 1])])
  for (const prefix of [false, true]) compare(data, 0, prefix);
assert(accepted > 50, 'The fast path must actually be exercised');

const fastDeflate = globalThis.__moonbit_pdf_image_deflate;
function decodePng(result) {
  assert.equal(result.$tag, 1);
  const bytes = Buffer.from(result._0), idat = [];
  let header;
  for (let offset = 8; offset < bytes.length;) {
    const length = bytes.readUInt32BE(offset), type = bytes.toString('ascii', offset + 4, offset + 8);
    const data = bytes.subarray(offset + 8, offset + 8 + length);
    if (type === 'IHDR') header = data;
    if (type === 'IDAT') idat.push(data);
    offset += length + 12;
  }
  return {header, rows: inflateSync(Buffer.concat(idat))};
}
for (const channels of [3, 4]) for (const width of [1, 7, 257]) {
  const height = 39, stride = width * channels + 1;
  const rows = Uint8Array.from({length: stride * height}, random);
  for (let y = 0; y < height; y++) rows[y * stride] = 0;
  delete globalThis.__moonbit_pdf_image_deflate;
  const expected = decodePng(bridge.png(width, height, channels === 4 ? 6 : 2, rows));
  globalThis.__moonbit_pdf_image_deflate = fastDeflate;
  assert.deepEqual(decodePng(bridge.png(width, height, channels === 4 ? 6 : 2, rows)), expected);
}
delete globalThis.__moonbit_pdf_image_inflate;
delete globalThis.__moonbit_pdf_image_deflate;
console.log(`Image Flate: ${comparisons} portable/host comparisons passed; ${accepted} nonempty fast decodes; RGB/RGBA PNG samples match.`);

// Optional local corpus check: preserve every payload field while comparing
// PNG samples rather than the choice of lossless DEFLATE representation.
if (process.argv[2]) {
  const {installPdfIccEngine} = await import('../../web/pdf-icc.mjs');
  const {installJbig2Decoder} = await import('../../codecs/jbig2/decoder.mjs');
  await installPdfIccEngine({wasmBinary: await readFile(resolve('web/vendor/lcms-wasm/lcms.wasm'))});
  await installJbig2Decoder({wasmBytes: await readFile(resolve('vendor/jbig2/jbig2.wasm'))});
  const input = new Uint8Array(await readFile(resolve(process.argv[2])));
  const hash = bytes => createHash('sha256').update(bytes).digest('hex');
  const canonical = payload => payload.replace(/data:image\/png;base64,([A-Za-z0-9+/=]+)/g, (_, data) => {
    const png = decodePng({$tag: 1, _0: Buffer.from(data, 'base64')});
    return 'png-samples:' + hash(png.header) + ':' + hash(png.rows);
  });
  function pages() {
    const opened = JSON.parse(bridge.open_pdf(input));
    assert(opened.ok);
    try {
      return Array.from({length: opened.pages}, (_, index) => {
        const payload = bridge.render_page(index + 1, 1, 0, true);
        assert(JSON.parse(payload).ok);
        return hash(canonical(payload));
      });
    } finally {bridge.close_pdf();}
  }
  const expected = pages();
  installPdfFlate();
  try {assert.deepEqual(pages(), expected);}
  finally {
    delete globalThis.__moonbit_pdf_image_inflate;
    delete globalThis.__moonbit_pdf_image_deflate;
  }
  console.log(`Image Flate: all ${expected.length} page payloads and decoded PNG samples match.`);
}

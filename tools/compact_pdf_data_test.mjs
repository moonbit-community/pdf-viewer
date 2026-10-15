import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {deflateSync} from 'node:zlib';
import {compactPdfData} from './compact_pdf_data.mjs';
import {pdfStaticIntegers} from '../web/pdf-static-data.mjs';

const directory = resolve('_build/static-data-test');
await mkdir(resolve(directory, '_generated'), {recursive: true});
await mkdir(resolve(directory, 'vendor/pako'), {recursive: true});
const runtime = await readFile(resolve('web/pdf-static-data.mjs'), 'utf8');
await writeFile(resolve(directory, 'pdf-static-data.mjs'), 'export const counts={integers:0,strings:0};\n' + runtime
  .replace('export function pdfStaticIntegers(encoded, count, length, stride) {', '$&\n counts.integers++;')
  .replace('export function pdfStaticString(encoded, length) {', '$&\n counts.strings++;'));
await writeFile(resolve(directory, 'vendor/pako/pako.mjs'), await readFile(resolve('web/vendor/pako/pako.mjs')));
const helper = await import(pathToFileURL(resolve(directory, 'pdf-static-data.mjs')));
let serial = 0;
async function load(source, compact) {
  const text = compact ? compactPdfData(source).source : source;
  const file = resolve(directory, '_generated', `case-${serial++}.mjs`);
  await writeFile(file, text);
  return import(pathToFileURL(file));
}

// Signed wraparound, irregular data and interleaved sorted columns exercise
// both compact encodings. A property key/string/comment must not be rewritten.
let seed = 123456789;
const random = () => seed = (Math.imul(seed, 1664525) + 1013904223) | 0;
for (const values of [
  Array.from({length: 4000}, (_, i) => [i, 65535 - i, -2147483648, 2147483647][i % 4]),
  Array.from({length: 4000}, random),
  Array.from({length: 4000}, (_, i) => i),
]) {
  const source = `const _M0table=${JSON.stringify(values)};
    export function values(){return _M0table;}
    export function props(){const object={_M0table:7};return [object._M0table,"_M0table",_M0table[3]];}
    // _M0table is a comment, not a use.\n`;
  const before = helper.counts.integers, module = await load(source, true);
  assert.equal(helper.counts.integers, before, 'Import must not decode the table');
  assert.deepEqual(module.values(), values);
  assert.deepEqual(module.props(), [7, '_M0table', values[3]]);
  assert.equal(module.values(), module.values(), 'Keep the original shared array identity');
  assert.equal(helper.counts.integers, before + 1, 'Decode each table only once');
}
const flat = Array.from({length: 4000}, (_, i) => i * 3);
const derivedSource = `const _M0flat=${JSON.stringify(flat)};
function _M0FP411moonbitlang7pdflite4text8cmapdata18pdf__cmap__unpack2(a){return a.map(value=>({_0:value}));}
const _M0derived=_M0FP411moonbitlang7pdflite4text8cmapdata18pdf__cmap__unpack2(_M0flat);
export function values(){return _M0derived;}`;
const beforeDerived = helper.counts.integers, derived = await load(derivedSource, true);
assert.equal(helper.counts.integers, beforeDerived, 'Derived initializers must not force the flat table');
assert.deepEqual(derived.values(), flat.map(value => ({_0: value})));
assert.equal(derived.values(), derived.values());
for (const use of ['export {_M0table};', 'function f(_M0table){return _M0table;}', 'const x={_M0table};', '_M0table=[];'])
  assert.throws(() => compactPdfData(`const _M0table=${JSON.stringify(flat)};${use}`), /Unsupported static PDF table reference/);
for (const literal of ['-0', '1.25', '2147483648', 'null']) {
  const source = `const _M0table=[${literal},${flat.join(',')}]; export function values(){return _M0table;}`;
  assert.equal(compactPdfData(source).statistics.tables, 0, 'Do not narrow non-int32 data');
}
const pack = bytes => deflateSync(bytes).toString('base64');
assert.throws(() => pdfStaticIntegers(pack(Buffer.from([128])), 1, 1, 1), /Invalid bundled PDF integer/);
assert.throws(() => pdfStaticIntegers(pack(Buffer.from([255, 255, 255, 255, 31])), 1, 5, 1), /Invalid bundled PDF integer/);
assert.throws(() => pdfStaticIntegers(pack(Buffer.from([0, 0])), 1, 2, 1), /Invalid bundled PDF integer count/);
assert.throws(() => pdfStaticIntegers(pack(Buffer.from([0])), 1, 1, 0), /Invalid bundled PDF integer length/);

// Compare every selected table, including the real unpacker results, against
// the untouched release bridge. Also compare every embedded CMap/font byte.
const original = await readFile(resolve('web/_generated/pdf.js'), 'utf8');
const compacted = compactPdfData(original);
assert.equal(compacted.statistics.tables, 53, 'Review data compaction after compiler/dependency changes');
assert.equal(compacted.statistics.derived, 77);
assert.equal(compacted.statistics.strings, 46);
const names = [...compacted.source.matchAll(/let (\S+)\$pdfData; function (\S+)\(\)/g)].map(match => match[2]);
assert.equal(names.length, 130);
const find = suffix => {
  const match = [...original.matchAll(/^function (\S+)\(/gm)].find(match => match[1].endsWith(suffix));
  assert(match, 'Compiler asset lookup names changed');
  return match[1];
};
const expose = `\nexport function staticValues(){return [${names.join(',')}];}
export const cmapLookup=${find('internal12cmap__assets6lookup')};
export const fontLookup=${find('internal12font__assets6lookup')};\n`;
const counted = original.replace(/^(function _M0FP411moonbitlang7pdflite4text8cmapdata\d+pdf__cmap__unpack(?:[123]|__csr)\([^)]*\) \{)/gm,
  '$&\n globalThis.pdfStaticUnpacks=(globalThis.pdfStaticUnpacks||0)+1;');
globalThis.pdfStaticUnpacks = 0;
const baseline = await load(counted + expose, false);
assert.equal(globalThis.pdfStaticUnpacks, 77, 'The baseline must reproduce eager CMap construction');
globalThis.pdfStaticUnpacks = 0;
const counts = {...helper.counts}, candidate = await load(counted + expose, true);
assert.deepEqual(helper.counts, counts, 'Full bridge import must not load compacted data');
assert.equal(globalThis.pdfStaticUnpacks, 0, 'Full bridge import must not expand derived CMaps');
const expected = baseline.staticValues(), actual = candidate.staticValues();
assert.deepEqual(actual, expected);
assert.equal(helper.counts.integers - counts.integers, 53);
assert.equal(globalThis.pdfStaticUnpacks, 77);
assert(candidate.staticValues().every((table, index) => table === actual[index]));
assert.equal(globalThis.pdfStaticUnpacks, 77, 'Repeated access must not rebuild derived CMaps');
delete globalThis.pdfStaticUnpacks;
const inventory = await readFile(resolve('internal/engine/builtin_cmap_assets_wbtest.mbt'), 'utf8');
const cmaps = [...inventory.matchAll(/"([^"]+)"/g)].map(match => match[1]);
const fonts = JSON.parse(await readFile(resolve('assets/standard14/inventory.json'))).fonts;
for (const name of [...cmaps, 'not-a-cmap']) assert.deepEqual(candidate.cmapLookup(name), baseline.cmapLookup(name));
for (const {name} of [...fonts, {name: 'not-a-font'}]) assert.deepEqual(candidate.fontLookup(name), baseline.fontLookup(name));
console.log(`Static PDF data: ${compacted.statistics.integers} integers, ${names.length} flat/derived tables, ${cmaps.length} CMaps and ${fonts.length} fonts match; lazy imports, memoization and rejected shapes passed.`);

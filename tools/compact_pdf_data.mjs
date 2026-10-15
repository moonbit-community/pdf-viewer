// Compact compiler-emitted static data, keeping the MoonBit algorithms intact.
// AST ranges prevent edits inside strings/comments and fail closed on compiler
// shape changes. Only uniquely bound top-level integer arrays become getters.
import {createRequire} from 'node:module';
import {deflateSync} from 'node:zlib';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const require = createRequire(resolve(root, 'tools/web-assets/package.json'));
const {parse} = require('acorn');
if (require('acorn/package.json').version !== '8.15.0') throw Error('PDF data build requires locked acorn 8.15.0');
const integer = node => node?.type === 'Literal' && Number.isInteger(node.value) ? node.value
  : node?.type === 'UnaryExpression' && node.operator === '-' && node.argument.type === 'Literal' && Number.isInteger(node.argument.value) ? -node.argument.value : NaN;
const packed = bytes => JSON.stringify(deflateSync(bytes, {level: 9}).toString('base64'));

function packIntegers(values) {
  const bytes = Buffer.alloc(values.length * 4);
  values.forEach((value, index) => bytes.writeInt32LE(value, index * 4));
  let best = {data: packed(bytes), length: bytes.length, stride: 0};
  // Flat CMaps interleave sorted keys, ranges and targets. Delta each column
  // before unsigned varints; preserve signed 32-bit wraparound exactly.
  for (const stride of [1, 2, 3, 4]) {
    const previous = new Array(stride).fill(0), output = [];
    values.forEach((value, index) => {
      const column = index % stride, delta = (value - previous[column]) | 0;
      previous[column] = value;
      let word = ((delta << 1) ^ (delta >> 31)) >>> 0;
      while (word >= 128) { output.push((word & 127) | 128); word >>>= 7; }
      output.push(word);
    });
    const data = packed(Buffer.from(output));
    if (data.length < best.data.length) best = {data, length: output.length, stride};
  }
  return best;
}

function walk(node, visit, parent = null) {
  if (!node || typeof node.type !== 'string') return;
  if (visit(node, parent) === false) return;
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) for (const child of value) walk(child, visit, node);
    else if (value && typeof value === 'object') walk(value, visit, node);
  }
}

export function compactPdfData(source) {
  const ast = parse(source, {ecmaVersion: 2022, sourceType: 'module'});
  const tables = new Map(), edits = new Map();
  const statistics = {tables: 0, derived: 0, integers: 0, strings: 0, originalBytes: 0, packedBytes: 0};
  for (const declaration of ast.body) {
    if (declaration.type !== 'VariableDeclaration' || declaration.kind !== 'const' || declaration.declarations.length !== 1) continue;
    const {id, init} = declaration.declarations[0];
    if (id.type !== 'Identifier' || !id.name.startsWith('_M0') || init?.type !== 'ArrayExpression' || init.end - init.start < 8192) continue;
    const values = init.elements.map(integer);
    if (!values.length || values.some(value => !Number.isInteger(value) || Object.is(value, -0) || value < -2147483648 || value > 2147483647)) continue;
    const {data, length, stride} = packIntegers(values), cache = id.name + '$pdfData';
    tables.set(id.name, declaration);
    edits.set(declaration.start, {end: declaration.end,
      text: `let ${cache}; function ${id.name}(){return ${cache} ??= __pdfStaticIntegers(${data},${values.length},${length},${stride});}`});
    statistics.tables++;
    statistics.integers += values.length;
    statistics.originalBytes += init.end - init.start;
    statistics.packedBytes += data.length;
  }
  // pdflite also expands flat CMap constants into pairs/ranges at module
  // initialization. These audited pure unpackers must be lazy as well, or
  // their initializers would immediately force all the compacted inputs.
  const derived = [];
  for (const declaration of ast.body) {
    if (declaration.type !== 'VariableDeclaration' || declaration.kind !== 'const' || declaration.declarations.length !== 1) continue;
    const {id, init} = declaration.declarations[0];
    if (id.type !== 'Identifier' || init?.type !== 'CallExpression' || init.callee.type !== 'Identifier' ||
        !/^_M0FP411moonbitlang7pdflite4text8cmapdata\d+pdf__cmap__unpack(?:[123]|__csr)$/.test(init.callee.name) ||
        init.arguments.some(argument => argument.type !== 'Identifier')) continue;
    tables.set(id.name, declaration);
    derived.push({declaration, id, init});
    statistics.derived++;
  }
  for (const {declaration, id, init} of derived) {
    const cache = id.name + '$pdfData';
    const args = init.arguments.map(argument => argument.name + (tables.has(argument.name) ? '()' : ''));
    edits.set(declaration.start, {end: declaration.end,
      text: `let ${cache}; function ${id.name}(){return ${cache} ??= ${init.callee.name}(${args.join(',')});}`});
  }
  const declarations = new Set(tables.values());
  walk(ast, (node, parent) => {
    if (declarations.has(node)) return false;
    if (node.type !== 'Identifier' || !tables.has(node.name)) return;
    // Generated globals cannot be rebound, exported, shadowed or used as an
    // object shorthand. Refuse unexpected shapes rather than changing meaning.
    if (parent.type === 'ExportSpecifier' || parent.type === 'VariableDeclarator' && parent.id === node ||
        /Function/.test(parent.type) && (parent.id === node || parent.params?.includes(node)) ||
        parent.type === 'AssignmentExpression' && parent.left === node ||
        parent.type === 'UpdateExpression' || parent.type === 'Property' && parent.shorthand)
      throw Error('Unsupported static PDF table reference: ' + node.name);
    if ((parent.type === 'Property' && parent.key === node || parent.type === 'MemberExpression' && parent.property === node) && !parent.computed) return;
    edits.set(node.start, {end: node.end, text: node.name + '()'});
  });
  // Resource literals remain lazy inside their existing lookup functions.
  // Their uncompressed string/byte values and decoder behavior stay identical.
  for (const fn of ast.body) {
    if (fn.type !== 'FunctionDeclaration' || !/internal12(?:cmap|font)__assets6lookup$/.test(fn.id?.name)) continue;
    walk(fn.body, node => {
      if (node.type !== 'Literal' || typeof node.value !== 'string' || node.value.length < 8192 || !/^[A-Za-z0-9+/=\s]+$/.test(node.value)) return;
      const bytes = Buffer.from(node.value, 'utf8'), data = packed(bytes);
      edits.set(node.start, {end: node.end, text: `__pdfStaticString(${data},${bytes.length})`});
      statistics.strings++;
      statistics.originalBytes += node.end - node.start;
      statistics.packedBytes += data.length;
    });
  }
  let result = source;
  const ordered = [...edits].sort((a, b) => b[0] - a[0]);
  let boundary = source.length;
  for (const [start, edit] of ordered) {
    if (edit.end > boundary) throw Error('Overlapping static PDF data edits');
    result = result.slice(0, start) + edit.text + result.slice(edit.end);
    boundary = start;
  }
  if (edits.size) result = 'import {pdfStaticIntegers as __pdfStaticIntegers,pdfStaticString as __pdfStaticString} from "../pdf-static-data.mjs";\n' + result;
  return {source: result, statistics};
}

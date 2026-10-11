/* Copyright 2026. Licensed under Apache-2.0. */
// Thin host for Mozilla's standalone PDFium codec, not a PDF renderer.
// The import/export names below are pinned to pdfjs-dist 6.4.299.
export const JBIG2_LIMITS = Object.freeze({
  maxDimension: 32768,
  maxPixels: 64 * 1024 * 1024,
  maxInputBytes: 16 * 1024 * 1024,
  maxOutputBytes: 8 * 1024 * 1024,
  maxHeapBytes: 128 * 1024 * 1024,
  maxSegments: 4096,
  maxReferences: 65536,
  maxSymbols: 1024 * 1024,
  maxWorkPixels: 256 * 1024 * 1024,
});

export class Jbig2DecodeError extends Error {
  constructor(message) { super(message); this.name = 'Jbig2DecodeError'; }
}
const reject = message => { throw new Jbig2DecodeError(message); };
const signature = [0x97, 0x4a, 0x42, 0x32, 0x0d, 0x0a, 0x1a, 0x0a];
const regionTypes = new Set([4, 6, 7, 20, 22, 23, 36, 38, 39, 40, 42, 43]);
const allowedTypes = new Set([0, ...regionTypes, 16, 48, 49, 50, 51, 52, 53, 62]);

export function stripJbig2FileHeader(bytes) {
  if (bytes.length < 8 || !signature.every((b, i) => bytes[i] === b)) return bytes;
  if (bytes.length < 9) reject('Truncated JBIG2 file header');
  const flags = bytes[8];
  if (!(flags & 1)) reject('Random-access JBIG2 files are unsupported');
  if (flags & 0xfc) reject('Reserved JBIG2 file flags');
  const size = flags & 2 ? 9 : 13;
  if (bytes.length < size) reject('Truncated JBIG2 page count');
  return bytes.subarray(size);
}

function dimensions(width, height, limits) {
  if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 ||
      height <= 0 || width > limits.maxDimension || height > limits.maxDimension ||
      width * height > limits.maxPixels) reject('JBIG2 dimensions exceed limit');
  const rowBytes = Math.ceil(width / 8);
  if (rowBytes * height > limits.maxOutputBytes) reject('JBIG2 output exceeds limit');
  return rowBytes;
}

// This is a bounded framing/size preflight, not another entropy decoder.
// Unknown-length segments are deliberately rejected rather than scanning for
// ambiguous entropy terminators. PDFium remains responsible for compression.
export function inspectJbig2(data, globals, width, height, limits = JBIG2_LIMITS) {
  const rowBytes = dimensions(width, height, limits);
  if (!(data instanceof Uint8Array) ||
      (globals != null && !(globals instanceof Uint8Array))) reject('Expected JBIG2 byte arrays');
  if (!data.length || data.length + (globals?.length || 0) > limits.maxInputBytes)
    reject('JBIG2 input exceeds limit or is empty');
  data = stripJbig2FileHeader(data);
  globals = globals?.length ? stripJbig2FileHeader(globals) : null;
  const summary = { data, globals, rowBytes, segments: 0, references: 0, workPixels: 0,
    types: new Set(), hasPage: false };
  const ids = new Set();
  function work(w, h) {
    if (w > limits.maxDimension || h > limits.maxDimension || w * h > limits.maxPixels)
      reject('JBIG2 region dimensions exceed limit');
    summary.workPixels += w * h;
    if (summary.workPixels > limits.maxWorkPixels) reject('JBIG2 region work exceeds limit');
  }
  function parse(bytes, isGlobal) {
    if (!bytes) return;
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const u32 = p => view.getUint32(p, false);
    let p = 0;
    while (p < bytes.length) {
      const require = n => { if (n < 0 || p + n > bytes.length) reject('Truncated JBIG2 segment'); };
      require(6);
      const number = u32(p); p += 4;
      if (ids.has(number)) reject('Duplicate JBIG2 segment');
      ids.add(number);
      const flags = bytes[p++], type = flags & 63;
      if (!allowedTypes.has(type)) reject('Unsupported JBIG2 segment type');
      if (++summary.segments > limits.maxSegments) reject('Too many JBIG2 segments');
      summary.types.add(type);
      let count = bytes[p] >>> 5;
      if (count === 7) {
        require(4); count = u32(p) & 0x1fffffff; p += 4;
        const flagsBytes = Math.ceil((count + 1) / 8);
        require(flagsBytes); p += flagsBytes;
      } else {
        if (count > 4) reject('Reserved JBIG2 reference count');
        p++;
      }
      summary.references += count;
      if (summary.references > limits.maxReferences) reject('Too many JBIG2 references');
      const refBytes = number <= 256 ? 1 : number <= 65536 ? 2 : 4;
      require(count * refBytes); p += count * refBytes;
      const pageBytes = flags & 64 ? 4 : 1;
      require(pageBytes + 4);
      const page = pageBytes === 4 ? u32(p) : bytes[p]; p += pageBytes;
      if ((isGlobal && page !== 0) || (!isGlobal && page > 1))
        reject('Unsupported JBIG2 page association');
      const length = u32(p); p += 4;
      if (length === 0xffffffff) reject('Unknown-length JBIG2 segments are unsupported');
      require(length);
      const end = p + length;
      const payload = n => { if (p + n > end) reject('Truncated JBIG2 segment payload'); };
      if (type === 48) {
        payload(19);
        if (isGlobal) reject('Page information in JBIG2 globals');
        // PDFium clips to the PDF image dimensions. Real scanning PDFs can
        // differ by a padding column; bound both sizes rather than reject it.
        const pageWidth = u32(p), pageHeight = u32(p + 4);
        dimensions(pageWidth, pageHeight === 0xffffffff ? height : pageHeight, limits);
        if (summary.hasPage) reject('Multiple JBIG2 pages are unsupported');
        summary.hasPage = true;
      }
      if (regionTypes.has(type)) {
        payload(17); work(u32(p), u32(p + 4));
      }
      if (type === 0) {
        payload(2);
        const sf = view.getUint16(p, false);
        let q = p + 2;
        if (!(sf & 1)) q += ((sf >> 10) & 3) === 0 ? 8 : 2;
        if ((sf & 2) && !(sf & 4096)) q += 4;
        if (q + 8 > end) reject('Truncated JBIG2 symbol dictionary');
        if (u32(q) > limits.maxSymbols || u32(q + 4) > limits.maxSymbols)
          reject('Too many JBIG2 symbols');
      } else if ([4, 6, 7].includes(type)) {
        payload(19);
        const tf = view.getUint16(p + 17, false);
        let q = p + 19 + (tf & 1 ? 2 : 0);
        if ((tf & 2) && !(tf & 32768)) q += 4;
        if (q + 4 > end) reject('Truncated JBIG2 text region');
        if (u32(q) > limits.maxSymbols) reject('Too many JBIG2 text instances');
      } else if (type === 16) {
        payload(7);
        const count = u32(p + 3) + 1;
        if (count > limits.maxSymbols) reject('Too many JBIG2 patterns');
        summary.workPixels += bytes[p + 1] * bytes[p + 2] * count;
        if (summary.workPixels > limits.maxWorkPixels) reject('JBIG2 pattern work exceeds limit');
      } else if ([20, 22, 23].includes(type)) {
        payload(38); work(u32(p + 18), u32(p + 22));
      }
      p = end;
    }
  }
  parse(globals, true); parse(data, false);
  if (!summary.hasPage) reject('Missing JBIG2 page information');
  return summary;
}

export async function createJbig2Decoder({ wasmBytes, wasmUrl = new URL('../../vendor/jbig2/jbig2.wasm', import.meta.url), limits = {} } = {}) {
  limits = Object.freeze({ ...JBIG2_LIMITS, ...limits });
  for (const [key, value] of Object.entries(limits)) {
    if (!Number.isSafeInteger(value) || value <= 0 || value > JBIG2_LIMITS[key])
      reject(`Invalid JBIG2 limit: ${key}`);
  }
  if (!wasmBytes) {
    const response = await fetch(wasmUrl);
    if (!response.ok) reject(`Unable to load JBIG2 codec: HTTP ${response.status}`);
    wasmBytes = await response.arrayBuffer();
  }
  const module = await WebAssembly.compile(wasmBytes);
  let lastStats = null;
  function decode(data, globals, width, height) {
    const started = performance.now();
    lastStats = null;
    const info = inspectJbig2(data, globals, width, height, limits);
    const outputSize = info.rowBytes * height;
    let exports, memory, imageData = null, allocations = 0, heapPeak = 0;
    const abort = () => reject('JBIG2 decoder failed');
    const range = (ptr, size) => {
      if (!Number.isSafeInteger(ptr) || !Number.isSafeInteger(size) || ptr < 0 || size < 0 ||
          ptr + size > memory.buffer.byteLength) reject('Invalid JBIG2 memory range');
      return new Uint8Array(memory.buffer, ptr, size);
    };
    const imports = { a: {
      // The standalone codec does not need an event-loop timer. Refuse one
      // rather than leave callbacks holding a completed/failed decode alive.
      a: (_which, timeout) => { if (timeout) abort(); return 0; },
      b: requested => {
        requested >>>= 0;
        if (requested > limits.maxHeapBytes) return 0;
        const pages = Math.ceil((requested - memory.buffer.byteLength) / 65536);
        try { if (pages > 0) memory.grow(pages); } catch { return 0; }
        heapPeak = Math.max(heapPeak, memory.buffer.byteLength);
        return 1;
      },
      c: abort, d: () => {}, e: abort,
      f: (ptr, pitch, offset) => {
        if (!imageData || offset < 0 || pitch < 0 || offset + pitch > outputSize) abort();
        imageData.set(range(ptr, pitch), offset);
      },
      g: size => {
        if (size !== outputSize || imageData) abort();
        imageData = new Uint8Array(size); allocations += size;
      },
      h: (ptr, pitch8, pitch32, rows) => {
        if (imageData || pitch8 !== info.rowBytes || rows !== height || pitch32 < pitch8) abort();
        range(ptr, pitch32 * rows);
        imageData = new Uint8Array(outputSize); allocations += outputSize;
        for (let y = 0; y < rows; y++) imageData.set(range(ptr + y * pitch32, pitch8), y * pitch8);
      },
    } };
    // Fresh instances release native symbol caches, including after a trap.
    exports = new WebAssembly.Instance(module, imports).exports;
    memory = exports.i; heapPeak = memory.buffer.byteLength;
    if (heapPeak > limits.maxHeapBytes) reject('JBIG2 initial heap exceeds limit');
    exports.j();
    const allocate = bytes => {
      if (!bytes?.length) return 0;
      const ptr = exports.k(bytes.length);
      if (!ptr) reject('JBIG2 input allocation failed');
      range(ptr, bytes.length).set(bytes);
      return ptr;
    };
    let inputPtr = 0, globalsPtr = 0;
    try {
      inputPtr = allocate(info.data); globalsPtr = allocate(info.globals);
      exports.m(inputPtr, info.data.length, width, height, globalsPtr, info.globals?.length || 0);
      if (!imageData || imageData.length !== outputSize) reject('JBIG2 decoder produced no image');
      lastStats = Object.freeze({ elapsedMs: performance.now() - started, heapBytes: heapPeak,
        outputBytes: outputSize, outputAllocatedBytes: allocations,
        inputBytes: info.data.length + (info.globals?.length || 0),
        segments: info.segments, references: info.references, types: [...info.types] });
      // PDFium emits PDF luminance: 0 is black and 1 is white. Do not invert;
      // the PDF image layer applies /Decode and ImageMask exactly once.
      return imageData;
    } catch (error) {
      if (error instanceof Jbig2DecodeError) throw error;
      throw new Jbig2DecodeError(`JBIG2 decoder rejected stream: ${error.message || error}`);
    } finally {
      if (inputPtr) exports.l(inputPtr);
      if (globalsPtr) exports.l(globalsPtr);
    }
  }
  return Object.freeze({ decode, get lastStats() { return lastStats; }, limits });
}

export async function installJbig2Decoder(options) {
  const decoder = await createJbig2Decoder(options);
  globalThis.__pdf_viewer_jbig2_decode = (data, globals, width, height) => {
    try { return decoder.decode(data, globals, width, height); } catch { return null; }
  };
  return decoder;
}

import {inflateBounded} from './vendor/pako/pako.mjs';

// Build-generated, trusted data only. PDF streams never enter this loader.
// Keep synchronous consumers and ordinary JS Array/String representations;
// the emitted getter owns each immutable table for the module's lifetime.
function unpack(encoded, length) {
  const binary = atob(encoded), input = new Uint8Array(binary.length);
  for (let i = 0; i < input.length; i++) input[i] = binary.charCodeAt(i);
  const bytes = inflateBounded(input, length);
  if (!bytes || bytes.length !== length) throw Error('Invalid bundled PDF data');
  return bytes;
}

export function pdfStaticIntegers(encoded, count, length, stride) {
  const bytes = unpack(encoded, length);
  const values = new Array(count);
  if (stride === 0) {
    if (length !== count * 4) throw Error('Invalid bundled PDF integer length');
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    for (let i = 0; i < count; i++) values[i] = view.getInt32(i * 4, true);
    return values;
  }
  if (![1, 2, 3, 4].includes(stride)) throw Error('Invalid bundled PDF integer stride');
  const previous = new Array(stride).fill(0);
  let position = 0;
  for (let i = 0; i < count; i++) {
    let word = 0, shift = 0, byte;
    do {
      if (position >= bytes.length || shift > 28) throw Error('Invalid bundled PDF integer');
      byte = bytes[position++];
      if (shift === 28 && byte > 15) throw Error('Invalid bundled PDF integer');
      word |= (byte & 127) << shift;
      shift += 7;
    } while (byte & 128);
    const column = i % stride;
    values[i] = previous[column] = (previous[column] + ((word >>> 1) ^ -(word & 1))) | 0;
  }
  if (position !== bytes.length) throw Error('Invalid bundled PDF integer count');
  return values;
}

export function pdfStaticString(encoded, length) {
  return new TextDecoder().decode(unpack(encoded, length));
}

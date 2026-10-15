// Local optimization of pako 2.1.0's slide_hash; the build verifies upstream
// source hashes before applying it. Preserve the compressor's positions and
// decisions exactly, including zero as its empty-chain sentinel.
export function pakoSlideHash(state) {
  const windowSize = state.w_size;
  // Pako owns aligned, even-length Uint16 tables. Apply the same saturating
  // subtraction to both native 16-bit lanes of each word, on either endian.
  for (const table of [state.head, state.prev]) {
    const words = new Uint32Array(table.buffer, table.byteOffset, table.length / 2);
    for (let i = 0; i < words.length; i++) {
      const packed = words[i];
      const low = (packed & 65535) - windowSize;
      const high = (packed >>> 16) - windowSize;
      words[i] = (low & ~(low >> 31)) | ((high & ~(high >> 31)) << 16);
    }
  }
}

export function optimizePakoDeflate(source) {
  const marker = 'const slide_hash = (s) => {';
  const start = source.indexOf(marker);
  const close = source.indexOf('\n};', start);
  if (start < 0 || close < start || source.indexOf(marker, start + 1) !== -1)
    throw Error('Pinned pako slide_hash source changed');
  const end = close + 3;
  return source.slice(0, start)
    + '/*! Locally modified pako 2.1.0 slide_hash; see vendor/pako/README.md. */\n'
    + 'const slide_hash = ' + pakoSlideHash.toString() + ';'
    + source.slice(end);
}

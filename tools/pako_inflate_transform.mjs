// Applied only after prepare_flate_assets verifies the locked pako sources.
// A distance-one match repeats the preceding byte, including overlapping runs.
// Keep pako's distance validation, window copies and stream state unchanged.
export function optimizePakoInflateFast(source) {
  const original = `              from = _out - dist;          /* copy direct from output */
              do {                        /* minimum length is three */
                output[_out++] = output[from++];
                output[_out++] = output[from++];
                output[_out++] = output[from++];
                len -= 3;
              } while (len > 2);
              if (len) {
                output[_out++] = output[from++];
                if (len > 1) {
                  output[_out++] = output[from++];
                }
              }`;
  const start = source.indexOf(original);
  if (start < 0 || source.indexOf(original, start + 1) !== -1)
    throw Error('Pinned pako inflate_fast source changed');
  return source.slice(0, start)
    + `/*! Locally modified pako 2.1.0 match expansion; see vendor/pako/README.md. */
              if (dist === 1) {
                output.fill(output[_out - 1], _out, _out + len);
                _out += len;
                len = 0;
              } else {
${original}
              }`
    + source.slice(start + original.length);
}

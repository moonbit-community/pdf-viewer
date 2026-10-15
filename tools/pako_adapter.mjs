// Bundled only from the locked pako 2.1.0 sources by prepare_web_assets.mjs.
// Use its single-stream driver: the high-level Inflate API concatenates zlib
// streams, whereas the PDF decoder stops after the first validated trailer.
import zlib from './web-assets/node_modules/pako/lib/zlib/inflate.js';
import ZStream from './web-assets/node_modules/pako/lib/zlib/zstream.js';
export {deflate} from './web-assets/node_modules/pako/dist/pako.esm.mjs';

export function inflateBounded(data, limit) {
  if (!Number.isSafeInteger(limit) || limit < 0 || limit > 67108864) return null;
  const stream = new ZStream();
  if (zlib.inflateInit2(stream, 15) !== 0) return null;
  try {
    stream.input = data;
    stream.next_in = 0;
    stream.avail_in = data.length;
    const chunks = [];
    let length = 0;
    for (;;) {
      // One excess byte detects overflow without allocating the whole bound.
      stream.output = new Uint8Array(Math.min(32768, limit - length + 1));
      stream.next_out = 0;
      stream.avail_out = stream.output.length;
      const before = stream.next_in;
      const status = zlib.inflate(stream, 0);
      length += stream.next_out;
      if (length > limit || (status !== 0 && status !== 1)) return null;
      if (stream.next_out) chunks.push(stream.output.subarray(0, stream.next_out));
      if (status === 1) {
        const output = new Uint8Array(length);
        let offset = 0;
        for (const chunk of chunks) { output.set(chunk, offset); offset += chunk.length; }
        return output;
      }
      if (before === stream.next_in && stream.next_out === 0) return null;
    }
  } finally { zlib.inflateEnd(stream); }
}

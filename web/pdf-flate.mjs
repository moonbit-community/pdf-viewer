import {deflate, inflateBounded} from './vendor/pako/pako.mjs';

// Synchronous typed-array codecs avoid the portable engine's per-byte output
// staging in JS. Invalid/oversized inputs fall back to its existing bounded
// decoder, preserving prefix recovery and error ordering for damaged PDFs.
export function installPdfFlate() {
  globalThis.__moonbit_pdf_image_inflate = (data, limit) => {
    try { return inflateBounded(data, limit); } catch { return null; }
  };
  globalThis.__moonbit_pdf_image_deflate = data => {
    try { return deflate(data, {level: 1}); } catch { return null; }
  };
}

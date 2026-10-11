// Measure the actual headless JS entry and its Canvas payload under a host
// heap cap, e.g. node --max-old-space-size=1536 this-script bridge.mjs PDF report.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {installPdfIccEngine} from '../../web/pdf-icc.mjs';
import {installJbig2Decoder} from '../../codecs/jbig2/decoder.mjs';
const [bridgePath, pdfPath, reportPath] = process.argv.slice(2);
assert(bridgePath && pdfPath && reportPath, 'Pass release pixel_plan.mjs, PDF and report.json');
const bridge = await import(pathToFileURL(resolve(bridgePath)));
const engine = await installPdfIccEngine();
await installJbig2Decoder({wasmBytes: readFileSync(new URL('../../vendor/jbig2/jbig2.wasm', import.meta.url))});
const bytes = new Uint8Array(readFileSync(pdfPath));
const hash = value => createHash('sha256').update(value).digest('hex');
try {
  const start = performance.now();
  const output = bridge.render_plan(bytes, 1, 1, 0);
  const elapsedMs = performance.now() - start;
  const parsed = JSON.parse(output);
  assert(parsed.ok, parsed.error);
  const plan = JSON.stringify(parsed.canvas);
  const text = parsed.canvas.items.filter(item => item.kind === 'text');
  const report = {
    pdf: pdfPath, sha256: hash(bytes),
    bridgeSha256: hash(readFileSync(bridgePath)), elapsedMs,
    responseCodeUnits: output.length, canvasBytes: Buffer.byteLength(plan),
    items: parsed.canvas.items.length, textItems: text.length,
    sourceSha256: hash(JSON.stringify(text.map(({paint}) => ({
      index: paint.index, text: paint.text, charcode: paint.charcode,
      quad: paint.quad, glyph_transform: paint.glyph_transform,
    })))),
    textSvgCodeUnits: text.reduce((sum, item) => sum + (item.text_svg?.length || 0), 0),
    textSvgJsonCodeUnits: text.reduce((sum, item) => sum + JSON.stringify(item.text_svg).length, 0),
    fontFaceFragments: text.filter(item => item.text_svg?.includes('@font-face')).length,
    nativePenFragmentsOmitted: text.filter(item => item.text_svg === null).length,
    icc: {...engine.statistics}, memory: process.memoryUsage(),
    maxRssKiB: process.resourceUsage().maxRSS,
  };
  writeFileSync(reportPath, JSON.stringify(report, null, 2));
  if (process.env.PDF_PROFILE_RENDER === '1') writeFileSync(`${reportPath}.canvas.json`, plan);
  console.log(JSON.stringify(report));
} finally {
  engine.dispose();
}

// Profile the actual release browser bridge without product logging changes.
// Build cmd/browser first; pass its copied .mjs path, PDF path and report path.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {installJbig2Decoder} from '../../codecs/jbig2/decoder.mjs';
const [modulePath, pdfPath, reportPath] = process.argv.slice(2);
assert(modulePath && pdfPath && reportPath, 'Pass release bridge.mjs, PDF and report.json');
const absolute = resolve(modulePath);
let source = readFileSync(absolute, 'utf8');
const bridgeSha256 = createHash('sha256').update(source).digest('hex');
const needles = [
  'pdf__page__model', 'pdf__collected__entries__of__ops', 'pdf__items__of__collected',
  'pdf__type3__outline__of__glyph', 'pdf__cff__outline__of__pdf__glyph',
  'pdf__type1__outline__of__pdf__glyph', 'pdf__truetype__outline__of__pdf__glyph',
  'pdf__read__font__for__viewer', 'pdf__svg__fonts', 'pdf__svg__text',
  'canvas__plan', 'render__svg', 'pdf__image__resource',
  'pdf__jbig2__samples', 'pdf__png__of__scanline',
];
const names = [...source.matchAll(/^function ([$\w]+)\(/gm)]
  .map(match => match[1]).filter(name => needles.some(needle => name.includes(needle)));
assert(names.some(name => name.includes('pdf__page__model')), 'Compiler names changed: update profiler');
source += '\nglobalThis.__pdfTextLoweringProfile = Object.create(null);\n';
for (const [index, name] of names.entries()) {
  const saved = `__pdf_profile_saved_${index}`;
  // Timings are inclusive. Nested stages must not be added together.
  source += `const ${saved}=${name};${name}=function(...args){const t=performance.now();try{return ${saved}.apply(this,args)}finally{const p=globalThis.__pdfTextLoweringProfile[${JSON.stringify(name)}]??={calls:0,ms:0,rss:0};p.calls++;p.ms+=performance.now()-t;p.rss=Math.max(p.rss,process.memoryUsage().rss)}};\n`;
}
const instrumented = `${absolute}.profile.mjs`;
writeFileSync(instrumented, source);
const viewer = await import(pathToFileURL(instrumented));
await installJbig2Decoder({wasmBytes: readFileSync(new URL('../../vendor/jbig2/jbig2.wasm', import.meta.url))});
const bytes = new Uint8Array(readFileSync(pdfPath));
let start = performance.now();
const opened = JSON.parse(viewer.open_pdf(bytes));
assert(opened.ok, JSON.stringify(opened));
const openMs = performance.now() - start;
start = performance.now();
const rendered = viewer.render_page(1, 1, 0);
const renderMs = performance.now() - start;
const parsed = JSON.parse(rendered);
assert(parsed.ok, JSON.stringify(parsed));
const sha256 = value => createHash('sha256').update(value).digest('hex');
const report = {
  pdf: pdfPath, sha256: sha256(bytes), bridgeSha256, openMs, renderMs,
  jsonLength: rendered.length, canvasItems: parsed.canvas.items.length,
  textLayerItems: parsed.layer.items.length,
  textLayerSha256: sha256(JSON.stringify(parsed.layer)),
  textPreview: parsed.layer.items.slice(0, 80).map(item => item.separator + item.text).join(''),
  memory: process.memoryUsage(), stages: globalThis.__pdfTextLoweringProfile,
};
writeFileSync(reportPath, JSON.stringify(report, null, 2));
if (process.env.PDF_PROFILE_RENDER === '1') writeFileSync(`${reportPath}.render.json`, rendered);
console.log(JSON.stringify(report));

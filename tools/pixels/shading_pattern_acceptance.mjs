// Complete PatternType2 PDFs: implicit nonisolated knockout Background+sh,
// internal ExtGState, and independent outer paint attributes. Formula oracles
// do not reuse the compositor; Poppler/PDF.js are additional diagnostics.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { execFileSync, spawnSync } from 'node:child_process';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
import { renderPdfCanvas } from '../../web/pdf-canvas.mjs';
import { createShadingPainter } from '../../web/pdf-shading.mjs';
import { createPatternPainter } from '../../web/pdf-patterns.mjs';
const require = createRequire(process.env.PDF_CANVAS_PACKAGE || import.meta.url);
const { createCanvas, Path2D, loadImage } = require('@napi-rs/canvas');
const pdfjs = await import(pathToFileURL(require.resolve('pdfjs-dist/legacy/build/pdf.mjs')));
const bridge = await import(pathToFileURL(resolve(process.argv[2] || '_build/pixel-plan.mjs')));
const output = resolve(process.env.PDF_PIXEL_OUTPUT || '_build/shading-pattern-acceptance'); mkdirSync(output, { recursive: true });
const options = { createCanvas, Path2D, loadImage }; options.paintShading = createShadingPainter(options); options.paintPattern = createPatternPainter(options);
const stream = (dictionary, data) => `<< ${dictionary} /Length ${data.length} >>\nstream\n${data}\nendstream`;
function fixture({ name, background, mask, stroke, noInnerState, bbox, indirect, outerScreen, affineMask }) {
  const ext = noInnerState ? '' : `/ca .5 /BM /Multiply ${mask ? '/SMask << /S /Luminosity /G 6 0 R >>' : ''}`;
  const extEntry = indirect ? '7 0 R' : `<< /Type /ExtGState ${ext} /LW 500 >>`;
  const paint = stroke ? '/Pattern CS /P SCN 10 w 10 50 m 90 50 l S' : '/Pattern cs /P scn 0 0 100 100 re f';
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources << /Pattern << /P 5 0 R >> /ExtGState << /Outer << /ca .5 /CA .5 ${outerScreen ? '/BM /Screen' : ''} >> >> >> /Contents 4 0 R >>`,
    stream('', `0.8 0.4 0.2 rg 0 0 100 100 re f /Outer gs ${paint}`),
    `<< /Type /Pattern /PatternType 2 ${affineMask ? '/Matrix [.5 0 0 .5 25 25]' : ''} /ExtGState ${extEntry} /Shading << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [${background ? '25 0 75 0' : '0 0 100 0'}] ${background ? '/Background [.1 .9 .2]' : ''} ${bbox ? '/BBox [10 20 90 80]' : ''} /Function << /FunctionType 2 /Domain [0 1] /C0 [.4 .8 .6] /C1 [.4 .8 .6] /N 1 >> >> >>`,
    ...(mask || indirect ? [mask ? stream('/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Group << /S /Transparency /I true /CS /DeviceGray >> /Resources << >>', '.25 g 0 0 50 100 re f .75 g 50 0 50 100 re f') : 'null'] : []),
    ...(indirect ? [`<< /Type /ExtGState ${ext} /LW 500 >>`] : []),
  ];
  return serialize(objects);
}
function serialize(objects) {
  let body = '%PDF-1.7\n', offsets = [0];
  for (let i = 0; i < objects.length; i++) { offsets.push(body.length); body += `${i + 1} 0 obj\n${objects[i]}\nendobj\n`; }
  const xref = body.length; body += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n` + offsets.slice(1).map(n => `${String(n).padStart(10, '0')} 00000 n \n`).join('');
  body += `trailer << /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return new TextEncoder().encode(body);
}
function expandedFixture({ background, mask, stroke, noInnerState, bbox, outerScreen, affineMask }) {
  const ext = noInnerState ? '' : `/ca .5 /BM /Multiply ${mask ? '/SMask << /S /Luminosity /G 6 0 R >>' : ''}`;
  const clip = stroke ? '10 45 80 10 re W n ' : '';
  const formPaint = `${bbox ? '10 20 80 60 re W n ' : ''}${background ? '.1 .9 .2 rg 0 0 100 100 re f ' : ''}/Inner gs /S sh`;
  return serialize([
    '<< /Type /Catalog /Pages 2 0 R >>', '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources << /XObject << /F 5 0 R >> /ExtGState << /Outer << /ca .5 /CA .5 ${outerScreen ? '/BM /Screen' : ''} >> >> >> /Contents 4 0 R >>`,
    stream('', `0.8 0.4 0.2 rg 0 0 100 100 re f /Outer gs q ${clip}/F Do Q`),
    stream(`/Type /XObject /Subtype /Form /BBox [0 0 100 100] ${affineMask ? '/Matrix [.5 0 0 .5 25 25]' : ''} /Group << /S /Transparency /I false /K true >> /Resources << /ExtGState << /Inner << ${ext} >> >> /Shading << /S 7 0 R >> >>`, formPaint),
    mask ? stream('/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Group << /S /Transparency /I true /CS /DeviceGray >> /Resources << >>', '.25 g 0 0 50 100 re f .75 g 50 0 50 100 re f') : 'null',
    `<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [${background ? '25 0 75 0' : '0 0 100 0'}] /Function << /FunctionType 2 /Domain [0 1] /C0 [.4 .8 .6] /C1 [.4 .8 .6] /N 1 >> >>`,
  ]);
}
const cases = [
  { name: 'multiply-inner-half-outer-half' },
  { name: 'indirect-pattern-extgstate', indirect: true },
  { name: 'inner-multiply-outer-screen', outerScreen: true },
  { name: 'default-inner-opacity-reset', noInnerState: true },
  { name: 'knockout-background-before-sh', background: true },
  { name: 'pattern-luminosity-mask', mask: true },
  { name: 'pattern-matrix-transforms-mask', mask: true, affineMask: true },
  { name: 'background-mask-bbox', mask: true, background: true, bbox: true },
  { name: 'pattern-stroke-inner-half', stroke: true },
];
const backdrop = [.8, .4, .2], shade = [.4, .8, .6], background = [.1, .9, .2];
const meanError = (a, b) => { let sum = 0; for (let i = 0; i < a.length; i += 4) for (let c = 0; c < 3; c++) sum += Math.abs(a[i + c] - b[i + c]); return sum / (a.length / 4 * 3); };
const referenceMetrics = (a, b) => {
  let maximum = 0, changedAbove8 = 0, x0 = 100, y0 = 100, x1 = -1, y1 = -1;
  for (let i = 0; i < a.length; i += 4) {
    let error = 0; for (let c = 0; c < 3; c++) error = Math.max(error, Math.abs(a[i + c] - b[i + c]));
    maximum = Math.max(maximum, error);
    if (error > 8) { changedAbove8++; const x = i / 4 % 100, y = Math.floor(i / 400); x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); }
  }
  return { meanAbsoluteError: meanError(a, b), maximum, changedAbove8, changedAbove8BoundsInclusive: changedAbove8 ? [x0, y0, x1, y1] : null };
};
const report = [];
for (const item of cases) {
  const bytes = fixture(item), file = `${output}/${item.name}.pdf`; writeFileSync(file, bytes);
  const parsed = JSON.parse(bridge.render_plan(bytes, 1, 1, 0)); assert.equal(parsed.ok, true, parsed.error);
  writeFileSync(`${output}/${item.name}.plan.json`, JSON.stringify(parsed.canvas));
  const canvas = createCanvas(100, 100); const rendered = await renderPdfCanvas(canvas, parsed.canvas, options);
  let maximum = 0;
  for (let y = 0; y < 100; y++) for (let x = 0; x < 100; x++) {
    const active = (!item.affineMask || x >= 25 && x < 75 && y >= 25 && y < 75) && (!item.stroke || x >= 10 && x < 90 && y >= 45 && y < 55) && (!item.bbox || x >= 10 && x < 90 && y >= 20 && y < 80);
    const isBackground = item.background && (x < 25 || x >= 75);
    const mask = item.mask ? x < 50 ? .25 : .75 : 1;
    const alpha = isBackground ? .5 : item.noInnerState ? .5 : .25 * mask;
    const source = isBackground ? background : item.noInnerState ? shade : shade.map((v, c) => v * backdrop[c]);
    for (let c = 0; c < 3; c++) {
      const color = item.outerScreen ? source[c] + backdrop[c] - source[c] * backdrop[c] : source[c];
      const expected = 255 * (active ? backdrop[c] * (1 - alpha) + color * alpha : backdrop[c]);
      maximum = Math.max(maximum, Math.abs(rendered.data[(100 * y + x) * 4 + c] - expected));
    }
    assert.equal(rendered.data[(100 * y + x) * 4 + 3], 255);
  }
  writeFileSync(`${output}/${item.name}.canvas.png`, canvas.toBuffer('image/png'));
  assert.ok(maximum <= 1.51, `${item.name} analytical error ${maximum}`);
  const task = pdfjs.getDocument({ data: new Uint8Array(bytes), useSystemFonts: false, isEvalSupported: false }); let pdfjsMean;
  try { const doc = await task.promise, page = await doc.getPage(1), ref = createCanvas(100, 100); await page.render({ canvasContext: ref.getContext('2d'), viewport: page.getViewport({ scale: 1 }) }).promise; pdfjsMean = meanError(rendered.data, ref.getContext('2d').getImageData(0, 0, 100, 100).data); writeFileSync(`${output}/${item.name}.pdfjs.png`, ref.toBuffer('image/png')); } finally { await task.destroy(); }
  const originalReferenceMetrics = {};
  for (const renderer of ['poppler', 'ghostscript']) {
    try {
      const prefix = `${output}/${item.name}.${renderer}`;
      if (renderer === 'poppler') execFileSync('pdftoppm', ['-singlefile', '-scale-to-x', '100', '-scale-to-y', '100', '-png', file, prefix], { stdio: 'pipe' });
      else execFileSync('gs', ['-q', '-dNOPAUSE', '-dBATCH', '-sDEVICE=png16m', '-r72', `-sOutputFile=${prefix}.png`, file], { stdio: 'pipe' });
      const ref = createCanvas(100, 100), ctx = ref.getContext('2d'); ctx.drawImage(await loadImage(readFileSync(`${prefix}.png`)), 0, 0);
      originalReferenceMetrics[renderer] = referenceMetrics(rendered.data, ctx.getImageData(0, 0, 100, 100).data);
    } catch (e) { originalReferenceMetrics[renderer] = { unavailable: String(e.message).split('\n')[0] }; }
  }
  // ISO 11.6.7 expands the definition to this ordinary transparency Form.
  // Mature readers can validate those operations even if their PatternType2
  // reader ignores the pattern's ExtGState dictionary itself.
  const expanded = `${output}/${item.name}.expanded.pdf`, expandedBytes = expandedFixture(item); writeFileSync(expanded, expandedBytes);
  const expandedErrors = {}, expandedMetrics = {};
  for (const renderer of ['poppler', 'ghostscript']) {
    try {
      const prefix = `${output}/${item.name}.expanded-${renderer}`;
      if (renderer === 'poppler') execFileSync('pdftoppm', ['-singlefile', '-scale-to-x', '100', '-scale-to-y', '100', '-png', expanded, prefix], { stdio: 'pipe' });
      else execFileSync('gs', ['-q', '-dNOPAUSE', '-dBATCH', '-sDEVICE=png16m', '-r72', `-sOutputFile=${prefix}.png`, expanded], { stdio: 'pipe' });
      const ref = createCanvas(100, 100), context = ref.getContext('2d'); context.drawImage(await loadImage(readFileSync(`${prefix}.png`)), 0, 0);
      expandedMetrics[renderer] = referenceMetrics(rendered.data, context.getImageData(0, 0, 100, 100).data);
      expandedErrors[renderer] = expandedMetrics[renderer].meanAbsoluteError;
    } catch (error) { expandedErrors[renderer] = String(error.message).split('\n')[0]; }
  }
  if (typeof expandedErrors.ghostscript === 'number') assert.ok(expandedErrors.ghostscript <= 1.1, `${item.name} expanded Ghostscript control diverged`);
  const result = { name: item.name, pixels: 10000, maximumAnalyticalByteError: maximum, pdfjsMeanError: pdfjsMean, originalReferenceMetrics, expandedReferenceMeanErrors: expandedErrors, expandedReferenceMetrics: expandedMetrics, expandedSha256: createHash('sha256').update(expandedBytes).digest('hex'), sha256: createHash('sha256').update(bytes).digest('hex') }; report.push(result); console.log(JSON.stringify(result));
}
const version = (command, args) => { const p = spawnSync(command, args, { encoding: 'utf8' }); return (p.stdout || p.stderr || String(p.error)).trim().split('\n')[0]; };
writeFileSync(`${output}/report.json`, JSON.stringify({
  references: { pdfjs: pdfjs.version, poppler: version('pdftoppm', ['-v']), ghostscript: version('gs', ['--version']) },
  criteria: { analyticalMaximumByteError: 1.51, expandedGhostscriptMaximumMeanByteError: 1.1,
    originalPatternReferenceDifferences: 'Recorded, not asserted equal: these readers ignore PatternType 2 ExtGState; see ISO 32000-1 11.6.7 and the expanded gs+sh controls.' },
  results: report,
}, null, 2) + '\n');

// End-to-end PDF parser -> retained samples -> Canvas pixel oracle. Generated
// fixtures are original test data (Apache-2.0); PDF.js is comparison only.
import assert from 'node:assert/strict';
import { mkdirSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { renderPdfCanvas } from '../../web/pdf-canvas.mjs';
import { createShadingPainter } from '../../web/pdf-shading.mjs';
const require = createRequire(process.env.PDF_CANVAS_PACKAGE || import.meta.url);
const { createCanvas, Path2D, loadImage } = require('@napi-rs/canvas');
const pdfjs = await import(pathToFileURL(require.resolve('pdfjs-dist/legacy/build/pdf.mjs')));
const bridge = await import(pathToFileURL(resolve(process.argv[2] || '_build/pixel-plan.mjs')));
const output = resolve(process.env.PDF_PIXEL_OUTPUT || '_build/shading-acceptance');
mkdirSync(output, { recursive: true });
const options = { createCanvas, Path2D, loadImage };
options.paintShading = createShadingPainter(options);
function pdf(objects) {
  let body = '%PDF-1.7\n', offsets = [0];
  for (let i = 0; i < objects.length; i++) { offsets.push(body.length); body += `${i + 1} 0 obj\n${objects[i]}\nendobj\n`; }
  const xref = body.length;
  body += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  body += offsets.slice(1).map(n => `${String(n).padStart(10, '0')} 00000 n \n`).join('');
  body += `trailer << /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return new TextEncoder().encode(body);
}
const stream = (dict, data) => `<< ${dict} /Length ${data.length} >>\nstream\n${data}\nendstream`;
const hex = values => values.map(n => n.toString(16).padStart(2, '0')).join('') + '>';
const function2 = '<< /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 2 >>';
function fixture(shading, { alpha = 1, extra = [], contents = '/G gs /S sh' } = {}) {
  return pdf([
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources << /Shading << /S 5 0 R >> /ExtGState << /G << /ca ' + alpha + ' >> >> >> /Contents 4 0 R >>',
    stream('', contents), shading, ...extra,
  ]);
}
function mesh(type, values, alpha = 1) {
  return fixture(stream(`/ShadingType ${type} /ColorSpace /DeviceGray /BitsPerCoordinate 8 /BitsPerComponent 8 /BitsPerFlag 8 /VerticesPerRow 2 /Decode [0 100 0 100 0 1] /Function ${function2} /Filter /ASCIIHexDecode`, hex(values)), { alpha });
}
const points = [[0, 0], [0, 85], [0, 170], [0, 255], [85, 255], [170, 255], [255, 255], [255, 170], [255, 85], [255, 0], [170, 0], [85, 0]];
const interiors = [[85, 85], [85, 170], [170, 170], [170, 85]];
const square = alpha => (x, y) => {
  const v = 255 * (1 - alpha + alpha * ((x + 0.5) / 100) ** 2);
  return [v, v, v, 255];
};
const cases = [
  { name: 'type4-nonlinear-alpha-seam', bytes: mesh(4, [0, 0, 0, 0, 0, 255, 0, 255, 0, 0, 255, 0, 0, 255, 255, 255, 0, 255, 0, 255, 0, 0, 255, 0], 0.5), expect: square(0.5) },
  { name: 'type5-nonlinear-lattice', bytes: mesh(5, [0, 0, 0, 255, 0, 255, 0, 255, 0, 255, 255, 255]), expect: square(1) },
  { name: 'type6-nonlinear-coons', bytes: mesh(6, [0, ...points.flat(), 0, 0, 255, 255]), expect: square(1) },
  { name: 'type7-nonlinear-tensor', bytes: mesh(7, [0, ...points.flat(), ...interiors.flat(), 0, 0, 255, 255]), expect: square(1) },
  { name: 'type1-two-inputs', bytes: fixture('<< /ShadingType 1 /ColorSpace /DeviceRGB /Domain [0 1 0 1] /Matrix [100 0 0 100 0 0] /Function 6 0 R >>', { extra: [stream('/FunctionType 0 /Domain [0 1 0 1] /Range [0 1 0 1 0 1] /Size [2 2] /BitsPerSample 8 /Filter /ASCIIHexDecode', '000000FF000000FF00FFFF00>')] }), expect: (x, y) => [255 * (x + 0.5) / 100, 255 * (99.5 - y) / 100, 0, 255] },
  { name: 'axial-false-extend', bytes: fixture('<< /ShadingType 2 /ColorSpace /DeviceGray /Coords [20 0 80 0] /Extend [false false] /Function << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 1 >> >>'), expect: (x, y) => {
    const v = x < 20 || x >= 80 ? 255 : 255 * (x + 0.5 - 20) / 60; return [v, v, v, 255];
  } },
  { name: 'radial-false-extend', bytes: fixture('<< /ShadingType 3 /ColorSpace /DeviceGray /Coords [50 50 0 50 50 40] /Extend [false false] /Function << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 1 >> >>'), expect: (x, y) => {
    const t = Math.hypot(x + 0.5 - 50, y + 0.5 - 50) / 40, v = t > 1 ? 255 : 255 * t; return [v, v, v, 255];
  } },
  { name: 'axial-high-exponent-zoom', bytes: fixture('<< /ShadingType 2 /ColorSpace /DeviceGray /Coords [0 0 100 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 10000 >> >>', { contents: '100 0 0 1 -9900 0 cm /G gs /S sh' }), expect: (x,y) => { const v=255*(.99+(x+.5)/10000)**10000; return [v,v,v,255]; } },
  { name: 'axial-narrow-stitch-boundary', bytes: fixture('<< /ShadingType 2 /ColorSpace /DeviceGray /Coords [0 0 100 0] /Domain [0.5 0.50003] /Function << /FunctionType 3 /Domain [0 1] /Functions [<< /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [0] /N 1 >> << /FunctionType 2 /Domain [0 1] /C0 [1] /C1 [1] /N 1 >> << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [0] /N 1 >>] /Bounds [0.50001 0.50002] /Encode [0 1 0 1 0 1] >> >>'), expect: (x,y) => { const t=.5+(x+.5)/100*.00003,v=t>=.50001&&t<.50002?255:0; return [v,v,v,255]; } },
  { name: 'type1-checker-discontinuities', bytes: fixture('<< /ShadingType 1 /ColorSpace /DeviceGray /Matrix [100 0 0 100 0 0] /Function 6 0 R >>', { extra: [stream('/FunctionType 4 /Domain [0 1 0 1] /Range [0 1]', '{ 4 mul floor exch 4 mul floor add 2 mod }')] }), expect: (x,y) => { const v=255*((Math.floor((x+.5)/25)+Math.floor((99.5-y)/25))%2); return [v,v,v,255]; } },

];
const report = [];
for (const item of cases) {
  writeFileSync(`${output}/${item.name}.pdf`, item.bytes);
  const parsed = JSON.parse(bridge.render_plan(item.bytes, 1, 1, 0));
  assert.ok(parsed.ok, parsed.error);
  const canvas = createCanvas(100, 100), rendered = await renderPdfCanvas(canvas, parsed.canvas, options);
  let maxOracleError = 0;
  for (let y = 0; y < 100; y++) for (let x = 0; x < 100; x++) {
    const expected = item.expect(x, y);
    for (let c = 0; c < 4; c++) maxOracleError = Math.max(maxOracleError, Math.abs(rendered.data[(y * 100 + x) * 4 + c] - expected[c]));
  }
  assert.ok(maxOracleError <= 1.51, `${item.name}: analytical pixel error ${maxOracleError}`);
  const task = pdfjs.getDocument({ data: item.bytes, useSystemFonts: false, isEvalSupported: false });
  let referenceMeanError = 0;
  try {
    const doc = await task.promise, page = await doc.getPage(1), ref = createCanvas(100, 100);
    await page.render({ canvasContext: ref.getContext('2d'), viewport: page.getViewport({ scale: 1 }) }).promise;
    const reference = ref.getContext('2d').getImageData(0, 0, 100, 100).data;
    for (let i = 0; i < reference.length; i += 4) for (let c = 0; c < 3; c++) referenceMeanError += Math.abs(reference[i + c] - rendered.data[i + c]);
    referenceMeanError /= 30000;
    writeFileSync(`${output}/${item.name}.reference.png`, ref.toBuffer('image/png'));
  } finally { await task.destroy(); }
  writeFileSync(`${output}/${item.name}.canvas.png`, canvas.toBuffer('image/png'));
  const result = { name: item.name, pixels: 10000, maxOracleError, referenceMeanError, pdfjs: pdfjs.version };
  report.push(result); console.log(JSON.stringify(result));
}
writeFileSync(`${output}/report.json`, JSON.stringify(report, null, 2));
console.log(`${report.length} complete PDF-to-pixel analytical cases passed`);

// Exercise the exact adapter hook used by the CMYK compositor from a parsed
// PDF, rather than reconstructing source inks from the finished RGB bitmap.
const cmykPdf = fixture(stream('/ShadingType 4 /ColorSpace /DeviceCMYK /BitsPerCoordinate 8 /BitsPerComponent 8 /BitsPerFlag 8 /Decode [0 100 0 100 0 1] /Filter /ASCIIHexDecode /Function << /FunctionType 2 /Domain [0 1] /C0 [0 .2 .4 .6] /C1 [1 .8 .3 .2] /N 2 >>', hex([0,0,0,0,0,255,0,255,0,0,255,0,0,255,255,255,0,255,0,255,0,0,255,0])), {alpha:0.5});
const cmykPlan=JSON.parse(bridge.render_plan(cmykPdf,1,1,0)).canvas;
const cmykPaint=cmykPlan.items[0].paint;
let maxPlaneError=0,maxPremultipliedPlaneError=0;
for(let component=0;component<4;component++) {
  const canvas=createCanvas(100,100),ctx=canvas.getContext('2d');
  options.paintShading(ctx,cmykPaint.shading,cmykPaint,{createCanvas,width:100,height:100,page:cmykPlan.page,matrix:[1,0,0,1,0,0],component,colourSpace:'DeviceCMYK'});
  const pixels=ctx.getImageData(0,0,100,100).data;
  for(let y=0;y<100;y++)for(let x=0;x<100;x++) {
    const t=((x+.5)/100)**2, expected=[t,.2+.6*t,.4-.1*t,.6-.4*t][component]*255,index=(y*100+x)*4;
    maxPlaneError=Math.max(maxPlaneError,Math.abs(pixels[index]-expected));
    maxPremultipliedPlaneError=Math.max(maxPremultipliedPlaneError,Math.abs(pixels[index]-expected)*pixels[index+3]/255);
    assert.equal(pixels[index+3],128,'mesh alpha must apply exactly once on every CMYK plane');
  }
}
// Canvas stores RGBA8 premultiplied internally. At alpha=.5, unpremultiplying
// amplifies one stored-byte rounding step. Validate the actual compositor
// input quantity, and retain the straight-channel error in the report.
assert.ok(maxPremultipliedPlaneError<=1,`CMYK premultiplied plane error ${maxPremultipliedPlaneError}`);
writeFileSync(`${output}/type4-cmyk-source-planes.pdf`,cmykPdf);
report.push({name:'type4-cmyk-source-planes',pixels:40000,maxPlaneError,maxPremultipliedPlaneError});
writeFileSync(`${output}/report.json`,JSON.stringify(report,null,2));
console.log(`40,000 source CMYK plane pixels passed; maximum error ${maxPlaneError}`);

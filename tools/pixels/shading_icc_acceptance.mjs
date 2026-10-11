// Complete PDF -> MoonBit source table/catalog -> actual LittleCMS target ->
// Canvas pixel oracle. This checks source components against an independent
// analytical Function, then transforms those exact inputs with the real CMM.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { installPdfIccEngine } from '../../web/pdf-icc.mjs';
import { paintShading } from '../../web/pdf-shading.mjs';
const require = createRequire(process.env.PDF_CANVAS_PACKAGE || import.meta.url);
const { createCanvas } = require('@napi-rs/canvas');
const engine = await installPdfIccEngine();
const bridge = await import(pathToFileURL(resolve(process.argv[2] || '_build/pixel-plan.mjs')));
const calibrated = process.argv.includes('--cal-gray');
const profile = readFileSync(new URL('../../assets/icc/rgb-gamma22.icc', import.meta.url));
const stream = (dictionary, bytes) => `<< ${dictionary} /Length ${bytes.length} >>\nstream\n${bytes}\nendstream`;
const objects = [
  '<< /Type /Catalog /Pages 2 0 R >>',
  '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
  '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources << /Shading << /S 5 0 R >> >> /Contents 4 0 R >>',
  stream('', '/RelativeColorimetric ri /S sh'),
  calibrated ? '<< /ShadingType 2 /ColorSpace [/CalGray << /WhitePoint [0.95047 1 1.08883] /Gamma 2 >>] /Coords [0 0 100 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [0] /C1 [1] /N 2 >> >>' : '<< /ShadingType 2 /ColorSpace [/ICCBased 6 0 R] /Coords [0 0 100 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [.1 .2 .3] /C1 [.8 .6 .4] /N 2 >> >>',
  stream('/N 3 /Alternate /DeviceRGB /Filter /ASCIIHexDecode', profile.toString('hex') + '>'),
];
let body = '%PDF-1.7\n', offsets = [0];
for (let i = 0; i < objects.length; i++) { offsets.push(body.length); body += `${i + 1} 0 obj\n${objects[i]}\nendobj\n`; }
const xref = body.length;
body += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n` + offsets.slice(1).map(n => `${String(n).padStart(10, '0')} 00000 n \n`).join('');
body += `trailer << /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
const bytes = new TextEncoder().encode(body), plan = JSON.parse(bridge.render_plan(bytes, 1, 1, 0)).canvas;
const item = plan.items[0].paint, source = item.shading.raster.source_colour;
assert.ok(item.shading.raster.error == null);
assert.ok(item.shading.raster.source_error == null);
assert.equal(source.space, calibrated ? 'PCSXYZ' : 'ICCBased');
if (!calibrated) assert.ok(plan.icc_profiles.some(p => p.id === source.icc_profile_id), 'shared page catalog must contain the actual shading source profile');
const targets = [{ id: 'target-rgb', components: 3, data_base64: profile.toString('base64') }];
const cmykPath = process.env.PDF_CMYK_PROFILE || '/usr/share/color/icc/ghostscript/default_cmyk.icc';
const cmyk = existsSync(cmykPath) ? readFileSync(cmykPath) : null;
if (cmyk) targets.push({ id: 'target-cmyk', components: 4, data_base64: cmyk.toString('base64') });
const scope = engine.createProfileScope([...plan.icc_profiles, ...targets]);
const output = resolve(process.env.PDF_PIXEL_OUTPUT || (calibrated ? '_build/shading-cal-acceptance' : '_build/shading-icc-acceptance'));
mkdirSync(output, { recursive: true }); writeFileSync(`${output}/icc-shading.pdf`, bytes);
const cases = [];
try {
  for (const target of targets) {
    let maximum = 0;
    const channels = target.components === 4 ? [0, 1, 2, 3] : [undefined];
    for (const component of channels) {
      const canvas = createCanvas(100, 100), context = canvas.getContext('2d');
      paintShading(context, item.shading, item, { createCanvas, width: 100, height: 100, page: plan.page, matrix: [1, 0, 0, 1, 0, 0], colourSpace: target.components === 4 ? 'DeviceCMYK' : 'DeviceRGB', component, iccProfileId: target.id, convertToGroup: value => scope.sourceToGroup(value, { profileId: target.id, components: target.components }) });
      const pixels = context.getImageData(0, 0, 100, 100).data;
      for (let x = 0; x < 100; x++) {
        const t = ((x + 0.5) / 100) ** 2;
        const components = calibrated ? [0.9642 * t * t, t * t, 0.8249 * t * t] : [0.1 + 0.7 * t, 0.2 + 0.4 * t, 0.3 + 0.1 * t];
        const expected = scope.sourceToGroup({ ...source, components }, { profileId: target.id, components: target.components });
        assert.ok(expected, 'target profile must genuinely support output conversion');
        for (let y = 0; y < 100; y++) {
          const offset = (100 * y + x) * 4;
          assert.equal(pixels[offset + 3], 255);
          for (let c = 0; c < 3; c++) maximum = Math.max(maximum, Math.abs(pixels[offset + c] - 255 * expected[component ?? c]));
        }
      }
      writeFileSync(`${output}/${target.id}-${component ?? 'rgb'}.png`, canvas.toBuffer('image/png'));
    }
    assert.ok(maximum < 0.6, `actual target-profile pixel error ${maximum}`);
    cases.push({ target: target.id, components: target.components, pixels: 10000 * channels.length, maximumByteError: maximum });
  }
} finally { scope.dispose(); }
const sha = data => createHash('sha256').update(data).digest('hex');
const report = { sourceSpace: calibrated ? 'CalGray Gamma2 with Function N2' : 'ICCBased RGB with Function N2', sourceProfileSha256: calibrated ? null : sha(profile), outputCmykProfileSha256: cmyk ? sha(cmyk) : null, outputCmykSkipped: cmyk ? null : 'Provide PDF_CMYK_PROFILE with a genuine CMYK output profile', pdfSha256: sha(bytes), cases };
writeFileSync(`${output}/report.json`, JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report, null, 2));

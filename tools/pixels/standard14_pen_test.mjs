// Default shipped web bridge/runtime acceptance for A1's bundled Standard14
// contours and A2's independent affine pen. No native text-outline resolver or
// host font registration is used. A native Canvas host executes the web code;
// this test does not claim to launch a browser or exercise its DOM.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync, writeFileSync, mkdirSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {execFileSync, spawnSync} from 'node:child_process';
import {renderPdfPage} from '../../web/pdf-runtime.mjs';

const require = createRequire(process.env.PDF_CANVAS_PACKAGE || import.meta.url);
const {createCanvas, Path2D, loadImage} = require('@napi-rs/canvas');
const pdfjs = await import(pathToFileURL(require.resolve('pdfjs-dist/legacy/build/pdf.mjs')));
const [bridgeName = 'web/_generated/pdf.js', fixtureDirectory = '_build/text-host-pen',
  outputDirectory = '_build/standard14-pen'] = process.argv.slice(2);
const bridge = await import(pathToFileURL(resolve(bridgeName)));
const destination = resolve(outputDirectory);
mkdirSync(destination, {recursive: true});
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const fontPath = require.resolve('pdfjs-dist/standard_fonts/LiberationSans-Regular.ttf');
execFileSync('moon', ['run', 'tools/text_host_pen.mbtx', '--', fixtureDirectory, fontPath], {stdio: 'pipe'});
const bytes = readFileSync(`${fixtureDirectory}/text-host-pen.pdf`);
const embeddedBytes = readFileSync(`${fixtureDirectory}/text-host-pen-embedded-control.pdf`);
const font = readFileSync(fontPath);
const inventory = JSON.parse(readFileSync(new URL('../../assets/standard14/inventory.json', import.meta.url)));
const helvetica = inventory.fonts.find(value => value.name === 'Helvetica');
assert.equal(bytes.length, 621, 'Use the unchanged tools/text_host_pen.mbtx fixture');
assert.equal(sha(bytes), 'faf86fff67b17f2d78afcf5353341c85b5949e560a11c5271166432e5193a538');
assert.equal(font.length, helvetica.bytes);
assert.equal(sha(font), helvetica.sha256, 'The embedded control must use the bundled A1 font bytes');
assert(embeddedBytes.toString('ascii').includes(font.toString('hex')),
  'Generate the existing A1 embedded control with these exact font bytes');

const options = {
  createCanvas, Path2D,
  // These fixtures must replay native paths. Even SVG image fallback is a
  // failure, so the result cannot depend on a silently substituted host font.
  loadImage: async () => { throw new Error('Bundled Standard14 must replay paths without SVG/host text'); },
  convertProcess: values => bridge.process_cmyk_to_rgb(...values),
};
const popplerVersion = spawnSync('pdftoppm', ['-v'], {encoding: 'utf8'});
assert.equal(popplerVersion.status, 0, 'Poppler must be available');
const report = {
  entry: 'web/_generated/pdf.js public open_pdf/render_page + web/pdf-runtime.mjs',
  bridge: resolve(bridgeName), bridgeSha256: sha(readFileSync(bridgeName)),
  fixtureBytes: bytes.length, fixtureSha256: sha(bytes),
  embeddedControlSha256: sha(embeddedBytes), fontSha256: sha(font),
  referenceRevision: inventory.reference_revision,
  nativeCanvas: require('@napi-rs/canvas/package.json').version,
  pdfjs: pdfjs.version,
  poppler: (popplerVersion.stdout + popplerVersion.stderr).trim(),
  ghostscript: execFileSync('gs', ['--version'], {encoding: 'utf8'}).trim(),
  nativeOutlineResolver: false, hostFontRegistration: false, browserDOMExecuted: false,
  acceptance: 'Strict replay, nonblank pixels and exact same-font embedded geometry/pixels; cross-renderer differences are reported without a widened tolerance',
  cases: [],
};

function checked(serialized) {
  const value = JSON.parse(serialized);
  assert.equal(value.ok, true, value.error);
  return value;
}
function renderPlan(pdf, scale, rotation, fallback) {
  checked(bridge.open_pdf(new Uint8Array(pdf)));
  try {
    if (fallback) checked(bridge.set_font_fallbacks(JSON.stringify(fallback)));
    return checked(bridge.render_page(1, scale, rotation));
  } finally { bridge.close_pdf(); }
}
function textItem(plan) {
  const items = plan.canvas.items.filter(item => item.kind === 'text');
  assert.equal(items.length, 1);
  assert.equal(items[0].paint.text, 'H');
  return items[0];
}
function modePdf(pdf, mode) {
  const source = pdf.toString('ascii');
  assert.equal(source.split(' 1 Tr ').length, 2);
  const changed = Buffer.from(source.replace(' 1 Tr ', ` ${mode} Tr `), 'ascii');
  assert.equal(changed.length, pdf.length, 'A one-byte Tr variant preserves the original xref');
  return changed;
}
function pixels(canvas) {
  return canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
}
function ink(data) {
  let count = 0;
  for (let i = 0; i < data.length; i += 4) {
    if (Math.min(data[i], data[i + 1], data[i + 2]) < 240) count++;
  }
  return count;
}
function compare(actual, expected) {
  assert.equal(actual.length, expected.length, 'Pixel dimensions must match');
  assert(ink(actual) > 0, 'The actual painted glyph must not be blank');
  assert(ink(expected) > 0, 'The reference painted glyph must not be blank');
  let absolute = 0, maximum = 0, changedAbove8 = 0;
  for (let i = 0; i < actual.length; i += 4) {
    let pixel = 0;
    for (let c = 0; c < 3; c++) {
      const difference = Math.abs(actual[i + c] - expected[i + c]);
      absolute += difference;
      pixel = Math.max(pixel, difference);
      maximum = Math.max(maximum, difference);
    }
    if (pixel > 8) changedAbove8++;
  }
  return {meanAbsoluteError: absolute / (actual.length / 4 * 3), maximum,
    changedAbove8, inkPixels: ink(actual), referenceInkPixels: ink(expected)};
}
function directPathPdf(path, pen, page, mode) {
  // Liberation Sans H contains only line contours. Use the existing embedded
  // A1 control, not the new bundled path under test, to construct this oracle.
  const tokens = path.match(/[A-Za-z]|[-+]?(?:\d*\.)?\d+(?:[eE][-+]?\d+)?/g) || [];
  const operations = [];
  for (let i = 0; i < tokens.length;) {
    const command = tokens[i++];
    if (command === 'Z') { operations.push('h'); continue; }
    assert(command === 'M' || command === 'L', 'H control expects only line contours');
    const x = Number(tokens[i++]), y = -Number(tokens[i++]);
    assert(Number.isFinite(x) && Number.isFinite(y));
    operations.push(`${x} ${y} ${command === 'M' ? 'm' : 'l'}`);
  }
  const m = pen.transform;
  const content = `q ${m[0]} ${-m[1]} ${-m[2]} ${m[3]} ${m[4] + page.origin_x} ${page.origin_y + page.height - m[5]} cm ${pen.line_width} w ${pen.line_cap} J ${pen.line_join} j ${pen.miter_limit} M ${operations.join(' ')} ${['f', 'S', 'B'][mode]} Q`;
  const objects = ['<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
    `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${page.width} ${page.height}] /Resources << >> /Contents 4 0 R >>`,
    `<< /Length ${content.length} >>\nstream\n${content}\nendstream`];
  let output = '%PDF-1.7\n';
  const offsets = [];
  objects.forEach((object, i) => { offsets.push(output.length); output += `${i + 1} 0 obj\n${object}\nendobj\n`; });
  const xref = output.length;
  output += 'xref\n0 5\n0000000000 65535 f \n' +
    offsets.map(value => `${String(value).padStart(10, '0')} 00000 n \n`).join('') +
    `trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return output;
}
async function rotatedImage(filename, width, height, rotation) {
  const image = await loadImage(filename), canvas = createCanvas(width, height);
  assert.equal(image.width, rotation % 180 ? height : width);
  assert.equal(image.height, rotation % 180 ? width : height);
  const context = canvas.getContext('2d');
  context.fillStyle = '#fff'; context.fillRect(0, 0, width, height);
  if (rotation === 90) context.translate(width, 0);
  if (rotation === 180) context.translate(width, height);
  if (rotation === 270) context.translate(0, height);
  context.rotate(rotation * Math.PI / 180); context.drawImage(image, 0, 0);
  return canvas;
}

const penControl = textItem(renderPlan(embeddedBytes, 1, 0)).paint.stroke;
assert.equal(penControl.line_width, 3);
assert.deepEqual(penControl.transform, [1.1, -0.15, -0.2, 0.85, 15, 140]);
assert.equal(penControl.fallback_scale, undefined, 'This text matrix must not become a similarity shortcut');
assert.equal(typeof penControl.svg_path, 'string');

// The unchanged stroke fixture is first; modes 0/2 exercise page fill_path and
// simultaneous fill/stroke without changing the font or affine matrices.
for (const mode of [1, 0, 2]) {
  const input = modePdf(bytes, mode), embeddedInput = modePdf(embeddedBytes, mode);
  const inputFilename = `${destination}/mode-${mode}.pdf`;
  const pathFilename = `${destination}/mode-${mode}-path-control.pdf`;
  writeFileSync(inputFilename, input);
  const pagePlan = renderPlan(embeddedInput, 1, 0).canvas;
  writeFileSync(pathFilename, directPathPdf(penControl.svg_path, penControl, pagePlan.page, mode));
  const task = pdfjs.getDocument({data: new Uint8Array(input),
    standardFontDataUrl: resolve(require.resolve('pdfjs-dist/package.json'), '../standard_fonts/') + '/',
    useSystemFonts: false, isEvalSupported: false});
  try {
    const document = await task.promise, referencePage = await document.getPage(1);
    for (const scale of [1, 2]) {
      const pathPoppler = `${destination}/mode-${mode}-path-poppler-${scale}`;
      const pathGs = `${destination}/mode-${mode}-path-ghostscript-${scale}.png`;
      const unmatchedPoppler = `${destination}/mode-${mode}-unmatched-poppler-${scale}`;
      execFileSync('pdftoppm', ['-r', String(scale * 72), '-singlefile', '-png', pathFilename, pathPoppler]);
      execFileSync('gs', ['-q', '-dSAFER', '-dBATCH', '-dNOPAUSE', '-sDEVICE=png16m',
        '-dTextAlphaBits=4', '-dGraphicsAlphaBits=4', `-r${scale * 72}`, `-sOutputFile=${pathGs}`, pathFilename]);
      execFileSync('pdftoppm', ['-r', String(scale * 72), '-singlefile', '-png', inputFilename, unmatchedPoppler]);
      for (const rotation of [0, 90, 180, 270]) {
        const actualPlan = renderPlan(input, scale, rotation);
        const controlPlan = renderPlan(embeddedInput, scale, rotation);
        const actualItem = textItem(actualPlan), controlItem = textItem(controlPlan);
        assert.deepEqual(actualPlan.canvas.diagnostics, []);
        assert.deepEqual(controlPlan.canvas.diagnostics, []);
        assert.equal(actualItem.text_svg, null, 'Default bundled glyph must not use host text/SVG rasterization');
        assert.equal(actualItem.paint.rendering_mode, mode);
        assert.deepEqual(actualItem.paint.glyph_transform, controlItem.paint.glyph_transform);
        assert.equal(actualItem.paint.advance_x, controlItem.paint.advance_x);
        assert.equal(actualItem.paint.fill_path, controlItem.paint.fill_path);
        assert.deepEqual(actualItem.paint.stroke, controlItem.paint.stroke);
        if (mode !== 1) assert.equal(typeof actualItem.paint.fill_path, 'string');
        if (mode !== 0) {
          assert.equal(typeof actualItem.paint.stroke.svg_path, 'string');
          assert.equal(actualItem.paint.stroke.unresolved, undefined);
        }
        const before = JSON.stringify(actualPlan.canvas);
        const target = createCanvas(1, 1), control = createCanvas(1, 1);
        const actual = await renderPdfPage(target, actualPlan.canvas, options);
        const expected = await renderPdfPage(control, controlPlan.canvas, options);
        assert.deepEqual(actual.diagnostics, []);
        assert.equal(JSON.stringify(actualPlan.canvas), before, 'Replay must preserve the source plan');
        const sameFont = compare(actual.data, expected.data);
        assert.equal(sameFont.maximum, 0, 'Default bundled and existing same-font embedded A1 pixels must match exactly');
        const viewport = referencePage.getViewport({scale, rotation});
        assert.equal(actual.width, Math.ceil(viewport.width));
        assert.equal(actual.height, Math.ceil(viewport.height));
        const pdfjsCanvas = createCanvas(actual.width, actual.height);
        await referencePage.render({canvasContext: pdfjsCanvas.getContext('2d'), viewport}).promise;
        const directPoppler = await rotatedImage(pathPoppler + '.png', actual.width, actual.height, rotation);
        const directGs = await rotatedImage(pathGs, actual.width, actual.height, rotation);
        const originalPoppler = await rotatedImage(unmatchedPoppler + '.png', actual.width, actual.height, rotation);
        const result = {mode, scale, rotation, width: actual.width, height: actual.height,
          diagnostics: actual.diagnostics, sameFontEmbeddedA1: sameFont,
          sameGeometryExplicitPath: {
            poppler: compare(actual.data, pixels(directPoppler)),
            ghostscript: compare(actual.data, pixels(directGs)),
          },
          unmatchedOriginalText: {
            pdfjs: compare(actual.data, pixels(pdfjsCanvas)),
            poppler: compare(actual.data, pixels(originalPoppler)),
          }};
        report.cases.push(result);
        console.log(JSON.stringify(result));
        const stem = `${destination}/mode-${mode}.scale-${scale}.rotation-${rotation}`;
        for (const [name, canvas] of [['default', target], ['embedded', control],
          ['path-poppler', directPoppler], ['path-ghostscript', directGs],
          ['unmatched-pdfjs', pdfjsCanvas], ['unmatched-poppler', originalPoppler]]) {
          writeFileSync(`${stem}.${name}.png`, canvas.toBuffer('image/png'));
        }
        if (scale === 1 && rotation === 0) writeFileSync(`${stem}.canvas.json`, before);
      }
    }
  } finally { await task.destroy(); }
}

// An intentional public override must still select the host branch. Resetting
// it must invalidate the page cache and restore bundled geometry immediately.
checked(bridge.open_pdf(new Uint8Array(bytes)));
try {
  checked(bridge.set_font_fallbacks(JSON.stringify([{pdf_name: '/F1', family: 'Liberation Sans'}])));
  const overridden = checked(bridge.render_page(1, 1, 0));
  assert.equal(overridden.layer.items[0].font_family, 'Liberation Sans');
  const host = textItem(overridden).paint;
  assert.equal(host.stroke.svg_path, undefined);
  assert.equal(host.stroke.unresolved, 'affine-text-pen-requires-glyph-outline');
  assert(overridden.canvas.diagnostics.some(value => value.code === 'PDF_TEXT_STROKE_GEOMETRY'));
  await assert.rejects(() => renderPdfPage(createCanvas(1, 1), overridden.canvas, options), /PDF_TEXT_STROKE_GEOMETRY/);
  checked(bridge.set_font_fallbacks('[]'));
  const restored = checked(bridge.render_page(1, 1, 0));
  assert.deepEqual(restored.canvas.diagnostics, []);
  assert.equal(textItem(restored).paint.stroke.svg_path, penControl.svg_path);
  const rendered = await renderPdfPage(createCanvas(1, 1), restored.canvas, options);
  assert.deepEqual(rendered.diagnostics, []);
  assert(ink(rendered.data) > 0);
  report.explicitOverride = {hostSelected: true, strictRejected: true, resetRestoresBundled: true};
} finally { bridge.close_pdf(); }
// The common check also supplies the freshly built public native parser. Its
// JSON must already contain bundled contours before the optional host adapter
// in the ordinary runner gets a chance to resolve anything.
if (process.env.PDF_NATIVE_PLAN) {
  const filename = `${destination}/native.canvas.json`;
  const png = `${destination}/native.png`;
  execFileSync(resolve(process.env.PDF_NATIVE_PLAN),
    [resolve(fixtureDirectory, 'text-host-pen.pdf'), filename, '1']);
  const plan = JSON.parse(readFileSync(filename));
  const text = plan.items.find(item => item.kind === 'text');
  assert.deepEqual(plan.diagnostics, []);
  assert.equal(typeof text.paint.stroke.svg_path, 'string');
  assert.equal(text.paint.stroke.unresolved, undefined);
  assert.equal(text.text_svg, null);
  const rendered = JSON.parse(execFileSync(process.execPath,
    ['tools/render_canvas.mjs', filename, png], {encoding: 'utf8',
      env: {...process.env, PDF_VIEWER_BRIDGE: resolve(bridgeName)}}));
  assert.deepEqual(rendered.diagnostics, []);
  const target = await rotatedImage(png, rendered.width, rendered.height, 0);
  const control = await rotatedImage(
    `${destination}/mode-1.scale-1.rotation-0.default.png`, rendered.width, rendered.height, 0);
  assert.deepEqual(pixels(target), pixels(control), 'Public native and default web RGBA must match');
  report.nativePublicEntry = {entry: 'cmd/main + tools/render_canvas.mjs',
    width: rendered.width, height: rendered.height, exactRgbaEquality: true,
    geometryResolvedBeforeHostReplay: true, diagnostics: rendered.diagnostics};
}
writeFileSync(`${destination}/report.json`, JSON.stringify(report, null, 2));
console.log(JSON.stringify({cases: report.cases.length, exactSameFont: true,
  explicitOverride: report.explicitOverride, report: `${destination}/report.json`}));

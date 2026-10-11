// Retained Type3 paint-scene pixel evidence. Fail on unreadable references, dimensions,
// or blank output; report every pixel difference without tolerance inflation.
import assert from 'node:assert/strict';
import {installPdfIccEngine} from '../../web/pdf-icc.mjs';
import {readFileSync, writeFileSync, mkdirSync} from 'node:fs';
import {resolve, basename} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';
import {execFileSync, spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const rendererUrl = process.env.PDF_CANVAS_RENDERER
  ? pathToFileURL(resolve(process.env.PDF_CANVAS_RENDERER))
  : new URL('../../web/pdf-canvas.mjs', import.meta.url);
const {renderPdfCanvas} = await import(rendererUrl);
const {createShadingPainter} = await import(new URL('./pdf-shading.mjs', rendererUrl));
const {createPatternPainter} = await import(new URL('./pdf-patterns.mjs', rendererUrl));

const require = createRequire(process.env.PDF_CANVAS_PACKAGE || import.meta.url);
const {createCanvas, Path2D, loadImage} = require('@napi-rs/canvas');
const {Resvg} = require('@resvg/resvg-js');
const pdfjs = await import(pathToFileURL(require.resolve('pdfjs-dist/legacy/build/pdf.mjs')));
const [bridgeName, filename] = process.argv.slice(2);
assert(bridgeName && filename, 'Pass the MoonBit bridge module and a PDF');
const bridge = await import(pathToFileURL(resolve(bridgeName)));
const baseline = process.env.PDF_STROKE_BASELINE_BRIDGE
  ? await import(pathToFileURL(resolve(process.env.PDF_STROKE_BASELINE_BRIDGE))) : null;
const destination = resolve(process.env.PDF_PIXEL_OUTPUT || '_build/type3-scene-validation');
mkdirSync(destination, {recursive: true});
const scales = (process.env.PDF_PIXEL_SCALES || '1,2').split(',').map(Number);
const rotations = (process.env.PDF_PIXEL_ROTATIONS || '0,90,180,270').split(',').map(Number);
const useGhostscript = process.env.PDF_STROKE_GHOSTSCRIPT !== '0';
const engine = await installPdfIccEngine();
const bytes = readFileSync(filename);
const standardFontDataUrl = resolve(require.resolve('pdfjs-dist/package.json'), '../standard_fonts/') + '/';
const task = pdfjs.getDocument({data: new Uint8Array(bytes), standardFontDataUrl, useSystemFonts: false, isEvalSupported: false});
const popplerVersion = spawnSync('pdftoppm', ['-v'], {encoding: 'utf8'});
assert.equal(popplerVersion.status, 0, 'Poppler must be available');
const report = {
  file: basename(filename), sha256: createHash('sha256').update(bytes).digest('hex'),
  pdfjs: pdfjs.version,
  poppler: (popplerVersion.stdout + popplerVersion.stderr).trim(),
  ghostscript: useGhostscript ? execFileSync('gs', ['--version'], {encoding: 'utf8'}).trim() : null,
  comparisons: [],
};
function compare(reference, actual) {
  assert.equal(actual.length, reference.length, 'Pixel dimensions must match');
  let absolute = 0, changedAbove8 = 0, maximum = 0, ink = 0;
  for (let i = 0; i < actual.length; i += 4) {
    let error = 0;
    for (let c = 0; c < 3; c++) {
      const difference = Math.abs(reference[i + c] - actual[i + c]);
      absolute += difference; error = Math.max(error, difference); maximum = Math.max(maximum, difference);
    }
    if (Math.min(actual[i], actual[i + 1], actual[i + 2]) < 240) ink++;
    if (error > 8) changedAbove8++;
  }
  assert(ink > 0, 'A painted fixture must not become a blank success');
  return {changedAbove8, meanAbsoluteError: absolute / (actual.length / 4 * 3), maximum, inkPixels: ink};
}
function compareSvg(reference, rendered) {
  if (rendered.pixels.length !== reference.length) return {
    dimensionMismatch: true, referenceBytes: reference.length,
    actualBytes: rendered.pixels.length, width: rendered.width, height: rendered.height,
  };
  return compare(reference, rendered.pixels);
}
function rasterReference(source, width, height, rotation) {
  const canvas = createCanvas(width, height), ctx = canvas.getContext('2d');
  ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, width, height);
  if (rotation === 90) ctx.translate(width, 0);
  if (rotation === 180) ctx.translate(width, height);
  if (rotation === 270) ctx.translate(0, height);
  ctx.rotate(rotation * Math.PI / 180); ctx.drawImage(source, 0, 0);
  return canvas;
}
function imageData(canvas) {
  return canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
}
try {
  const document = await task.promise;
  for (let pageNumber = 1; pageNumber <= document.numPages; pageNumber++) {
    const page = await document.getPage(pageNumber);
    for (const scale of scales) {
      const prefix = `${destination}/poppler-${pageNumber}-${scale}`;
      execFileSync('pdftoppm', ['-r', String(72 * scale), '-f', String(pageNumber), '-l', String(pageNumber), '-singlefile', '-png', filename, prefix]);
      const popplerImage = await loadImage(`${prefix}.png`);
      let ghostscriptImage = null;
      if (useGhostscript) {
        const png = `${destination}/ghostscript-${pageNumber}-${scale}.png`;
        execFileSync('gs', ['-q', '-dSAFER', '-dBATCH', '-dNOPAUSE', '-sDEVICE=png16m', '-dTextAlphaBits=4', '-dGraphicsAlphaBits=4', `-r${72 * scale}`, `-dFirstPage=${pageNumber}`, `-dLastPage=${pageNumber}`, `-sOutputFile=${png}`, filename]);
        ghostscriptImage = await loadImage(png);
      }
      for (const rotation of rotations) {
        const viewport = page.getViewport({scale, rotation: (page.rotate + rotation) % 360});
        const width = Math.ceil(viewport.width), height = Math.ceil(viewport.height);
        const reference = createCanvas(width, height);
        await page.render({canvasContext: reference.getContext('2d'), viewport}).promise;
        const poppler = rasterReference(popplerImage, width, height, rotation);
        const parsed = JSON.parse(bridge.render_plan(new Uint8Array(bytes), pageNumber, scale, rotation));
        assert(parsed.ok, parsed.error);
        const target = createCanvas(width, height);
        const options = {createCanvas, Path2D, loadImage, convertProcess: values => bridge.process_cmyk_to_rgb(...values)};
        options.paintShading = createShadingPainter(options);
        options.paintPattern = createPatternPainter(options);
        const actual = await renderPdfCanvas(target, parsed.canvas, options);
        const svg = new Resvg(parsed.svg, {background: '#fff', font: {loadSystemFonts: false}}).render();
        const popplerPixels = imageData(poppler), referencePixels = imageData(reference);
        const result = {
          page: pageNumber, scale, rotation, width, height,
          versusPoppler: {canvas: compare(popplerPixels, actual.data), svg: compareSvg(popplerPixels, svg)},
          versusPdfjs: {canvas: compare(referencePixels, actual.data), svg: compareSvg(referencePixels, svg)},
          references: compare(popplerPixels, referencePixels),
        };
        if (baseline) {
          const before = JSON.parse(baseline.render_plan(new Uint8Array(bytes), pageNumber, scale, rotation));
          assert(before.ok, before.error);
          const beforeSvg = new Resvg(before.svg, {background: '#fff', font: {loadSystemFonts: false}}).render();
          result.baselineSvgVersusPoppler = compareSvg(popplerPixels, beforeSvg);
        }
        const stem = `${destination}/page-${pageNumber}.scale-${scale}.rotation-${rotation}`;
        if (ghostscriptImage) {
          const ghostscript = rasterReference(ghostscriptImage, width, height, rotation);
          const pixels = imageData(ghostscript);
          result.versusGhostscript = {canvas: compare(pixels, actual.data), svg: compareSvg(pixels, svg), poppler: compare(pixels, popplerPixels), pdfjs: compare(pixels, referencePixels)};
          writeFileSync(`${stem}.ghostscript.png`, ghostscript.toBuffer('image/png'));
        }
        writeFileSync(`${stem}.canvas.png`, target.toBuffer('image/png'));
        writeFileSync(`${stem}.svg.png`, svg.asPng());
        writeFileSync(`${stem}.pdfjs.png`, reference.toBuffer('image/png'));
        writeFileSync(`${stem}.poppler.png`, poppler.toBuffer('image/png'));
        report.comparisons.push(result);
        console.log(JSON.stringify(result));
      }
    }
  }
} finally {
  await task.destroy();
  engine.dispose();
}
writeFileSync(`${destination}/report.json`, JSON.stringify(report, null, 2));

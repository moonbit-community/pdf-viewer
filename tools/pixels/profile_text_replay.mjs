// Actual fresh release browser bridge plus Canvas entry; no product logging.
// Optional PDF_CANVAS_RENDERER selects a worktree adapter during integration.
import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {installPdfIccEngine} from '../../web/pdf-icc.mjs';
const rendererUrl = process.env.PDF_CANVAS_RENDERER
  ? pathToFileURL(resolve(process.env.PDF_CANVAS_RENDERER))
  : new URL('../../web/pdf-canvas.mjs', import.meta.url);
const {renderPdfCanvas} = await import(rendererUrl);
const {createShadingPainter} = await import(new URL('./pdf-shading.mjs', rendererUrl));
const {createPatternPainter} = await import(new URL('./pdf-patterns.mjs', rendererUrl));
const [bridgeName, filename, output] = process.argv.slice(2);
assert(bridgeName && filename && output, 'Pass fresh browser.mjs, input.pdf, report.json');
const bridge = await import(pathToFileURL(resolve(bridgeName)));
const require = createRequire(process.env.PDF_CANVAS_PACKAGE || import.meta.url);
const {createCanvas, Path2D, loadImage} = require('@napi-rs/canvas');
const engine = await installPdfIccEngine();
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const bytes = new Uint8Array(readFileSync(filename));
const start = performance.now();
const opened = JSON.parse(bridge.open_pdf(bytes));
assert(opened.ok, opened.error);
const openMs = performance.now() - start;
const loweringStart = performance.now();
const json = bridge.render_page(1,1,0);
const bridgeMs = performance.now() - loweringStart;
const parsed = JSON.parse(json);
assert(parsed.ok, parsed.error);
const afterBridge = process.memoryUsage();
const textItems = parsed.canvas.items.filter(item => item.kind === 'text');
let svgLoads = 0;
const options = {createCanvas,Path2D,loadImage:async source => {
  if (typeof source === 'string' && source.startsWith('data:image/svg+xml')) svgLoads++;
  return loadImage(source);
},convertProcess: values => bridge.process_cmyk_to_rgb(...values)};
options.paintShading = createShadingPainter(options);
options.paintPattern = createPatternPainter(options);
const canvas = createCanvas(1,1);
const canvasStart = performance.now();
const actual = await renderPdfCanvas(canvas,parsed.canvas,options);
const canvasMs = performance.now() - canvasStart;
const report = {
  entry:'fresh cmd/browser --release --target js and Canvas adapter',
  file:filename, sha256:hash(bytes), bridgeSha256:hash(readFileSync(bridgeName)),
  openMs,bridgeMs,canvasMs,totalMs:performance.now()-start,
  canvasItems:parsed.canvas.items.length,textItems:textItems.length,
  directFillItems:textItems.filter(item => item.paint.fill_path != null).length,
  textSvgItems:textItems.filter(item => item.text_svg != null).length,
  textSvgLoads:svgLoads, peakRssKiB:process.resourceUsage().maxRSS, afterBridge,afterCanvas:process.memoryUsage(),
  selectionSha256:hash(JSON.stringify(parsed.layer)),
  svgSha256:hash(parsed.svg),
  canvasPixelSha256:hash(actual.data),diagnostics:actual.diagnostics,
};
writeFileSync(output,JSON.stringify(report,null,2));
writeFileSync(`${output}.png`,canvas.toBuffer('image/png'));
if (process.env.PDF_PROFILE_RENDER === '1') writeFileSync(`${output}.render.json`,json);
console.log(JSON.stringify(report));
options.paintPattern.dispose?.();
bridge.close_pdf();engine.dispose();

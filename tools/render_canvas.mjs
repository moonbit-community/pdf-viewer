#!/usr/bin/env node
/** Render the public native/Wasm/JS canvas_plan JSON with a native Canvas host.
 * Install @napi-rs/canvas in the project or set PDF_CANVAS_PACKAGE to the
 * package.json of an existing host installation. No PDF parsing is repeated.
 */
import {readFileSync,writeFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';
import {renderPdfCanvas} from '../web/pdf-canvas.mjs';
import {createPatternPainter} from '../web/pdf-patterns.mjs';
import {createShadingPainter} from '../web/pdf-shading.mjs';
import {installPdfIccEngine} from '../web/pdf-icc.mjs';
import {createNativeTextOutlineResolver} from '../web/pdf-native-text.mjs';
const require=createRequire(process.env.PDF_CANVAS_PACKAGE || import.meta.url);
const {createCanvas,Path2D,loadImage,convertSVGTextToPath}=require('@napi-rs/canvas');
if(process.argv.length!==4){console.error('usage: node tools/render_canvas.mjs input.canvas.json output.png');process.exit(2);}
const plan=JSON.parse(readFileSync(resolve(process.argv[2]),'utf8'));
const engine=await installPdfIccEngine();
try {
  const bridge=await import(process.env.PDF_VIEWER_BRIDGE ? pathToFileURL(resolve(process.env.PDF_VIEWER_BRIDGE)) : new URL('../web/_generated/pdf.js',import.meta.url));
  const options={createCanvas,Path2D,loadImage,convertProcess:values=>bridge.process_cmyk_to_rgb(...values)};
  if(typeof convertSVGTextToPath==='function'&&typeof Path2D.prototype.toSVGString==='function') {
    options.resolveTextOutline=createNativeTextOutlineResolver({convertSVGTextToPath,Path2D});
  }
  // Reuse the MoonBit colour transform; do not maintain a second JS formula.
  options.paintShading=createShadingPainter(options);
  options.paintPattern=createPatternPainter(options);
  try {
    const canvas=createCanvas(1,1),result=await renderPdfCanvas(canvas,plan,options);
    writeFileSync(resolve(process.argv[3]),canvas.toBuffer('image/png'));
    console.log(JSON.stringify({width:result.width,height:result.height,diagnostics:result.diagnostics}));
  } finally {options.paintPattern.dispose();}
} finally {engine.dispose();}

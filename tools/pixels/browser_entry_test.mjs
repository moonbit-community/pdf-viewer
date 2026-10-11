import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {initializePdfGraphics,renderPdfPage} from '../../web/pdf-runtime.mjs';
import * as bridge from '../../web/_generated/pdf.js';
const require=createRequire(process.env.PDF_CANVAS_PACKAGE || import.meta.url);
const {createCanvas,Path2D,loadImage}=require('@napi-rs/canvas');
const engines=await initializePdfGraphics({jbig2:{wasmBytes:readFileSync(new URL('../../web/vendor/jbig2/jbig2.wasm',import.meta.url))}});
assert.equal(engines.diagnostics.length,0);
assert.ok(engines.icc&&engines.jbig2);
const fixture=process.argv[2] || '_build/a2-validation/after/affine-strokes.pdf';
const opened=JSON.parse(bridge.open_pdf(new Uint8Array(readFileSync(fixture))));
assert.equal(opened.ok,true);
let painted=0;
for(let number=1;number<=opened.pages;number++) {
 const result=JSON.parse(bridge.render_page(number,1,0));assert.equal(result.ok,true);assert.equal(result.canvas.version,1);
 const canvas=createCanvas(1,1);
 const output=await renderPdfPage(canvas,result.canvas,{createCanvas,Path2D,loadImage,convertProcess:values=>bridge.process_cmyk_to_rgb(...values)});
 assert.equal(output.width,Math.ceil(result.layer.viewport.width));assert.equal(output.height,Math.ceil(result.layer.viewport.height));
 assert.equal(output.data.length,output.width*output.height*4);painted++;
}
bridge.close_pdf();
console.log(JSON.stringify({entry:'web/pdf-runtime.mjs + cmd/browser',fixture,pages:painted,icc:engines.icc.name,jbig2:'installed',scope:'actual shipped JS entry with native Canvas host; not a browser DOM test'}));

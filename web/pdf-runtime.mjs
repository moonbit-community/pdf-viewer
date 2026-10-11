import {createShadingPainter} from './pdf-shading.mjs';
import { installPdfIccEngine } from './pdf-icc.mjs';
import { installJbig2Decoder } from './vendor/jbig2/decoder.mjs';
import { renderPdfCanvas } from './pdf-canvas.mjs';
import { createPatternPainter } from './pdf-patterns.mjs';

let initialization;
/** Install mature synchronous image/colour primitives before parsing pages. */
export function initializePdfGraphics(options={}) {
  if (!initialization) initialization=(async()=>{
    const diagnostics=[];
    let icc=null,jbig2=null;
    try { icc=await installPdfIccEngine(options.icc); }
    catch(error) { diagnostics.push({code:'icc-engine-unavailable',message:`ICC profiles use their PDF Alternate colour space: ${error.message}`}); }
    try { jbig2=await installJbig2Decoder(options.jbig2); }
    catch(error) { diagnostics.push({code:'jbig2-engine-unavailable',message:`JBIG2 images cannot decode: ${error.message}`}); }
    return {icc,jbig2,diagnostics};
  })();
  return initialization;
}

export async function renderPdfPage(canvas,plan,options={}) {
  const configured={...options};
  configured.paintShading=options.paintShading || createShadingPainter(configured);
  configured.paintPattern=options.paintPattern || createPatternPainter(configured);
  try { return await renderPdfCanvas(canvas,plan,configured); }
  finally { if(!options.paintPattern)configured.paintPattern.dispose?.(); }
}

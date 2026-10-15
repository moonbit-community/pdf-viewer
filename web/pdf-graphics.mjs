// Parsing needs synchronous codec/colour hooks, without the display renderer.
import {installPdfIccEngine} from './pdf-icc.mjs';
import {installJbig2Decoder} from './vendor/jbig2/decoder.mjs';

let initialization;
export function initializePdfGraphics(options={}){
  if(!initialization)initialization=(async()=>{
    const diagnostics=[];
    // Resolve from this root adapter so the published Worker can bundle the
    // codec without changing its Wasm asset location under repository paths.
    // These independent engines must both settle before PDF work is accepted,
    // but their fetch/compile steps need not form a startup waterfall.
    const [colour,codec]=await Promise.allSettled([
      installPdfIccEngine(options.icc),
      installJbig2Decoder({wasmUrl:new URL('./vendor/jbig2/jbig2.wasm',import.meta.url),...options.jbig2}),
    ]);
    const icc=colour.status==='fulfilled'?colour.value:null;
    const jbig2=codec.status==='fulfilled'?codec.value:null;
    if(colour.status==='rejected')diagnostics.push({code:'icc-engine-unavailable',message:`ICC profiles use their PDF Alternate colour space: ${colour.reason.message}`});
    if(codec.status==='rejected')diagnostics.push({code:'jbig2-engine-unavailable',message:`JBIG2 images cannot decode: ${codec.reason.message}`});
    return {icc,jbig2,diagnostics};
  })();
  return initialization;
}

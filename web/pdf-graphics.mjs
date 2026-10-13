// Parsing needs synchronous codec/colour hooks, without the display renderer.
import {installPdfIccEngine} from './pdf-icc.mjs';
import {installJbig2Decoder} from './vendor/jbig2/decoder.mjs';

let initialization;
export function initializePdfGraphics(options={}){
  if(!initialization)initialization=(async()=>{
    const diagnostics=[];
    let icc=null,jbig2=null;
    try{icc=await installPdfIccEngine(options.icc);}
    catch(error){diagnostics.push({code:'icc-engine-unavailable',message:`ICC profiles use their PDF Alternate colour space: ${error.message}`});}
    try{jbig2=await installJbig2Decoder(options.jbig2);}
    catch(error){diagnostics.push({code:'jbig2-engine-unavailable',message:`JBIG2 images cannot decode: ${error.message}`});}
    return {icc,jbig2,diagnostics};
  })();
  return initialization;
}

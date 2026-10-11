// Browser APIs and existing PDF rendering engines exposed to the MoonBit UI.
import {pdf,open_pdf,open_pdf_url,open_pdf_with_password} from './pdf-client.js';
import {PageScheduler} from './page-scheduler.js';
import {AnnotationLayer} from './annotation-layer.js';
import {makeAccessibilityLayer} from './accessibility-layer.js';
import {makeXfaLayer,clearXfaFonts} from './pdf-xfa-layer.mjs';
import {installPdfIccEngine} from './pdf-icc.mjs';
import {renderPdfPage} from './pdf-runtime.mjs';

let initialization,measure;
export const viewerHost={
  pdf,makeAccessibilityLayer,makeXfaLayer,clearXfaFonts,
  initializeGraphics(){
    return initialization ||= installPdfIccEngine().then(()=>[],error=>[{
      code:'icc-engine-unavailable',
      message:`ICC profiles use their PDF Alternate colour space: ${error.message}`,
    }]);
  },
  openDocument(file,data,password){
    const encoded=password===null?null:new TextEncoder().encode(password);
    return file.url?open_pdf_url(file.url,encoded):encoded===null?open_pdf(data):open_pdf_with_password(data,encoded);
  },
  paintCanvas(canvas,result,outputScale,isCurrent,convertProcess){
    return renderPdfPage(canvas,result.canvas,{
      unsupported:'warn',returnPixels:false,outputScale,isCurrent,
      yieldToHost:()=>new Promise(resolve=>setTimeout(resolve,0)),
      convertProcess:values=>convertProcess(...values),
    });
  },
  createAnnotations(viewer,navigate,sourceURL){return new AnnotationLayer({viewer,navigate,sourceURL});},
  createScheduler(options){return new PageScheduler(options);},
  measure(text,family,weight,style){
    measure ||= document.createElement('canvas').getContext('2d');
    measure.font=`${style} ${weight} 100px ${family}`;
    return Math.max(0.001,measure.measureText(text).width/100);
  },
};
globalThis.pdfViewerHost=viewerHost;

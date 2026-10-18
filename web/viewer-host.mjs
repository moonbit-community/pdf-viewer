import {PdfRenderTask,yieldPdfTask} from './pdf-render-task.mjs';
// Browser APIs and existing PDF rendering engines exposed to the MoonBit UI.
import {pdf,open_pdf,open_pdf_url,open_pdf_with_password} from './pdf-client.js';
import {PageScheduler} from './page-scheduler.js';
import {AnnotationLayer} from './annotation-layer.js';
import {makeAccessibilityLayer} from './accessibility-layer.js';
import {makeXfaLayer,clearXfaFonts} from './pdf-xfa-layer.mjs';
import {installPdfIccEngine} from './pdf-icc.mjs';
import {renderPdfPage} from './pdf-runtime.mjs';
import {PdfRenderAssets} from './pdf-render-assets.mjs';
import {createPatternTileCache} from './pdf-patterns.mjs';
import {expandPdfCanvasProgram} from './pdf-canvas-program.mjs';
import {loadPdfRaster} from './pdf-canvas.mjs';

let initialization,measure;
let renderTask=new PdfRenderTask(yieldPdfTask);
const loadRaster=async uri=>{
  if(!uri.startsWith('pdf-raster:'))return loadPdfRaster(uri);
  const value=await pdf.loadRaster(uri);
  return typeof value==='string'?loadPdfRaster(value):value;
};
let renderAssets=new PdfRenderAssets({loadImage:loadRaster});
let patternTiles=createPatternTileCache();
let loadRenderImage=renderAssets.acquire.bind(renderAssets);
function clearRenderAssets(){renderTask=new PdfRenderTask(yieldPdfTask);renderAssets.dispose();patternTiles.dispose();renderAssets=new PdfRenderAssets({loadImage:loadRaster});patternTiles=createPatternTileCache();loadRenderImage=renderAssets.acquire.bind(renderAssets);}
// Keep the established module singleton: consumer bridge functions and the
// reader must address the same document and Worker.
Object.assign(pdf,{rasterImages:true,onRaster:(uri,bitmap)=>renderAssets.supply(uri,bitmap),
  onRasterReset:clearRenderAssets,rasterKeys:()=>renderAssets.rasterKeys()});
export const viewerHost={
  pdf,makeAccessibilityLayer,makeXfaLayer,clearXfaFonts,
  preparePage(number,scale,rotation,options){
    return pdf.callPage([number,scale,rotation,true,true,true],options);
  },
  clearRenderAssets,
  renderAssetsDiagnostics(){return {...renderAssets.diagnostics(),patterns:patternTiles.diagnostics()};},
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
    const assets=renderAssets,tiles=patternTiles,loadImage=loadRenderImage;
    // RPC snapshots belong to this viewer. Expand each wire program once and
    // release its resource table before repeated viewport paints.
    if((result.canvas?.version===2||result.canvas?.version===3)&&isCurrent?.()!==false)result.canvas=expandPdfCanvasProgram(result.canvas);
    return renderPdfPage(canvas,result.canvas,{
      unsupported:'warn',returnPixels:false,outputScale,isCurrent,
      yieldToHost:yieldPdfTask,_renderTask:renderTask,
      convertProcess:values=>convertProcess(...values),
      loadImage,releaseImage:image=>assets.release(image),
      patternTileCache:tiles,
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

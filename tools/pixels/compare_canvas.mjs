import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,basename,dirname} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {renderPdfCanvas} from '../../web/pdf-canvas.mjs';
import {createShadingPainter} from '../../web/pdf-shading.mjs';
import {createPatternPainter} from '../../web/pdf-patterns.mjs';
import {installPdfIccEngine} from '../../web/pdf-icc.mjs';
import {installJbig2Decoder} from '../../codecs/jbig2/decoder.mjs';
const require=createRequire(process.env.PDF_CANVAS_PACKAGE || import.meta.url);
const {createCanvas,Path2D,loadImage}=require('@napi-rs/canvas');
const pdfjs=await import(pathToFileURL(require.resolve('pdfjs-dist/legacy/build/pdf.mjs')));
const {Resvg}=require('@resvg/resvg-js');
// Explicit Canvas-only measurement when a compatibility SVG renderer is unavailable
// or cannot finish; the report retains the skipped renderer rather than a pass.
const measureSvg=process.env.PDF_PIXEL_SVG!=='0';
const bridge=await import(pathToFileURL(resolve(process.argv[2] || '_build/pixel-plan.mjs')));
const destination=resolve(process.env.PDF_PIXEL_OUTPUT || '_build/pixel-results');mkdirSync(destination,{recursive:true});
const filenames=process.argv.slice(3);if(!filenames.length)throw Error('Pass fixture paths after the MoonBit bridge module');
await installPdfIccEngine();
await installJbig2Decoder({wasmBytes:readFileSync(new URL('../../vendor/jbig2/jbig2.wasm',import.meta.url))});
const report=[];
for(const filename of filenames){
 const bytes=readFileSync(filename),name=basename(filename,'.pdf');
 const task=pdfjs.getDocument({data:new Uint8Array(bytes),useSystemFonts:false,isEvalSupported:false,wasmUrl:dirname(require.resolve('pdfjs-dist/package.json'))+'/wasm/',standardFontDataUrl:dirname(require.resolve('pdfjs-dist/package.json'))+'/standard_fonts/'});
 try {
 const document=await task.promise;
 for(let pageNo=1;pageNo<=document.numPages;pageNo++){
  const page=await document.getPage(pageNo),vp=page.getViewport({scale:1}),w=Math.ceil(vp.width),h=Math.ceil(vp.height);
  const reference=createCanvas(w,h);await page.render({canvasContext:reference.getContext('2d'),viewport:vp}).promise;
  const target=createCanvas(w,h),start=performance.now(),rss=process.memoryUsage().rss;
  const parsed=JSON.parse(bridge.render_plan(new Uint8Array(bytes),pageNo,1,0));
  if(!parsed.ok)throw Error(parsed.error);
  writeFileSync(`${destination}/${name}-${pageNo}.plan.json`,JSON.stringify(parsed.canvas));
  const options={createCanvas,Path2D,loadImage,convertProcess:values=>bridge.process_cmyk_to_rgb(...values)}; options.paintShading=createShadingPainter(options); options.paintPattern=createPatternPainter(options);
  const actual=await renderPdfCanvas(target,parsed.canvas,options);
  const elapsed=performance.now()-start,ref=reference.getContext('2d').getImageData(0,0,w,h).data;
  const compare=rgba=>{if(rgba.length!==ref.length)return {dimensionMismatch:true,referenceBytes:ref.length,actualBytes:rgba.length};let changed=0,absolute=0,maximum=0;for(let i=0;i<ref.length;i+=4){let error=0;for(let c=0;c<3;c++){const d=Math.abs(ref[i+c]-rgba[i+c]);error=Math.max(error,d);absolute+=d;maximum=Math.max(maximum,d);}if(error>8)changed++;}return {changedAbove8:changed,meanAbsoluteError:absolute/(w*h*3),maximum};};
  const svg=measureSvg?new Resvg(parsed.svg,{background:'#fff',font:{loadSystemFonts:false}}).render():null;
  writeFileSync(`${destination}/${name}-${pageNo}.reference.png`,reference.toBuffer('image/png'));writeFileSync(`${destination}/${name}-${pageNo}.canvas.png`,target.toBuffer('image/png'));
  const result={file:basename(filename),page:pageNo,width:w,height:h,pdfjs:pdfjs.version,sha256:createHash('sha256').update(bytes).digest('hex'),canvas:compare(actual.data),svg:svg?{width:svg.width,height:svg.height,...compare(svg.pixels)}:{skipped:true,reason:'Explicit PDF_PIXEL_SVG=0 Canvas-only measurement'},milliseconds:elapsed,rssDelta:process.memoryUsage().rss-rss};
  report.push(result);console.log(JSON.stringify(result));
 }
 }catch(error){const result={file:basename(filename),error:String(error.stack||error)};report.push(result);console.log(JSON.stringify(result));}
 finally{await task.destroy();}
}
writeFileSync(`${destination}/report.json`,JSON.stringify({fixtureRevision:'89b500f5e1d98ed89bb90211e45b28730b2d99ac',cases:report},null,2));

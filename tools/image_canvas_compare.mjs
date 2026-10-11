#!/usr/bin/env node
// Reproduce the image manifest on the public Canvas replay path. No packages
// are installed, PDFs uploaded or input fixtures changed by this tool.
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
const require=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url);
const {createCanvas,Path2D,loadImage}=require('@napi-rs/canvas');
const pdfjs=await import(pathToFileURL(require.resolve('pdfjs-dist/legacy/build/pdf.mjs')));
const web=process.env.PDF_CANVAS_WEB?pathToFileURL(resolve(process.env.PDF_CANVAS_WEB)+'/'):new URL('../web/',import.meta.url);
const {renderPdfCanvas}=await import(new URL('pdf-canvas.mjs',web));
const {createPatternPainter}=await import(new URL('pdf-patterns.mjs',web));
const {createShadingPainter}=await import(new URL('pdf-shading.mjs',web));
if(process.argv.length!==5)throw Error('usage: node tools/image_canvas_compare.mjs bridge.mjs fixture-directory output-directory');
const bridge=await import(pathToFileURL(resolve(process.argv[2]))),fixtures=resolve(process.argv[3]),out=resolve(process.argv[4]);mkdirSync(out,{recursive:true});
const manifest=JSON.parse(readFileSync(new URL('image_cases.json',import.meta.url)));
const report={referenceRevision:manifest.reference_revision,pdfjsVersion:pdfjs.version,scale:manifest.scale,results:[]};
for(const entry of manifest.cases){
 const bytes=readFileSync(resolve(fixtures,entry.file));
 const task=pdfjs.getDocument({data:new Uint8Array(bytes),useSystemFonts:false,isEvalSupported:false,wasmUrl:dirname(require.resolve('pdfjs-dist/package.json'))+'/wasm/',standardFontDataUrl:dirname(require.resolve('pdfjs-dist/package.json'))+'/standard_fonts/'});
 try{
  const doc=await task.promise;
  for(const number of entry.pages)for(const rotation of entry.rotations){
   const result={file:entry.file,sha256:createHash('sha256').update(bytes).digest('hex'),page:number,rotation},start=performance.now();
   try{
    const plan=JSON.parse(bridge.render_plan(new Uint8Array(bytes),number,manifest.scale,rotation));if(!plan.ok)throw Error(plan.error);
    const options={createCanvas,Path2D,loadImage,convertProcess:v=>bridge.process_cmyk_to_rgb(...v)};options.paintPattern=createPatternPainter(options);options.paintShading=createShadingPainter(options);
    const canvas=createCanvas(1,1),painted=await renderPdfCanvas(canvas,plan.canvas,options);
    const page=await doc.getPage(number),viewport=page.getViewport({scale:manifest.scale,rotation:(page.rotate+rotation)%360}),ref=createCanvas(Math.ceil(viewport.width),Math.ceil(viewport.height));
    await page.render({canvasContext:ref.getContext('2d'),viewport}).promise;
    writeFileSync(resolve(out,entry.file+'.'+rotation+'.actual.png'),canvas.toBuffer('image/png'));writeFileSync(resolve(out,entry.file+'.'+rotation+'.reference.png'),ref.toBuffer('image/png'));
    result.width=canvas.width;result.height=canvas.height;result.diagnostics=painted.diagnostics;
    if(canvas.width!==ref.width||canvas.height!==ref.height)throw Error('Canvas/reference dimensions differ');
    const a=canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data,b=ref.getContext('2d').getImageData(0,0,ref.width,ref.height).data;let sum=0,above8=0,maximum=0;
    for(let i=0;i<a.length;i+=4){let error=0;for(let k=0;k<3;k++){const d=Math.abs(a[i+k]-b[i+k]);sum+=d;error=Math.max(error,d);}if(error>8)above8++;maximum=Math.max(maximum,error);}
    result.comparison={above8,maximum,meanAbsoluteError:sum/(canvas.width*canvas.height*3)};
   }catch(error){result.error=String(error.stack||error);}
   result.milliseconds=performance.now()-start;report.results.push(result);console.log(JSON.stringify(result));writeFileSync(resolve(out,'report.json'),JSON.stringify(report,null,2));
  }
 }finally{await task.destroy();}
}

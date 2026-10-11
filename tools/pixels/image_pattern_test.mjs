#!/usr/bin/env node
// Full PDF bridge -> shipped Canvas runtime regression for stencil Pattern paint.
// Host packages are supplied by the caller; this tool installs nothing.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
if(process.argv.length!==5)throw Error('usage: node tools/pixels/image_pattern_test.mjs browser-bridge.mjs image-pattern.pdf output-directory');
const require=createRequire(process.env.PDF_CANVAS_PACKAGE || import.meta.url);
const {createCanvas,Path2D,loadImage}=require('@napi-rs/canvas');
const pdfjs=await import(pathToFileURL(require.resolve('pdfjs-dist/legacy/build/pdf.mjs')));
const web=process.env.PDF_CANVAS_WEB?pathToFileURL(resolve(process.env.PDF_CANVAS_WEB)+'/'):new URL('../../web/',import.meta.url);
const {initializePdfGraphics,renderPdfPage}=await import(new URL('pdf-runtime.mjs',web));
const engines=await initializePdfGraphics({jbig2:{wasmBytes:readFileSync(new URL('vendor/jbig2/jbig2.wasm',web))}});
assert.deepEqual(engines.diagnostics,[]);
const bridge=await import(pathToFileURL(resolve(process.argv[2]))),fixture=resolve(process.argv[3]),out=resolve(process.argv[4]);
mkdirSync(out,{recursive:true});
const bytes=readFileSync(fixture),cases=JSON.parse(readFileSync(fixture.replace(/\.pdf$/,'.cases.json')));
const opened=JSON.parse(bridge.open_pdf(new Uint8Array(bytes)));assert.equal(opened.ok,true);assert.equal(opened.pages,cases.length);
const task=pdfjs.getDocument({data:new Uint8Array(bytes),useSystemFonts:false,isEvalSupported:false,wasmUrl:dirname(require.resolve('pdfjs-dist/package.json'))+'/wasm/',standardFontDataUrl:dirname(require.resolve('pdfjs-dist/package.json'))+'/standard_fonts/'});
const report={scope:'cmd/browser --release + web/pdf-runtime.mjs with native Canvas API host, not a browser DOM test',fixtureSha256:createHash('sha256').update(bytes).digest('hex'),pdfjsVersion:pdfjs.version,scale:1,results:[]};
const actual=[],references=[];
try{
 const reference=await task.promise;
 for(let number=1;number<=opened.pages;number++){
  const parsed=JSON.parse(bridge.render_page(number,1,0));assert.equal(parsed.ok,true);
  const canvas=createCanvas(1,1),rendered=await renderPdfPage(canvas,parsed.canvas,{createCanvas,Path2D,loadImage,convertProcess:values=>bridge.process_cmyk_to_rgb(...values)});
  const page=await reference.getPage(number),viewport=page.getViewport({scale:1}),ref=createCanvas(Math.ceil(viewport.width),Math.ceil(viewport.height));
  await page.render({canvasContext:ref.getContext('2d'),viewport}).promise;
  const a=canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data,b=ref.getContext('2d').getImageData(0,0,ref.width,ref.height).data;assert.equal(a.length,b.length);
  let maximum=0,sum=0,above8=0;
  for(let i=0;i<a.length;i+=4){let error=0;for(let k=0;k<4;k++){const d=Math.abs(a[i+k]-b[i+k]);maximum=Math.max(maximum,d);error=Math.max(error,d);sum+=d;}if(error>8)above8++;}
  const rowPixels=(data)=>[2,7,12,17].map(x=>Array.from(data.slice((10*canvas.width+x)*4,(10*canvas.width+x)*4+4)));
  const operatorList=await page.getOperatorList();
  const result={page:number,pdfjsSolidMaskOperation:operatorList.fnArray.includes(pdfjs.OPS.paintSolidColorImageMask),name:cases[number-1],width:canvas.width,height:canvas.height,diagnostics:rendered.diagnostics,comparison:{maximum,above8,meanAbsoluteError:sum/a.length},actualPixels:rowPixels(a),referencePixels:rowPixels(b)};
  report.results.push(result);actual.push(new Uint8Array(a));references.push(new Uint8Array(b));console.log(JSON.stringify(result));
  writeFileSync(resolve(out,cases[number-1]+'.actual.png'),canvas.toBuffer('image/png'));writeFileSync(resolve(out,cases[number-1]+'.reference.png'),ref.toBuffer('image/png'));
  writeFileSync(resolve(out,cases[number-1]+'.plan.json'),JSON.stringify(parsed.canvas));
 }
}finally{bridge.close_pdf();await task.destroy();writeFileSync(resolve(out,'report.json'),JSON.stringify(report,null,2)+'\n');}
for(const result of report.results){
 const control=cases.indexOf(result.name+'-two-pixel-control');
 if(control>=0){
  const a=actual[result.page-1],b=references[control];let maximum=0,sum=0,above8=0;
  for(let i=0;i<a.length;i+=4){let error=0;for(let k=0;k<4;k++){const d=Math.abs(a[i+k]-b[i+k]);maximum=Math.max(maximum,d);error=Math.max(error,d);sum+=d;}if(error>8)above8++;}
  result.equivalentTwoPixelControl={page:control+1,maximum,above8,meanAbsoluteError:sum/a.length};
  assert.deepEqual(a,actual[control],result.name+' opaque sample count independence');
 }
}
writeFileSync(resolve(out,'report.json'),JSON.stringify(report,null,2)+'\n');
for(const result of report.results){
 assert.deepEqual(result.diagnostics,[],result.name);
 const comparison=result.equivalentTwoPixelControl||result.comparison;
 if(result.name.startsWith('uncoloured-green')){
  // The existing pattern painter evaluates transparent cell edges directly in
  // device space. PDF.js filters its repeating alpha tile. Keep this measured
  // policy difference separate from stencil/path paint or mask correctness.
  assert.ok(comparison.maximum<=26,result.name);
  const reference=references[result.equivalentTwoPixelControl?result.equivalentTwoPixelControl.page-1:result.page-1],a=actual[result.page-1];
  const edges=new Set([0,4,5,9,10,14,15,19]);let interiorAbove8=0;
  for(let i=0;i<a.length;i+=4)if(!edges.has((i/4)%20)&&[0,1,2,3].some(k=>Math.abs(a[i+k]-reference[i+k])>8))interiorAbove8++;
  result.transparentCellEdgeResidual={interiorAbove8,edgeColumns:[...edges]};assert.equal(interiorAbove8,0,result.name);
  assert.deepEqual(a,actual[cases.indexOf('uncoloured-green-path')],result.name+' matches ordinary path');
 }else assert.equal(comparison.above8,0,result.name);
}
writeFileSync(resolve(out,'report.json'),JSON.stringify(report,null,2)+'\n');
assert.deepEqual(actual[cases.indexOf('selected-after-cm-stencil')],actual[cases.indexOf('selected-after-cm-path')]);
assert.deepEqual(report.results[0].actualPixels,[[255,0,0,255],[0,0,255,255],[255,0,0,255],[0,0,255,255]]);

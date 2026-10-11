#!/usr/bin/env node
// Local PDFs stay on the machine. Compare the packaged viewer and pinned
// PDF.js at identical Canvas dimensions; keep parsing and painting separate.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {resolve,extname,sep} from 'node:path';

const filename=process.argv[2];
assert(filename,'Usage: node tools/render_benchmark.mjs <PDF> [pages, e.g. 1,2,12]');
const requested=(process.argv[3]||'1').split(',').map(Number);
assert(requested.every(n=>Number.isInteger(n)&&n>0),'Page numbers must be positive integers');
const engine=process.env.PDF_BROWSER||'webkit';
assert(['webkit','chromium'].includes(engine),'PDF_BROWSER must be webkit or chromium');
const require=createRequire(resolve('tools/test-host/package.json'));
const launcher=require('playwright')[engine];
const roots={viewer:resolve('_build/pages'),reference:resolve('reference/pdf.js/build/generic')};
const mime={'.mjs':'text/javascript','.js':'text/javascript','.html':'text/html','.css':'text/css','.wasm':'application/wasm','.svg':'image/svg+xml'};
const output=resolve('_build/render-benchmark-'+Date.now());
await mkdir(output,{recursive:true});
const data=await readFile(resolve(filename));
const server=createServer(async(req,res)=>{
 const path=new URL(req.url,'http://localhost').pathname,reference=path.startsWith('/pdfjs/');
 const root=reference?roots.reference:roots.viewer,target=resolve(root,reference?path.slice(7):path.slice(1)||'index.html');
 if(!target.startsWith(root+sep)){res.writeHead(404).end();return;}
 try{const bytes=await readFile(target);res.writeHead(200,{'Content-Type':mime[extname(target)]||'application/octet-stream'}).end(bytes);}
 catch{res.writeHead(404).end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
let browser;
try{
 browser=await launcher.launch({headless:true});
 const page=await browser.newPage({viewport:{width:1280,height:900},deviceScaleFactor:2});
 const errors=[];page.on('pageerror',error=>errors.push(String(error)));page.setDefaultTimeout(60000);
 await page.goto('http://127.0.0.1:'+server.address().port,{waitUntil:'networkidle'});
 await page.locator('#open-empty').waitFor({state:'visible'});
 await page.evaluate(()=>{
  const state=window.pdfBenchmark={saved:new Map(),paints:[],worker:[],active:0,paint:pdfViewerHost.paintCanvas};
  const call=pdfViewerHost.pdf.call;
  pdfViewerHost.pdf.call=function(method,args,...rest){
   const t=performance.now(),promise=call.call(this,method,args,...rest);
   promise.then(result=>state.worker.push({method,page:method.startsWith('render_')?args[0]:null,ms:performance.now()-t,chars:typeof result==='string'?result.length:0}),()=>{});
   return promise;
  };
  pdfViewerHost.paintCanvas=async function(...args){
   state.saved.set(args[1].page,args);state.active++;const t=performance.now();
   try{return await state.paint(...args);}
   finally{state.paints.push({page:args[1].page,ms:performance.now()-t});state.active--;}
  };
 });
 const opened=Date.now();
 await page.locator('#file-input').setInputFiles({name:'benchmark.pdf',mimeType:'application/pdf',buffer:data});
 await page.waitForFunction(()=>document.querySelector('.page[data-page="1"]')?.dataset.rendered==='true'&&document.querySelector('#viewer').getAttribute('aria-busy')==='false');
 const report={engine,dpr:2,firstReaderMs:Date.now()-opened,pages:[],errors};
 for(const number of requested){
  if(number!==1){await page.locator('#page-number').fill(String(number));await page.locator('#page-number').press('Enter');}
  await page.waitForFunction(n=>document.querySelector('.page[data-page="'+n+'"]')?.dataset.rendered==='true',number);
 }
 // Finish nearby UI paints and parsing before measuring either renderer.
 await page.waitForFunction(()=>{const worker=pdfViewerHost.pdf.diagnostics();return !window.pdfBenchmark.active&&!worker.active&&!worker.queued;});
 await page.evaluate(()=>pdfViewerHost.pdf.close());
 report.worker=await page.evaluate(()=>window.pdfBenchmark.worker);
 report.pdfjs=await page.evaluate(async bytes=>{
  const state=window.pdfBenchmark,t=performance.now(),pdfjs=await import('/pdfjs/build/pdf.mjs');
  pdfjs.GlobalWorkerOptions.workerSrc='/pdfjs/build/pdf.worker.mjs';const imported=performance.now();
  state.referenceTask=pdfjs.getDocument({data:new Uint8Array(bytes),useSystemFonts:false,isEvalSupported:false,
   cMapUrl:'/pdfjs/web/cmaps/',cMapPacked:true,standardFontDataUrl:'/pdfjs/web/standard_fonts/',wasmUrl:'/pdfjs/web/wasm/'});
  state.reference=await state.referenceTask.promise;
  return {version:pdfjs.version,importMs:imported-t,openMs:performance.now()-imported};
 },[...data]);
 for(const number of requested){
  const result=await page.evaluate(async({number,compareRetained})=>{
   const state=window.pdfBenchmark,args=state.saved.get(number),canvas=document.createElement('canvas');
   const measure=async draw=>{
    const t=performance.now();await draw();const painted=performance.now();
    const pixels=canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data;
    const flushed=performance.now();
    return {paintMs:painted-t,flushMs:flushed-painted,totalMs:flushed-t,pixels};
   };
   const warm=[];let actual;
   for(let i=0;i<3;i++){const {pixels,...timing}=await measure(()=>state.paint(canvas,args[1],args[2],()=>true,args[4]));warm.push(timing);actual=pixels;}
   const dimensions=[canvas.width,canvas.height],pdfPage=await state.reference.getPage(number);
   const viewport=pdfPage.getViewport({scale:args[1].layer.viewport.width/pdfPage.getViewport({scale:1}).width});
   const reference=document.createElement('canvas');reference.width=dimensions[0];reference.height=dimensions[1];
   const times=[];let expected;
   for(let i=0;i<3;i++){
    const t=performance.now();await pdfPage.render({canvasContext:reference.getContext('2d'),viewport,transform:[args[2],0,0,args[2],0,0]}).promise;
    const painted=performance.now();expected=reference.getContext('2d').getImageData(0,0,...dimensions).data;const flushed=performance.now();
    times.push({paintMs:painted-t,flushMs:flushed-painted,totalMs:flushed-t});
   }
   const compare=(reference,actual)=>{
    let absolute=0,above8=0,ink=0;
    for(let i=0;i<actual.length;i+=4){let delta=0;for(let c=0;c<3;c++){const d=Math.abs(reference[i+c]-actual[i+c]);absolute+=d;delta=Math.max(delta,d);}if(delta>8)above8++;if(Math.min(actual[i],actual[i+1],actual[i+2])<240)ink++;}
    return {meanAbsoluteError:absolute/(actual.length/4*3),pixelsAbove8:above8,ink};
   };
   const comparison=compare(expected,actual),result={page:number,dimensions,
    ours:{readerPaintMs:state.paints.find(p=>p.page===number)?.ms,replay:warm},pdfjs:{first:times[0],replay:times.slice(1)},versusPdfjs:comparison};
   if(compareRetained){
    const {renderPdfPage}=await import('/pdf-runtime.mjs');
    await renderPdfPage(canvas,args[1].canvas,{unsupported:'warn',returnPixels:false,nativeCanvas:false,outputScale:args[2],convertProcess:values=>args[4](...values)});
    const retained=canvas.getContext('2d').getImageData(0,0,...dimensions).data;
    result.versusRetained=compare(retained,actual);result.retainedVersusPdfjs=compare(expected,retained);
   }
   canvas.width=canvas.height=reference.width=reference.height=1;return result;
  },{number,compareRetained:process.env.PDF_BENCH_COMPARE_RETAINED==='1'});
  assert(result.versusPdfjs.ink>0,'The reader must paint visible content');report.pages.push(result);console.log(JSON.stringify(result));
 }
 await page.evaluate(()=>window.pdfBenchmark.referenceTask.destroy());
 assert.deepEqual(errors,[]);await writeFile(resolve(output,'report.json'),JSON.stringify(report,null,2));
 console.log('REPORT '+output);
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}

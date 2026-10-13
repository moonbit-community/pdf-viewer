#!/usr/bin/env node
// Local PDFs stay on the machine. Compare the packaged viewer and pinned
// PDF.js at identical Canvas dimensions; keep parsing and painting separate.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {resolve,extname,sep} from 'node:path';
import {createHash} from 'node:crypto';
import {execFile,execFileSync} from 'node:child_process';
import {instrumentCanvasModule,installBrowserRenderProfile,summarizeRenderPlan} from './pixels/browser_render_profile.mjs';

const filename=process.argv[2];
assert(filename,'Usage: node tools/render_benchmark.mjs <PDF> [pages, e.g. 1,2,12]');
const requested=(process.argv[3]||'1').split(',').map(Number);
assert(requested.every(n=>Number.isInteger(n)&&n>0),'Page numbers must be positive integers');
const engine=process.env.PDF_BROWSER||'webkit';
assert(['webkit','chromium'].includes(engine),'PDF_BROWSER must be webkit or chromium');
const require=createRequire(resolve('tools/test-host/package.json'));
const launcher=require('playwright')[engine];
const roots={viewer:resolve(process.env.PDF_BENCH_VIEWER_ROOT||'_build/pages'),reference:resolve('reference/pdf.js/build/generic')};
const pins=JSON.parse(await readFile(resolve('tools/ci/toolchain.json')));
const referenceRevision=execFileSync('git',['-C',resolve('reference/pdf.js'),'rev-parse','HEAD'],{encoding:'utf8'}).trim();
assert.equal(referenceRevision,pins.pdfjs_reference,'Benchmark requires the pinned PDF.js checkout');
assert.equal(execFileSync('git',['-C',resolve('reference/pdf.js'),'diff','--name-only','HEAD','src','external','gulpfile.mjs','package.json','package-lock.json'],{encoding:'utf8'}).trim(),'',
 'Benchmark requires unmodified PDF.js reference sources');
const referenceBuild=JSON.parse(await readFile(resolve('reference/pdf.js/build/version.json')));
assert(referenceBuild.commit.length>=7&&referenceRevision.startsWith(referenceBuild.commit),'Rebuild PDF.js at its pinned revision');
const mime={'.mjs':'text/javascript','.js':'text/javascript','.html':'text/html','.css':'text/css','.wasm':'application/wasm','.svg':'image/svg+xml'};
const output=resolve('_build/render-benchmark-'+Date.now());
const profileRequested=process.env.PDF_BENCH_PROFILE==='1';
const diagnosticOnly=process.env.PDF_BENCH_DIAGNOSTIC_ONLY==='1';
const profileEnabled=profileRequested&&diagnosticOnly;
await mkdir(output,{recursive:true});
const data=await readFile(resolve(filename));
const server=createServer(async(req,res)=>{
 const path=new URL(req.url,'http://localhost').pathname,reference=path.startsWith('/pdfjs/');
 const root=reference?roots.reference:roots.viewer,target=resolve(root,reference?path.slice(7):path.slice(1)||'index.html');
 if(!target.startsWith(root+sep)){res.writeHead(404).end();return;}
 try{
  let bytes=await readFile(target);
  if(profileEnabled&&!reference&&path==='/pdf-canvas.mjs')bytes=instrumentCanvasModule(bytes.toString());
  // Older readable artifacts predate the opt-in Worker startup diagnostic.
  // New bundled entries report through the protocol instead of source edits.
  if(profileEnabled&&!reference&&path==='/pdf-worker.js'&&bytes.toString().includes('async function start() {')&&!bytes.toString().includes('profileStartup'))bytes=bytes.toString()
   .replace('async function start() {','const benchmarkModuleReady=performance.now();\nasync function start() {')
   .replace('const graphics = await initializePdfGraphics();','const initializeStart=performance.now();\n  const graphics = await initializePdfGraphics();')
   .replace('self.postMessage({ type: "ready", graphics: {','self.postMessage({ type: "ready", benchmark: {moduleReadyMs:benchmarkModuleReady,graphicsMs:performance.now()-initializeStart,resources:performance.getEntriesByType("resource").map(r=>({name:new URL(r.name).pathname,duration:r.duration,bytes:r.transferSize}))}, graphics: {');
  res.writeHead(200,{'Content-Type':mime[extname(target)]||'application/octet-stream'}).end(bytes);
 }
 catch{res.writeHead(404).end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
let browser;
try{
 browser=await launcher.launch({headless:true});
 const page=await browser.newPage({viewport:{width:1280,height:900},deviceScaleFactor:2});
 const errors=[];page.on('pageerror',error=>errors.push(String(error)));page.setDefaultTimeout(60000);
 await page.addInitScript(({profileEnabled})=>{
  window.pdfBenchmarkWorkerStartup=[];
  window.pdfBenchmarkWorkerMessages=[];
  const original=window.Worker;
  window.Worker=new Proxy(original,{construct(Target,args){
   if(profileEnabled){
    const url=new URL(args[0],document.baseURI);url.searchParams.set('profile','startup');args=[url,...args.slice(1)];
   }
   const start=performance.now(),worker=new Target(...args),posted=new Map(),post=worker.postMessage;
   worker.postMessage=function(message,...rest){
    if(message?.id!=null)posted.set(message.id,{method:message.method,page:message.method?.startsWith('render_')?message.args[0]:null,start:performance.now()});
    return post.call(this,message,...rest);
   };
   worker.addEventListener('message',event=>{
    if(event.data?.type==='ready')window.pdfBenchmarkWorkerStartup.push({url:String(args[0]),ms:performance.now()-start,graphics:event.data.graphics,benchmark:event.data.benchmark});
    const request=posted.get(event.data?.id);
    if(request){posted.delete(event.data.id);window.pdfBenchmarkWorkerMessages.push({id:event.data.id,method:request.method,page:request.page,
     ms:performance.now()-request.start,chars:typeof event.data.result==='string'?event.data.result.length:0});}
   });
   return worker;
  }});
 },{profileEnabled});
 await page.goto('http://127.0.0.1:'+server.address().port,{waitUntil:'networkidle'});
 await page.locator('#open-empty').waitFor({state:'visible'});
 if(profileEnabled)await page.evaluate(installBrowserRenderProfile);
 await page.evaluate(()=>{
  const state=window.pdfBenchmark={saved:new Map(),renderArgs:new Map(),paints:[],worker:[],active:0,paint:pdfViewerHost.paintCanvas};
  const call=pdfViewerHost.pdf.call;
  pdfViewerHost.pdf.call=function(method,args,...rest){
   if(method==='render_page')state.renderArgs.set(args[0],[...args]);
   const t=performance.now(),promise=call.call(this,method,args,...rest),id=this.nextId;
   promise.then(result=>state.worker.push({id,method,page:method.startsWith('render_')?args[0]:null,ms:performance.now()-t,chars:typeof result==='string'?result.length:0}),()=>{});
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
 const report={engine,dpr:2,sourceSha256:createHash('sha256').update(data).digest('hex'),sourceBytes:data.length,
  viewerRoot:roots.viewer,referenceRevision,profileEnabled,scope:diagnosticOnly?'diagnostic-only':'ordinary samples without Canvas profiler hooks',
  firstReaderMs:Date.now()-opened,pages:[],navigation:[],errors};
 for(const number of requested){
  if(number!==1){await page.locator('#page-number').fill(String(number));await page.locator('#page-number').press('Enter');}
  await page.waitForFunction(n=>document.querySelector('.page[data-page="'+n+'"]')?.dataset.rendered==='true',number);
 }
 // Finish nearby UI paints and parsing before measuring either renderer.
 await page.waitForFunction(()=>{const worker=pdfViewerHost.pdf.diagnostics();return !window.pdfBenchmark.active&&!worker.active&&!worker.queued;});
 for(const number of requested){
  const before=await page.evaluate(n=>{const s=pdfBenchmark;s.navigationCanvas=s.saved.get(n)?.[0];return {paints:s.paints.length,requests:s.worker.filter(r=>r.method==='render_page').length};},number);
  const start=Date.now();await page.locator('#page-number').fill(String(number));await page.locator('#page-number').press('Enter');
  await page.waitForFunction(n=>document.querySelector('.page[data-page="'+n+'"]')?.dataset.rendered==='true',number);
  report.navigation.push(await page.evaluate(({number,before,ms})=>{
   const s=pdfBenchmark;
   return {page:number,ms,reusedCanvas:s.navigationCanvas===document.querySelector('.page[data-page="'+number+'"] canvas'),
    paints:s.paints.length-before.paints,requests:s.worker.filter(r=>r.method==='render_page').length-before.requests};
  },{number,before,ms:Date.now()-start}));
 }
 await page.waitForFunction(()=>{const worker=pdfViewerHost.pdf.diagnostics();return !window.pdfBenchmark.active&&!worker.active&&!worker.queued;});
 report.cache=await page.evaluate(async()=> (await (await import('./viewer.js')).runtimeDiagnostics()).display_cache);
 report.workerReplay=await page.evaluate(async pages=>{
  const state=pdfBenchmark,rows=[];
  for(const number of pages){
   const base=[...state.renderArgs.get(number)],replay=[];
   for(const scale of [1.125,1.25,1.375]){
    const args=[...base];args[1]*=scale;
    const start=performance.now(),result=await pdfViewerHost.pdf.call('render_page',args),received=performance.now();
    const parsed=JSON.parse(result),finished=performance.now();
    if(!parsed.ok)throw Error(parsed.error);
    if(JSON.stringify(parsed.accessibility)!==JSON.stringify(state.saved.get(number)[1].accessibility))throw Error('Zoom must retain original semantic data');
    replay.push({ms:received-start,jsonParseMs:finished-received,chars:result.length});
   }
   rows.push({page:number,replay,medianMs:replay.map(r=>r.ms).sort((a,b)=>a-b)[1]});
  }
  return {pages:rows,cache:JSON.parse(await pdfViewerHost.pdf.call('cache_info',[]))};
 },requested);
 await page.evaluate(()=>pdfViewerHost.pdf.close());
 report.worker=await page.evaluate(()=>window.pdfBenchmark.worker);
 report.workerStartup=await page.evaluate(()=>window.pdfBenchmarkWorkerStartup);
 if(profileEnabled)assert(report.workerStartup.length&&report.workerStartup.every(startup=>startup.benchmark),'Worker startup diagnostics are missing');
 report.build={};
 for(const file of ['_generated/pdf.js','_generated/viewer.js','pdf-worker.js','pdf-client.js','viewer-host.mjs','pdf-graphics.mjs',
  'pdf-runtime.mjs','pdf-canvas.mjs','pdf-canvas-native.mjs','pdf-patterns.mjs','pdf-render-assets.mjs','pdf-shading.mjs','pdf-xfa.mjs','pdf-xfa-layer.mjs','vendor/xfa/xfa.mjs']){
  const bytes=await readFile(resolve(roots.viewer,file)).catch(error=>{if(file==='pdf-graphics.mjs'&&error.code==='ENOENT')return null;throw error;});
  report.build[file]=bytes?{bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex')}:null;
 }
 report.workerTransport=await page.evaluate(()=>window.pdfBenchmarkWorkerMessages);
 for(const request of report.worker){const posted=report.workerTransport.find(r=>r.id===request.id);if(posted){request.transportMs=posted.ms;request.queueMs=Math.max(0,request.ms-posted.ms);}}
 report.pdfjs=await page.evaluate(async bytes=>{
  const state=window.pdfBenchmark,t=performance.now(),pdfjs=await import('/pdfjs/build/pdf.mjs');
  pdfjs.GlobalWorkerOptions.workerSrc='/pdfjs/build/pdf.worker.mjs';const imported=performance.now();
  state.referenceTask=pdfjs.getDocument({data:new Uint8Array(bytes),useSystemFonts:false,isEvalSupported:false,
   cMapUrl:'/pdfjs/web/cmaps/',cMapPacked:true,standardFontDataUrl:'/pdfjs/web/standard_fonts/',wasmUrl:'/pdfjs/web/wasm/'});
  state.reference=await state.referenceTask.promise;
  return {version:pdfjs.version,build:pdfjs.build,importMs:imported-t,openMs:performance.now()-imported};
 },[...data]);
 assert.equal(report.pdfjs.build,referenceBuild.commit,'Loaded PDF.js must match the checked build');
 for(const number of requested){
  const result=await page.evaluate(async({number,compareRetained,profileEnabled,summarizeSource})=>{
   const state=window.pdfBenchmark,args=state.saved.get(number),canvas=document.createElement('canvas');
   const measure=async draw=>{
    const t=performance.now();await draw();const painted=performance.now();
    const pixels=canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data;
    const flushed=performance.now();
    return {paintMs:painted-t,flushMs:flushed-painted,totalMs:flushed-t,pixels};
   };
   const assetsBefore=pdfViewerHost.renderAssetsDiagnostics(),warm=[];let actual;
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
   const hash=async bytes=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),byte=>byte.toString(16).padStart(2,'0')).join('');
   const cloneStart=performance.now(),cloned={...args[1],canvas:structuredClone(args[1].canvas)},cloneMs=performance.now()-cloneStart;
   const {pixels:clonePixels,...cloneReplay}=await measure(()=>state.paint(canvas,cloned,args[2],()=>true,args[4]));
   const rgbaSha256=await hash(actual),cloneSha256=await hash(clonePixels);
   if(cloneSha256!==rgbaSha256)throw Error('Freshly parsed immutable cell objects must retain identical pixels');
   const comparison=compare(expected,actual),result={page:number,dimensions,
    ours:{readerPaintMs:state.paints.find(p=>p.page===number)?.ms,replay:warm,rgbaSha256,cloneReplay:{...cloneReplay,cloneMs,rgbaSha256:cloneSha256},assetsBefore,assetsAfter:pdfViewerHost.renderAssetsDiagnostics()},pdfjs:{first:times[0],replay:times.slice(1),rgbaSha256:await hash(expected)},versusPdfjs:comparison};
   if(profileEnabled){
    const {renderPdfPage}=await import('/pdf-runtime.mjs'),{prepareNativeCanvasItems}=await import('/pdf-canvas-native.mjs');
    const summarize=(0,eval)('('+summarizeSource+')');
    result.plan=summarize(args[1].canvas,prepareNativeCanvasItems,{returnPixels:false,outputScale:args[2]});
    const profile=pdfRenderProfile;profile.begin();
    await state.paint(canvas,args[1],args[2],()=>true,args[4]);
    result.profile=profile.finish();
    result.profile.assets=pdfViewerHost.renderAssetsDiagnostics();
    profile.begin();
    await renderPdfPage(canvas,args[1].canvas,{unsupported:'warn',returnPixels:false,outputScale:args[2],
      convertProcess:values=>args[4](...values)});
    result.profileWithoutDocumentAssets=profile.finish();
    profile.begin();
    await pdfPage.render({canvasContext:reference.getContext('2d'),viewport,transform:[args[2],0,0,args[2],0,0]}).promise;
    result.pdfjs.profile=profile.finish();
   }
   if(compareRetained){
    const {renderPdfPage}=await import('/pdf-runtime.mjs');
    await renderPdfPage(canvas,args[1].canvas,{unsupported:'warn',returnPixels:false,nativeCanvas:false,outputScale:args[2],convertProcess:values=>args[4](...values)});
    const retained=canvas.getContext('2d').getImageData(0,0,...dimensions).data;
    result.versusRetained=compare(retained,actual);result.retainedVersusPdfjs=compare(expected,retained);
   }
   canvas.width=canvas.height=reference.width=reference.height=1;return result;
  },{number,compareRetained:process.env.PDF_BENCH_COMPARE_RETAINED==='1',profileEnabled,summarizeSource:summarizeRenderPlan.toString()});
  assert(result.versusPdfjs.ink>0,'The reader must paint visible content');report.pages.push(result);console.log(JSON.stringify(result));
 }
 if(profileEnabled)report.pdfjs.preparation=await page.evaluate(async({bytes,pages})=>{
  const pdfjs=await import('/pdfjs/build/pdf.mjs'),data=new Uint8Array(bytes),start=performance.now();
  const task=pdfjs.getDocument({data,useSystemFonts:false,isEvalSupported:false,cMapUrl:'/pdfjs/web/cmaps/',cMapPacked:true,
   standardFontDataUrl:'/pdfjs/web/standard_fonts/',wasmUrl:'/pdfjs/web/wasm/'});
  try{
   const document=await task.promise,opened=performance.now(),rows=[];
   for(const number of pages){
    const start=performance.now(),page=await document.getPage(number),ready=performance.now();
    const operations=await page.getOperatorList(),prepared=performance.now();
    await page.getOperatorList();const cached=performance.now();
    rows.push({page:number,getPageMs:ready-start,operatorListMs:prepared-ready,totalMs:prepared-start,
     cachedMs:cached-prepared,operations:operations.fnArray.length});
   }
   return {openMs:opened-start,pages:rows};
  }finally{await task.destroy();}
 },{bytes:[...data],pages:requested});
 await page.evaluate(()=>window.pdfBenchmark.referenceTask.destroy());
 assert.deepEqual(errors,[]);await writeFile(resolve(output,'report.json'),JSON.stringify(report,null,2));
 if(!profileRequested||diagnosticOnly)console.log('REPORT '+output);
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}

// A separate process/browser prevents even inactive profiler wrappers from
// changing ordinary paint samples. Only diagnostic fields cross this boundary.
if(profileRequested&&!diagnosticOnly){
 const stdout=await new Promise((resolveChild,rejectChild)=>execFile(process.execPath,[resolve(process.argv[1]),filename,requested.join(',')],{
  env:{...process.env,PDF_BENCH_DIAGNOSTIC_ONLY:'1'},maxBuffer:16777216,
 },(error,stdout,stderr)=>error?rejectChild(Object.assign(error,{message:stderr||error.message})):resolveChild(stdout)));
 const path=stdout.match(/REPORT ([^\r\n]+)/)?.[1];assert(path,'Diagnostic child must finish with a report');
 const ordinary=JSON.parse(await readFile(resolve(output,'report.json'))),diagnostic=JSON.parse(await readFile(resolve(path,'report.json')));
 assert.equal(diagnostic.sourceSha256,ordinary.sourceSha256,'Diagnostic input changed');
 assert.deepEqual(diagnostic.build,ordinary.build,'Diagnostic viewer assets changed');
 assert.equal(diagnostic.referenceRevision,ordinary.referenceRevision,'Diagnostic reference changed');
 assert.equal(diagnostic.engine,ordinary.engine,'Diagnostic browser changed');
 assert.equal(diagnostic.dpr,ordinary.dpr,'Diagnostic output scale changed');
 for(const page of ordinary.pages){
  const probe=diagnostic.pages.find(p=>p.page===page.page);assert(probe,'Diagnostic page is missing');
  assert.deepEqual(probe.dimensions,page.dimensions,'Diagnostic page dimensions changed');
  for(const field of ['plan','profile','profileWithoutDocumentAssets'])page[field]=probe[field];
  page.pdfjs.profile=probe.pdfjs.profile;
 }
 ordinary.pdfjs.preparation=diagnostic.pdfjs.preparation;
 ordinary.diagnostic={report:path,scope:diagnostic.scope,workerStartup:diagnostic.workerStartup};
 ordinary.profileEnabled=true;
 await writeFile(resolve(output,'report.json'),JSON.stringify(ordinary,null,2));
 console.log('REPORT '+output);
}

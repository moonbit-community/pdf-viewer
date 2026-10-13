#!/usr/bin/env node
// Measure a first PDF page through the packaged reader's ordinary file input.
// Each sample owns a fresh browser context and Worker. Private PDFs stay local.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve,extname,sep} from 'node:path';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';

const filename=process.argv[2];
assert(filename,'Usage: node tools/first_load_benchmark.mjs <PDF> [report.json]');
const engine=process.env.PDF_BROWSER||'webkit',samples=Number(process.env.PDF_BENCH_SAMPLES||5);
assert(['webkit','chromium'].includes(engine),'PDF_BROWSER must be webkit or chromium');
assert(Number.isInteger(samples)&&samples>=3&&samples<=15,'PDF_BENCH_SAMPLES must be an integer from 3 to 15');
const require=createRequire(resolve('tools/test-host/package.json'));
const launcher=require('playwright')[engine];
const viewerRoot=resolve(process.env.PDF_BENCH_VIEWER_ROOT||'_build/pages');
const baselineRoot=process.env.PDF_BENCH_BASELINE_ROOT?resolve(process.env.PDF_BENCH_BASELINE_ROOT):null;
const referenceRoot=resolve('reference/pdf.js/build/generic');
const pins=JSON.parse(await readFile('tools/ci/toolchain.json'));
const revision=execFileSync('git',['-C','reference/pdf.js','rev-parse','HEAD'],{encoding:'utf8'}).trim();
assert.equal(revision,pins.pdfjs_reference,'Benchmark requires the pinned PDF.js checkout');
assert.equal(execFileSync('git',['-C','reference/pdf.js','diff','--name-only','HEAD','src','external','gulpfile.mjs','package.json','package-lock.json'],{encoding:'utf8'}).trim(),'','PDF.js sources must be unmodified');
const referenceBuild=JSON.parse(await readFile('reference/pdf.js/build/version.json'));
assert(referenceBuild.commit.length>=7&&revision.startsWith(referenceBuild.commit),'Rebuild PDF.js at its pinned revision');
const bytes=await readFile(resolve(filename)),sha256=data=>createHash('sha256').update(data).digest('hex');
const output=resolve(process.argv[3]||`_build/first-load-${Date.now()}/report.json`);
await mkdir(resolve(output,'..'),{recursive:true});
const mime={'.html':'text/html','.js':'text/javascript','.mjs':'text/javascript','.css':'text/css','.wasm':'application/wasm'};
const server=createServer(async(req,res)=>{
  const path=new URL(req.url,'http://localhost').pathname;
  if(path==='/fixture.pdf'){res.writeHead(200,{'Content-Type':'application/pdf','Cache-Control':'no-store'}).end(bytes);return;}
  if(path==='/reference.html'){res.writeHead(200,{'Content-Type':'text/html'}).end('<!doctype html><html><body><canvas></canvas></body></html>');return;}
  const reference=path.startsWith('/pdfjs/'),baseline=baselineRoot&&path.startsWith('/baseline/');
  const root=reference?referenceRoot:baseline?baselineRoot:viewerRoot;
  const target=resolve(root,reference?path.slice(7):baseline?path.slice(10)||'index.html':path.slice(1)||'index.html');
  if(!target.startsWith(root+sep)){res.writeHead(404).end();return;}
  try{res.writeHead(200,{'Content-Type':mime[extname(target)]||'application/octet-stream','Cache-Control':'no-store'}).end(await readFile(target));}
  catch{res.writeHead(404).end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const origin=`http://127.0.0.1:${server.address().port}`;
let browser;
try{
  browser=await launcher.launch({headless:true});
  const report={engine,browserVersion:browser.version(),playwrightVersion:require('playwright/package.json').version,timestamp:new Date().toISOString(),samples,dpr:2,sourceSha256:sha256(bytes),sourceBytes:bytes.length,viewerRoot,referenceRevision:revision,
    scope:'Reader shell and PDF.js module loaded before timing; each sample starts at reading a File with a fresh document/Worker. Canvas-visible includes a pixel flush and two animation frames. Reader-ready additionally includes mounted text/annotations/fonts, before document metadata necessarily completes; PDF.js uses its Canvas API without viewer UI.',
    baselineRoot,ours:[],baseline:[],pdfjs:[]};
  for(const [name,root] of [['build',viewerRoot],['baselineBuild',baselineRoot]]){
    if(!root)continue;report[name]={};
    for(const file of ['pdf-worker.js','_generated/viewer.js','viewer-host.mjs','pdf-client.js']){
      const source=await readFile(resolve(root,file));report[name][file]={bytes:source.length,sha256:sha256(source)};
    }
  }
  for(let index=0;index<samples;index++){
    const variants=baselineRoot?(index%2?['ours','baseline']:['baseline','ours']):['ours'];
    for(const variant of variants){
      const context=await browser.newContext({viewport:{width:1280,height:900},deviceScaleFactor:2});
      const page=await context.newPage(),errors=[];page.on('pageerror',error=>errors.push(String(error)));page.setDefaultTimeout(60000);
      await page.addInitScript(()=>{
        const state=window.firstLoad={requests:[],workers:[],start:0};
        const Original=window.Worker;
        window.Worker=new Proxy(Original,{construct(Target,args){
          const worker=new Target(...args),created=performance.now(),post=worker.postMessage,pending=new Map();
          worker.postMessage=function(message,...rest){
            if(message?.id!=null)pending.set(message.id,{method:message.method,page:message.method?.startsWith('render_')?message.args[0]:null,start:performance.now()});
            return post.call(this,message,...rest);
          };
          worker.addEventListener('message',event=>{
            if(event.data?.type==='ready')state.workers.push({created,ready:performance.now(),ms:performance.now()-created});
            const request=pending.get(event.data?.id);
            if(request){pending.delete(event.data.id);state.requests.push({...request,end:performance.now(),ms:performance.now()-request.start,chars:typeof event.data.result==='string'?event.data.result.length:0});}
          });
          return worker;
        }});
        document.addEventListener('change',event=>{if(event.target.id==='file-input')state.start=performance.now();},true);
      });
      await page.goto(origin+(variant==='baseline'?'/baseline/':''),{waitUntil:'networkidle'});await page.locator('#open-empty').waitFor({state:'visible'});
      await page.evaluate(async()=>{
        const state=firstLoad,paint=pdfViewerHost.paintCanvas;
        pdfViewerHost.paintCanvas=async function(...args){
          const start=performance.now(),result=await paint.apply(this,args),paintEnd=performance.now();
          if(args[1].page===1&&!state.canvas){
            state.canvas=args[0];state.paintMs=paintEnd-start;
            state.canvas.getContext('2d').getImageData(0,0,1,1);state.flushMs=performance.now()-paintEnd;
            requestAnimationFrame(()=>requestAnimationFrame(()=>{state.visible=performance.now();}));
          }
          return result;
        };
        const observer=new MutationObserver(()=>{
          if(!state.start||state.ready)return;
          if(document.querySelector('.page[data-page="1"]')?.dataset.rendered==='true'&&document.querySelector('#viewer').getAttribute('aria-busy')==='false'){
            state.ready=performance.now();observer.disconnect();
          }
        });
        observer.observe(document.getElementById('viewer'),{subtree:true,childList:true,attributes:true,attributeFilter:['data-rendered','aria-busy']});
        state.file=new File([await (await fetch('/fixture.pdf')).arrayBuffer()],'benchmark.pdf',{type:'application/pdf'});
      });
      await page.evaluate(()=>{
        const input=document.getElementById('file-input'),transfer=new DataTransfer();transfer.items.add(firstLoad.file);input.files=transfer.files;
        input.dispatchEvent(new Event('change',{bubbles:true}));
      });
      await page.waitForFunction(()=>firstLoad.visible&&firstLoad.ready);
      const ours=await page.evaluate(async()=>{
        const s=firstLoad,c=s.canvas,rgba=c.getContext('2d').getImageData(0,0,c.width,c.height).data;
        const hash=[...new Uint8Array(await crypto.subtle.digest('SHA-256',rgba))].map(x=>x.toString(16).padStart(2,'0')).join('');
        const requests=s.requests.filter(r=>r.end<=s.ready).map(r=>({...r,start:r.start-s.start,end:r.end-s.start}));
        const result={canvasVisibleMs:s.visible-s.start,readerReadyMs:s.ready-s.start,paintMs:s.paintMs,flushMs:s.flushMs,
          width:c.width,height:c.height,rgbaSha256:hash,workers:s.workers.map(w=>({...w,created:w.created-s.start,ready:w.ready-s.start})),requests};
        pdfViewerHost.pdf.close();return result;
      });
      assert.deepEqual(errors,[],'Reader must have no browser exceptions');report[variant].push(ours);await context.close();
    }
    const ours=report.ours.at(-1);
    const referenceContext=await browser.newContext({viewport:{width:1280,height:900},deviceScaleFactor:2}),referencePage=await referenceContext.newPage();
    const referenceErrors=[];referencePage.on('pageerror',error=>referenceErrors.push(String(error)));
    await referencePage.goto(origin+'/reference.html');
    await referencePage.evaluate(async()=>{
      window.pdfjs=await import('/pdfjs/build/pdf.mjs');pdfjs.GlobalWorkerOptions.workerSrc='/pdfjs/build/pdf.worker.mjs';
      window.firstFile=new File([await (await fetch('/fixture.pdf')).arrayBuffer()],'benchmark.pdf',{type:'application/pdf'});
    });
    const reference=await referencePage.evaluate(async({width,height})=>{
      const start=performance.now(),data=new Uint8Array(await firstFile.arrayBuffer()),readEnd=performance.now();
      const task=pdfjs.getDocument({data,useSystemFonts:false,isEvalSupported:false,cMapUrl:'/pdfjs/web/cmaps/',cMapPacked:true,standardFontDataUrl:'/pdfjs/web/standard_fonts/',wasmUrl:'/pdfjs/web/wasm/'});
      const document=await task.promise,openEnd=performance.now(),page=await document.getPage(1),pageEnd=performance.now();
      const viewport=page.getViewport({scale:width/(2*page.getViewport({scale:1}).width)}),canvas=window.document.querySelector('canvas'),ctx=canvas.getContext('2d');
      if(Math.ceil(viewport.height*2)!==height)throw Error('Reference and reader Canvas dimensions must match');
      canvas.width=width;canvas.height=height;const paintStart=performance.now();
      await page.render({canvasContext:ctx,viewport,transform:[2,0,0,2,0,0],background:'rgb(255,255,255)'}).promise;
      const paintEnd=performance.now();ctx.getImageData(0,0,1,1);const flushEnd=performance.now();
      await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));const visible=performance.now();
      const rgba=ctx.getImageData(0,0,width,height).data,hash=[...new Uint8Array(await crypto.subtle.digest('SHA-256',rgba))].map(x=>x.toString(16).padStart(2,'0')).join('');
      await task.destroy();return {canvasVisibleMs:visible-start,readMs:readEnd-start,openMs:openEnd-readEnd,getPageMs:pageEnd-openEnd,paintMs:paintEnd-paintStart,flushMs:flushEnd-paintEnd,width,height,rgbaSha256:hash};
    },{width:ours.width,height:ours.height});
    assert.deepEqual(referenceErrors,[],'PDF.js must have no browser exceptions');report.pdfjs.push(reference);await referenceContext.close();
    console.log(JSON.stringify({sample:index+1,baseline:report.baseline.at(-1)?.canvasVisibleMs,ours:ours.canvasVisibleMs,ready:ours.readerReadyMs,pdfjs:reference.canvasVisibleMs}));
  }
  const median=values=>{const sorted=[...values].sort((a,b)=>a-b);return (sorted[Math.floor((sorted.length-1)/2)]+sorted[Math.floor(sorted.length/2)])/2;};
  report.medians={oursCanvasVisibleMs:median(report.ours.map(r=>r.canvasVisibleMs)),oursReaderReadyMs:median(report.ours.map(r=>r.readerReadyMs)),pdfjsCanvasVisibleMs:median(report.pdfjs.map(r=>r.canvasVisibleMs))};
  if(baselineRoot){
    report.medians.baselineCanvasVisibleMs=median(report.baseline.map(r=>r.canvasVisibleMs));
    report.medians.baselineReaderReadyMs=median(report.baseline.map(r=>r.readerReadyMs));
    assert.equal(new Set([...report.ours,...report.baseline].map(r=>r.rgbaSha256)).size,1,'Optimization must retain every reader pixel');
    assert(report.baseline.every(r=>r.width===report.ours[0].width&&r.height===report.ours[0].height),'Baseline and candidate must use matching dimensions');
  }
  assert.equal(new Set(report.ours.map(r=>r.rgbaSha256)).size,1,'Reader pixels must be stable across fresh opens');
  assert.equal(new Set(report.pdfjs.map(r=>r.rgbaSha256)).size,1,'Reference pixels must be stable across fresh opens');
  await writeFile(output,JSON.stringify(report,null,2));console.log('REPORT '+output);console.log(JSON.stringify(report.medians));
}finally{await browser?.close();await new Promise(resolve=>server.close(resolve));}

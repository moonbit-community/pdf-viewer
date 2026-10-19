// Real Chromium sampling of independent page and Worker targets. No renderer
// source rewriting or per-call wrappers in sampled/timing runs.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {resolve,extname,sep} from 'node:path';
import {execFileSync} from 'node:child_process';
import {loadavg} from 'node:os';

const [filename,destination]=process.argv.slice(2);
assert(filename&&destination,'Usage: PDF_PROFILE_ROOT=<packaged site> node tools/pixels/compare_cpu_profiles.mjs <PDF> <output directory>');
const output=resolve(destination),ours=resolve(process.env.PDF_PROFILE_ROOT||'_build/pages');
const capture=process.env.PDF_PROFILE_MODE||'sampled',samples=Number(process.env.PDF_PROFILE_SAMPLES||3);
assert(['sampled','timing','counts'].includes(capture));assert(Number.isInteger(samples)&&samples>=1&&samples<=10);
const engine=process.env.PDF_PROFILE_BROWSER||'chromium';assert(['chromium','webkit'].includes(engine));assert(capture!=='sampled'||engine==='chromium','CPU sampling requires Chromium CDP');
const variants=(process.env.PDF_PROFILE_VARIANTS||'ours,reference,reference-streaming').split(',');
assert(variants.every(v=>['ours','reference','reference-streaming'].includes(v)));
const roots={ours,reference:resolve('reference/pdf.js/build/generic')},bytes=await readFile(filename);
const sha=b=>createHash('sha256').update(b).digest('hex');
assert.equal(sha(bytes),'3662ff519e485810520552bf301d8c3b2b917fd2f83303f4965d7abed367e113','This study is fixed to the original 14-page tracemonkey.pdf');
const pins=JSON.parse(await readFile('tools/ci/toolchain.json'));
const revision=execFileSync('git',['-C','reference/pdf.js','rev-parse','HEAD'],{encoding:'utf8'}).trim();
assert.equal(revision,pins.pdfjs_reference);
assert.equal(execFileSync('git',['-C','reference/pdf.js','diff','--name-only','HEAD','src','external','gulpfile.mjs','package.json','package-lock.json'],{encoding:'utf8'}).trim(),'');
const report={complete:false,capture,engine,samples,variants,fixtureSha256:sha(bytes),commit:execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim(),pdfjsRevision:revision,
 scope:'Original PDF, fresh context/document/Worker per sweep, first sequential full-document render at CSS1216/DPR2. Open/startup/DOM/hash/teardown excluded. Full RGBA readback included. Ours prepares Canvas, selection, accessibility, annotations and editor. reference calls getOperatorList, text, annotations and structure before render (OPLIST is a different intent); reference-streaming renders concurrently with text/annotations/structure without the extra OPLIST. Semantic models are different. CPU sampling is diagnostic, not an uninstrumented latency benchmark. Counts use separate instrumented runs.',
 artifacts:{ours:sha(await readFile(resolve(ours,'pdf-worker.js'))),reference:sha(await readFile(resolve(roots.reference,'build/pdf.worker.mjs')))},rows:[]};
await mkdir(output,{recursive:true});
const server=createServer(async(req,res)=>{
 const path=new URL(req.url,'http://localhost').pathname;
 if(path==='/probe.html'){res.writeHead(200,{'Content-Type':'text/html'}).end('<!doctype html><body>');return;}
 if(path==='/fixture.pdf'){res.writeHead(200).end(bytes);return;}
 const [,variant,...parts]=path.split('/'),root=roots[variant];
 if(!root){res.writeHead(404).end();return;}
 const file=resolve(root,parts.join('/'));if(!file.startsWith(root+sep)){res.writeHead(404).end();return;}
 try{const data=await readFile(file);res.writeHead(200,{'Content-Type':({'.js':'text/javascript','.mjs':'text/javascript','.wasm':'application/wasm'})[extname(file)]||'application/octet-stream'}).end(data);}catch{res.writeHead(404).end();}
});
await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await createRequire(resolve('tools/test-host/package.json'))('playwright')[engine].launch({headless:true});
report.browser=browser.version();

// Legacy non-flat attachment lets a public Playwright browser CDP session
// address a real dedicated Worker without relying on Playwright internals.
async function workerSession(root,targetId){
 const {sessionId}=await root.send('Target.attachToTarget',{targetId,flatten:false});
 let next=0;const pending=new Map();
 const listener=event=>{if(event.sessionId!==sessionId)return;const message=JSON.parse(event.message),p=pending.get(message.id);if(!p)return;pending.delete(message.id);message.error?p.reject(Error(JSON.stringify(message.error))):p.resolve(message.result);};
 root.on('Target.receivedMessageFromTarget',listener);
 return {send(method,params={}){return new Promise((resolve,reject)=>{const id=++next;pending.set(id,{resolve,reject});root.send('Target.sendMessageToTarget',{sessionId,message:JSON.stringify({id,method,params})}).catch(reject);});},async detach(){root.off('Target.receivedMessageFromTarget',listener);await root.send('Target.detachFromTarget',{sessionId});}};
}

try{
 for(let sample=0;sample<samples;sample++)for(const variant of sample%2?[...variants].reverse():variants){
  const context=await browser.newContext({deviceScaleFactor:2});
  let root,worker,main;
  try{
   const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(String(e)));
   await page.goto(`http://127.0.0.1:${server.address().port}/probe.html`);
   const opened=await page.evaluate(async variant=>{
    const bytes=new Uint8Array(await(await fetch('/fixture.pdf')).arrayBuffer());
    const check=raw=>{const p=JSON.parse(raw);if(!p.ok)throw Error(p.error);return p;};
    const state=globalThis.probe={variant,pages:[],intervals:[],check};
    const start=performance.now();
    if(variant==='ours'){
     state.api=(await import('/ours/viewer-host.mjs')).viewerHost;state.api.pdf.reset();check(await state.api.openDocument(new File([bytes],'document.pdf'),bytes,null));
     state.layouts=check(await state.api.pdf.call('page_layouts')).layouts;state.count=state.layouts.length;
    }else{
     state.api=await import('/reference/build/pdf.mjs');state.api.GlobalWorkerOptions.workerSrc='/reference/build/pdf.worker.mjs';
     state.task=state.api.getDocument({data:bytes,useSystemFonts:false,isEvalSupported:false,cMapUrl:'/reference/web/cmaps/',cMapPacked:true,standardFontDataUrl:'/reference/web/standard_fonts/',wasmUrl:'/reference/web/wasm/'});
     state.document=await state.task.promise;state.count=state.document.numPages;
    }
    return {pages:state.count,openMs:performance.now()-start};
   },variant);
   let clock=null;
   if(capture==='sampled'){
    root=await browser.newBrowserCDPSession();
    const targets=(await root.send('Target.getTargets')).targetInfos.filter(t=>t.type==='worker'&&t.url.includes(variant==='ours'?'/ours/pdf-worker.js':'/reference/build/pdf.worker.mjs'));
    assert.equal(targets.length,1,'Exactly one real PDF Worker required');
    worker=await workerSession(root,targets[0].targetId);main=await context.newCDPSession(page);
    await main.send('Performance.enable');
    const metrics=Object.fromEntries((await main.send('Performance.getMetrics')).metrics.map(m=>[m.name,m.value]));
    const origins=await page.evaluate(()=>({now:performance.now(),origin:performance.timeOrigin}));
    clock={navigationStartUs:metrics.NavigationStart*1e6,metricsTimestampUs:metrics.Timestamp*1e6,...origins};
    assert(Number.isFinite(clock.navigationStartUs));
    for(const session of [main,worker]){await session.send('Profiler.enable');await session.send('Profiler.setSamplingInterval',{interval:1000});await session.send('Profiler.start');}
   }
   if(capture==='counts')await page.evaluate(()=>{
    const p=globalThis.canvasCounts={active:false,methods:{},paths:{calls:0,stringCalls:0,stringChars:0}};
    const Path=globalThis.Path2D;globalThis.Path2D=new Proxy(Path,{construct(Target,args){if(p.active){p.paths.calls++;if(typeof args[0]==='string'){p.paths.stringCalls++;p.paths.stringChars+=args[0].length;}}return Reflect.construct(Target,args,Target);}});
    for(const proto of new Set([globalThis.CanvasRenderingContext2D?.prototype,globalThis.OffscreenCanvasRenderingContext2D?.prototype].filter(Boolean)))for(const name of ['getImageData','putImageData','fillText','strokeText','fill','stroke','drawImage','createLinearGradient','createRadialGradient','setTransform','transform','save','restore']){
     const original=proto[name];proto[name]=function(...args){if(p.active){const r=p.methods[name]||={calls:0,pixels:0};r.calls++;if(name==='getImageData')r.pixels+=args[2]*args[3];else if(name==='putImageData')r.pixels+=args.length>=7?args[5]*args[6]:args[0].width*args[0].height;}return original.apply(this,args);};
    }
   });
   const load=loadavg();
   const result=await page.evaluate(async()=>{
    const s=globalThis.probe,{variant,api,check}=s;
    const digest=async data=>[...new Uint8Array(await crypto.subtle.digest('SHA-256',data))].map(x=>x.toString(16).padStart(2,'0')).join('');
    const measure=async(page,phase,fn)=>{const start=performance.now();try{return await fn();}finally{s.intervals.push({page,phase,start,end:performance.now()});}};
    for(let number=1;number<=s.count;number++){
     const canvas=document.createElement('canvas');let payload,content,counts=null;
     const start=performance.now();let prepareMs=0,paintMs=0;
     if(globalThis.canvasCounts){canvasCounts.methods={};canvasCounts.paths={calls:0,stringCalls:0,stringChars:0};canvasCounts.active=true;}
     if(variant==='ours'){
      const at=performance.now();payload=await measure(number,'prepare',()=>api.preparePage(number,1216/s.layouts[number-1].width,0));if(!payload.ok)throw Error(payload.error);prepareMs=performance.now()-at;
      const paintAt=performance.now();await measure(number,'paint',async()=>{const painted=await api.paintCanvas(canvas,payload,2,()=>true,()=>{throw Error('Unexpected host CMM');});if(painted.diagnostics.length)throw Error(JSON.stringify(painted.diagnostics));});paintMs=performance.now()-paintAt;
     }else{
      const page=await s.document.getPage(number),unit=page.getViewport({scale:1,rotation:0}),viewport=page.getViewport({scale:1216/unit.width,rotation:0});
      const text=async()=>{const result={items:[],styles:Object.create(null),lang:null},reader=page.streamTextContent({includeMarkedContent:true}).getReader();try{for(;;){const {value,done}=await reader.read();if(done)break;result.lang??=value.lang;Object.assign(result.styles,value.styles);result.items.push(...value.items);}}finally{reader.releaseLock();}return result;};
      const semantics=async()=>{const [textContent,annotations,structure]=await Promise.all([text(),page.getAnnotations({intent:'display'}),page.getStructTree()]);return {text:textContent,annotations,structure};};
      const paint=async()=>{canvas.width=Math.ceil(viewport.width*2);canvas.height=Math.ceil(viewport.height*2);await page.render({canvasContext:canvas.getContext('2d'),viewport,transform:[2,0,0,2,0,0],background:'rgb(255,255,255)'}).promise;};
      if(variant==='reference-streaming'){
       const at=performance.now();await measure(number,'render+semantics',async()=>{const [,value]=await Promise.all([paint(),semantics()]);content=value;});paintMs=performance.now()-at;
      }else{
       const at=performance.now();await measure(number,'prepare',async()=>{[,content]=await Promise.all([page.getOperatorList(),semantics()]);});prepareMs=performance.now()-at;
       const paintAt=performance.now();await measure(number,'paint',paint);paintMs=performance.now()-paintAt;
      }
     }
     if(globalThis.canvasCounts){canvasCounts.active=false;counts=structuredClone(canvasCounts);delete counts.active;}
     const pixels=await measure(number,'flush',()=>canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data),end=performance.now();
     const semantic=payload?Object.fromEntries(['ok','page','svg','layer','editor','annotations','accessibility','intent'].map(k=>[k,payload[k]])):content;
     const flush=s.intervals.at(-1),flushMs=flush.end-flush.start;
     const row={page:number,start,end,prepareMs,paintMs,totalMs:end-start,flushMs,setupMs:end-start-prepareMs-paintMs-flushMs,rgbaSha256:await digest(pixels),semanticSha256:await digest(new TextEncoder().encode(JSON.stringify(semantic))),counts};
     s.pages.push(row);canvas.width=canvas.height=0;
    }
    return {pages:s.pages,intervals:s.intervals,totalMs:s.pages.reduce((n,p)=>n+p.totalMs,0),prepareMs:s.pages.reduce((n,p)=>n+p.prepareMs,0),paintMs:s.pages.reduce((n,p)=>n+p.paintMs,0)};
   });
   if(capture==='sampled'){
    for(const [thread,session] of [['main',main],['worker',worker]]){
     const {profile}=await session.send('Profiler.stop');
     assert(profile.samples.length>0);await writeFile(resolve(output,`${capture}-${sample}-${variant}-${thread}.cpuprofile`),JSON.stringify(profile));
     // Chromium TimeTicks is shared by page and Worker targets. Validate the
     // NavigationStart translation before assigning samples to phase windows.
     assert(profile.startTime<clock.navigationStartUs+result.intervals[0].start*1000);
     assert(profile.endTime>clock.navigationStartUs+result.intervals.at(-1).end*1000);
    }
   }
   assert.deepEqual(errors,[]);
   // Ours has known Chromium same-code raster nondeterminism. Retain all
   // hashes and report mismatches; do not whitelist or treat them as equality.
   report.rows.push({sample,variant,load,clock,...opened,...result});
   await writeFile(resolve(output,`${capture}.json`),JSON.stringify(report,null,2)+'\n');
   console.log(JSON.stringify({capture,sample,variant,totalMs:result.totalMs,prepareMs:result.prepareMs,paintMs:result.paintMs,load}));
   await page.evaluate(async()=>{const s=globalThis.probe;if(s.variant==='ours'){s.api.pdf.close();s.api.clearRenderAssets();}else await s.task.destroy();});
  }finally{if(worker)await worker.detach().catch(()=>{});if(main)await main.detach();if(root)await root.detach();await context.close();}
 }
 report.complete=true;await writeFile(resolve(output,`${capture}.json`),JSON.stringify(report,null,2)+'\n');
}finally{await browser.close();await new Promise(r=>server.close(r));}

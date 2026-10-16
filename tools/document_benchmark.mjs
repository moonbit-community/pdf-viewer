// First sequential document sweep through independent packaged sites and PDF.js.
// Build every variant before running; keep all other heavy work stopped.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile,writeFile,mkdir,access} from 'node:fs/promises';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {resolve,dirname,extname,sep} from 'node:path';
import {execFileSync} from 'node:child_process';
const filename=process.argv[2],baseline=process.env.PDF_BENCH_BASELINE_ROOT;
assert(filename&&baseline,'Usage: PDF_BENCH_BASELINE_ROOT=<packaged site> node tools/document_benchmark.mjs <PDF> [report.json]');
const output=resolve(process.argv[3]||'_build/document-benchmark/report.json'),engine=process.env.PDF_BROWSER||'chromium',samples=Number(process.env.PDF_BENCH_SAMPLES||3);
assert(['chromium','webkit'].includes(engine));assert(Number.isInteger(samples)&&samples>=3&&samples<=15);
const roots={baseline:resolve(baseline),candidate:resolve(process.env.PDF_BENCH_VIEWER_ROOT||'_build/pages'),reference:resolve('reference/pdf.js/build/generic')};
const pins=JSON.parse(await readFile('tools/ci/toolchain.json')),revision=execFileSync('git',['-C','reference/pdf.js','rev-parse','HEAD'],{encoding:'utf8'}).trim();
assert.equal(revision,pins.pdfjs_reference);assert(revision.startsWith(JSON.parse(await readFile('reference/pdf.js/build/version.json')).commit));
assert.equal(execFileSync('git',['-C','reference/pdf.js','diff','--name-only','HEAD','src','external','gulpfile.mjs','package.json','package-lock.json'],{encoding:'utf8'}).trim(),'');
const capturePage=Number(process.env.PDF_BENCH_CAPTURE_PAGE||0);assert(Number.isInteger(capturePage)&&capturePage>=0);
const bytes=await readFile(filename),hash=b=>createHash('sha256').update(b).digest('hex');
const report={scope:'Three variants in alternating fresh contexts, documents and Workers. First sequential full-document sweep at CSS width 1216 / DPR 2. Preparation, painting and full RGBA readback are timed; startup/opening, hashes, DOM and teardown are excluded. Ours includes selection/accessibility preparation; PDF.js is a render-only lower bound. Require exact baseline/candidate pixels and complete semantics per page; PDF.js hashes are reported separately.',complete:false,engine,samples,capturePage,fixtureSha256:hash(bytes),pdfjsRevision:revision,workerSha256:{},hostSha256:{},rows:[]};
for(const [variant,root] of Object.entries(roots))report.workerSha256[variant]=hash(await readFile(resolve(root,variant==='reference'?'build/pdf.worker.mjs':'pdf-worker.js')));
for(const variant of ['baseline','candidate']){
 const modules=['viewer-host.mjs','pdf-canvas.mjs','pdf-canvas-program.mjs','pdf-runtime.mjs','pdf-shading.mjs'];
 try{await access(resolve(roots[variant],'pdf-canvas-text-runs.mjs'));modules.push('pdf-canvas-text-runs.mjs');}catch(error){if(error.code!=='ENOENT')throw error;}
 report.hostSha256[variant]=Object.fromEntries(await Promise.all(modules.map(async file=>[file,hash(await readFile(resolve(roots[variant],file)))])));
}
const mime={'.js':'text/javascript','.mjs':'text/javascript','.wasm':'application/wasm'},server=createServer(async(req,res)=>{
 const path=new URL(req.url,'http://localhost').pathname;
 if(path==='/probe.html'){res.writeHead(200,{'Content-Type':'text/html'}).end('<!doctype html><body>');return;}
 if(path==='/fixture.pdf'){res.writeHead(200).end(bytes);return;}
 const[,variant,...parts]=path.split('/'),root=roots[variant];if(!root){res.writeHead(404).end();return;}
 const file=resolve(root,parts.join('/'));if(!file.startsWith(root+sep)){res.writeHead(404).end();return;}
 try{res.writeHead(200,{'Content-Type':mime[extname(file)]||'application/octet-stream'}).end(await readFile(file));}catch{res.writeHead(404).end();}
});
await mkdir(dirname(output),{recursive:true});await new Promise(r=>server.listen(0,'127.0.0.1',r));
const browser=await createRequire(resolve('tools/test-host/package.json'))('playwright')[engine].launch({headless:true}),expected=new Map();
try{
 for(let pair=0;pair<samples;pair++)for(const variant of pair%2?['reference','candidate','baseline']:['baseline','candidate','reference']){
  const context=await browser.newContext({deviceScaleFactor:2});
  try{
   const page=await context.newPage(),errors=[];page.on('pageerror',e=>errors.push(String(e)));await page.goto('http://127.0.0.1:'+server.address().port+'/probe.html');
   const result=await page.evaluate(async({variant,capturePage})=>{
    const bytes=new Uint8Array(await(await fetch('/fixture.pdf')).arrayBuffer()),check=raw=>{const p=JSON.parse(raw);if(!p.ok)throw Error(p.error);return p;};
    const digest=async b=>[...new Uint8Array(await crypto.subtle.digest('SHA-256',b))].map(x=>x.toString(16).padStart(2,'0')).join('');
    let api,task,documentHandle,count,layouts;
    if(variant==='reference'){
     api=await import('/reference/build/pdf.mjs');api.GlobalWorkerOptions.workerSrc='/reference/build/pdf.worker.mjs';
     task=api.getDocument({data:bytes,useSystemFonts:false,isEvalSupported:false,cMapUrl:'/reference/web/cmaps/',cMapPacked:true,standardFontDataUrl:'/reference/web/standard_fonts/',wasmUrl:'/reference/web/wasm/'});
     documentHandle=await task.promise;count=documentHandle.numPages;
    }else{
     api=(await import('/'+variant+'/viewer-host.mjs')).viewerHost;api.pdf.reset();check(await api.openDocument(new File([bytes],'document.pdf'),bytes,null));
     layouts=check(await api.pdf.call('page_layouts')).layouts;count=layouts.length;
    }
    const pages=[];
    for(let number=1;number<=count;number++){
     const canvas=document.createElement('canvas'),start=performance.now();let payload,prepareMs=null;
     if(variant==='reference'){
      const page=await documentHandle.getPage(number),unit=page.getViewport({scale:1,rotation:0}),viewport=page.getViewport({scale:1216/unit.width,rotation:0});
      canvas.width=Math.ceil(viewport.width*2);canvas.height=Math.ceil(viewport.height*2);
      await page.render({canvasContext:canvas.getContext('2d'),viewport,transform:[2,0,0,2,0,0],background:'rgb(255,255,255)'}).promise;
     }else{
      const layout=layouts[number-1];payload=check(await api.pdf.call('render_page',[number,1216/layout.width,0,true,true,true]));prepareMs=performance.now()-start;
      const result=await api.paintCanvas(canvas,payload,2,()=>true,()=>{throw Error('Unexpected host CMM');});if(result.diagnostics.length)throw Error(JSON.stringify(result.diagnostics));
     }
     const painted=performance.now(),pixels=canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data,end=performance.now();
     const semanticSha256=payload?await digest(new TextEncoder().encode(JSON.stringify(Object.fromEntries(['ok','page','svg','layer','editor','annotations','accessibility','intent'].map(k=>[k,payload[k]]))))):null;
     pages.push({page:number,prepareMs,totalMs:end-start,paintAndPrepareMs:painted-start,flushMs:end-painted,rgbaSha256:await digest(pixels),semanticSha256,capturePNG:number===capturePage?canvas.toDataURL():null});canvas.width=canvas.height=0;
    }
    const cache=variant==='reference'?null:check(await api.pdf.call('cache_info'));
    if(variant==='reference')await task.destroy();else{api.pdf.close();api.clearRenderAssets();}
    return{pages,totalMs:pages.reduce((s,p)=>s+p.totalMs,0),prepareMs:variant==='reference'?null:pages.reduce((s,p)=>s+p.prepareMs,0),cache};
   },{variant,capturePage});
   for(const row of result.pages){if(row.capturePNG)await writeFile(resolve(dirname(output),`pixels-${pair}-${variant}-${row.page}.png`),Buffer.from(row.capturePNG.split(',')[1],'base64'));delete row.capturePNG;}
   report.rows.push({pair,variant,...result});await writeFile(output,JSON.stringify(report,null,2)+'\n');
   assert.deepEqual(errors,[]);
   if(variant!=='reference')for(const row of result.pages){const previous=expected.get(row.page);if(previous){assert.equal(row.rgbaSha256,previous.rgbaSha256,variant+' pixels '+row.page);assert.equal(row.semanticSha256,previous.semanticSha256,variant+' semantics '+row.page);}else expected.set(row.page,row);}
   console.log(JSON.stringify({pair,variant,pages:result.pages.length,totalMs:result.totalMs,prepareMs:result.prepareMs}));
  }finally{await context.close();}
 }
}finally{await browser.close();await new Promise(r=>server.close(r));}
report.complete=true;await writeFile(output,JSON.stringify(report,null,2)+'\n');
console.log(output);

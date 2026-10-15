#!/usr/bin/env node
// Exercise the published artifact through a repository subpath, with no dev
// server, comparison checkout or test PDFs in the site directory.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {mkdir,readFile,stat,writeFile} from 'node:fs/promises';
import {extname,resolve,sep} from 'node:path';
import {layerFixture} from './pixels/layer_fixtures.mjs';
import {xfaFixture,makePdf,stream} from './pixels/readonly_fixtures.mjs';
import {waitForUI,holdBootstrapFramesUntilFile} from './browser_ui.mjs';

const require=createRequire(resolve('tools/test-host/package.json'));
const {chromium,webkit}=require('playwright');
const engine=process.env.PDF_BROWSER||'chromium';
assert.ok(['chromium','webkit'].includes(engine),'PDF_BROWSER must be chromium or webkit');
const launcher=engine==='webkit'?webkit:chromium;
const root=resolve(process.env.PDF_PAGES_ROOT||'_build/pages'),prefix='/pdf-viewer/';
const output=resolve('_build/pages-test-'+engine+'-'+Date.now());await mkdir(output,{recursive:true});
const mime={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8',
  '.js':'text/javascript; charset=utf-8','.mjs':'text/javascript; charset=utf-8',
  '.wasm':'application/wasm','.pdf':'application/pdf','.svg':'image/svg+xml'};
const requests=[],failures=[],checks=[];let browser,page,ok=false,current='initialization';
const server=createServer(async(request,response)=>{
  const url=new URL(request.url,'http://localhost');
  if(!['GET','HEAD'].includes(request.method))failures.push(request.method+' '+url.pathname);
  if(!url.pathname.startsWith(prefix)){response.writeHead(404).end();return;}
  const path=resolve(root,decodeURIComponent(url.pathname.slice(prefix.length))||'index.html');
  if(!path.startsWith(root+sep)){response.writeHead(404).end();return;}
  try{
    const bytes=await readFile(path);
    // A plain static host may answer a Range request with the complete file.
    response.writeHead(200,{'Content-Type':mime[extname(path)]||'application/octet-stream',
      'Content-Length':bytes.length,'Cache-Control':'no-store'}).end(bytes);
  }catch{response.writeHead(404).end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const base=process.argv[2]||'http://127.0.0.1:'+server.address().port+prefix;
async function check(name,work){current=name;await work();checks.push(name);console.log('PASS '+name);}
async function idle(filename){
  await waitForUI(page,filename=>Boolean(
    document.querySelector('#viewer')?.getAttribute('aria-busy')==='false'&&
      !document.querySelector('#edit-toggle').disabled&&
      document.querySelector('#file-name').textContent===filename&&
      document.querySelector('#page-count').textContent==='/ 2'&&
      document.querySelector('.page[data-page="1"][data-rendered="true"]')
  ),filename);
}
function readingFixture(profile){
  const count=6,samples=Buffer.alloc(256*128*3);
  for(let i=0;i<256*128;i++)samples.set(i%2?[32,96,160]:[255,255,255],i*3);
  const objects=['<< /Type /Catalog /Pages 2 0 R >>',
    `<< /Type /Pages /Count ${count} /MediaBox [0 0 612 792] /Kids [${Array.from({length:count},(_,i)=>`${6+i*2} 0 R`).join(' ')}] >>`,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',stream('/N 3 /Alternate /DeviceRGB',profile),
    stream('/Type /XObject /Subtype /Image /Width 256 /Height 128 /BitsPerComponent 8 /ColorSpace [/ICCBased 4 0 R]',samples)];
  for(let i=1;i<=count;i++){
    objects.push(`<< /Type /Page /Parent 2 0 R /Resources << /Font << /F 3 0 R >> /XObject << /I 5 0 R >> >> /Contents ${7+(i-1)*2} 0 R >>`,
      stream('',Array.from({length:16},(_,row)=>`BT /F 12 Tf 30 ${750-row*24} Td (Page ${i}: a real reading surface with text and images.) Tj ET`).join('\n')+'\nq 500 0 0 250 30 50 cm /I Do Q'));
  }
  return makePdf(objects);
}
function codecFixture(profile){
  const u32=value=>[value>>>24,value>>>16&255,value>>>8&255,value&255];
  const image=black=>{
    const payload=[...u32(8),...u32(8),...u32(72),...u32(72),black?4:0,0,0];
    return stream('/Type /XObject /Subtype /Image /Width 8 /Height 8 /BitsPerComponent 1 /ColorSpace /DeviceGray /Filter /JBIG2Decode',
      Buffer.from([...u32(1),48,0,1,...u32(payload.length),...payload]));
  };
  return makePdf([
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Count 2 /Kids [3 0 R 4 0 R] /MediaBox [0 0 32 32] >>',
    '<< /Type /Page /Parent 2 0 R /Resources << /XObject << /Black 5 0 R /White 6 0 R >> >> /Contents 8 0 R >>',
    '<< /Type /Page /Parent 2 0 R /Resources << /ColorSpace << /ICC [/ICCBased 7 0 R] >> >> /Contents 9 0 R >>',
    image(true),image(false),stream('/N 3 /Alternate /DeviceRGB',profile),
    stream('','q 16 0 0 32 0 0 cm /Black Do Q q 16 0 0 32 16 0 cm /White Do Q'),
    stream('','/ICC cs .25 .5 .75 scn 0 0 32 32 re f'),
  ]);
}
function alphaRasterFixture(){
  return makePdf([
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Count 1 /Kids [3 0 R] /MediaBox [0 0 32 32] >>',
    '<< /Type /Page /Parent 2 0 R /Resources << /XObject << /I 5 0 R >> >> /Contents 4 0 R >>',
    stream('','q 24 0 0 24 4 4 cm /I Do Q'),
    stream('/Type /XObject /Subtype /Image /Width 2 /Height 2 /BitsPerComponent 8 /ColorSpace /DeviceRGB /SMask 6 0 R /Interpolate true',Buffer.from([255,0,0,0,255,0,0,0,255,255,128,0])),
    stream('/Type /XObject /Subtype /Image /Width 2 /Height 2 /BitsPerComponent 8 /ColorSpace /DeviceGray',Buffer.from([0,64,128,255])),
  ]);
}
try{
  browser=await launcher.launch({headless:true,...(engine==='chromium'?{
    executablePath:process.env.PDF_CHROMIUM||chromium.executablePath(),args:['--no-sandbox'],
  }:{})});
  page=await browser.newPage({viewport:{width:1280,height:900},deviceScaleFactor:2,acceptDownloads:true});
  page.setDefaultTimeout(30000);
  page.context().on('request',request=>{if(/^https?:/.test(request.url()))requests.push(new URL(request.url()).pathname);});
  page.on('request',request=>{
    if(/^https?:/.test(request.url())&&
      (new URL(request.url()).origin!==new URL(base).origin||!['GET','HEAD'].includes(request.method())))
      failures.push(request.method()+' '+request.url());
  });
  page.on('pageerror',error=>{failures.push(String(error));console.error('Browser error',error.stack||String(error));});
  page.on('requestfailed',request=>failures.push(request.url()+' '+request.failure()?.errorText));
  page.on('response',response=>{if(response.status()>=400)failures.push(response.url()+' '+response.status());});
  await check('Static artifact starts Rabbita through a repository subpath',async()=>{
    await page.goto(base);
    await page.locator('#open-empty').waitFor({state:'visible'});
    assert.equal(await page.locator('#error').isVisible(),false);
    assert.equal(await page.locator('#empty-state').isVisible(),true);
    assert.equal(await page.locator('#download').isDisabled(),true);
    await assert.rejects(stat(resolve(root,'_test')),{code:'ENOENT'});
    await stat(resolve(root,'.nojekyll'));
    await stat(resolve(root,'licenses/liberation-fonts.txt'));
    assert.equal(requests.includes(prefix+'_generated/pdf.js'),false,'The main thread loads only the UI; the full parser belongs to the Worker');
    assert.equal(requests.includes(prefix+'vendor/xfa/xfa.mjs'),false,'The XFA engine loads only when an XFA document needs it');
  });
  await check('Packaged Worker paints a local PDF without network uploads',async()=>{
    const startupRequestStart=requests.length;
    await page.locator('#file-input').setInputFiles({name:'local.pdf',mimeType:'application/pdf',buffer:layerFixture()});
    await idle('local.pdf');
    const startupRequests=requests.slice(startupRequestStart);
    for(const asset of ['_generated/pdf.js','pdf-graphics.mjs','pdf-range.mjs','pdf-runtime.mjs','pdf-canvas.mjs','pdf-patterns.mjs','pdf-shading.mjs','pdf-xfa.mjs','vendor/xfa/xfa.mjs'])
      assert.ok(!startupRequests.some(path=>path.endsWith('/'+asset)),'Ordinary PDF startup must not load '+asset);
    const graphics=await page.evaluate(()=>pdfViewerHost.pdf.diagnostics().graphics);
    assert.deepEqual(graphics,{icc:true,jbig2:true,diagnostics:[]},'Both codecs must initialize from bundled Worker asset URLs');
    assert.equal(await page.locator('#page-count').innerText(),'/ 2');
    const painted=await page.locator('#pages .page[data-page="1"] canvas').evaluate(canvas=>{
      const ctx=canvas.getContext('2d'),bytes=ctx.getImageData(0,0,canvas.width,canvas.height).data;
      return canvas.width>0&&canvas.height>0&&bytes.some((value,index)=>index%4!==3&&value<128);
    });
    assert.equal(painted,true);
    await page.locator('#search-query').fill('Alpha');
    await page.waitForFunction(()=>document.querySelector('#search-status').textContent==='1 / 1');
    assert.ok(requests.includes(prefix+'pdf-worker.js'));
    assert.ok(requests.includes(prefix+'_generated/viewer.js'));
  });
  await check('Static viewer edits downloads and reopens a form',async()=>{
    await page.locator('#layers-toggle').click();
    await page.locator('#layer-7').click();
    await page.waitForFunction(()=>document.querySelector('#layer-7').checked&&!document.querySelector('#layers-config').disabled);
    await page.locator('#edit-toggle').click();
    await page.waitForFunction(()=>!document.querySelector('#editor-toolbar').hidden&&!document.querySelector('#edit-toggle').disabled);
    const field=page.locator('[data-field-name="layer-field"]');
    await field.fill('Saved from GitHub Pages');await field.press('Tab');
    await page.waitForFunction(()=>document.querySelector('#editor-dirty').textContent==='Unsaved'&&!document.querySelector('#edit-toggle').disabled);
    const downloaded=page.waitForEvent('download');await page.locator('#download').click();
    const saved=resolve(output,'saved.pdf');await (await downloaded).saveAs(saved);
    await page.waitForFunction(()=>document.querySelector('#editor-status').textContent.startsWith('Downloaded')&&document.querySelector('#editor-dirty').textContent==='');
    const bytes=await readFile(saved);assert.equal(bytes.subarray(0,5).toString(),'%PDF-');
    await page.locator('#file-input').setInputFiles({name:'saved.pdf',mimeType:'application/pdf',buffer:bytes});await idle('saved.pdf');
    await page.locator('#layers-toggle').click();await page.locator('#layer-7').click();
    await page.waitForFunction(()=>document.querySelector('#layer-7').checked&&!document.querySelector('#layers-config').disabled);
    await page.locator('#edit-toggle').click();
    await page.waitForFunction(()=>!document.querySelector('#editor-toolbar').hidden&&!document.querySelector('#edit-toggle').disabled);
    assert.equal(await field.inputValue(),'Saved from GitHub Pages');
  });
  await check('Packaged XFA renders readonly fields and copies pending source ranges',async()=>{
    await page.locator('#file-input').setInputFiles({name:'xfa.pdf',mimeType:'application/pdf',buffer:xfaFixture()});
    await page.waitForFunction(()=>document.querySelector('.xfaLayer input')?.value==='Bound value');
    await waitForUI(page,()=>document.querySelector('#viewer').getAttribute('aria-busy')==='false');
    const input=page.locator('.xfaLayer input').first();
    assert.equal(await input.isEditable(),false);
    const copy=await page.evaluate(async()=>{
      const host=await import('./viewer.js'),span=document.querySelector('.xfa-text'),node=span.firstChild;
      const select=end=>getSelection().setBaseAndExtent(node,0,node,end);
      select(2);await host.readSelection();
      const expected=JSON.parse(await pdfViewerHost.pdf.call('select_page_text',[1,+span.dataset.item,0,+span.dataset.item,node.length])).selection.text;
      const call=pdfViewerHost.pdf.call,write=navigator.clipboard.write,writeText=navigator.clipboard.writeText;
      let release,requests=0,receive;const copied=new Promise(resolve=>receive=resolve);
      pdfViewerHost.pdf.call=function(method,...args){
        if(method==='select_page_text'){requests++;return new Promise(resolve=>release=()=>resolve(call.call(this,method,...args)));}
        return call.call(this,method,...args);
      };
      navigator.clipboard.write=async items=>receive(await (await items[0].getType('text/plain')).text());
      navigator.clipboard.writeText=text=>{receive(text);return Promise.resolve();};
      try{
        select(node.length);document.querySelector('#copy-selection').click();
        await new Promise(requestAnimationFrame);
        if(!release)throw Error('XFA copy did not resolve the new source range');
        release();release=null;
        const text=await Promise.race([copied,new Promise((_,reject)=>setTimeout(()=>reject(Error('Copy button dropped a pending selection')),1500))]);
        return {text,expected,requests};
      }finally{
        pdfViewerHost.pdf.call=call;navigator.clipboard.write=write;navigator.clipboard.writeText=writeText;
        release?.();
      }
    });
    assert.equal(copy.requests,1,'XFA retains Worker selection instead of stale indexes from the previous PDF');
    assert.equal(copy.text,copy.expected,'The copy button waits for the new XFA source range');
    assert.equal(await page.locator('#error').isVisible(),false);
    assert.ok(requests.includes(prefix+'vendor/xfa/xfa.mjs'));
    assert.ok(requests.includes(prefix+'vendor/xfa/xfa.css'));
    const cancelledChildren=await page.evaluate(async()=>{
      const data=JSON.parse(await pdfViewerHost.pdf.call('render_page',[1,1,0]));
      const pending=pdfViewerHost.makeXfaLayer({...data,xfa:{...data.xfa,fonts:[]}});
      pdfViewerHost.clearXfaFonts();
      return (await pending).childElementCount;
    });
    assert.equal(cancelledChildren,0,'A document reset while the lazy XFA import resolves must discard the old layer');
  });
  await check('Bundled Worker decodes JBIG2 and ICC pixels with Wasm assets below the subpath',async()=>{
    for(const asset of ['vendor/jbig2/jbig2.wasm','vendor/lcms-wasm/lcms.wasm']){
      const response=await fetch(base+asset);assert.equal(response.status,200);
      assert.equal(response.headers.get('content-type'),'application/wasm');
      const bytes=new Uint8Array(await response.arrayBuffer());assert.deepEqual([...bytes.slice(0,4)],[0,97,115,109]);
    }
    const licenses=await fetch(base+'vendor/jbig2/LICENSE_JBIG2');assert.equal(licenses.status,200);
    assert.ok((await licenses.text()).length>100);
    await page.locator('#file-input').setInputFiles({name:'codecs.pdf',mimeType:'application/pdf',
      buffer:codecFixture(await readFile(resolve('assets/icc/rgb-gamma22.icc')))});
    await idle('codecs.pdf');
    const sample=(number,x)=>page.locator(`.page[data-page="${number}"] canvas`).evaluate((canvas,x)=>
      [...canvas.getContext('2d').getImageData(Math.floor(canvas.width*x),Math.floor(canvas.height/2),1,1).data],x);
    assert.deepEqual(await sample(1,.25),[0,0,0,255],'Bundled Worker must decode the black JBIG2 image');
    assert.deepEqual(await sample(1,.75),[255,255,255,255],'Bundled Worker must decode the white JBIG2 image');
    await page.locator('#page-number').fill('2');await page.locator('#page-number').press('Enter');
    await page.waitForFunction(()=>document.querySelector('.page[data-page="2"]')?.dataset.rendered==='true');
    const icc=await sample(2,.5);
    assert.equal(icc[3],255);
    assert.ok(icc.slice(0,3).some((value,index)=>Math.abs(value-[.25,.5,.75][index]*255)>2),
      'ICC pixels must use the actual profile rather than the DeviceRGB Alternate');
    assert.deepEqual(failures,[]);
    assert.ok(requests.length>10&&requests.every(path=>path.startsWith(prefix)));
  });
  await check('Document pattern tiles reuse cloned plans and reset after document invalidation',async()=>{
    await waitForUI(page,()=>document.querySelector('#viewer').getAttribute('aria-busy')==='false');
    const result=await page.evaluate(async()=>{
      const pageInfo={number:1,origin_x:0,origin_y:0,width:20,height:20,blend_space:'DeviceRGB'};
      const viewport={width:20,height:20,matrix:[1,0,0,-1,0,20]};
      const path={svg_path:'M0 0H20V20H0Z',filled:true,stroked:false,fill_alpha:1,blend_mode:'normal',clips:[]};
      const cell={name:'P',bbox:{min_x:0,min_y:0,max_x:20,max_y:20},x_step:20,y_step:20,matrix:[1,0,0,1,0,0],
        tile_plan:{version:1,page:pageInfo,viewport,items:[{kind:'path',paint:{...path,fill_color:'#ff0000'}}]}};
      const plan={version:1,page:pageInfo,viewport,items:[{kind:'path',paint:{...path,pattern:cell}}]};
      const paint=async input=>{
        const canvas=document.createElement('canvas');
        await pdfViewerHost.paintCanvas(canvas,{canvas:input},1,()=>true,()=>[0,0,0]);
        return [...canvas.getContext('2d').getImageData(0,0,20,20).data];
      };
      pdfViewerHost.clearRenderAssets();
      try{
        const first=await paint(plan),cloned=await paint(structuredClone(plan));
        const warm=pdfViewerHost.renderAssetsDiagnostics().patterns;
        const changed=structuredClone(plan);changed.items[0].paint.pattern.tile_plan.items[0].paint.fill_color='#00ff00';
        const green=await paint(changed),modified=pdfViewerHost.renderAssetsDiagnostics().patterns;
        pdfViewerHost.clearRenderAssets();
        const cleared=pdfViewerHost.renderAssetsDiagnostics().patterns;
        const reset=await paint(plan),rebuilt=pdfViewerHost.renderAssetsDiagnostics().patterns;
        return {same:first.every((value,index)=>value===cloned[index]&&value===reset[index]),
          red:first.slice(840,844),green:green.slice(840,844),warm,modified,cleared,rebuilt};
      }finally{pdfViewerHost.clearRenderAssets();}
    });
    assert.equal(result.same,true,'Fresh viewport JSON and document rebuild preserve every pixel');
    assert.deepEqual(result.red,[255,0,0,255]);assert.deepEqual(result.green,[0,255,0,255]);
    assert.equal(result.warm.loads,1);assert.equal(result.warm.hits,1,'The actual viewer loader is stable across paints');
    assert.equal(result.modified.loads,2);assert.equal(result.warm.leased_entries,0);
    assert.equal(result.cleared.entries,0);assert.equal(result.cleared.bytes,0);
    assert.equal(result.rebuilt.loads,1);assert.equal(result.rebuilt.hits,0);
  });
  await check('Compiled glyphs cross the packaged Worker once and keep single image glyphs native',async()=>{
    await page.goto(base);await page.locator('#open-empty').waitFor({state:'visible'});
    await page.evaluate(()=>{
      const host=pdfViewerHost,paint=host.paintCanvas;
      window.glyphPaints=[];
      host.paintCanvas=async(...args)=>{
        const version=args[1].canvas.version,result=await paint(...args);
        const {prepareNativeCanvasItems}=await import('./pdf-canvas-native.mjs');
        const native=prepareNativeCanvasItems(args[1].canvas,{returnPixels:false});
        window.glyphPaints.push({version,expanded:args[1].canvas.version,native:native!==null});
        window.glyphPaintArgs=args;return result;
      };
    });
    const fixture=makePdf([
      '<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 80 80] /Contents 4 0 R /Resources << /Font << /F 5 0 R >> >> >>',
      stream('','0 .2 .8 rg BT /F 24 Tf 5 10 Td (AAA) Tj ET BT /F 24 Tf 5 40 Td (B) Tj ET'),
      '<< /Type /Font /Subtype /Type3 /FontBBox [0 0 600 900] /FontMatrix [.001 0 0 .001 0 0] /FirstChar 65 /LastChar 66 /Widths [600 600] /Encoding << /Differences [65 /A /B] >> /CharProcs << /A 6 0 R /B 7 0 R >> /Resources << /XObject << /I 8 0 R >> >> >>',
      stream('','600 0 0 0 600 900 d1 0 0 600 900 re 100 100 400 700 re f*'),
      stream('','600 0 d0 600 0 0 900 0 0 cm /I Do'),
      stream('/Type /XObject /Subtype /Image /Width 4 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /SMask 9 0 R',Buffer.from([255,0,0,0,255,0,0,0,255,255,0,255])),
      stream('/Type /XObject /Subtype /Image /Width 4 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray',Buffer.from([0,80,160,255])),
    ]);
    await page.locator('#file-input').setInputFiles({name:'glyphs.pdf',mimeType:'application/pdf',buffer:fixture});
    await waitForUI(page,()=>document.querySelector('.page[data-page="1"]')?.dataset.rendered==='true'&&document.querySelector('#viewer').getAttribute('aria-busy')==='false');
    const result=await page.evaluate(async()=>{
      const args=window.glyphPaintArgs,owned=args[1],expanded=owned.canvas,paint=pdfViewerHost.paintCanvas;
      const raster=async()=>{
        const canvas=document.createElement('canvas');await paint(canvas,owned,args[2],()=>true,args[4]);
        return [...canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data];
      };
      const first=await raster(),second=await raster();
      const selection=JSON.parse(await pdfViewerHost.pdf.call('select_page_text',[1,-1,-1,-1,-1]));
      const legacy=JSON.parse(await pdfViewerHost.pdf.call('render_page',[1,1,0,true]));
      const svg=JSON.parse(await pdfViewerHost.pdf.call('render_page',[1,1,0]));
      return {paints:window.glyphPaints,identity:owned.canvas===expanded,same:first.every((v,i)=>v===second[i]),
        ink:first.some((v,i)=>i%4!==3&&v<128),legacy:legacy.canvas.version,svg:svg.svg,
        selection:selection.selection.text,cache:JSON.parse(await pdfViewerHost.pdf.call('cache_info'))};
    });
    assert.equal(result.paints[0].version,2);assert.equal(result.paints[0].expanded,1);
    assert.ok(result.paints.every(p=>p.native===true),'The masked image glyph must keep this whole page on native Canvas');
    assert.equal(result.identity,true);assert.equal(result.same,true);assert.equal(result.ink,true);
    assert.equal(result.legacy,1);assert.match(result.svg,/<svg/);assert.match(result.selection,/AAA/);
    assert.equal(result.cache.compiled_resources.entries,1);assert.deepEqual(failures,[]);
  });
  await check('Scrolling during Retina rendering cancels old pages and keeps controls responsive',async()=>{
    await page.goto(base);
    await page.evaluate(()=>{
      const times=window.renderTicks=[];window.renderTimer=setInterval(()=>times.push(performance.now()),25);
      // Keep an actual Canvas task pending until scrolling has changed its
      // lifetime. Fast hosts may finish Worker parsing before we can scroll;
      // their Worker cancellation count cannot prove paint cancellation.
      const host=globalThis.pdfViewerHost,paint=host.paintCanvas;
      host.paintCanvas=async(...args)=>{
        const first=args[1].page===1&&!window.firstPaintPaused;
        if(first){
          window.firstPaintPaused=true;
          await new Promise(resolve=>window.resumeFirstPaint=resolve);
        }
        try{return await paint(...args);}
        catch(error){if(first&&error.name==='AbortError')window.firstPaintCancelled=true;throw error;}
      };
    });
    await page.locator('#file-input').setInputFiles({name:'reading.pdf',mimeType:'application/pdf',
      buffer:readingFixture(await readFile(resolve('assets/icc/rgb-gamma22.icc')))});
    await page.waitForFunction(()=>typeof window.resumeFirstPaint==='function'&&document.querySelector('#page-count').textContent==='/ 6'&&document.querySelector('.page[data-page="6"]')?.offsetHeight>0);
    assert.equal(await page.locator('.page[data-page="1"] canvas').count(),1,
      'The pending page exposes its Canvas so completed tiles can appear before the whole page finishes');
    assert.equal(await page.locator('.page[data-page="1"]').getAttribute('data-rendered'),'false');
    await page.locator('.page[data-page="6"]').evaluate(page=>page.scrollIntoView({block:'start'}));
    await page.waitForFunction(()=>document.querySelector('#page-number').value==='6');
    await page.evaluate(()=>window.resumeFirstPaint());
    await waitForUI(page,()=>document.querySelector('#page-number').value==='6'&&document.querySelector('.page[data-page="6"]')?.dataset.rendered==='true'&&document.querySelector('#viewer').getAttribute('aria-busy')==='false');
    assert.equal(await page.locator('#error').isVisible(),false);
    assert.match(await page.locator('#status').textContent(),/^6 pages · /,'Cancelled first-page work must not leave a permanent loading status');
    assert.equal(await page.evaluate(()=>window.firstPaintCancelled),true,'The actual renderer rejects the obsolete first-page paint after scrolling');
    assert.equal(await page.locator('.page[data-page="1"] canvas').count(),0,
      'A cancelled page removes its partial paint without retaining an obsolete Canvas');
    const tick=await page.evaluate(()=>{
      clearInterval(window.renderTimer);const times=window.renderTicks;
      return {count:times.length,maxGap:Math.max(0,...times.slice(1).map((time,i)=>time-times[i]))};
    });
    assert.ok(tick.count>2);assert.ok(tick.maxGap<1000,`Main-thread rendering blocked controls for ${tick.maxGap} ms`);
    await page.screenshot({path:resolve(output,'retina-reading.png')});
    for(const number of [1,2,3,4,5,6]){
      await page.locator('#page-number').fill(String(number));await page.locator('#page-number').press('Enter');
      await page.waitForFunction(n=>document.querySelector('.page[data-page="'+n+'"]')?.dataset.rendered==='true',number);
      const ink=await page.locator(`.page[data-page="${number}"] canvas`).evaluate(canvas=>{
        const small=document.createElement('canvas');small.width=small.height=32;
        const ctx=small.getContext('2d');ctx.drawImage(canvas,0,0,32,32);
        return ctx.getImageData(0,0,32,32).data.some((value,index)=>index%4!==3&&value<128);
      });
      assert.equal(ink,true,`Page ${number} must contain painted pixels`);
      assert.equal(await page.locator('#error').isVisible(),false);
    }
    assert.deepEqual(failures,[]);
  });
  await check('Recent pages reuse their surfaces, unchanged viewports stay cached and eviction releases Canvas storage',async()=>{
    await page.evaluate(async()=>{
      const {PageScheduler}=await import('./page-scheduler.js'),update=PageScheduler.prototype.update;
      const call=pdfViewerHost.pdf.call;
      const probe=window.pageCacheProbe={canvas:document.querySelector('.page[data-page="6"] canvas'),glyph:document.querySelector('.page[data-page="6"] .glyph-text'),requests:[],update,call};
      PageScheduler.prototype.update=function(...args){probe.scheduler=this;return update.apply(this,args);};
      pdfViewerHost.pdf.call=function(method,args,...rest){if(method==='render_page')probe.requests.push(args[0]);return call.call(this,method,args,...rest);};
    });
    const navigate=async number=>{
      await page.locator('#page-number').fill(String(number));await page.locator('#page-number').press('Enter');
      await page.waitForFunction(n=>document.querySelector('.page[data-page="'+n+'"]')?.dataset.rendered==='true',number);
    };
    try{
      await navigate(3);await navigate(6);
      const warm=await page.evaluate(async()=>{
        const p=pageCacheProbe,data=await (await import('./viewer.js')).runtimeDiagnostics();
        return {sameCanvas:p.canvas===document.querySelector('.page[data-page="6"] canvas'),sameGlyph:p.glyph===document.querySelector('.page[data-page="6"] .glyph-text'),requests:p.requests.filter(n=>n===6).length,cache:data.display_cache};
      });
      assert.equal(warm.sameCanvas,true,'Returning to a recent page reuses its completed Canvas');
      assert.equal(warm.sameGlyph,true,'Returning does not rebuild the native text layer');
      assert.equal(warm.requests,0,'A cached page needs no Worker rendering request');
      assert.ok(warm.cache.entries<=warm.cache.max_pages&&warm.cache.bytes<=warm.cache.budget_bytes);
      await page.setViewportSize({width:1280,height:920});
      await page.waitForTimeout(250);
      await page.locator('#zoom').selectOption('fit');
      await waitForUI(page,()=>document.querySelector('#viewer').getAttribute('aria-busy')==='false');
      const unchanged=await page.evaluate(()=>({same:pageCacheProbe.canvas===document.querySelector('.page[data-page="6"] canvas'),requests:pageCacheProbe.requests.filter(n=>n===6).length}));
      assert.equal(unchanged.same,true,'Height-only resize and the same zoom preserve the painted page');assert.equal(unchanged.requests,0);
      await page.evaluate(()=>{
        const p=pageCacheProbe;p.maxPages=p.scheduler.maxCachedPages;p.maxBytes=p.scheduler.maxCachedBytes;
        p.scheduler.maxCachedPages=1;p.scheduler.maxCachedBytes=p.canvas.width*p.canvas.height*4;
      });
      await page.locator('#view-mode').selectOption('page');
      await navigate(3);await navigate(6);
      const evicted=await page.evaluate(async()=>{
        const p=pageCacheProbe,data=await (await import('./viewer.js')).runtimeDiagnostics();
        return {released:p.canvas.width===0&&p.canvas.height===0,requests:p.requests.filter(n=>n===6).length,cache:data.display_cache};
      });
      assert.equal(evicted.released,true,'Eviction releases the old Canvas backing store');assert.equal(evicted.requests,1,'An evicted page renders exactly once on return');
      assert.equal(evicted.cache.entries,1);assert.ok(evicted.cache.evictions>0&&evicted.cache.bytes<=evicted.cache.budget_bytes);
      assert.equal(await page.locator('#error').isVisible(),false);assert.deepEqual(failures,[]);
    }finally{
      await page.evaluate(async()=>{
        const p=pageCacheProbe,{PageScheduler}=await import('./page-scheduler.js');
        PageScheduler.prototype.update=p.update;pdfViewerHost.pdf.call=p.call;
        if(p.maxPages!==undefined){p.scheduler.maxCachedPages=p.maxPages;p.scheduler.maxCachedBytes=p.maxBytes;}
      });
      await page.locator('#view-mode').selectOption('scroll');await page.setViewportSize({width:1280,height:900});
      await page.waitForTimeout(250);
    }
  });
  await check('Displayed selection bypasses the Worker and immediate copy uses the current source range',async()=>{
    await page.locator('#viewer').focus();
    const result=await page.evaluate(async()=>{
      const host=await import('./viewer.js'),root=document.querySelector('.page[data-page="6"]');
      const glyphs=[...root.querySelectorAll('.glyph')],node=index=>glyphs[index].querySelector('.glyph-text').firstChild;
      const select=end=>getSelection().setBaseAndExtent(node(0),0,node(end),node(end).length);
      const args=[6,+glyphs[0].dataset.item,0,+glyphs[25].dataset.item,node(25).length];
      const expected=JSON.parse(await pdfViewerHost.pdf.call('select_page_text',args)).selection;
      const call=pdfViewerHost.pdf.call,updates=[],pending=[],writeText=navigator.clipboard.writeText;let requests=0;
      const {PageScheduler}=await import('./page-scheduler.js'),update=PageScheduler.prototype.update;
      let scheduled=0;const schedules=[];PageScheduler.prototype.update=function(...args){scheduled++;schedules.push({page:args[0],scroll:document.querySelector('#viewer').scrollTop,stack:new Error().stack});return update.apply(this,args);};
      const listener=event=>{if(event.detail)updates.push(event.detail);};
      document.querySelector('#viewer').addEventListener('pdf-selection-change',listener);
      // Hold any selection request as if a synchronous render occupied the
      // Worker. Mounted text must stay selectable without waiting for it.
      pdfViewerHost.pdf.call=function(method,...args){
        if(method==='select_page_text'){requests++;return new Promise(resolve=>pending.push(()=>resolve(call.call(this,method,...args))));}
        return call.call(this,method,...args);
      };
      try{
        select(5);
        await Promise.race([host.readSelection(),new Promise((_,reject)=>setTimeout(()=>reject(Error('Displayed selection waited for the PDF Worker')),1000))]);
        // Initial pinning can also deliver one viewport observation. Measure
        // range extensions after that layout, with the pin set unchanged.
        await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
        scheduled=0;schedules.length=0;
        for(let end=6;end<=24;end++){select(end);await new Promise(requestAnimationFrame);}
        await host.readSelection();
        const before=updates.at(-1).text;
        // Copy within the same event turn, before selectionchange can publish
        // the longer range. Clipboard text and source quads must both be fresh.
        select(25);const data=new DataTransfer(),event=new ClipboardEvent('copy',{clipboardData:data,cancelable:true,bubbles:true});
        document.dispatchEvent(event);
        const actual=updates.at(-1).ranges[0];
        const buttonCopy=new Promise(resolve=>{navigator.clipboard.writeText=text=>{resolve(text);return Promise.resolve();};});
        select(24);document.querySelector('#copy-selection').click();
        const buttonText=await Promise.race([buttonCopy,new Promise((_,reject)=>setTimeout(()=>reject(Error('Copy button waited for the PDF Worker')),1000))]);
        return {requests,scheduled,schedules,before,buttonText,prevented:event.defaultPrevented,text:data.getData('text/plain'),actual,expected};
      }finally{
        navigator.clipboard.writeText=writeText;
        pdfViewerHost.pdf.call=call;PageScheduler.prototype.update=update;
        document.querySelector('#viewer').removeEventListener('pdf-selection-change',listener);
        for(const release of pending)release();
      }
    });
    assert.equal(result.requests,0,'Dragging displayed text does not enqueue PDF parsing work');
    assert.equal(result.scheduled,0,'Extending selection within a page does not reschedule page rendering: '+JSON.stringify(result.schedules));
    assert.notEqual(result.before,result.expected.text);
    assert.equal(result.buttonText,result.before,'The copy button refreshes a selection changed in the same event turn');
    assert.equal(result.prevented,true);assert.equal(result.text,result.expected.text);
    assert.deepEqual(result.actual,result.expected,'Local selection retains the exact Worker source indices and original quads');
    assert.equal(await page.locator('#error').isVisible(),false);assert.deepEqual(failures,[]);
  });
  await check('Transferable raster samples and warm replay match PNG after eviction, cancellation and reopen',async()=>{
    const result=await page.evaluate(async()=>{
      const api=pdfViewerHost,checked=raw=>{const value=JSON.parse(raw);if(!value.ok)throw Error(value.error);return value;};
      const source=()=>api.pdf.call('cache_info').then(checked).then(value=>value.raster_sources);
      const hash=async bytes=>[...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))].map(value=>value.toString(16).padStart(2,'0')).join('');
      const replaySamples=new Map();
      const paint=async(prepared,label)=>{
        const canvas=document.createElement('canvas');
        try{
          // This high-frequency fixture also has a one-pixel cold/warm Canvas
          // difference on the legacy PNG path. Compare equally warmed replay;
          // native decoded image samples are checked independently below.
          for(let repeat=0;repeat<2;repeat++){
            const painted=await api.paintCanvas(canvas,prepared,2,()=>true,()=>{throw Error('Unexpected process conversion');});
            if(painted.diagnostics.length)throw Error(JSON.stringify(painted.diagnostics));
            canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height);
          }
          const pixels=canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data;
          replaySamples.set(label,{width:canvas.width,pixels});
          return await hash(pixels);
        }
        finally{canvas.width=canvas.height=0;}
      };
      const initial=await source(),raw=await api.pdf.call('render_page',[1,1,0,true,true]),prepared=checked(raw),bitmapHash=await paint(prepared,'bitmap');
      let legacy;
      api.pdf.rasterImages=false;
      try{legacy=checked(await api.pdf.call('render_page',[1,1,0,true,true]));}finally{api.pdf.rasterImages=true;}
      if(JSON.stringify(legacy).includes('pdf-raster:'))throw Error('Legacy callers received a private raster ID');
      const legacyHash=await paint(legacy,'png');
      const normalized=plan=>JSON.stringify(plan).replace(/pdf-raster:[a-z0-9-]+:[0-9]+:[0-9]+|data:image\/png;base64,[A-Za-z0-9+/=]+/g,'<image>');
      const compare=(left,right)=>{
        const difference={pixels:0,maxDelta:0,bounds:[Infinity,Infinity,-1,-1],examples:[]};
        const a=replaySamples.get(left),b=replaySamples.get(right);
        for(let i=0;i<a.pixels.length;i+=4)if(a.pixels.slice(i,i+4).some((value,lane)=>value!==b.pixels[i+lane])){
          const x=i/4%a.width,y=Math.floor(i/4/a.width);difference.pixels++;
          difference.bounds=[Math.min(difference.bounds[0],x),Math.min(difference.bounds[1],y),Math.max(difference.bounds[2],x),Math.max(difference.bounds[3],y)];
          for(let lane=0;lane<4;lane++)difference.maxDelta=Math.max(difference.maxDelta,Math.abs(a.pixels[i+lane]-b.pixels[i+lane]));
          if(difference.examples.length<4)difference.examples.push({x,y,bitmap:[...a.pixels.slice(i,i+4)],png:[...b.pixels.slice(i,i+4)]});
        }
        return difference;
      };
      const difference={plansEqual:normalized(prepared.canvas)===normalized(legacy.canvas)};
      if(bitmapHash!==legacyHash)difference.initial=compare('bitmap','png');
      for(const key of ['layer','editor','annotations','accessibility','intent'])if(JSON.stringify(prepared[key])!==JSON.stringify(legacy[key]))throw Error('Semantic payload changed: '+key);
      if(!initial.supported)return {supported:false,bitmapHash,legacyHash,difference};
      const uri=raw.match(/pdf-raster:[a-z0-9-]+:[0-9]+:[0-9]+/)?.[0];if(!uri)throw Error('No transferable image in the reading fixture');
      const firstImage=(value,prefix)=>typeof value==='string'?(value.startsWith(prefix)?value:null):value&&typeof value==='object'?Object.values(value).map(child=>firstImage(child,prefix)).find(Boolean):null;
      const png=firstImage(legacy.canvas,'data:image/png'),load=(await import('./pdf-canvas.mjs')).loadPdfRaster;
      const decoded=[];
      for(const image of [await api.pdf.loadRaster(uri),await load(png)]){
        const canvas=document.createElement('canvas');
        try{canvas.width=image.width;canvas.height=image.height;canvas.getContext('2d').drawImage(image,0,0);decoded.push(await hash(canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data));}
        finally{image.close?.();canvas.width=canvas.height=0;}
      }
      if(decoded[0]!==decoded[1])throw Error('Transferred bitmap samples differ from decoded PNG');
      const before=await source();api.clearRenderAssets();
      const rebuiltHash=await paint(prepared,'rebuilt'),rebuilt=await source();
      if(rebuilt.rebuilds<=before.rebuilds)throw Error('Evicted bitmaps were not rebuilt from retained source rows');
      await api.pdf.call('render_page',[1,1,0,true,true]);
      const reused=await source();if(reused.transfers!==rebuilt.transfers)throw Error('Resident bitmaps were transferred twice');
      // A full-pool reset also evicts SVG glyph images. Use the same reset for
      // the PNG reference, while the native-sample assertion above isolates
      // source-row reconstruction from browser glyph rasterization.
      api.clearRenderAssets();const resetLegacyHash=await paint(legacy,'reset-png');
      api.clearRenderAssets();const controller=new AbortController();
      const cancelled=api.pdf.call('render_page',[1,1.25,0,true,true],{signal:controller.signal});controller.abort();
      try{await cancelled;throw Error('Cancelled raster render resolved');}catch(error){if(error.name!=='AbortError')throw error;}
      const afterCancel=await source();if(afterCancel.transfers<=reused.transfers)throw Error('Cancellation did not exercise an active transfer');
      if(api.renderAssetsDiagnostics().entries!==0)throw Error('Cancelled reply published bitmaps');
      const recovered=await paint(checked(await api.pdf.call('render_page',[1,1,0,true,true])),'recovered');
      if(bitmapHash!==rebuiltHash)difference.poolReset=compare('bitmap','rebuilt');
      if(legacyHash!==resetLegacyHash)difference.pngPoolReset=compare('png','reset-png');
      if(rebuiltHash!==resetLegacyHash)difference.rebuilt=compare('rebuilt','reset-png');
      if(recovered!==resetLegacyHash)difference.recovered=compare('recovered','reset-png');
      let reopenURI=uri;
      for(const method of ['set_font_fallbacks','apply_edits']){
        checked(await api.pdf.call(method,['[]']));
        if(api.renderAssetsDiagnostics().entries!==0)throw Error('Document invalidation retained decoded bitmaps: '+method);
        try{await api.pdf.loadRaster(reopenURI);throw Error('An expired raster was recreated');}catch(error){if(error.code!=='raster-expired')throw error;}
        const fresh=await api.pdf.call('render_page',[1,1,0,true,true]);checked(fresh);
        const next=fresh.match(/pdf-raster:[a-z0-9-]+:[0-9]+:[0-9]+/)?.[0];
        if(!next||next===reopenURI)throw Error('Document invalidation reused a stale raster ID');reopenURI=next;
      }
      api.pdf.close();if(api.renderAssetsDiagnostics().entries!==0)throw Error('Closing a document retained decoded rasters');
      return {supported:true,uri:reopenURI,bitmapHash,legacyHash,rebuiltHash,resetLegacyHash,recovered,sources:afterCancel,difference,imageBitmapLoader:typeof createImageBitmap};
    });
    assert.equal(result.bitmapHash,result.legacyHash,'Transferred and encoded images must paint identical full-page RGBA: '+JSON.stringify({difference:result.difference,imageBitmapLoader:result.imageBitmapLoader}));
    if(result.supported){
      if(result.bitmapHash!==result.rebuiltHash)console.log('Full-pool reset replay',JSON.stringify(result));
      assert.equal(result.rebuiltHash,result.resetLegacyHash,'Reconstructed bitmaps must match PNG after the same pool reset: '+JSON.stringify(result.difference));
      assert.equal(result.recovered,result.resetLegacyHash,'Cancelled transfers must recover exact PNG pixels: '+JSON.stringify(result.difference));
      assert(result.sources.bytes<=result.sources.budget_bytes&&result.sources.entries<=result.sources.max_entries);
      await page.locator('#file-input').setInputFiles({name:'bitmap-reopened.pdf',mimeType:'application/pdf',buffer:readingFixture(await readFile('assets/icc/rgb-gamma22.icc'))});
      await page.waitForFunction(()=>document.querySelector('#viewer').getAttribute('aria-busy')==='false'&&document.querySelector('#file-name').textContent==='bitmap-reopened.pdf'&&document.querySelector('.page[data-rendered="true"]'));
      const expired=await page.evaluate(async uri=>{try{await pdfViewerHost.pdf.loadRaster(uri);return null;}catch(error){return error.code;}},result.uri);
      assert.equal(expired,'raster-expired','A reopened Worker must reject IDs from the previous document');
    }
    assert.deepEqual(failures,[]);
  });
  await check('RGBA bitmaps and PNG fallbacks preserve pixels across unsupported hosts, transfer failure and source saturation',async()=>{
    for(const mode of ['rgba','unsupported','transfer-failure','full-budget']){
      const context=await browser.newContext({viewport:{width:1280,height:900},deviceScaleFactor:2}),errors=[];
      try{
        await context.route('**/pdf-worker.js',async route=>{
          const response=await route.fetch(),body=await response.text();
          const prefix=mode==='rgba'?'':mode==='unsupported'?'globalThis.OffscreenCanvas=undefined;':mode==='transfer-failure'?
            'const rasterTestPost=self.postMessage.bind(self);self.postMessage=(message,transfer)=>{if(Array.isArray(message.rasterImages)&&message.rasterImages.length)throw new DOMException("Unsupported bitmap transfer","DataCloneError");return rasterTestPost(message,transfer);};':
            'let rasterTestStore;Object.defineProperty(globalThis,"__moonbit_pdf_rasters",{configurable:true,get(){return rasterTestStore;},set(value){rasterTestStore=value;value.limit=0;}});';
          await route.fulfill({response,body:prefix+'\n'+body});
        });
        const fallback=await context.newPage();fallback.on('pageerror',error=>errors.push(String(error)));await fallback.goto(base);
        await fallback.locator('#file-input').setInputFiles({name:'fallback.pdf',mimeType:'application/pdf',buffer:mode==='rgba'?alphaRasterFixture():readingFixture(await readFile('assets/icc/rgb-gamma22.icc'))});
        await fallback.waitForFunction(()=>document.querySelector('#viewer').getAttribute('aria-busy')==='false'&&document.querySelector('#file-name').textContent==='fallback.pdf'&&document.querySelector('.page[data-page="1"][data-rendered="true"]'));
        const result=await fallback.evaluate(async mode=>{
          const raw=await pdfViewerHost.pdf.call('render_page',[1,1,0,true,true]),info=JSON.parse(await pdfViewerHost.pdf.call('cache_info'));
          const pixels=[];
          if(mode==='rgba'){
            const paint=async prepared=>{
              const c=document.createElement('canvas');try{await pdfViewerHost.paintCanvas(c,prepared,2,()=>true,()=>{throw Error('Unexpected process conversion');});return [...c.getContext('2d').getImageData(0,0,c.width,c.height).data];}finally{c.width=c.height=0;}
            };
            pixels.push(await paint(JSON.parse(raw)));pdfViewerHost.pdf.rasterImages=false;
            try{pixels.push(await paint(JSON.parse(await pdfViewerHost.pdf.call('render_page',[1,1,0,true,true]))));}finally{pdfViewerHost.pdf.rasterImages=true;}
          }
          return {ok:JSON.parse(raw).ok,privateURI:raw.includes('pdf-raster:'),sources:info.raster_sources,error:document.querySelector('#error').textContent,pixels};
        },mode);
        assert.equal(result.ok,true,mode);assert.equal(result.error,'',mode);
        if(mode==='rgba'){assert.deepEqual(result.pixels[0],result.pixels[1],'Interpolated RGBA and transparent-edge pixels must match PNG exactly');if(result.sources.supported)assert(result.privateURI);}
        else assert.equal(result.privateURI,false,mode);
        if(mode==='full-budget'){assert.equal(result.sources.bytes,0);assert.equal(result.sources.entries,0);if(result.sources.supported)assert(result.sources.rejections>0);}
        else if(mode!=='rgba')assert.equal(result.sources.supported,false,mode);
        assert.deepEqual(errors,[],mode);
      }finally{await context.close();}
    }
  });
  await check('A file chosen before the first controller frame waits for initialization',async()=>{
    for(const mode of ['open','replace','close']){
      const context=await browser.newContext({viewport:{width:1280,height:900}}),early=await context.newPage(),errors=[];
      try{
        early.on('pageerror',error=>{errors.push(String(error));console.error('Bootstrap error',error.stack||String(error));});
        await holdBootstrapFramesUntilFile(early);await early.goto(base);
        await early.locator('#file-input').setInputFiles({name:'early.pdf',mimeType:'application/pdf',buffer:layerFixture()});
        if(mode==='replace')await early.locator('#file-input').setInputFiles({name:'replacement.pdf',mimeType:'application/pdf',buffer:layerFixture()});
        if(mode==='close'){
          await early.evaluate(async()=>{(await import('./viewer.js')).closeDocument();});
          await waitForUI(early,()=>document.querySelector('#file-name').textContent==='No document open'&&document.querySelector('#page-count').textContent==='/ 0'&&document.querySelector('#viewer').getAttribute('aria-busy')==='false');
          assert.equal(await early.evaluate(()=>pdfViewerHost.pdf.diagnostics().worker),false,'Closing during bootstrap must cancel the pending open');
        }else{
          await waitForUI(early,name=>document.querySelector('#file-name').textContent===name&&document.querySelector('#page-count').textContent==='/ 2'&&document.querySelector('#viewer').getAttribute('aria-busy')==='false'&&document.querySelector('.page[data-rendered="true"]'),mode==='replace'?'replacement.pdf':'early.pdf');
        }
        assert.equal(await early.locator('#error').isVisible(),false);assert.deepEqual(errors,[],mode);
      }finally{await context.close();}
    }
  });
  ok=true;
}catch(error){
  console.error(current,error);
  if(page)console.error('Viewer state',await page.evaluate(()=>({
    count:document.querySelector('#page-count')?.textContent,
    countText:document.querySelector('#page-count')?.innerText,
    file:document.querySelector('#file-name')?.textContent,
    busy:document.querySelector('#viewer')?.getAttribute('aria-busy'),
    error:document.querySelector('#error')?.textContent,
    worker:globalThis.pdfViewerHost?.pdf.diagnostics(),
    mainIccReady:!!globalThis.__moonbit_pdf_icc,
  })).catch(()=>null));
  if(page)await page.screenshot({path:resolve(output,'failure.png'),fullPage:true}).catch(()=>{});
  process.exitCode=1;
}finally{
  await writeFile(resolve(output,'report.json'),JSON.stringify({ok,engine,failed:ok?null:current,checks,failures,requests},null,2));
  if(browser)await browser.close();
  await new Promise(resolve=>server.close(resolve));
  console.log(output);
}

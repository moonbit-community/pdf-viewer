#!/usr/bin/env node
import assert from 'node:assert/strict';
import {waitForUI} from './browser_ui.mjs';
import {createRequire} from 'node:module';
import {mkdirSync,writeFileSync,readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {layerFixture} from './pixels/layer_fixtures.mjs';

const require=createRequire(resolve('tools/test-host/package.json'));
const {chromium}=require('playwright');
const {createCanvas,DOMMatrix,ImageData,Path2D}=require('@napi-rs/canvas');
Object.assign(globalThis,{DOMMatrix,ImageData,Path2D,OffscreenCanvas:function(w,h){return createCanvas(w,h);}});
const pdfjs=await import(pathToFileURL(require.resolve('pdfjs-dist/legacy/build/pdf.mjs')));
const base=process.argv[2]||'http://127.0.0.1:4315';
const output=resolve('_build/layers-test-'+Date.now());mkdirSync(output,{recursive:true});
const source=resolve(output,'layers.pdf'),large=layerFixture({large:true});writeFileSync(source,layerFixture());
const browser=await chromium.launch({executablePath:process.env.PDF_CHROMIUM||chromium.executablePath(),headless:true,args:['--no-sandbox']});
const page=await browser.newPage({viewport:{width:1280,height:900},acceptDownloads:true});
page.setDefaultTimeout(30000);
const checks=[],errors=[],colourComparisons=[];let current='initialization',ok=false;
page.on('pageerror',error=>errors.push(String(error)));
async function check(name,work){current=name;await work();checks.push(name);console.log('PASS '+name);}
async function idle(){
  await waitForUI(page,()=>Boolean(document.querySelector('#viewer')?.getAttribute('aria-busy')==='false' &&
      !document.querySelector('#edit-toggle').disabled &&
      document.querySelector('#layers-config')?.disabled!==true &&
      document.querySelector('.page[data-page="'+document.querySelector('#page-number').value+'"][data-rendered="true"]')));
}
async function waitLayers(expected,config){
  await page.waitForFunction(({expected,config})=>(config===undefined||document.querySelector('.layers-panel')?.dataset.configIndex===String(config)) && Object.entries(expected).every(([id,visible])=>{
    const control=document.querySelector('#layer-'+id);
    return control && control.checked===visible;
  })&&!document.querySelector('#layers-config').disabled,{expected,config});await idle();
}
const text=()=>page.locator('#pages .page[data-page="1"] .text-layer').evaluate(node=>node.textContent);
const layerText=result=>result.layer.items.map(item=>item.text).join('');
async function rpc(method,args=[]){return JSON.parse(await page.evaluate(async({method,args})=>pdfViewerHost.pdf.call(method,args),{method,args}));}
async function open(){
  await page.goto(base);await page.locator('#file-input').setInputFiles(source);await idle();
  await page.locator('#layers-toggle').click();await page.waitForSelector('#layers-config');await idle();
}
const samples=(ctx,m)=>[25,65,105,145].map(x=>{
  const y=20,px=Math.round(m[0]*x+m[2]*y+m[4]),py=Math.round(m[1]*x+m[3]*y+m[5]);
  return [...ctx.getImageData(px,py,1,1).data].slice(0,3);
});
const displaySamples=()=>page.locator('#pages .page[data-page="1"] .paint-layer canvas').evaluate(canvas=>{
  const editor=canvas.closest('.page').querySelector('.editor-layer'),view=JSON.parse(editor.dataset.viewport);
  const m=view.matrix.map(n=>n*canvas.width/view.width);
  return [25,65,105,145].map(x=>[...canvas.getContext('2d').getImageData(Math.round(m[0]*x+m[2]*20+m[4]),Math.round(m[1]*x+m[3]*20+m[5]),1,1).data].slice(0,3));
});
const blue=[0,0,255],red=[255,0,0],pink=[255,0,255],green=[0,255,0],white=[255,255,255];
try{
  await open();
  await check('Rabbita layers show Unicode nested order usage hints and locked controls',async()=>{
    assert.match(await page.locator('.layers-panel').innerText(),/图层[\s\S]*中文[\s\S]*Nested[\s\S]*Beta/);
    assert.equal(await page.locator('#layer-10').isDisabled(),true);
    assert.match(await page.locator('#layer-8').locator('..').innerText(),/打印隐藏/);
    assert.match(await page.locator('#layer-9').locator('..').innerText(),/打印可见/);
    assert.deepEqual(await displaySamples(),[blue,white,pink,white]);
    assert.equal(await page.locator('#pages [data-field-name="layer-field"]').count(),0);
  });
  await check('Layer radio toggles invalidate paint text annotations and worker caches',async()=>{
    await rpc('render_page',[2,1,0]);
    await page.locator('#layer-7').click();await waitLayers({6:false,7:true});
    assert.match(await text(),/Beta/);assert.doesNotMatch(await text(),/Alpha|Member/);
    assert.deepEqual(await displaySamples(),[white,red,pink,white]);
    const entries=await page.locator('#pages .page[data-page="1"] .editor-layer').evaluate(node=>JSON.parse(node.dataset.entries));
    assert.equal(entries.find(entry=>entry.field_name==='layer-field').values[0],'Before');
    assert.deepEqual(await page.locator('#pages .annotation-target').evaluateAll(nodes=>nodes.map(node=>Number(node.dataset.annotationIndex))),[0,1]);
    const second=await rpc('render_page',[2,1,0]);assert.match(layerText(second),/Second Beta/);
    await page.locator('#layer-6').click();await waitLayers({6:true,7:false});
    assert.equal(await page.locator('#pages [data-field-name="layer-field"]').count(),0);
    assert.equal(await page.locator('#pages .annotation-target').count(),0);
    assert.deepEqual((await rpc('render_page',[2,1,0])).layer.items,[]);
  });
  await check('Layer configurations reset overrides and locked radio failures stay atomic',async()=>{
    await page.locator('#layers-config').selectOption('0');await waitLayers({6:false,7:true,8:false,9:false},0);
    await page.locator('#layer-7').click();await waitLayers({7:false});
    await page.locator('#layers-reset').click();await waitLayers({7:true});
    await page.locator('#layers-config').selectOption('1');await waitLayers({6:true,7:false},1);
    await page.evaluate(()=>{
      const original=pdfViewerHost.pdf.call.bind(pdfViewerHost.pdf);
      pdfViewerHost.pdf.call=async(method,args,options)=>{
        const result=await original(method,args,options);
        if(method==='set_optional_content_visibility'&&!JSON.parse(result).ok){
          // Reproduce native property drift while a rejected response arrives.
          document.querySelector('#layer-7').checked=true;
          pdfViewerHost.pdf.call=original;
        }
        return result;
      };
    });
    await page.locator('#layer-7').click();
    await page.waitForFunction(()=>!document.querySelector('#error').hidden && !document.querySelector('#layers-config').disabled);
    await idle();
    assert.equal(await page.locator('#layer-7').isChecked(),false);
    const failed=await rpc('set_optional_content_visibility',[6,false]);assert.equal(failed.ok,false);assert.equal(failed.code,'layer-error');
    assert.match(await text(),/Alpha/);assert.doesNotMatch(await text(),/Beta/);
    await page.evaluate(()=>{
      const original=pdfViewerHost.pdf.call.bind(pdfViewerHost.pdf);
      pdfViewerHost.pdf.call=async(method,args,options)=>{
        const result=await original(method,args,options);
        if(method==='set_optional_content_config'&&args[0]===-1){
          pdfViewerHost.pdf.call=original;
          window.layerConfigResponseReady=true;
          await new Promise(resolve=>{window.releaseLayerConfigResponse=resolve;});
        }
        return result;
      };
    });
    await page.locator('#layers-config').selectOption('-1');
    await page.waitForFunction(()=>window.layerConfigResponseReady);
    // Both configurations have the same checked groups; wait for the accepted
    // configuration rather than mistaking the previous group state for success.
    assert.equal(await page.locator('.layers-panel').getAttribute('data-config-index'),'1');
    assert.equal(await page.locator('#layers-config').isDisabled(),true);
    await page.evaluate(()=>{window.releaseLayerConfigResponse();});
    await waitLayers({6:true,7:false},-1);
    assert.equal(await page.locator('#error').isVisible(),false);
  });
  await check('Layer changes clear stale native selection and search results',async()=>{
    await page.evaluate(async()=>{const host=await import('./viewer.js');await host.selectAllText();});
    await page.locator('#search-query').fill('Alpha');
    await page.waitForFunction(()=>document.querySelector('#search-status').textContent==='1 / 1');
    await page.locator('#layer-7').click();await waitLayers({6:false,7:true});
    assert.equal(await page.locator('#search-query').inputValue(),'');
    assert.equal(await page.locator('.pdf-search-hit').count(),0);
    assert.equal(await page.evaluate(()=>getSelection().toString()),'');
    assert.deepEqual((await rpc('search_pdf',['Alpha',false,false,false])).results,[]);
  });
  await check('Layer usage prints actual Canvas output against pinned PDF.js intent',async()=>{
    await page.locator('#layers-reset').click();await waitLayers({6:true,7:false,8:true,9:false});
    await page.evaluate(()=>{window.print=()=>{window.layerPrintCalls=(window.layerPrintCalls||0)+1;};});
    await page.locator('#print').click();
    await page.waitForFunction(()=>window.layerPrintCalls===1 && !document.querySelector('#print').disabled);
    assert.equal(await page.locator('#print-pages .page').count(),2);
    const printed=await page.locator('#print-pages .page[data-page="1"] canvas').evaluate(canvas=>
      [25,65,105,145].map(x=>[...canvas.getContext('2d').getImageData(Math.round(x*canvas.width/200),Math.round(280*canvas.height/300),1,1).data].slice(0,3)));
    const loading=pdfjs.getDocument({data:new Uint8Array(readFileSync(source)),useSystemFonts:true,isEvalSupported:false});
    const document=await loading.promise,reference=await document.getPage(1),viewport=reference.getViewport({scale:1});
    const canvas=createCanvas(viewport.width,viewport.height),ctx=canvas.getContext('2d');
    await reference.render({canvasContext:ctx,viewport,intent:'print'}).promise;
    assert.deepEqual(printed,samples(ctx,viewport.transform));assert.deepEqual(printed,[blue,white,white,green]);
    await loading.destroy();
    await page.locator('#layer-9').click();await waitLayers({9:true});
    assert.equal(await page.locator('#print-pages .page').count(),0);
    assert.deepEqual(await displaySamples(),[blue,white,pink,green]);
    await page.locator('#layer-8').click();await waitLayers({8:false});
    assert.doesNotMatch(layerText(await rpc('render_print_page',[1,1,0])),/Screen/);
  });
  await check('Layer changes regenerate thumbnails with current visibility',async()=>{
    await page.locator('#thumbnail-toggle').click();
    await page.waitForFunction(()=>document.querySelector('.thumbnail-preview canvas')?.width>0);
    const old=await page.locator('.thumbnail-preview').first().evaluate(node=>node.querySelector('canvas').toDataURL());
    await page.locator('#layers-toggle').click();await page.waitForSelector('#layers-config');
    await page.locator('#layer-7').click();await waitLayers({6:false,7:true});
    await page.locator('#thumbnail-toggle').click();
    await page.waitForFunction(old=>{const canvas=document.querySelector('.thumbnail-preview canvas');return canvas?.width>0 && canvas.toDataURL()!==old;},old);
  });
  await check('Layer selection survives field editing undo redo and saved original configuration',async()=>{
    await page.locator('#layers-toggle').click();await page.waitForSelector('#layers-config');
    await page.locator('#edit-toggle').click();await page.waitForFunction(()=>!document.querySelector('#editor-toolbar').hidden&&!document.querySelector('#edit-toggle').disabled);await idle();
    const field=page.locator('#pages [data-field-name="layer-field"]');await field.fill('Edited layer field');await field.press('Tab');
    await page.waitForFunction(()=>document.querySelector('#editor-dirty').textContent==='未保存'&&!document.querySelector('#edit-toggle').disabled);await idle();
    assert.match(await text(),/Beta/);assert.doesNotMatch(await text(),/Alpha/);
    await page.locator('#edit-undo').click();await page.waitForFunction(()=>document.querySelector('[data-field-name="layer-field"]')?.value==='Before'&&!document.querySelector('#edit-toggle').disabled);
    await page.locator('#edit-redo').click();await page.waitForFunction(()=>document.querySelector('[data-field-name="layer-field"]')?.value==='Edited layer field'&&!document.querySelector('#edit-toggle').disabled);
    assert.match(await text(),/Beta/);
    await field.fill('Active before layer toggle');
    await page.locator('#layer-6').click();await waitLayers({6:true,7:false});
    assert.equal(await page.locator('#pages [data-field-name="layer-field"]').count(),0);
    await page.locator('#layer-7').click();await waitLayers({6:false,7:true});
    assert.equal(await field.inputValue(),'Active before layer toggle');
    const downloaded=page.waitForEvent('download');await page.locator('#download').click();const download=await downloaded;
    const saved=resolve(output,'saved.pdf');await download.saveAs(saved);
    await page.waitForFunction(()=>document.querySelector('#editor-status').textContent.startsWith('已下载')&&document.querySelector('#editor-dirty').textContent==='');
    const loading=pdfjs.getDocument({data:new Uint8Array(readFileSync(saved)),isEvalSupported:false}),document=await loading.promise;
    const config=await document.getOptionalContentConfig();assert.equal(config.getGroup('6R').visible,true);assert.equal(config.getGroup('7R').visible,false);
    const annotations=await (await document.getPage(1)).getAnnotations();assert.equal(annotations.find(item=>item.fieldName==='layer-field').fieldValue,'Active before layer toggle');await loading.destroy();
  });
  await check('HTTP Range hydration and editor completion retain layer selection',async()=>{
    await page.route('**/layer-range.pdf',async route=>{
      const header=route.request().headers().range;
      if(!header)return route.fulfill({status:200,headers:{'content-type':'application/pdf','content-length':String(large.length),etag:'"layer-v1"'},body:large});
      const [,a,b]=/^bytes=(\d+)-(\d+)$/.exec(header),start=Number(a),end=Math.min(large.length,Number(b)+1);
      await route.fulfill({status:206,headers:{'content-type':'application/pdf',etag:'"layer-v1"','content-range':`bytes ${start}-${end-1}/${large.length}`},body:large.subarray(start,end)});
    });
    await page.goto(base+'/?file='+encodeURIComponent(base+'/layer-range.pdf'));await idle();
    await page.locator('#layers-toggle').click();await page.waitForSelector('#layers-config');
    await page.locator('#layer-7').click();await waitLayers({6:false,7:true});
    const before=await page.evaluate(async()=>(await (await import('./viewer.js')).runtimeDiagnostics()).cache.range);
    assert.equal(before.mode,'range');assert.ok(before.received_bytes<large.length/10,JSON.stringify(before));
    await rpc('render_page',[2,1,0]);assert.match(await text(),/Beta/);
    await page.locator('#edit-toggle').click();await page.waitForFunction(()=>!document.querySelector('#editor-toolbar').hidden&&!document.querySelector('#edit-toggle').disabled);await idle();
    assert.equal(await page.locator('#layer-7').isChecked(),true);assert.match(await text(),/Beta/);assert.doesNotMatch(await text(),/Alpha/);
    assert.equal((await rpc('optional_content_info')).layers.groups.find(group=>group.id===7).visible,true);
    assert.equal(layerText(await rpc('render_page',[2,1,0])),'Second Beta');
  });
  await check('Layer sidebar follows wrapped reader and editor toolbars',async()=>{
    for(const width of [680,1280]){
      await page.setViewportSize({width,height:900});
      await page.waitForFunction(()=>{
        const viewer=document.querySelector('#viewer'),page=document.querySelector('#pages .page[data-page="1"]');
        const layer=page.querySelector('.editor-layer');if(!layer)return false;
        const viewport=JSON.parse(layer.dataset.viewport);
        const scale=Math.max(.1,Math.min(4,(viewer.clientWidth-64)/200));
        return Math.abs(viewport.scale-scale)<1e-6 && viewer.getAttribute('aria-busy')==='false';
      });await idle();
      const geometry=await page.evaluate(()=>{
        const sidebar=document.querySelector('#sidebar').getBoundingClientRect(),viewer=document.querySelector('#viewer').getBoundingClientRect();
        const toolbar=document.querySelector('#editor-toolbar').getBoundingClientRect();
        const button=document.querySelector('#print'),box=button.getBoundingClientRect();
        return {top:sidebar.top,viewerTop:viewer.top,bottom:sidebar.bottom,viewerBottom:viewer.bottom,toolbarBottom:toolbar.bottom,printAccessible:document.elementFromPoint(box.x+box.width/2,box.y+box.height/2)===button};
      });
      assert.equal(geometry.top,geometry.viewerTop);assert.equal(geometry.bottom,geometry.viewerBottom);
      assert.ok(geometry.top>=geometry.toolbarBottom);assert.equal(geometry.printAccessible,true);
    }
  });
  await check('Late layer replies cannot publish into a replacement document',async()=>{
    await page.evaluate(()=>{
      window.print=()=>{window.staleLayerPrint=true;};
      const original=pdfViewerHost.pdf.call.bind(pdfViewerHost.pdf);
      pdfViewerHost.pdf.call=async(method,args,options)=>{
        if(method==='set_optional_content_visibility'){
          const result=await original(method,args,options);window.layerReplyWaiting=true;
          await new Promise(resolve=>window.releaseLayerReply=resolve);return result;
        }
        return original(method,args,options);
      };
    });
    await page.locator('#layer-6').click();await page.waitForFunction(()=>window.layerReplyWaiting===true);
    await page.keyboard.press('Control+p');
    await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
    assert.equal(await page.evaluate(()=>Boolean(window.staleLayerPrint)),false);
    await page.locator('#file-input').setInputFiles(source);
    await page.waitForFunction(()=>document.querySelector('#file-name').textContent==='layers.pdf'&&document.querySelector('#editor-toolbar').hidden);
    await page.evaluate(()=>window.releaseLayerReply());await idle();
    assert.match(await text(),/Alpha/);assert.doesNotMatch(await text(),/Beta/);
    assert.equal((await rpc('optional_content_info')).layers.groups.find(group=>group.id===6).visible,true);
    assert.equal(await page.locator('#error').isVisible(),false);
    assert.equal(await page.evaluate(()=>Boolean(window.staleLayerPrint)),false);
  });
  await check('Real PDF.js optional-content fixtures toggle Form transparency and painted colours',async()=>{
    for(const name of ['issue17679.pdf','issue17679_2.pdf']){
      const file=resolve('reference/pdf.js/test/pdfs',name);
      await page.goto(base);await page.locator('#file-input').setInputFiles(file);await idle();
      await page.locator('#layers-toggle').click();await page.waitForSelector('#layers-config');
      const loading=pdfjs.getDocument({data:new Uint8Array(readFileSync(file)),isEvalSupported:false}),document=await loading.promise;
      const reference=await document.getPage(1),viewport=reference.getViewport({scale:1}),config=await document.getOptionalContentConfig();
      for(const [greenVisible,redVisible] of [[true,true],[true,false],[false,true]]){
        for(const [id,visible] of [[6,greenVisible],[7,redVisible]]){
          if(await page.locator('#layer-'+id).isChecked()!==visible){await page.locator('#layer-'+id).click();await waitLayers({[id]:visible});}
          config.setVisibility(id+'R',visible);
        }
        const canvas=createCanvas(viewport.width,viewport.height),ctx=canvas.getContext('2d');
        await reference.render({canvasContext:ctx,viewport,optionalContentConfigPromise:Promise.resolve(config)}).promise;
        const expected=[];
        for(const y of [20,60,95])for(const x of [10,25,50,75,90])expected.push([...ctx.getImageData(x,y,1,1).data].slice(0,3));
        const actual=await page.locator('#pages .paint-layer canvas').evaluate(canvas=>{
          const result=[],ctx=canvas.getContext('2d');
          for(const y of [20,60,95])for(const x of [10,25,50,75,90])result.push([...ctx.getImageData(Math.round(x*canvas.width/100),Math.round(y*canvas.height/100),1,1).data].slice(0,3));
          return result;
        });
        const maxChannelDelta=Math.max(...actual.flatMap((rgb,i)=>rgb.map((value,c)=>Math.abs(value-expected[i][c]))));
        colourComparisons.push({file:name,visible:[greenVisible,redVisible],samples:expected.length,max_channel_delta:maxChannelDelta});
        // pdflite's CSS byte rounding and PDF.js's float-to-byte path differ
        // by one byte for the fixture's 0.3 green component. Visibility and
        // compositing must still agree at every measured point.
        assert.ok(maxChannelDelta<=1,name+' '+JSON.stringify(colourComparisons.at(-1)));
      }
      await loading.destroy();
    }
  });
  assert.deepEqual(errors,[]);ok=true;
}catch(error){
  console.error(current,error);
  console.error('Layer failure state',JSON.stringify(await page.evaluate(async()=>({
    manifest:JSON.parse(await pdfViewerHost.pdf.call('optional_content_info',[])),
    config:document.querySelector('#layers-config')?.value,
    controls:[...document.querySelectorAll('[data-layer-id]')].map(node=>({id:node.id,checked:node.checked,disabled:node.disabled})),
    error:document.querySelector('#error')?.textContent,
  })).catch(()=>null)));
  await page.screenshot({path:resolve(output,'failure.png'),fullPage:true}).catch(()=>{});throw error;
}finally{
  writeFileSync(resolve(output,'report.json'),JSON.stringify({ok,failed:ok?null:current,checks,errors,colour_comparisons:colourComparisons},null,2));await browser.close();console.log(output);
}

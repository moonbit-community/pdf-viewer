#!/usr/bin/env node
// Exercise the published artifact through a repository subpath, with no dev
// server, comparison checkout or test PDFs in the site directory.
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {createRequire} from 'node:module';
import {mkdir,readFile,stat,writeFile} from 'node:fs/promises';
import {extname,resolve,sep} from 'node:path';
import {layerFixture} from './pixels/layer_fixtures.mjs';
import {xfaFixture} from './pixels/readonly_fixtures.mjs';
import {waitForUI} from './browser_ui.mjs';

const require=createRequire(resolve('tools/test-host/package.json'));
const {chromium}=require('playwright');
const root=resolve('_build/pages'),prefix='/pdf-viewer/';
const output=resolve('_build/pages-test-'+Date.now());await mkdir(output,{recursive:true});
const mime={'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8',
  '.js':'text/javascript; charset=utf-8','.mjs':'text/javascript; charset=utf-8',
  '.wasm':'application/wasm','.pdf':'application/pdf','.svg':'image/svg+xml'};
const requests=[],failures=[],checks=[];let browser,page,ok=false,current='initialization';
const server=createServer(async(request,response)=>{
  const url=new URL(request.url,'http://localhost');requests.push(url.pathname);
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
const base='http://127.0.0.1:'+server.address().port+prefix;
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
try{
  browser=await chromium.launch({executablePath:process.env.PDF_CHROMIUM||chromium.executablePath(),
    headless:true,args:['--no-sandbox']});
  page=await browser.newPage({viewport:{width:1280,height:900},acceptDownloads:true});
  page.setDefaultTimeout(30000);
  page.on('request',request=>{
    if(/^https?:/.test(request.url())&&
      (new URL(request.url()).origin!==new URL(base).origin||!['GET','HEAD'].includes(request.method())))
      failures.push(request.method()+' '+request.url());
  });
  page.on('pageerror',error=>failures.push(String(error)));
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
  });
  await check('Packaged Worker paints a local PDF without network uploads',async()=>{
    await page.locator('#file-input').setInputFiles({name:'local.pdf',mimeType:'application/pdf',buffer:layerFixture()});
    await idle('local.pdf');
    assert.equal(await page.locator('#page-count').innerText(),'/ 2');
    const painted=await page.locator('#pages .page[data-page="1"] canvas').evaluate(canvas=>{
      const ctx=canvas.getContext('2d'),bytes=ctx.getImageData(0,0,canvas.width,canvas.height).data;
      return canvas.width>0&&canvas.height>0&&bytes.some((value,index)=>index%4!==3&&value<128);
    });
    assert.equal(painted,true);
    await page.locator('#search-query').fill('Alpha');
    await page.waitForFunction(()=>document.querySelector('#search-status').textContent==='1 / 1');
    assert.ok(requests.includes(prefix+'pdf-worker.js'));
    assert.ok(requests.includes(prefix+'_generated/pdf.js'));
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
    await page.waitForFunction(()=>document.querySelector('#editor-dirty').textContent==='未保存'&&!document.querySelector('#edit-toggle').disabled);
    const downloaded=page.waitForEvent('download');await page.locator('#download').click();
    const saved=resolve(output,'saved.pdf');await (await downloaded).saveAs(saved);
    await page.waitForFunction(()=>document.querySelector('#editor-status').textContent.startsWith('已下载')&&document.querySelector('#editor-dirty').textContent==='');
    const bytes=await readFile(saved);assert.equal(bytes.subarray(0,5).toString(),'%PDF-');
    await page.locator('#file-input').setInputFiles({name:'saved.pdf',mimeType:'application/pdf',buffer:bytes});await idle('saved.pdf');
    await page.locator('#layers-toggle').click();await page.locator('#layer-7').click();
    await page.waitForFunction(()=>document.querySelector('#layer-7').checked&&!document.querySelector('#layers-config').disabled);
    await page.locator('#edit-toggle').click();
    await page.waitForFunction(()=>!document.querySelector('#editor-toolbar').hidden&&!document.querySelector('#edit-toggle').disabled);
    assert.equal(await field.inputValue(),'Saved from GitHub Pages');
  });
  await check('Packaged XFA module and CSS render native readonly fields',async()=>{
    await page.goto(base);
    await page.locator('#file-input').setInputFiles({name:'xfa.pdf',mimeType:'application/pdf',buffer:xfaFixture()});
    await page.waitForFunction(()=>document.querySelector('.xfaLayer input')?.value==='Bound value');
    const input=page.locator('.xfaLayer input').first();
    assert.equal(await input.isEditable(),false);
    assert.ok(requests.includes(prefix+'vendor/xfa/xfa.mjs'));
    assert.ok(requests.includes(prefix+'vendor/xfa/xfa.css'));
  });
  await check('All codec assets load with Wasm MIME types below the subpath',async()=>{
    for(const asset of ['vendor/jbig2/jbig2.wasm','vendor/lcms-wasm/lcms.wasm']){
      const response=await fetch(base+asset);assert.equal(response.status,200);
      assert.equal(response.headers.get('content-type'),'application/wasm');
      const bytes=new Uint8Array(await response.arrayBuffer());assert.deepEqual([...bytes.slice(0,4)],[0,97,115,109]);
    }
    const licenses=await fetch(base+'vendor/jbig2/LICENSE_JBIG2');assert.equal(licenses.status,200);
    assert.ok((await licenses.text()).length>100);
    assert.deepEqual(failures,[]);
    assert.ok(requests.length>10&&requests.every(path=>path.startsWith(prefix)));
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
  })).catch(()=>null));
  if(page)await page.screenshot({path:resolve(output,'failure.png'),fullPage:true}).catch(()=>{});
  process.exitCode=1;
}finally{
  await writeFile(resolve(output,'report.json'),JSON.stringify({ok,failed:ok?null:current,checks,failures,requests},null,2));
  if(browser)await browser.close();
  await new Promise(resolve=>server.close(resolve));
  console.log(output);
}

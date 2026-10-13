#!/usr/bin/env node
// Exercise character ranges and persisted selection highlights through the
// compiled MoonBit app, native DOM ranges, Worker, and downloaded PDF bytes.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {mkdir,writeFile,readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {makePdf,stream,xfaFixture,xfaAccessFixture} from './pixels/readonly_fixtures.mjs';
import {waitForUI} from './browser_ui.mjs';
import {namespaceFixture} from './pixels/accessibility_fixtures.mjs';

const require=createRequire(resolve('tools/test-host/package.json'));
const engine=process.env.PDF_BROWSER||'chromium';
const launcher=require('playwright')[engine];
assert(launcher,'Unknown browser');
const base=process.argv[2]||'http://127.0.0.1:4318';
const output=resolve('_build/text-interaction-'+engine+'-'+Date.now());
await mkdir(output,{recursive:true});
const cmap='/CIDInit /ProcSet findresource begin 12 dict begin begincmap /CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def /CMapName /Text def /CMapType 2 def 1 begincodespacerange <00> <FF> endcodespacerange 1 beginbfchar <58> <006600660069> endbfchar endcmap CMapName currentdict /CMap defineresource pop end end';
const fixture=makePdf([
 '<< /Type /Catalog /Pages 2 0 R >>',
 '<< /Type /Pages /Count 2 /Kids [3 0 R 4 0 R] >>',
 '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 240 200] /Resources << /Font << /F1 5 0 R >> >> /Contents 6 0 R >>',
 '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 240 200] /Rotate 90 /Resources << /Font << /F1 5 0 R >> >> /Contents 8 0 R >>',
 '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding /ToUnicode 7 0 R >>',
 stream('', 'BT /F1 20 Tf 1 .2 .15 1 30 100 Tm (XAB) Tj ET'),
 stream('', cmap),
 stream('', 'BT /F1 20 Tf 30 100 Td (AB) Tj ET'),
]);
const browser=await launcher.launch({headless:true});
const page=await browser.newPage({viewport:{width:1280,height:900}});
page.setDefaultTimeout(30000);
const errors=[],checks=[];
const canonicalQuads=quads=>quads.map(quad=>Object.fromEntries(Object.entries(quad).map(([key,point])=>
 [key,{x:Math.round(point.x*1e9)/1e9,y:Math.round(point.y*1e9)/1e9}])));
page.on('pageerror',error=>errors.push(String(error)));
page.on('dialog',dialog=>dialog.accept());
async function check(name,run){await run();checks.push({name,ok:true});console.log('PASS '+name);}
async function load(){
 await page.locator('#file-input').setInputFiles({name:'text-ranges.pdf',mimeType:'application/pdf',buffer:fixture});
 await waitForUI(page,()=>document.querySelector('.page[data-page="1"]')?.dataset.rendered==='true'&&document.querySelector('#viewer').getAttribute('aria-busy')==='false');
}
try{
 await page.goto(base);await page.locator('#open-empty').waitFor({state:'visible'});
 await check('Search paints precise ranges across a multi-character glyph and another item',async()=>{
  await load();
  const result=await page.evaluate(async()=>{
   const viewer=await import('./viewer.js');
   const glyphs=[...document.querySelectorAll('.page[data-page="1"] .glyph-text')];
   const first=glyphs.find(node=>node.textContent==='ffi');
   const range=document.createRange();range.setStart(first.firstChild,0);range.setEnd(first.firstChild,1);
   const selection=getSelection();selection.removeAllRanges();selection.addRange(range);
   const nodes=glyphs.map(node=>node.firstChild);
   document.getElementById('search-query').value='fiA';await viewer.performSearch();
   return {ranges:[...CSS.highlights.get('pdf-search-active')].map(range=>range.toString()),
    unchanged:glyphs.every((node,index)=>node.firstChild===nodes[index]),selection:selection.toString(),
    precise:document.getElementById('pages').dataset.searchRanges};
  });
  assert.deepEqual(result.ranges,['fi','A']);assert.equal(result.unchanged,true);
  assert.equal(result.selection,'f');assert.equal(result.precise,'true');
  await page.locator('#search-query').fill('');
  await page.waitForFunction(()=>CSS.highlights.get('pdf-search-hit').size===0);
 });
 await check('Selected text becomes affine highlight geometry and downloads incrementally',async()=>{
  await load();await page.locator('#edit-toggle').click();
  await waitForUI(page,()=>!document.getElementById('editor-toolbar').hidden&&!document.getElementById('edit-toggle').disabled);
  const expected=await page.evaluate(async()=>{
   const viewer=await import('./viewer.js'),layer=document.querySelector('.page[data-page="1"] .text-layer');
   const glyphs=[...layer.querySelectorAll('.glyph-text')];
   const range=document.createRange();range.setStart(glyphs[0].firstChild,0);range.setEnd(glyphs[1].firstChild,1);
   getSelection().removeAllRanges();getSelection().addRange(range);await viewer.readSelection();
   const response=JSON.parse(await pdfViewerHost.pdf.call('select_page_text',[1,0,0,1,1]));
   return response.selection.quads;
  });
  await page.locator('#edit-highlight-selection').click();
  await page.waitForFunction(()=>document.getElementById('editor-dirty').textContent==='Unsaved'&&!document.getElementById('edit-toggle').disabled);
  await waitForUI(page,()=>document.querySelector('.page[data-page="1"]')?.dataset.rendered==='true');
  const annotation=page.locator('.page[data-page="1"] .editor-annotation').first();
  const currentQuads=()=>page.evaluate(async()=>JSON.parse(await pdfViewerHost.pdf.call('render_page',[1,1,0,true])).annotations[0].quad_points);
  const entry=async()=>JSON.parse(await annotation.getAttribute('data-entry'));
  const assertMapped=async before=>{
   const after=await entry(),old=before.bounds,bounds=after.bounds;
   const mapped=expected.map(quad=>Object.fromEntries(Object.entries(quad).map(([key,point])=>[key,{
    x:bounds[0]+(point.x-old[0])*(bounds[2]-bounds[0])/(old[2]-old[0]),
    y:bounds[1]+(point.y-old[1])*(bounds[3]-bounds[1])/(old[3]-old[1]),
   }])));
   assert.deepEqual(canonicalQuads(await currentQuads()),canonicalQuads(mapped));
  };
  const beforeMove=await entry(),box=await annotation.boundingBox();
  await page.mouse.move(box.x+box.width/2,box.y+box.height/2);await page.mouse.down();
  await page.mouse.move(box.x+box.width/2+48,box.y+box.height/2-24);await page.mouse.up();
  await page.waitForFunction(old=>{
   const node=document.querySelector('.page[data-page="1"] .editor-annotation');
   return node&&JSON.parse(node.dataset.entry).bounds[0]>old[0]+1&&!document.getElementById('edit-toggle').disabled;
  },beforeMove.bounds);
  await assertMapped(beforeMove);
  await page.locator('#edit-undo').click();
  await page.waitForFunction(old=>{const node=document.querySelector('.editor-annotation');return node&&JSON.parse(node.dataset.entry).bounds[0]===old[0]&&!document.getElementById('edit-toggle').disabled;},beforeMove.bounds);
  assert.deepEqual(canonicalQuads(await currentQuads()),canonicalQuads(expected));
  await annotation.click();
  const beforeResize=await entry(),handle=await page.locator('.editor-resize').first().boundingBox();
  await page.mouse.move(handle.x+handle.width/2,handle.y+handle.height/2);await page.mouse.down();
  await page.mouse.move(handle.x+handle.width/2+24,handle.y+handle.height/2+18);await page.mouse.up();
  await page.waitForFunction(old=>{const node=document.querySelector('.editor-annotation');return node&&JSON.parse(node.dataset.entry).bounds[2]>old[2]+1&&!document.getElementById('edit-toggle').disabled;},beforeResize.bounds);
  await assertMapped(beforeResize);
  await page.locator('#edit-undo').click();
  await page.waitForFunction(old=>{const node=document.querySelector('.editor-annotation');return node&&JSON.parse(node.dataset.entry).bounds[2]===old[2]&&!document.getElementById('edit-toggle').disabled;},beforeResize.bounds);
  assert.deepEqual(canonicalQuads(await currentQuads()),canonicalQuads(expected));
  const download=page.waitForEvent('download');await page.locator('#download').click();
  const saved=resolve(output,'selected-text.pdf');await (await download).saveAs(saved);
  const bytes=await readFile(saved);assert.deepEqual(bytes.subarray(0,fixture.length),fixture);
  const data=await page.evaluate(async()=>{
   const client=pdfViewerHost.pdf;
   return JSON.parse(await client.call('render_page',[1,1,0,true]));
  });
  assert.deepEqual(canonicalQuads(data.annotations[0].quad_points),canonicalQuads(expected));
  assert.equal(data.annotations[0].contents,'ffiA');
  await page.locator('#edit-undo').click();
  await page.waitForFunction(()=>!document.getElementById('edit-toggle').disabled&&document.getElementById('edit-redo').disabled===false);
  const undone=await page.evaluate(async()=>JSON.parse(await pdfViewerHost.pdf.call('render_page',[1,1,0,true])).annotations);
  assert.equal(undone.length,0);
  await page.locator('#edit-redo').click();
  await page.waitForFunction(()=>!document.getElementById('edit-toggle').disabled&&document.getElementById('editor-dirty').textContent==='');
  await page.locator('#file-input').setInputFiles(saved);
  await waitForUI(page,()=>document.querySelector('.page[data-page="1"]')?.dataset.rendered==='true');
  const reopened=await page.evaluate(async()=>JSON.parse(await pdfViewerHost.pdf.call('render_page',[1,1,0,true])).annotations);
  assert.deepEqual(canonicalQuads(reopened[0].quad_points),canonicalQuads(expected));
 });
 await check('Cross-page selected highlights undo and redo as one change with rotated page geometry',async()=>{
  await load();await page.locator('.page[data-page="2"]').scrollIntoViewIfNeeded();
  await waitForUI(page,()=>document.querySelector('.page[data-page="2"]')?.dataset.rendered==='true');
  await page.locator('#edit-toggle').click();
  await waitForUI(page,()=>!document.getElementById('editor-toolbar').hidden&&!document.getElementById('edit-toggle').disabled);
  const expected=await page.evaluate(async()=>{
   const first=[...document.querySelectorAll('.page[data-page="1"] .glyph-text')];
   const last=[...document.querySelectorAll('.page[data-page="2"] .glyph-text')];
   const range=document.createRange();range.setStart(first[0].firstChild,1);range.setEnd(last.at(-1).firstChild,1);
   getSelection().removeAllRanges();getSelection().addRange(range);
   const client=pdfViewerHost.pdf;
   return Promise.all([[1,0,1,2,1],[2,0,0,1,1]].map(async args=>
    JSON.parse(await client.call('select_page_text',args)).selection.quads));
  });
  await page.locator('#edit-highlight-selection').click();
  await page.waitForFunction(()=>document.getElementById('editor-dirty').textContent==='Unsaved'&&!document.getElementById('edit-toggle').disabled);
  const annotations=()=>page.evaluate(async()=>Promise.all([1,2].map(async number=>
   JSON.parse(await pdfViewerHost.pdf.call('render_page',[number,1,0,true])).annotations)));
  const added=await annotations();
  assert.deepEqual(added.map(items=>items.length),[1,1]);
  assert.deepEqual(added.map(items=>items[0].contents),['fiAB','AB']);
  assert.deepEqual(added.map(items=>canonicalQuads(items[0].quad_points)),expected.map(canonicalQuads));
  await page.locator('#edit-undo').click();
  await page.waitForFunction(()=>!document.getElementById('edit-toggle').disabled&&!document.getElementById('edit-redo').disabled);
  assert.deepEqual((await annotations()).map(items=>items.length),[0,0]);
  await page.locator('#edit-redo').click();
  await page.waitForFunction(()=>!document.getElementById('edit-toggle').disabled&&document.getElementById('edit-redo').disabled);
  assert.deepEqual((await annotations()).map(items=>canonicalQuads(items[0].quad_points)),expected.map(canonicalQuads));
 });
 await check('Dynamic XFA fills Unicode data with undo redo focused saving and fresh reopen',async()=>{
  const source=xfaFixture();
  await page.locator('#file-input').setInputFiles({name:'xfa.pdf',mimeType:'application/pdf',buffer:source});
  await waitForUI(page,()=>document.querySelector('.page[data-page="1"]')?.dataset.rendered==='true'&&document.querySelector('#viewer').getAttribute('aria-busy')==='false');
  const field=page.locator('.page[data-page="1"] [data-xfa-id]').first();
  assert.equal(await field.inputValue(),'Bound value');assert.equal(await field.getAttribute('aria-readonly'),'true');
  assert.equal(await field.getAttribute('aria-label'),'customer');
  await page.locator('#edit-toggle').click();
  await waitForUI(page,()=>!document.getElementById('editor-toolbar').hidden&&!document.getElementById('edit-toggle').disabled);
  assert.equal(await field.getAttribute('aria-readonly'),'false');assert.equal(await page.locator('#edit-text').isDisabled(),true);
  await field.fill('Edited & Unicode 你好');await field.press('Tab');
  await page.waitForFunction(()=>document.getElementById('editor-dirty').textContent==='Unsaved'&&!document.getElementById('edit-toggle').disabled);
  await page.locator('#edit-undo').click();
  await page.waitForFunction(()=>document.querySelector('[data-xfa-id]')?.value==='Bound value'&&!document.getElementById('edit-toggle').disabled);
  await page.locator('#edit-redo').click();
  await page.waitForFunction(()=>document.querySelector('[data-xfa-id]')?.value==='Edited & Unicode 你好'&&!document.getElementById('edit-toggle').disabled);
  await field.fill('Focused save 你好 & final');
  const download=page.waitForEvent('download');await field.press('Meta+s');
  const saved=resolve(output,'xfa-edited.pdf');await (await download).saveAs(saved);
  const bytes=await readFile(saved);assert.deepEqual(bytes.subarray(0,source.length),source);
  await page.locator('#file-input').setInputFiles(saved);
  await waitForUI(page,()=>document.querySelector('[data-xfa-id]')?.value==='Focused save 你好 & final'&&document.querySelector('#viewer').getAttribute('aria-busy')==='false');
  assert.equal(await page.locator('[data-xfa-id]').first().getAttribute('aria-readonly'),'true');
 });
 await check('XFA access keeps unsupported and locked fields readonly and radio edits survive remount print and reopen',async()=>{
  await page.locator('#file-input').setInputFiles({name:'xfa-access.pdf',mimeType:'application/pdf',buffer:xfaAccessFixture()});
  await waitForUI(page,()=>document.querySelector('input[xfaOn="A"]')&&document.querySelector('#viewer').getAttribute('aria-busy')==='false');
  await page.locator('#edit-toggle').click();
  await waitForUI(page,()=>!document.getElementById('editor-toolbar').hidden&&!document.getElementById('edit-toggle').disabled);
  assert.equal(await page.getByLabel('locked',{exact:true}).isEditable(),false);
  assert.equal(await page.getByLabel('protected',{exact:true}).isEditable(),false);
  const rejected=await page.evaluate(async()=>{
   try{return JSON.parse(await pdfViewerHost.pdf.call('apply_edits',[JSON.stringify([
    {kind:'xfa',data_id:document.querySelector('[aria-label="locked"]').dataset.xfaId,value:'Forbidden edit'},
   ])]));}catch(error){return {ok:false,error:error.message};}
  });
  assert.equal(rejected.ok,false);assert.match(rejected.error,/Invalid XFA field/);
  const unbound=page.locator('input[value="Initial unbound"]');
  assert.equal(await unbound.isEditable(),false);assert.equal(await unbound.getAttribute('data-xfa-id'),null);
  assert.equal(await page.locator('select[multiple]').isDisabled(),true);
  const radios=page.locator('#pages input[type=radio]');
  assert.deepEqual(await radios.evaluateAll(nodes=>nodes.map(node=>node.checked)),[false,true]);
  await page.locator('#pages input[xfaOn="A"]').check();
  await page.waitForFunction(()=>document.querySelector('#pages input[xfaOn="A"]')?.checked&&!document.querySelector('#pages input[xfaOn="B"]')?.checked&&!document.getElementById('edit-toggle').disabled);
  await page.evaluate(async()=>{window.print=()=>{};await (await import('./viewer.js')).printDocument();});
  assert.deepEqual(await page.locator('#print-pages input[type=radio]').evaluateAll(nodes=>nodes.map(node=>node.checked)),[true,false]);
  const download=page.waitForEvent('download');await page.locator('#download').click();
  const saved=resolve(output,'xfa-access-edited.pdf');await (await download).saveAs(saved);
  await page.locator('#file-input').setInputFiles(saved);
  await waitForUI(page,()=>document.querySelector('#pages input[xfaOn="A"]')?.checked&&!document.querySelector('#pages input[xfaOn="B"]')?.checked&&document.querySelector('#viewer').getAttribute('aria-busy')==='false');
 });
 await check('Tagged PDF namespace headings formulas and MathML expose native accessibility semantics',async()=>{
  await page.locator('#file-input').setInputFiles({name:'namespace.pdf',mimeType:'application/pdf',buffer:namespaceFixture()});
  await waitForUI(page,()=>document.querySelector('.accessibility-layer math')&&document.querySelector('#viewer').getAttribute('aria-busy')==='false');
  const data=await page.evaluate(()=>{
   const layer=document.querySelector('.accessibility-layer'),math=layer.querySelector('math');
   return {heading:layer.querySelector('[role=heading]')?.textContent,level:layer.querySelector('[role=heading]')?.getAttribute('aria-level'),
    formula:layer.querySelector('[role=math]')?.getAttribute('aria-label'),namespace:math?.namespaceURI,
    tokens:[...math.querySelectorAll('mi,mn')].map(node=>node.textContent),superscript:!!math.querySelector('msup'),
    copies:[...layer.querySelectorAll('[role=math],math')].map(node=>node.textContent)};
  });
  assert.equal(data.heading,'Heading');assert.equal(data.level,'2');assert.equal(data.formula,'x squared');
  assert.equal(data.namespace,'http://www.w3.org/1998/Math/MathML');assert.deepEqual(data.tokens,['x','2']);
  assert.equal(data.superscript,true);
  if(engine==='chromium'){
   const cdp=await page.context().newCDPSession(page);const {nodes}=await cdp.send('Accessibility.getFullAXTree');
   assert(nodes.some(node=>node.role?.value==='heading'&&node.name?.value==='Heading'));
   assert(nodes.some(node=>node.role?.value==='math'&&node.name?.value==='x squared'));
   await cdp.detach();
  }
  await page.screenshot({path:resolve(output,'tagged-semantics.png')});
 });
 assert.deepEqual(errors,[]);
 await writeFile(resolve(output,'report.json'),JSON.stringify({engine,checks,errors},null,2));
 console.log('REPORT '+output);
}catch(error){await page.screenshot({path:resolve(output,'failure.png'),fullPage:true});throw error;}
finally{await browser.close();}

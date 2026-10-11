#!/usr/bin/env node
// Native browser interactions exercise the shipped MoonBit/Rabbita editor.
// Saved bytes are reopened by this viewer and the pinned PDF.js reader.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {execFileSync} from 'node:child_process';
import {mkdirSync,writeFileSync,readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

const require=createRequire(resolve('tools/test-host/package.json'));
const {chromium}=require('playwright');
const {createCanvas,DOMMatrix,ImageData,Path2D}=require('@napi-rs/canvas');
Object.assign(globalThis,{DOMMatrix,ImageData,Path2D,OffscreenCanvas:function(width,height){return createCanvas(width,height);}});
const pdfjs=await import(pathToFileURL(require.resolve('pdfjs-dist/legacy/build/pdf.mjs')));
const base=process.argv[2]||'http://127.0.0.1:4315';
const filter=process.env.PDF_EDITOR_CHECK_FILTER||'';
const output=resolve('_build/editor-'+(filter?'focused-':'test-')+Date.now());
mkdirSync(output,{recursive:true});
function fixture(){
  const stream=text=>'<< /Length '+Buffer.byteLength(text)+' >>\nstream\n'+text+'\nendstream';
  const objects=[
    '<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [5 0 R 8 0 R 9 0 R 10 0 R 11 0 R 14 0 R 19 0 R] /DA (/Helv 12 Tf 0 g) /DR << /Font << /Helv 16 0 R >> >> >> >>',
    '<< /Type /Pages /Count 2 /Kids [3 0 R 4 0 R] >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 340 440] /CropBox [20 20 320 420] /UserUnit 1.5 /Annots [6 0 R 8 0 R 9 0 R 10 0 R 12 0 R 13 0 R 14 0 R 15 0 R 19 0 R] /Resources << /Font << /Helv 16 0 R >> >> /Contents 17 0 R >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 240 240] /CropBox [20 20 220 220] /UserUnit 2 /Rotate 90 /Annots [7 0 R] /Resources << /Font << /Helv 16 0 R >> >> /Contents 18 0 R >>',
    '<< /FT /Tx /T (person) /V (Before) /Kids [6 0 R 7 0 R] /MaxLen 80 >>',
    '<< /Subtype /Widget /Rect [40 360 270 380] /Parent 5 0 R /F 4 >>',
    '<< /Subtype /Widget /Rect [30 150 180 175] /Parent 5 0 R /F 4 >>',
    '<< /Subtype /Widget /Rect [40 310 140 340] /FT /Ch /Ff 131072 /T (status) /Opt [[(Y) (Yes)] [(N) (No)]] /V (N) /F 4 >>',
    '<< /Subtype /Widget /Rect [160 280 270 340] /FT /Ch /Ff 2097152 /T (interests) /Opt [[(A) (Alpha)] [(B) (Beta)] [(C) (Gamma)]] /V [(A)] /I [0] /F 4 >>',
    '<< /Subtype /Widget /Rect [40 250 60 270] /FT /Btn /T (accept) /V /Off /AS /Off /F 4 >>',
    '<< /FT /Btn /Ff 49152 /T (radio) /V /A /Kids [12 0 R 13 0 R] /Opt [(A) (B)] >>',
    '<< /Subtype /Widget /Rect [100 250 120 270] /Parent 11 0 R /AS /A /F 4 >>',
    '<< /Subtype /Widget /Rect [140 250 160 270] /Parent 11 0 R /AS /Off /F 4 >>',
    '<< /Subtype /Widget /Rect [40 200 270 230] /FT /Tx /T (readonly) /Ff 1 /V (Fixed) /F 4 >>',
    '<< /Subtype /FreeText /Rect [40 165 150 190] /Contents (Existing) /DA (/Helv 12 Tf 0 g) /F 4 >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    stream('BT /Helv 16 Tf 40 390 Td (Editor acceptance) Tj ET'),
    stream('BT /Helv 14 Tf 30 190 Td (Rotated page) Tj ET'),
    '<< /Subtype /Widget /Rect [40 280 140 305] /FT /Ch /Ff 131072 /T (duplicate) /Opt [[(D) (First)] [(D) (Second)]] /V (D) /I [0] /F 4 >>',
  ];
  let text='%PDF-1.7\n',offsets=[];
  for(let i=0;i<objects.length;i++){offsets.push(Buffer.byteLength(text));text+=(i+1)+' 0 obj\n'+objects[i]+'\nendobj\n';}
  const xref=Buffer.byteLength(text);
  text+='xref\n0 '+(objects.length+1)+'\n0000000000 65535 f \n';
  for(const offset of offsets) text+=String(offset).padStart(10,'0')+' 00000 n \n';
  text+='trailer\n<< /Size '+(objects.length+1)+' /Root 1 0 R >>\nstartxref\n'+xref+'\n%%EOF\n';
  return Buffer.from(text);
}
const source=resolve(output,'editor-fixture.pdf');
writeFileSync(source,fixture());
execFileSync('moon',['run','tools/editor_encrypted_fixtures.mbtx',source,output],{
  stdio:['ignore','pipe','pipe'],timeout:120000,maxBuffer:8*1024*1024,
});
const image=createCanvas(240,80),imageCtx=image.getContext('2d');
imageCtx.strokeStyle='#123f92';imageCtx.lineWidth=5;
imageCtx.beginPath();imageCtx.moveTo(15,65);imageCtx.lineTo(60,15);imageCtx.lineTo(90,60);imageCtx.lineTo(140,25);imageCtx.lineTo(225,45);imageCtx.stroke();
const imagePath=resolve(output,'signature.png');
writeFileSync(imagePath,image.toBuffer('image/png'));
const browser=await chromium.launch({executablePath:process.env.PDF_CHROMIUM||chromium.executablePath(),headless:true,args:['--no-sandbox']});
const page=await browser.newPage({viewport:{width:1280,height:900},acceptDownloads:true});
const checks=[],errors=[];
page.on('pageerror',error=>errors.push(String(error)));
let current='initialization',completed=false;
async function check(name,work){if(filter&&!name.includes(filter)) return;current=name;await work();checks.push(name);console.log('PASS '+name);}
const frame=()=>page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
async function idle(){
  await page.waitForFunction(async()=>{
    const ready=()=>document.querySelector('#viewer')?.getAttribute('aria-busy')==='false' &&
      !document.querySelector('#edit-toggle').disabled && document.querySelector('.page[data-page="'+document.querySelector('#page-number').value+'"][data-rendered="true"]');
    if(!ready()) return false;
    await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
    return Boolean(ready());
  });
}
async function entries(number=1){
  return page.evaluate(async number=>{
    const layer=document.querySelector('.page[data-page="'+number+'"] .editor-layer');
    if(layer) return JSON.parse(layer.dataset.entries);
    const client=await import('./pdf-client.js');
    return JSON.parse(await client.render_page(number,1,0)).editor;
  },number);
}
async function point(number,x,y){
  await page.waitForSelector('.page[data-page="'+number+'"][data-rendered="true"] .editor-layer');
  return page.evaluate(({number,x,y})=>{
    const page=document.querySelector('.page[data-page="'+number+'"]'),rect=page.getBoundingClientRect();
    const m=JSON.parse(page.querySelector('.editor-layer').dataset.viewport).matrix;
    return {x:rect.left+m[0]*x+m[2]*y+m[4],y:rect.top+m[1]*x+m[3]*y+m[5]};
  },{number,x,y});
}
async function drag(number,coordinates){
  const start=await point(number,...coordinates[0]);
  await page.mouse.move(start.x,start.y);await page.mouse.down();
  for(const [x,y] of coordinates.slice(1)){const p=await point(number,x,y);await page.mouse.move(p.x,p.y,{steps:4});}
  await page.mouse.up();
}
async function draw(tool,coordinates,number=1){
  await page.locator('#page-number').fill(String(number));await page.locator('#page-number').press('Enter');
  await page.waitForFunction(number=>document.querySelector('#page-number').value===String(number),number);
  await frame();
  const before=(await entries(number)).length;
  await page.locator('#edit-'+tool).click();await frame();
  await drag(number,coordinates);
  await page.waitForFunction(({number,before})=>{
    const layer=document.querySelector('.page[data-page="'+number+'"] .editor-layer');
    return layer && JSON.parse(layer.dataset.entries).length===before+1 && !document.querySelector('#edit-toggle').disabled;
  },{number,before});
  await idle();
  return (await entries(number)).at(-1);
}
async function waitField(name,value){
  await page.waitForFunction(({name,value})=>{
    const layer=document.querySelector('.page[data-page="1"] .editor-layer');
    return layer && JSON.parse(layer.dataset.entries).some(entry=>entry.field_name===name && JSON.stringify(entry.values)===JSON.stringify(value)) && !document.querySelector('#edit-toggle').disabled;
  },{name,value});await idle();
}
async function waitEntry(id,expected){
  await page.waitForFunction(({id,expected})=>{
    const entries=[...document.querySelectorAll('.editor-layer')].flatMap(layer=>JSON.parse(layer.dataset.entries));
    const entry=entries.find(entry=>entry.id===id);
    return entry && Object.entries(expected).every(([key,value])=>key==='bounds'?
      value.every((n,i)=>Math.abs(entry.bounds[i]-n)<.6):JSON.stringify(entry[key])===JSON.stringify(value));
  },{id,expected});await idle();
}
async function waitLength(number,count){
  await page.waitForFunction(({number,count})=>{
    const layer=document.querySelector('.page[data-page="'+number+'"] .editor-layer');
    return layer && JSON.parse(layer.dataset.entries).length===count;
  },{number,count});await idle();
}
async function waitSaved(){
  // The download event can arrive before Rabbita publishes the saved snapshot.
  await page.waitForFunction(()=>document.querySelector('#editor-dirty').textContent==='' &&
    document.querySelector('#editor-status').textContent.startsWith('已下载') &&
    !document.querySelector('#edit-toggle').disabled);
  await idle();
}
async function captureDownload(){
  const promise=page.waitForEvent('download');
  await page.locator('#download').click();
  const download=await promise,dest=resolve(output,download.suggestedFilename());
  await download.saveAs(dest);await waitSaved();return dest;
}
async function openEncrypted(name,password){
  assert.equal(await page.locator('#editor-dirty').innerText(),'','Previous encrypted session must be saved');
  const prompt=password===undefined?null:page.waitForEvent('dialog');
  const upload=page.locator('#file-input').setInputFiles(resolve(output,name));
  if(prompt){
    const dialog=await prompt;
    console.log('Password prompt:',name,dialog.type(),dialog.message());
    if(dialog.type()!=='prompt'){
      await dialog.dismiss();await upload;
      assert.fail('Expected password prompt, got '+dialog.type()+': '+dialog.message());
    }
    await dialog.accept(password);
  }
  await upload;
  await page.waitForFunction(name=>document.querySelector('#file-name').textContent===name &&
    document.querySelector('#editor-toolbar').hidden,name);
  await idle();
  await page.locator('#zoom').selectOption('1');
  await page.waitForFunction(()=>{
    const layer=document.querySelector('.page[data-page="1"] .editor-layer');
    return layer && JSON.parse(layer.dataset.viewport).scale===1;
  });await idle();
}
async function enterEditor(){
  await page.locator('#edit-toggle').click();
  await page.waitForFunction(()=>!document.querySelector('#editor-toolbar').hidden &&
    !document.querySelector('#edit-toggle').disabled);
  await idle();
}
try {
  await page.goto(base);
  await page.locator('#file-input').setInputFiles(source);await idle();
  await page.locator('#zoom').selectOption('1');await idle();
  await check('Rabbita editor opens native controls and retains readonly restrictions',async()=>{
    const canvas=await page.locator('.page[data-page="1"] .paint-layer canvas').evaluate(canvas=>{window.editorOriginalCanvas=canvas;return canvas.width;});
    assert.ok(canvas>0);
    await page.locator('#edit-toggle').click();await frame();
    assert.equal(await page.locator('#editor-toolbar').isVisible(),true);
    assert.equal(await page.locator('[data-field-name="readonly"]').isDisabled(),true);
    assert.equal(await page.locator('[data-field-name="readonly"]').evaluate(control=>getComputedStyle(control).opacity),'1');
    assert.equal(await page.evaluate(()=>document.querySelector('.page[data-page="1"] .paint-layer canvas')===window.editorOriginalCanvas),true);
  });
  await check('Unicode text filling synchronizes inherited widgets across pages',async()=>{
    const field=page.locator('.page[data-page="1"] [data-field-name="person"]');
    await field.fill('你好 MoonBit');await field.press('Tab');await waitField('person',['你好 MoonBit']);
    assert.deepEqual((await entries(2))[0].values,['你好 MoonBit']);
  });
  await check('Choice controls preserve export values and multiple selection indices',async()=>{
    await page.locator('[data-field-name="status"]').selectOption('Y');await waitField('status',['Y']);
    await page.locator('[data-field-name="interests"]').selectOption(['B','C']);await waitField('interests',['B','C']);
    assert.deepEqual((await entries()).find(entry=>entry.field_name==='interests').options.filter(option=>option.selected).map(option=>option.export_value),['B','C']);
    await page.locator('[data-field-name="duplicate"]').selectOption({index:1});
    await page.waitForFunction(()=>{
      const layer=document.querySelector('.page[data-page="1"] .editor-layer');
      return layer && JSON.parse(layer.dataset.entries).find(entry=>entry.field_name==='duplicate').options[1].selected;
    });await idle();
    assert.deepEqual((await entries()).find(entry=>entry.field_name==='duplicate').options.filter(option=>option.selected).map(option=>option.display_value),['Second']);
  });
  await check('Checkbox and radio clicks write consistent V AS and sibling appearances',async()=>{
    await page.locator('[data-field-name="accept"]').check();await waitField('accept',['Yes']);
    await page.locator('[data-editor-id="object:13"]').check();await waitField('radio',['B']);
    const radios=(await entries()).filter(entry=>entry.field_name==='radio');
    assert.deepEqual(radios.map(entry=>entry.checked),[false,true]);
  });
  await check('Existing annotation changes accumulate across text and geometry updates',async()=>{
    await page.locator('.page[data-page="1"] .editor-annotation').click();await frame();
    await page.locator('#editor-text').fill('Existing revised');await frame();
    await page.locator('#edit-apply-text').click();await waitEntry('object:15',{contents:'Existing revised'});
    await drag(1,[[95,177.5],[105,182.5]]);await waitEntry('object:15',{bounds:[50,170,160,195]});
    const existing=(await entries()).find(entry=>entry.id==='object:15');
    assert.equal(existing.contents,'Existing revised');
    assert.ok(Math.abs(existing.bounds[0]-50)<.6 && Math.abs(existing.bounds[1]-170)<.6);
  });
  let textAnnotation;
  await check('Native pointer creates Unicode FreeText using CropBox and UserUnit coordinates',async()=>{
    await page.locator('#editor-text').fill('中文批注 MoonBit');await frame();
    textAnnotation=await draw('text',[[60,80],[200,120]]);
    assert.equal(textAnnotation.contents,'中文批注 MoonBit');
    assert.ok(textAnnotation.bounds.every((v,i)=>Math.abs(v-[60,80,200,120][i])<.6));
  });
  await check('Selected annotations support text edits moving and resizing',async()=>{
    await page.locator('#edit-select').click();await frame();
    await page.locator('.page[data-page="1"] .editor-annotation').last().click();await frame();
    await page.locator('#editor-text').fill('修改后的批注');await frame();
    await page.locator('#edit-apply-text').click();await waitEntry(textAnnotation.id,{contents:'修改后的批注'});
    let entry=(await entries()).find(entry=>entry.id===textAnnotation.id);
    assert.equal(entry.contents,'修改后的批注');
    const mid=[(entry.bounds[0]+entry.bounds[2])/2,(entry.bounds[1]+entry.bounds[3])/2];
    await drag(1,[mid,[mid[0]+20,mid[1]+10]]);await waitEntry(textAnnotation.id,{bounds:[80,90,220,130]});
    entry=(await entries()).find(entry=>entry.id===textAnnotation.id);
    assert.ok(Math.abs(entry.bounds[0]-80)<.6 && Math.abs(entry.bounds[1]-90)<.6);
    await page.locator('.page[data-page="1"] .editor-annotation').last().click();await frame();
    const handle=page.locator('.editor-resize'),box=await handle.boundingBox();
    await page.mouse.move(box.x+box.width/2,box.y+box.height/2);await page.mouse.down();
    await page.mouse.move(box.x+box.width/2+30,box.y+box.height/2+15,{steps:5});await page.mouse.up();await idle();
    await page.waitForFunction(id=>{
      const layer=document.querySelector('.page[data-page="1"] .editor-layer');
      const entry=layer && JSON.parse(layer.dataset.entries).find(entry=>entry.id===id);
      return entry && entry.bounds[2]>220 && entry.bounds[1]<90;
    },textAnnotation.id);await idle();
    entry=(await entries()).find(entry=>entry.id===textAnnotation.id);
    assert.ok(entry.bounds[2]>220 && entry.bounds[1]<90);
  });
  await check('Highlight and ink tools create persisted PDF annotation appearances',async()=>{
    assert.equal((await draw('highlight',[[50,135],[210,150]])).subtype,'highlight');
    assert.equal((await draw('ink',[[50,35],[65,65],[90,45],[130,55]])).subtype,'ink');
  });
  await check('Handwritten and image signatures are placed with their PDF geometry',async()=>{
    assert.equal((await draw('signature',[[180,35],[195,60],[220,40],[245,55]])).contents,'手写签名');
    await check('Handwriting groups multiple strokes and supports undoing one stroke',async()=>{
      const signature=(await entries()).at(-1),before=(await entries()).length;
      await drag(1,[[185,65],[205,75],[245,65]]);
      await page.waitForFunction(id=>{
        const layer=document.querySelector('.page[data-page="1"] .editor-layer');
        return layer && JSON.parse(layer.dataset.entries).find(entry=>entry.id===id)?.paths.length===2;
      },signature.id);await idle();
      assert.equal((await entries()).length,before);
      assert.equal((await entries()).find(entry=>entry.id===signature.id).paths.length,2);
      await page.locator('#edit-undo').click();await waitEntry(signature.id,{paths:[signature.paths[0]]});
      assert.equal((await entries()).find(entry=>entry.id===signature.id).paths.length,1);
      await page.locator('#edit-redo').click();
      await page.waitForFunction(id=>{
        const layer=document.querySelector('.page[data-page="1"] .editor-layer');
        return layer && JSON.parse(layer.dataset.entries).find(entry=>entry.id===id)?.paths.length===2;
      },signature.id);await idle();
      assert.equal((await entries()).find(entry=>entry.id===signature.id).paths.length,2);
    });
    await page.locator('#signature-image').setInputFiles(imagePath);
    await page.waitForFunction(()=>document.querySelector('#editor-status').textContent.includes('图片签名的放置区域'));
    const stamp=await draw('image',[[180,165],[270,195]]);
    assert.equal(stamp.subtype,'stamp');
    assert.ok(Math.abs((stamp.bounds[2]-stamp.bounds[0])/(stamp.bounds[3]-stamp.bounds[1])-3)<.02);
  });
  await check('Delete undo and redo restore annotation and field snapshots',async()=>{
    await page.locator('#edit-select').click();await frame();
    const before=(await entries()).length;
    await page.locator('.page[data-page="1"] .editor-annotation').last().click();await frame();
    await page.locator('#edit-delete').click();await waitLength(1,before-1);assert.equal((await entries()).length,before-1);
    await page.locator('#edit-undo').click();await waitLength(1,before);assert.equal((await entries()).length,before);
    await page.locator('#edit-redo').click();await waitLength(1,before-1);assert.equal((await entries()).length,before-1);
    await page.locator('#edit-undo').click();await waitLength(1,before);
  });
  await check('Rotated second page keeps native controls and pointer geometry',async()=>{
    await page.locator('#page-number').fill('2');await page.locator('#page-number').press('Enter');
    await page.waitForFunction(()=>document.querySelector('#page-number').value==='2');await frame();
    await page.locator('#editor-text').fill('Rotated');await frame();
    const entry=await draw('text',[[40,50],[110,85]],2);
    assert.ok(entry.bounds.every((v,i)=>Math.abs(v-[40,50,110,85][i])<.6));
  });
  await check('Printing includes edited AP on every physical PDF page',async()=>{
    await page.evaluate(async()=>{window.print=()=>{};await (await import('./viewer.js')).printDocument();});
    assert.equal(await page.locator('#print-pages canvas').count(),2);
    assert.equal(await page.locator('#print-pages .editor-field').count(),0);
    const cdp=await page.context().newCDPSession(page);
    const printed=await cdp.send('Page.printToPDF',{preferCSSPageSize:true,printBackground:true});
    await cdp.detach();
    const printPath=resolve(output,'printed-edits.pdf');
    writeFileSync(printPath,Buffer.from(printed.data,'base64'));
    const task=pdfjs.getDocument({data:new Uint8Array(readFileSync(printPath)),verbosity:0});
    assert.equal((await task.promise).numPages,2);
    await task.destroy();
  });
  let saved;
  await check('Download writes PDF.js-readable values and annotation appearances',async()=>{
    saved=await captureDownload();
    const bytes=new Uint8Array(readFileSync(saved));
    assert.equal(Buffer.from(bytes.subarray(0,5)).toString(),'%PDF-');
    const loading=pdfjs.getDocument({data:bytes,disableFontFace:true,verbosity:0});
    const document=await loading.promise;
    assert.equal(document.numPages,2);
    const annotations=await (await document.getPage(1)).getAnnotations();
    assert.equal(annotations.find(a=>a.fieldName==='person').fieldValue,'你好 MoonBit');
    assert.deepEqual(annotations.find(a=>a.fieldName==='status').fieldValue,['Y']);
    assert.deepEqual(annotations.find(a=>a.fieldName==='interests').fieldValue,['B','C']);
    assert.equal(annotations.find(a=>a.fieldName==='accept').fieldValue,'Yes');
    assert.equal(annotations.filter(a=>a.fieldName==='radio').every(a=>a.fieldValue==='B'),true);
    assert.equal(annotations.find(a=>a.contentsObj?.str==='修改后的批注').hasAppearance,true);
    assert.ok(annotations.some(a=>a.contentsObj?.str==='Existing revised' && a.hasAppearance));
    assert.ok(annotations.some(a=>a.contentsObj?.str==='手写签名' && a.hasAppearance));
    assert.ok(annotations.some(a=>a.contentsObj?.str==='图片签名' && a.hasAppearance));
    await loading.destroy();
    assert.equal(await page.locator('#editor-dirty').innerText(),'');
  });
  await check('PDF.js paints saved handwritten and image signatures through portable AP',async()=>{
    const task=pdfjs.getDocument({data:new Uint8Array(readFileSync(saved)),disableFontFace:true,verbosity:0,
      standardFontDataUrl:resolve(require.resolve('pdfjs-dist/package.json'),'..','standard_fonts')+'/'});
    const document=await task.promise,reference=await document.getPage(1),viewport=reference.getViewport({scale:1});
    const canvas=createCanvas(Math.ceil(viewport.width),Math.ceil(viewport.height)),ctx=canvas.getContext('2d');
    await reference.render({canvasContext:ctx,viewport,annotationMode:pdfjs.AnnotationMode.ENABLE}).promise;
    const annotations=await reference.getAnnotations();
    for(const contents of ['手写签名','图片签名','修改后的批注','Existing revised']){
      const annotation=annotations.find(annotation=>annotation.contentsObj?.str===contents);
      const rect=[...viewport.convertToViewportPoint(annotation.rect[0],annotation.rect[1]),...viewport.convertToViewportPoint(annotation.rect[2],annotation.rect[3])];
      const x=Math.max(0,Math.floor(Math.min(rect[0],rect[2]))),y=Math.max(0,Math.floor(Math.min(rect[1],rect[3])));
      const w=Math.min(canvas.width-x,Math.ceil(Math.abs(rect[2]-rect[0]))),h=Math.min(canvas.height-y,Math.ceil(Math.abs(rect[3]-rect[1])));
      const data=ctx.getImageData(x,y,w,h).data;
      let ink=0;
      for(let i=0;i<data.length;i+=4)if(data[i]<230||data[i+1]<230||data[i+2]<230)ink++;
      assert.ok(ink>20,'PDF.js produced a blank saved appearance: '+contents);
      if(contents==='修改后的批注'||contents==='Existing revised')
        assert.ok(ink<w*h*.5,'FreeText colour incorrectly filled the text box: '+contents);
    }
    writeFileSync(resolve(output,'pdfjs-saved-appearances.png'),canvas.toBuffer('image/png'));
    await task.destroy();
  });
  await check('Saved PDF reopens in viewer and accepts another editing session',async()=>{
    await page.locator('#file-input').setInputFiles(saved);await idle();
    const reopened=await entries();
    assert.equal(reopened.find(entry=>entry.id===textAnnotation.id).contents,'修改后的批注');
    assert.deepEqual(reopened.find(entry=>entry.field_name==='person').values,['你好 MoonBit']);
    assert.equal(await page.locator('#editor-toolbar').isVisible(),false);
    await page.locator('#edit-toggle').click();await frame();
    await page.locator('#editor-text').fill('Another session');await frame();
    assert.notEqual((await draw('text',[[50,95],[200,115]])).id,textAnnotation.id);
    await page.screenshot({path:resolve(output,'edited-reader.png'),fullPage:true});
  });
  await check('Ctrl S flushes the active form input before saving',async()=>{
    const field=page.locator('.page[data-page="1"] [data-field-name="person"]');
    await field.fill('Saved from active field');
    const promise=page.waitForEvent('download');
    await field.press(process.platform==='darwin'?'Meta+s':'Control+s');
    const download=await promise,dest=resolve(output,'keyboard-saved.pdf');
    await download.saveAs(dest);await waitSaved();
    const task=pdfjs.getDocument({data:new Uint8Array(readFileSync(dest)),verbosity:0});
    const annotations=await (await (await task.promise).getPage(1)).getAnnotations();
    assert.equal(annotations.find(annotation=>annotation.fieldName==='person').fieldValue,'Saved from active field');
    await task.destroy();
  });
  await check('Undo and redo compare against the saved snapshot for dirty state',async()=>{
    assert.equal(await page.locator('#editor-dirty').innerText(),'');
    await page.locator('#edit-undo').click();
    await page.waitForFunction(()=>document.querySelector('#editor-dirty').textContent==='未保存');await idle();
    assert.equal(await page.locator('#editor-dirty').innerText(),'未保存');
    await page.locator('#edit-redo').click();
    await page.waitForFunction(()=>document.querySelector('#editor-dirty').textContent==='');await idle();
    assert.equal(await page.locator('#editor-dirty').innerText(),'');
    await page.locator('#edit-undo').click();await waitField('person',['你好 MoonBit']);
    await page.locator('#edit-undo').click();
    await page.waitForFunction(()=>{
      const layer=document.querySelector('.page[data-page="1"] .editor-layer');
      return layer && !JSON.parse(layer.dataset.entries).some(entry=>entry.contents==='Another session');
    });await idle();
    const originalBytes=readFileSync(saved);
    const originalDownload=await captureDownload();
    assert.deepEqual(readFileSync(originalDownload),originalBytes);
    assert.equal(await page.locator('#editor-dirty').innerText(),'');
    await page.locator('#edit-redo').click();
    await page.waitForFunction(()=>{
      const layer=document.querySelector('.page[data-page="1"] .editor-layer');
      return layer && JSON.parse(layer.dataset.entries).some(entry=>entry.contents==='Another session');
    });await idle();
    assert.equal(await page.locator('#editor-dirty').innerText(),'未保存');
    await page.locator('#edit-redo').click();await waitField('person',['Saved from active field']);
    assert.equal(await page.locator('#editor-dirty').innerText(),'未保存');
    await captureDownload();
    assert.equal(await page.locator('#editor-dirty').innerText(),'');
  });
  await check('Unsaved edits can cancel document replacement without losing changes',async()=>{
    await page.locator('#editor-text').fill('Unsaved note');await frame();
    await draw('text',[[50,130],[190,155]]);
    const name=await page.locator('#file-name').innerText();
    const dialog=page.waitForEvent('dialog');
    const upload=page.locator('#file-input').setInputFiles(source);
    await (await dialog).dismiss();await upload;await frame();
    assert.equal(await page.locator('#file-name').innerText(),name);
    assert.ok((await entries()).some(entry=>entry.contents==='Unsaved note'));
    const accepted=page.waitForEvent('dialog'),replace=page.locator('#file-input').setInputFiles(source);
    await (await accepted).accept();await replace;
    await page.waitForFunction(()=>document.querySelector('#file-name').textContent==='editor-fixture.pdf' &&
      document.querySelector('#editor-toolbar').hidden);
    await waitField('person',['Before']);
    assert.equal(await page.locator('#file-name').innerText(),'editor-fixture.pdf');
  });
  await check('Late editing replies cannot publish into a replacement document',async()=>{
    await page.locator('#edit-toggle').click();
    await page.locator('.page[data-page="1"] [data-field-name="person"]').waitFor();
    await page.evaluate(()=>{
      const client=globalThis.pdfViewerHost.pdf,call=client.call.bind(client);
      const gate=new Promise(resolve=>{window.releaseLateEdit=resolve;});
      window.restoreEditClient=()=>{client.call=call;};
      client.call=(method,args,options)=>{
        const result=call(method,args,options);
        if(method!=='apply_edits') return result;
        window.lateEditWaiting=true;
        return result.then(async value=>{window.lateEditReady=true;await gate;window.lateEditReleased=true;return value;});
      };
      const field=document.querySelector('.page[data-page="1"] [data-field-name="person"]');
      field.value='Stale value';field.dispatchEvent(new Event('change',{bubbles:true}));
    });
    await page.waitForFunction(()=>window.lateEditReady);
    await page.evaluate(async()=>{window.restoreEditClient();(await import('./viewer.js')).closeDocument();});
    await page.locator('#file-input').setInputFiles(source);await idle();
    await page.evaluate(()=>window.releaseLateEdit());await page.waitForFunction(()=>window.lateEditReleased);await frame();
    assert.deepEqual((await entries()).find(entry=>entry.field_name==='person').values,['Before']);
    assert.equal(await page.locator('#editor-toolbar').isVisible(),false);
    // A failed preparation from a closed document must not report an error
    // into its replacement, even when the transport already returned.
    await page.evaluate(()=>{
      const client=globalThis.pdfViewerHost.pdf,call=client.call.bind(client);
      const gate=new Promise((_,reject)=>{window.rejectLatePreparation=()=>reject(new Error('Late preparation failure'));});
      window.restorePreparationClient=()=>{client.call=call;};
      client.call=(method,args,options)=>{
        const result=call(method,args,options);
        if(method!=='editor_info') return result;
        return result.then(async value=>{window.latePreparationReady=true;await gate;return value;})
          .catch(error=>{window.latePreparationReleased=true;throw error;});
      };
    });
    await page.locator('#edit-toggle').click();await page.waitForFunction(()=>window.latePreparationReady);
    await page.evaluate(async()=>{window.restorePreparationClient();(await import('./viewer.js')).closeDocument();});
    await page.locator('#file-input').setInputFiles(source);await waitField('person',['Before']);
    await page.evaluate(()=>window.rejectLatePreparation());await page.waitForFunction(()=>window.latePreparationReleased);await frame();
    assert.equal(await page.locator('#error').innerText(),'');
    // Decode failures also belong to the document and picker generation that
    // started them; replacing it must suppress a delayed decoder rejection.
    await page.locator('#edit-toggle').click();
    await page.locator('.page[data-page="1"] [data-field-name="person"]').waitFor();
    await page.evaluate(()=>{
      window.originalEditorBitmap=createImageBitmap;
      window.createImageBitmap=()=>new Promise((_,reject)=>{
        window.lateBitmapReady=true;
        window.rejectLateBitmap=()=>{window.lateBitmapReleased=true;reject(new Error('Late bitmap failure'));};
      });
    });
    await page.locator('#signature-image').setInputFiles(imagePath);await page.waitForFunction(()=>window.lateBitmapReady);
    await page.evaluate(async()=>{window.createImageBitmap=window.originalEditorBitmap;(await import('./viewer.js')).closeDocument();});
    await page.locator('#file-input').setInputFiles(source);await waitField('person',['Before']);
    await page.evaluate(()=>window.rejectLateBitmap());await page.waitForFunction(()=>window.lateBitmapReleased);await frame();
    assert.equal(await page.locator('#error').innerText(),'');
    assert.equal(await page.locator('#editor-toolbar').isVisible(),false);
  });
  await check('HTTP Range editing completes the source and retains unvisited objects',async()=>{
    await page.goto(base+'/?file=/_test/range-large.pdf');await idle();
    await page.locator('#view-mode').selectOption('page');
    await page.locator('#zoom').selectOption('0.75');await idle();
    await page.locator('#edit-toggle').click();
    await page.waitForFunction(()=>!document.querySelector('#editor-toolbar').hidden && !document.querySelector('#edit-toggle').disabled);
    const diagnostics=await page.evaluate(async()=>JSON.parse(await globalThis.pdfViewerHost.pdf.call('cache_info')));
    assert.ok(diagnostics.range.received_bytes>=diagnostics.range.total_bytes);
    await page.locator('#editor-text').fill('Range saved');await frame();
    await draw('text',[[25,600],[150,640]]);
    const dest=await captureDownload();
    assert.ok(readFileSync(dest).length>=diagnostics.range.total_bytes);
    const task=pdfjs.getDocument({data:new Uint8Array(readFileSync(dest)),verbosity:0});
    const document=await task.promise;
    assert.equal(document.numPages,2);
    assert.ok((await (await document.getPage(1)).getAnnotations()).some(annotation=>annotation.contentsObj?.str==='Range saved'));
    await document.getPage(2);
    await task.destroy();
  });
  await check('Real PDF.js form fixture fills saves and reopens with the selected export value',async()=>{
    await page.goto(base+'/?file=/fixtures/annotation-choice-widget.pdf');await idle();
    await page.locator('#edit-toggle').click();
    await page.waitForFunction(()=>!document.querySelector('#editor-toolbar').hidden && !document.querySelector('#edit-toggle').disabled);
    const fields=await entries(),entry=fields.find(entry=>entry.field_type==='Ch' && entry.editable && entry.options.length>1 && !(entry.field_flags&262144));
    assert.ok(entry,'Real fixture has no editable choice control');
    const option=entry.options.find(option=>!option.selected)||entry.options[0];
    await page.locator('[data-editor-id="'+entry.id+'"]').selectOption(option.export_value);await waitField(entry.field_name,[option.export_value]);
    const dest=await captureDownload();
    const task=pdfjs.getDocument({data:new Uint8Array(readFileSync(dest)),verbosity:0});
    const annotations=await (await (await task.promise).getPage(1)).getAnnotations();
    assert.deepEqual(annotations.find(annotation=>annotation.fieldName===entry.field_name).fieldValue,[option.export_value]);
    await task.destroy();
  });
  await check('Encrypted RC4 and AES PDFs retain passwords permissions and edited appearances',async()=>{
    for(let method=0;method<6;method++){
      const name='encrypted-'+method+'.pdf';
      const sourceTask=pdfjs.getDocument({data:new Uint8Array(readFileSync(resolve(output,name))),password:'reader',verbosity:0});
      const before=await sourceTask.promise,permissions=await before.getPermissions(),fingerprint=before.fingerprints[0];
      await sourceTask.destroy();
      await openEncrypted(name,'reader');
      await enterEditor();
      await page.locator('.page[data-page="1"] [data-field-name="person"]').fill('你好 AES '+method);
      await page.locator('.page[data-page="1"] [data-field-name="person"]').press('Tab');await waitField('person',['你好 AES '+method]);
      await page.locator('#editor-text').fill('Encrypted annotation '+method);await frame();
      await draw('text',[[50,110],[205,145]]);
      const dest=await captureDownload(),first=readFileSync(dest);
      if(method>=3){await captureDownload();assert.notDeepEqual(readFileSync(dest),first,'AES saves must use fresh IVs');}
      const locked=pdfjs.getDocument({data:new Uint8Array(readFileSync(dest)),verbosity:0});
      await assert.rejects(locked.promise,{name:'PasswordException'});await locked.destroy();
      for(const password of ['reader','owner']){
        const task=pdfjs.getDocument({data:new Uint8Array(readFileSync(dest)),password,verbosity:0});
        const document=await task.promise;
        assert.deepEqual(await document.getPermissions(),permissions);
        assert.equal(document.fingerprints[0],fingerprint);
        const firstPage=await document.getPage(1),annotations=await firstPage.getAnnotations();
        assert.equal(annotations.find(annotation=>annotation.fieldName==='person').fieldValue,'你好 AES '+method);
        assert.ok(annotations.some(annotation=>annotation.contentsObj?.str==='Encrypted annotation '+method));
        const viewport=firstPage.getViewport({scale:1}),canvas=createCanvas(Math.ceil(viewport.width),Math.ceil(viewport.height));
        await firstPage.render({canvasContext:canvas.getContext('2d'),viewport}).promise;
        assert.equal((await (await document.getPage(2)).getAnnotations()).find(annotation=>annotation.fieldName==='person').fieldValue,'你好 AES '+method);
        await task.destroy();
      }
      await openEncrypted(dest.split('/').at(-1),'reader');
      await enterEditor();await waitField('person',['你好 AES '+method]);
      assert.ok((await entries()).some(entry=>entry.contents==='Encrypted annotation '+method));
      console.log('Verified encrypted fixture:',method);
    }
  });
  await check('Encrypted user permissions restrict editing and owner credentials unlock supported changes',async()=>{
    await openEncrypted('encrypted-6.pdf','reader');await enterEditor();
    for(const tool of ['text','highlight','ink','signature','image']) assert.equal(await page.locator('#edit-'+tool).isDisabled(),true);
    assert.equal(await page.locator('#signature-image').isDisabled(),true);
    const forbidden=await page.evaluate(async()=>JSON.parse(await globalThis.pdfViewerHost.pdf.call('apply_edits',[
      JSON.stringify([{kind:'delete',id:'object:15',page:1}]),
    ])));
    assert.equal(forbidden.ok,false);assert.match(forbidden.error,/permissions/);
    const person=page.locator('.page[data-page="1"] [data-field-name="person"]');
    await person.fill('Permitted form');await person.press('Tab');await waitField('person',['Permitted form']);
    const saved=await captureDownload();
    const task=pdfjs.getDocument({data:new Uint8Array(readFileSync(saved)),password:'reader',verbosity:0});
    const document=await task.promise;
    assert.ok(!(await document.getPermissions()).has(pdfjs.PermissionFlag.MODIFY_ANNOTATIONS));
    assert.equal((await (await document.getPage(1)).getAnnotations()).find(annotation=>annotation.fieldName==='person').fieldValue,'Permitted form');
    await task.destroy();
    await openEncrypted('encrypted-7.pdf','reader');await page.locator('#edit-toggle').click();
    await page.waitForFunction(()=>document.querySelector('#error').textContent.includes('权限禁止'));
    assert.equal(await page.locator('#editor-toolbar').isVisible(),false);
    await openEncrypted('encrypted-7.pdf','owner');await enterEditor();
    assert.equal(await page.locator('#edit-text').isDisabled(),false);
    await page.locator('#editor-text').fill('Owner annotation');await frame();await draw('text',[[50,110],[205,145]]);
    const ownerSaved=await captureDownload();
    const ownerTask=pdfjs.getDocument({data:new Uint8Array(readFileSync(ownerSaved)),password:'reader',verbosity:0});
    const reopened=await ownerTask.promise;
    assert.ok(!(await reopened.getPermissions()).has(pdfjs.PermissionFlag.MODIFY_ANNOTATIONS));
    assert.ok((await (await reopened.getPage(1)).getAnnotations()).some(annotation=>annotation.contentsObj?.str==='Owner annotation'));
    await ownerTask.destroy();
    await openEncrypted('encrypted-8.pdf');await enterEditor();
    assert.equal(await page.locator('#edit-text').isDisabled(),true);
    const blank=page.locator('.page[data-page="1"] [data-field-name="person"]');
    await blank.fill('Empty user password');await blank.press('Tab');await waitField('person',['Empty user password']);
    const blankSaved=await captureDownload();
    const blankTask=pdfjs.getDocument({data:new Uint8Array(readFileSync(blankSaved)),verbosity:0});
    assert.equal((await (await (await blankTask.promise).getPage(1)).getAnnotations()).find(annotation=>annotation.fieldName==='person').fieldValue,'Empty user password');
    await blankTask.destroy();
  });
  await check('Real encrypted PDF.js fixtures preserve edits with ASCII and Unicode passwords',async()=>{
    for(const [name,password] of [['issue6010_1.pdf','abc'],['issue6010_2.pdf','æøå']]){
      writeFileSync(resolve(output,name),readFileSync(resolve('reference/pdf.js/test/pdfs',name)));
      const originalTask=pdfjs.getDocument({data:new Uint8Array(readFileSync(resolve(output,name))),password,verbosity:0});
      const original=await originalTask.promise,permissions=await original.getPermissions();
      const viewport=(await original.getPage(1)).getViewport({scale:1});
      const start=viewport.convertToPdfPoint(viewport.width*.1,viewport.height*.55);
      const end=viewport.convertToPdfPoint(viewport.width*.95,viewport.height*.95);
      await originalTask.destroy();
      await openEncrypted(name,password);await enterEditor();
      await page.locator('#editor-text').fill('Real encrypted note');await frame();
      await draw('text',[start,end]);
      const saved=await captureDownload();
      const task=pdfjs.getDocument({data:new Uint8Array(readFileSync(saved)),password,verbosity:0});
      const document=await task.promise,first=await document.getPage(1);
      assert.deepEqual(await document.getPermissions(),permissions);
      assert.ok((await first.getAnnotations()).some(annotation=>annotation.contentsObj?.str==='Real encrypted note'));
      const view=first.getViewport({scale:1}),canvas=createCanvas(Math.ceil(view.width),Math.ceil(view.height));
      await first.render({canvasContext:canvas.getContext('2d'),viewport:view}).promise;
      await task.destroy();
      await openEncrypted(saved.split('/').at(-1),password);await enterEditor();
      assert.ok((await entries()).some(entry=>entry.contents==='Real encrypted note'));
    }
  });
  assert.deepEqual(errors,[]);
  completed=true;
} catch(error){
  console.error(await page.evaluate(()=>({status:document.querySelector('#editor-status')?.textContent,error:document.querySelector('#error')?.textContent,pages:[...document.querySelectorAll('.page')].map(page=>({page:page.dataset.page,box:page.getBoundingClientRect().toJSON(),entries:page.querySelector('.editor-layer')?.dataset.entries && JSON.parse(page.querySelector('.editor-layer').dataset.entries).length}))})));
  await page.screenshot({path:resolve(output,'failure.png'),fullPage:true}).catch(()=>{});
  console.error('FAIL '+current+':',error);
  process.exitCode=1;
} finally {
  writeFileSync(resolve(output,'report.json'),JSON.stringify({ok:completed,checks,failed:completed?null:current,errors,browser:browser.version()},null,2));
  await browser.close();
  console.log('Editor acceptance: '+checks.length+' passed; '+output);
}

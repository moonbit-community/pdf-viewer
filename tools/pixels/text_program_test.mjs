import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import * as bridge from '../../web/_generated/pdf.js';
import {initializePdfGraphics,renderPdfPage} from '../../web/pdf-runtime.mjs';
import {decodePdfPageData} from '../../web/pdf-page-data.mjs';
import {expandPdfTextRuns} from '../../web/pdf-canvas-text-runs.mjs';
import {expandPdfCanvasProgram} from '../../web/pdf-canvas-program.mjs';
const {createCanvas,Path2D,loadImage}=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url)('@napi-rs/canvas');
await initializePdfGraphics({jbig2:{wasmBytes:readFileSync('vendor/jbig2/jbig2.wasm')}});
const stream=text=>`<< /Length ${text.length} >>\nstream\n${text}\nendstream`;
function fixture(contents){
 const form='BT /F1 18 Tf 10 30 Td (ACA) Tj ET',cmap='begincmap 1 begincodespacerange <00> <FF> endcodespacerange 3 beginbfchar <41> <00660069> <42> <D83DDE00> <43> <0043> endbfchar endcmap';
 const objects=['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
  '<< /Type /Page /Parent 2 0 R /MediaBox [7 13 107 93] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> /XObject << /X 10 0 R >> >> >>',stream(contents),
  '<< /Type /Font /Subtype /Type3 /FontBBox [0 0 600 800] /FontMatrix [.001 .0001 -.0002 .001 0 0] /FirstChar 65 /LastChar 67 /Widths [600 600 500] /Encoding << /Differences [65 /A /B /C] >> /ToUnicode 9 0 R /CharProcs << /A 6 0 R /B 7 0 R /C 8 0 R >> /Resources << >> >>',
  stream('600 0 d0 0 0 m 100 800 400 100 600 800 c 600 0 l h f'),
  stream('600 0 d0 1 0 0 rg 0 0 600 800 re f'),stream('500 0 d0'),stream(cmap),
  `<< /Type /XObject /Subtype /Form /BBox [0 0 100 80] /Group << /S /Transparency /I true /K true /CS /DeviceRGB >> /Resources << /Font << /F1 5 0 R >> >> /Length ${form.length} >>\nstream\n${form}\nendstream`];
 let pdf='%PDF-1.7\n',offsets=[];for(const [i,o] of objects.entries()){offsets.push(pdf.length);pdf+=`${i+1} 0 obj\n${o}\nendobj\n`;}
 const xref=pdf.length;pdf+=`xref\n0 ${objects.length+1}\n0000000000 65535 f \n${offsets.map(n=>String(n).padStart(10,'0')+' 00000 n \n').join('')}trailer\n<< /Root 1 0 R /Size ${objects.length+1} >>\nstartxref\n${xref}\n%%EOF\n`;return new TextEncoder().encode(pdf);
}
function prepare(bytes,compiled){assert(JSON.parse(bridge.open_pdf(bytes)).ok);const r=JSON.parse(bridge.render_page(1,1,0,compiled,compiled,compiled));assert(r.ok,r.error);bridge.close_pdf();return r;}
let checks=0;
for(const contents of [
 'BT /F1 18 Tf 10 30 Td (ACACA) Tj ET',
 'BT /F1 18 Tf 10 30 Td (AABACA) Tj ET',
 'BT /F1 18 Tf 10 30 Td (AC) Tj 0 0 1 rg (AC) Tj ET 1 0 0 rg 70 30 10 10 re f',
 'q 10 15 70 55 re W n .9 .2 -.1 .8 8 10 cm BT /F1 18 Tf 10 30 Td (ACA) Tj ET Q',
 'q 1 0 0 1 10 10 cm /X Do Q q .8 .2 -.1 .9 20 5 cm /X Do Q',
]){
 const bytes=fixture(contents),old=prepare(bytes,false),next=prepare(bytes,true);assert.equal(next.canvas.version,3);
 assert(JSON.parse(bridge.open_pdf(bytes)).ok);
 for(const rotation of [0,90,180,270]){
  const expected=JSON.parse(bridge.render_page(1,1.7,rotation,true,true,true)),packet=bridge.render_page_data(1,1.7,rotation);
  const transferred=structuredClone(packet,{transfer:packet.buffers});
  assert(packet.buffers.every(b=>b.byteLength===0),'Transfer detaches only packet-owned buffers');
  assert.deepEqual(decodePdfPageData(transferred),expected,'Complete affine/Unicode/mixed-scene packet result');
 }
 bridge.close_pdf();
 const raw=expandPdfTextRuns(next.canvas);assert.equal(raw.length,old.canvas.items.length);
 for(let i=0;i<raw.length;i++)assert.deepEqual(raw[i].paint,old.canvas.items[i].paint,'Every source identity, transform and paint field');
 for(const key of ['layer','editor','annotations','accessibility'])assert.deepEqual(next[key],old[key],key);
 assert(raw.some(i=>i.paint.text==='fi'));assert(next.canvas.text_states.length<raw.length);
 const before=JSON.stringify(next.canvas);
 for(const extra of [{returnPixels:false},{nativeCanvas:false,transparent:true},{nativeCanvas:false,tileSize:32}]){
  const a=createCanvas(1,1),b=createCanvas(1,1),options={createCanvas,Path2D,loadImage,width:200,height:160,matrix:[2,.1,-.05,2,0,0],...extra};
  const left=await renderPdfPage(a,old.canvas,options),right=await renderPdfPage(b,next.canvas,options);
  assert.deepEqual(b.getContext('2d').getImageData(0,0,200,160).data,a.getContext('2d').getImageData(0,0,200,160).data);
  for(const key of ['data','shape','premultiplied'])assert.deepEqual(right[key],left[key],key);checks++;
 }
 assert.equal(JSON.stringify(next.canvas),before,'Rendering preserves the immutable state/operand program');
}
const state={kind:'text',paint:{}},base={version:3,text_states:[state],items:[{kind:'text_run',state:0,text:['A'],draws:Array(29).fill(0)}]};
assert(JSON.parse(bridge.open_pdf(fixture('BT /F1 18 Tf (AA) Tj ET'))).ok);
const compatible=JSON.parse(bridge.render_page(1,1,0,true,true));
assert.equal(compatible.canvas.version,2,'A client without text-run capability retains version 2');
assert.equal(compatible.canvas.items.length,2);bridge.close_pdf();
assert.equal(expandPdfTextRuns(base).length,1);
for(const bad of [
 {...base,text_states:null},{...base,text_states:Array(16385).fill(state)},
 {...base,text_states:[{kind:'path',paint:{}}]}, {...base,text_states:[{kind:'text',paint:[]}]},
 ...[-1,.5,1].map(state=>({...base,items:[{...base.items[0],state}]})),
 {...base,items:[{...base.items[0],draws:[0]}]}, {...base,items:[{...base.items[0],text:[42]}]},
 ...[NaN,Infinity,-.5].map(n=>({...base,items:[{...base.items[0],draws:[n,...Array(28).fill(0)]}]})),
 {...base,items:[{...base.items[0],text:Array(4097).fill('A'),draws:Array(4097*29).fill(0)}]},
])assert.throws(()=>expandPdfTextRuns(bad));
assert.throws(()=>expandPdfCanvasProgram({...base,glyph_resources:[]}),'A text operand must reference an existing glyph resource');
console.log(`PASS ${checks} text-program native/retained/tiled comparisons; complete operands, Unicode, mixed fallbacks, Form scopes and malformed packets`);

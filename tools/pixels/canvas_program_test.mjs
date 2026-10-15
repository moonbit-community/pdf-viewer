import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import * as bridge from '../../web/_generated/pdf.js';
import {initializePdfGraphics,renderPdfPage} from '../../web/pdf-runtime.mjs';
import {expandPdfCanvasProgram} from '../../web/pdf-canvas-program.mjs';
const require=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url);
const {createCanvas,Path2D,loadImage}=require('@napi-rs/canvas');
await initializePdfGraphics({jbig2:{wasmBytes:readFileSync('vendor/jbig2/jbig2.wasm')}});
const options={createCanvas,Path2D,loadImage};
function fixture(charproc,contents,extra=''){
 const objects=[
  '<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
  `<< /Type /Page /Parent 2 0 R /MediaBox [17 31 217 191] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> /ExtGState << /GS << /ca .4 >> >> >> >>`,
  `<< /Length ${contents.length} >>\nstream\n${contents}\nendstream`,
  '<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1000 1000] /FontMatrix [.001 .0001 -.0002 .001 0 0] /FirstChar 65 /LastChar 65 /Widths [600] /Encoding << /Type /Encoding /Differences [65 /A] >> /CharProcs << /A 6 0 R >> /Resources << >> >>',
  `<< /Length ${charproc.length} >>\nstream\n${charproc}\nendstream`,
 ];
 let text='%PDF-1.7\n',offsets=[];for(const [i,o] of objects.entries()){offsets.push(text.length);text+=`${i+1} 0 obj\n${o}\nendobj\n`;}
 const xref=text.length;text+=`xref\n0 ${objects.length+1}\n0000000000 65535 f \n`;for(const n of offsets)text+=String(n).padStart(10,'0')+' 00000 n \n';
 text+=`trailer\n<< /Size ${objects.length+1} /Root 1 0 R ${extra} >>\nstartxref\n${xref}\n%%EOF\n`;return new TextEncoder().encode(text);
}
function prepare(bytes,omit){assert(JSON.parse(bridge.open_pdf(bytes)).ok);const result=JSON.parse(bridge.render_page(1,1,0,omit,omit));assert(result.ok);bridge.close_pdf();return result;}
let checks=0;
for(const [name,charproc,compiled] of [
 ['curve','600 0 0 0 600 900 d1 0 0 m 80 900 400 100 600 900 c 600 0 l h f',true],
 ['evenodd','600 0 0 0 600 900 d1 1 0 0 rg 0 0 600 900 re 100 200 300 400 re f*',true],
 ['empty','600 0 d0',true],
 ['saved path','600 0 d0 0 0 m q 100 800 l Q 600 0 l h f',true],
 ['degenerate','600 0 d0 100 0 m 100 900 l h f',true],
 ['coloured fallback','600 0 d0 1 0 0 rg 0 0 600 900 re f',false],
 ['matrix fallback','600 0 d0 1 .2 0 1 0 0 cm 0 0 600 900 re f',false],
 ['stroke fallback','600 0 d0 0 0 600 900 re S',false],
 ['multiple paints fallback','600 0 d0 0 0 300 900 re f 300 0 300 900 re f',false],
]){
 for(const mode of [0,1,2,3,4,5,6,7]){
  const bytes=fixture(charproc,`1 0 0 1 23 37 cm 0 .2 .8 rg 0 0 180 140 re W n BT /F1 40 Tf ${mode} Tr 5 10 Td (AA) Tj ET`),old=prepare(bytes,false),next=prepare(bytes,true);
  assert.equal(next.canvas.version,compiled&&mode!==3?2:1,name+' version');
  for(const key of ['layer','editor','annotations','accessibility'])assert.deepEqual(next[key],old[key],name+' '+key);
  for(const retained of [false,true]){
   const a=createCanvas(1,1),b=createCanvas(1,1),opts={...options,width:400,height:320,matrix:[2,.15,-.1,2,0,0],returnPixels:retained,nativeCanvas:!retained};
   await renderPdfPage(a,old.canvas,opts);await renderPdfPage(b,next.canvas,opts);
   assert.deepEqual(b.getContext('2d').getImageData(0,0,b.width,b.height).data,a.getContext('2d').getImageData(0,0,a.width,a.height).data,`${name} mode ${mode} retained ${retained}`);checks++;
  }
 }
}
const bytes=fixture('600 0 d0 0 0 600 900 re f','/GS gs BT /F1 40 Tf 20 30 Td (AA) Tj ET');
assert.equal(prepare(bytes,true).canvas.version,1,'Inherited transparency retains the interpreter');
assert(JSON.parse(bridge.open_pdf(fixture('600 0 d0 0 0 600 900 re f','BT /F1 40 Tf 20 30 Td (A) Tj ET'))).ok);
const compact=JSON.parse(bridge.render_page(1,1,0,true,true));
assert.equal(compact.canvas.version,2);
let intermediateSurfaces=0;
await renderPdfPage(createCanvas(1,1),compact.canvas,{...options,returnPixels:false,width:1000,height:1000,maxWorkingBytes:64*1024*1024,
 createCanvas:(w,h)=>{if(w>1||h>1)intermediateSurfaces++;return createCanvas(w,h);}});
assert.equal(intermediateSurfaces,0,'Expand before choosing native memory accounting and tiled rendering');
const before=JSON.parse(bridge.cache_info());assert.equal(before.compiled_resources.entries,1);
assert.equal(JSON.parse(bridge.render_page(1,1,0,false)).canvas.version,1,'A later SVG request rebuilds the complete public model');
assert(JSON.parse(bridge.render_page(1,2,90,false)).svg.includes('<svg'));
assert(JSON.parse(bridge.cache_info()).estimated_bytes<=before.budget_bytes);
bridge.close_pdf();
const resource={id:6,commands:[0,0,0,1,1,0,1,0,1,3],even_odd:false},base={version:2,page:{origin_x:0,origin_y:0,height:20},glyph_resources:[resource],items:[{kind:'text',glyph:{resource:6,matrix:[1,0,0,1,0,0]},paint:{bounds:{min_x:0,min_y:0,max_x:1,max_y:1}}}]};
for(const bad of [
 {...base,glyph_resources:[resource,resource]},
 {...base,glyph_resources:[{...resource,commands:[9]}]},
 {...base,glyph_resources:[{...resource,commands:[0,Infinity,0]}]},
 {...base,glyph_resources:[{...resource,commands:[2,0]}]},
 {...base,items:[{...base.items[0],glyph:{resource:7,matrix:[1,0,0,1,0,0]}}]},
 {...base,items:[{...base.items[0],glyph:{resource:6,matrix:[1,0]}}]},
])assert.throws(()=>expandPdfCanvasProgram(bad));
console.log(`PASS ${checks} compiled/legacy native and retained pixel comparisons; semantics, SVG upgrade and malformed resources`);

import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import * as bridge from '../../web/_generated/pdf.js';
import {initializePdfGraphics,renderPdfPage} from '../../web/pdf-runtime.mjs';
import {expandPdfCanvasProgram} from '../../web/pdf-canvas-program.mjs';
const {createCanvas,Path2D,loadImage}=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url)('@napi-rs/canvas');
await initializePdfGraphics({jbig2:{wasmBytes:readFileSync('vendor/jbig2/jbig2.wasm')}});
const options={createCanvas,Path2D,loadImage};
function fixture(type,contents){
 const geometry=type===1?'/Domain [0 1 0 1] /Matrix [80 0 0 65 7 13]':`/Coords [${type===2?'7 13 103 93':'30 30 2 55 45 60'}]`;
 const fn=type===1?'6 0 R':'<< /FunctionType 2 /Domain [0 1] /C0 [.1 .2 .8] /C1 [.9 .7 .1] /N 2 >>';
 const objects=['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
  '<< /Type /Page /Parent 2 0 R /MediaBox [7 13 103 93] /Contents 4 0 R /Resources << /Shading << /S 5 0 R >> /ExtGState << /GS << /ca .43 >> >> >> >>',
  `<< /Length ${contents.length} >>\nstream\n${contents}\nendstream`,
  `<< /ShadingType ${type} /ColorSpace /DeviceRGB ${geometry} /Extend [true false] /BBox [8 14 100 90] /Background [.1 .2 .3] /Function ${fn} >>`];
 if(type===1){const code='{ pop dup dup }';objects.push(`<< /FunctionType 4 /Domain [0 1 0 1] /Range [0 1 0 1 0 1] /Length ${code.length} >>\nstream\n${code}\nendstream`);}
 let text='%PDF-1.7\n',offsets=[];for(const [i,o] of objects.entries()){offsets.push(text.length);text+=`${i+1} 0 obj\n${o}\nendobj\n`;}
 const xref=text.length;text+=`xref\n0 ${objects.length+1}\n0000000000 65535 f \n`;for(const n of offsets)text+=String(n).padStart(10,'0')+' 00000 n \n';
 text+=`trailer\n<< /Size ${objects.length+1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;return new TextEncoder().encode(text);
}
function prepare(bytes,compact){assert(JSON.parse(bridge.open_pdf(bytes)).ok);const result=JSON.parse(bridge.render_page(1,1,0,compact,compact));assert(result.ok,result.error);bridge.close_pdf();return result;}
let checks=0;
for(const type of [1,2,3])for(const prefix of ['', '/GS gs']){
 const bytes=fixture(type,`q ${prefix} 10 16 34 42 re W n /S sh Q q ${prefix} .8 .15 -.1 .9 18 5 cm 45 20 40 50 re W n /S sh Q`);
 const legacy=prepare(bytes,false),compact=prepare(bytes,true),expanded=expandPdfCanvasProgram(compact.canvas);
 assert.equal(compact.canvas.version,2);assert.equal(compact.canvas.shading_resources.length,1);
 const calls=expanded.items.filter(i=>i.kind==='shading');assert.equal(calls.length,2);
 assert.equal(calls[0].paint.shading.raster,calls[1].paint.shading.raster,'Placements retain shared object identity');
 assert.deepEqual(expanded,legacy.canvas,'Expansion recovers the complete legacy plan');
 for(const key of ['layer','editor','annotations','accessibility'])assert.deepEqual(compact[key],legacy[key],key);
 for(const extra of [{nativeCanvas:true},{nativeCanvas:false,transparent:true},{nativeCanvas:false,tileSize:32}]){
  const a=createCanvas(1,1),b=createCanvas(1,1),opts={...options,width:192,height:160,matrix:[2,.1,-.05,2,0,0],...extra};
  const old=await renderPdfPage(a,legacy.canvas,opts),next=await renderPdfPage(b,compact.canvas,opts);
  for(const key of ['data','shape','premultiplied'])assert.deepEqual(next[key],old[key],`${type} ${prefix} ${key}`);checks++;
 }
 assert(JSON.parse(bridge.open_pdf(bytes)).ok);assert(JSON.parse(bridge.render_page(1,1,0,true,true)).ok);
 assert(JSON.parse(bridge.render_page(1,1,0,false,false)).svg.includes('<svg'),'Later SVG requests rebuild public models');bridge.close_pdf();
}
const base={version:2,glyph_resources:[],shading_resources:[{id:0,raster:{}}],items:[{kind:'shading',paint:{shading:{raster_resource:0}}}]};
for(const bad of [
 {...base,shading_resources:{}}, {...base,shading_resources:Array(65).fill({id:0,raster:{}})},
 {...base,shading_resources:[{id:0,raster:null}]}, {...base,shading_resources:[{id:0,raster:[]}]},
 {...base,shading_resources:[...base.shading_resources,...base.shading_resources]},
 {...base,items:[{kind:'path',paint:{shading:{raster_resource:0}}}]},
 {...base,items:[{kind:'shading',paint:{shading:{raster_resource:1}}}]},
 {...base,items:[{kind:'shading',paint:{shading:{raster_resource:.5}}}]},
])assert.throws(()=>expandPdfCanvasProgram(bad));
// Decode each shared source once across placements and tiles, then discard the
// cache. A caller may mutate a host-authored plan before a subsequent render.
const owned=prepare(fixture(2,'/S sh q .8 0 0 .8 7 13 cm /S sh Q'),true).canvas;
const atob=globalThis.atob;let decodes=0;
globalThis.atob=value=>{decodes++;return atob(value);};
try{
 for(const tileSize of [0,32]){
  decodes=0;await renderPdfPage(createCanvas(1,1),owned,{...options,tileSize});
  assert.equal(decodes,1,'Decode once across placements and tiles');
 }
 const before=await renderPdfPage(createCanvas(1,1),owned,options),raster=owned.shading_resources[0].raster;
 raster.samples=Buffer.alloc(Buffer.from(raster.samples,'base64').length).toString('base64');
 decodes=0;const after=await renderPdfPage(createCanvas(1,1),owned,options);
 assert.equal(decodes,1,'A separate render owns a fresh decoder cache');assert.notDeepEqual(after.data,before.data);
}finally{globalThis.atob=atob;}
console.log(`PASS ${checks} shared shading native/retained/tiled pixel comparisons; exact plan, semantics, ownership, SVG upgrade and malformed resources`);

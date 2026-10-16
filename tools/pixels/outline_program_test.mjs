import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import * as bridge from '../../web/_generated/pdf.js';
import {initializePdfGraphics,renderPdfPage} from '../../web/pdf-runtime.mjs';
import {expandPdfCanvasProgram} from '../../web/pdf-canvas-program.mjs';
const require=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url);
const {createCanvas,Path2D,loadImage}=require('@napi-rs/canvas');
await initializePdfGraphics({jbig2:{wasmBytes:readFileSync('vendor/jbig2/jbig2.wasm')}});
const options={createCanvas,Path2D,loadImage},ascii=s=>[...Buffer.from(s)],hex=a=>Buffer.from(a).toString('hex')+'>';
function number(n){if(n>=-107&&n<=107)return[n+139];if(n>=108&&n<=1131)return[247+((n-108)>>8),(n-108)&255];if(n<=-108&&n>=-1131)return[251+((-n-108)>>8),(-n-108)&255];throw Error('Fixture integer out of range');}
const op=(values,code)=>[...values.flatMap(number),code];
function type1(){
 const a=[...op([0,500],13),...op([0,0],21),...op([500,0],5),...op([0,700],5),...op([-500,0],5),14];
 const b=[...op([0,500],13),...op([50,80],21),...op([80,200,120,300,200,-300],8),...op([-400,-200],5),14];
 const plain=[0,0,0,0,...ascii('/lenIV -1 def\n/Subrs 0 array def\n/CharStrings 2 dict dup begin\n'),...ascii(`/A ${a.length} RD `),...a,...ascii(' ND\n'),...ascii(`/B ${b.length} RD `),...b,...ascii(' ND\nend\n')];
 let state=55665;const encrypted=plain.map(p=>{const c=p^(state>>8);state=((c+state)*52845+22719)&65535;return c;});
 return[...ascii('/FontMatrix [.001 .0001 -.0002 .001 0 0] def\n/Encoding StandardEncoding def\neexec\n'),...encrypted];
}
function cff(){
 const index=arrays=>arrays.length?[0,arrays.length,1,1,...arrays.reduce((a,v)=>[...a,a.at(-1)+v.length],[1]).slice(1),...arrays.flat()]:[0,0];
 const int=n=>[29,(n>>>24)&255,(n>>>16)&255,(n>>>8)&255,n&255];
 const top=(charset,chars)=>index([[...int(charset),15,...int(chars),17]]),name=index([ascii('OutlineTest')]);
 const start=4+name.length+top(0,0).length+4,charset=[0,0,34,0,35];
 const a=[...op([0,0],21),...op([500,0,0,700,-500,0],5),14],b=[...op([50,80],21),...op([80,200,120,300,200,-300],8),...op([-400,-200],5),14];
 return[1,0,4,4,...name,...top(start,start+charset.length),0,0,0,0,...charset,...index([[14],a,b])];
}
function fixture(kind,contents){
 const font=kind==='type1'?type1():cff(),file=kind==='type1'?'FontFile':'FontFile3',fontDictionary=name=>`<< /Type /Font /Subtype /Type1 /BaseFont /OutlineTest /FirstChar 65 /LastChar 65 /Widths [500] /Encoding << /Differences [65 /${name}] >> /FontDescriptor 6 0 R >>`;
 const objects=['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
  '<< /Type /Page /Parent 2 0 R /MediaBox [17 31 217 191] /Resources << /Font << /F1 5 0 R /F2 8 0 R >> /ExtGState << /GS << /ca .35 /BM /Multiply >> /Mask << /SMask << /S /Alpha /G 9 0 R >> >> >> /Pattern << /P 10 0 R >> >> /Contents 4 0 R >>',
  `<< /Length ${contents.length} >>\nstream\n${contents}\nendstream`,fontDictionary('A'),
  `<< /Type /FontDescriptor /FontName /OutlineTest /Flags 32 /FontBBox [0 0 1000 1000] /Ascent 1000 /Descent 0 /ItalicAngle 0 /StemV 80 /${file} 7 0 R >>`,
  `<< /Length ${hex(font).length} /Filter /ASCIIHexDecode ${kind==='cff'?'/Subtype /Type1C':''} >>\nstream\n${hex(font)}\nendstream`,fontDictionary('B'),
  '<< /Type /XObject /Subtype /Form /BBox [17 31 217 191] /Group << /S /Transparency /CS /DeviceRGB >> /Resources << >> /Length 21 >>\nstream\n1 g 17 31 90 160 re f\nendstream',
  '<< /Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 8 8] /XStep 8 /YStep 8 /Resources << >> /Length 21 >>\nstream\n1 0 0 rg 0 0 4 8 re f\nendstream'];
 let text='%PDF-1.7\n',offsets=[];for(const [i,obj] of objects.entries()){offsets.push(text.length);text+=`${i+1} 0 obj\n${obj}\nendobj\n`;}
 const xref=text.length;text+=`xref\n0 ${objects.length+1}\n0000000000 65535 f \n${offsets.map(n=>String(n).padStart(10,'0')+' 00000 n \n').join('')}trailer\n<< /Root 1 0 R /Size ${objects.length+1} >>\nstartxref\n${xref}\n%%EOF\n`;
 return new TextEncoder().encode(text);
}
function prepare(bytes,compiled){assert(JSON.parse(bridge.open_pdf(bytes)).ok);const result=JSON.parse(bridge.render_page(1,1,0,compiled,compiled,compiled));assert(result.ok,result.error);bridge.close_pdf();return result;}
let checks=0;
for(const kind of ['type1','cff'])for(const mode of [0,1,2,3,4,5,6,7])for(const prefix of ['', '/GS gs', '/Mask gs', '/Pattern cs /P scn']){
 const bytes=fixture(kind,`q .8 .3 -.2 1 30 40 cm 0 .2 .8 rg ${prefix} 20 30 160 120 re W n BT /F1 35 Tf ${mode} Tr 25 40 Td (AA) Tj /F2 29 Tf (AA) Tj ET Q 1 0 0 rg 80 70 15 15 re f`),old=prepare(bytes,false),next=prepare(bytes,true);
 assert.equal(next.canvas.version,mode===0?3:1,kind+' mode '+mode);
 if(mode===0){assert.equal(next.canvas.glyph_resources.length,2,'Distinct PDF encodings of the same program');assert(next.canvas.glyph_resources.every(r=>r.kind==='outline'));}
 for(const key of ['layer','editor','annotations','accessibility'])assert.deepEqual(next[key],old[key],kind+' '+key);
 const expanded=expandPdfCanvasProgram(next.canvas);
 assert.deepEqual(expanded.items.map(i=>i.paint.fill_path),old.canvas.items.map(i=>i.paint.fill_path),kind+' exact positioned paths');
 for(const retained of [false,true]){
  const a=createCanvas(1,1),b=createCanvas(1,1),opts={...options,width:400,height:320,matrix:[2,.15,-.1,2,0,0],returnPixels:retained,nativeCanvas:!retained};
  await renderPdfPage(a,old.canvas,opts);await renderPdfPage(b,next.canvas,opts);
  assert.deepEqual(b.getContext('2d').getImageData(0,0,b.width,b.height).data,a.getContext('2d').getImageData(0,0,a.width,a.height).data,`${kind} ${mode} ${prefix} retained ${retained}`);checks++;
 }
}
const malformed={version:2,page:{origin_x:0,origin_y:0,height:100},items:[{kind:'text',paint:{},glyph:{resource:-1,matrix:[1,0,0,1,0,0]}}]};
for(const commands of [[9],[0,1],[0,Infinity,0]])assert.throws(()=>expandPdfCanvasProgram({...malformed,glyph_resources:[{id:-1,kind:'outline',commands}]}));
assert.throws(()=>expandPdfCanvasProgram({...malformed,glyph_resources:[{id:-1,kind:'unknown',commands:[]}]}));
console.log(`PASS ${checks} ordinary glyph native/retained pixel comparisons; exact paths, encodings, clipping, masks, patterns, alpha, blend and semantics`);

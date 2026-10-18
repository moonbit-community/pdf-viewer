import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import * as bridge from '../../web/_generated/pdf.js';
import {makePdf,stream} from './readonly_fixtures.mjs';
import {initializePdfGraphics,renderPdfPage} from '../../web/pdf-runtime.mjs';
import {expandPdfCanvasProgram,prepareNativePdfProgram,nativePdfGlyphRun,nativePdfGlyphPath} from '../../web/pdf-canvas-program.mjs';
import {prepareNativeCanvasItems} from '../../web/pdf-canvas-native.mjs';

const require=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url);
const {createCanvas,Path2D,loadImage}=require('@napi-rs/canvas');
await initializePdfGraphics({jbig2:{wasmBytes:readFileSync('vendor/jbig2/jbig2.wasm')}});
const fonts=JSON.parse(readFileSync('assets/standard14/inventory.json')).fonts;
function fixture(font,embedded,prefix,mode=0){
  const content=`q -.8 .3 .2 1 180 15 cm ${prefix} 20 30 160 120 re W n BT /F1 23 Tf ${mode} Tr 25 40 Td (AB a8) Tj /F2 19 Tf (AB) Tj ET Q`;
  const dictionary=diff=>`<< /Type /Font /Subtype /${embedded?'TrueType':'Type1'} /BaseFont /${embedded?'EmbeddedProbe':font.name} /Encoding << /BaseEncoding /WinAnsiEncoding /Differences [65 /${diff}] >> /FirstChar 0 /LastChar 255 /Widths [${Array(256).fill(600).join(' ')}] ${embedded?'/FontDescriptor 8 0 R':''} /ToUnicode 7 0 R >>`;
  const objects=[
    '<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [17 31 217 191] /Resources << /Font << /F1 5 0 R /F2 6 0 R >> /ExtGState << /GS << /ca .35 /BM /Multiply >> /Mask << /SMask << /S /Alpha /G 10 0 R >> >> >> /Pattern << /P 11 0 R >> >> /Contents 4 0 R >>',
    stream('',content),dictionary('Z'),dictionary('A'),
    stream('','3 beginbfchar <41> <D83DDE00> <42> <> <61> <FFFD> endbfchar'),
    '<< /Type /FontDescriptor /FontName /EmbeddedProbe /Flags 32 /FontBBox [0 -600 2100 2200] /Ascent 1900 /Descent -500 /ItalicAngle 0 /StemV 80 /FontFile2 9 0 R >>',
    embedded?stream('',readFileSync('reference/pdf.js/external/standard_fonts/'+font.file)):'null',
    stream('/Type /XObject /Subtype /Form /BBox [17 31 217 191] /Group << /S /Transparency /CS /DeviceRGB >> /Resources << >>','1 g 17 31 90 160 re f'),
    stream('/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 8 8] /XStep 8 /YStep 8 /Resources << >>','1 0 0 rg 0 0 4 8 re f'),
  ];
  return makePdf(objects);
}
function prepare(bytes,compiled){
  assert(JSON.parse(bridge.open_pdf(bytes)).ok);
  const result=JSON.parse(bridge.render_page(1,1,0,compiled,compiled,compiled));
  assert(result.ok,result.error);bridge.close_pdf();return result;
}
let checks=0,quadratics=0;
// A1 omits optional whitespace between closed contours. Keep every command
// and decimal coordinate exact while comparing this equivalent SVG spelling.
const contourSpacing=path=>path.replace(/ZM/g,'Z M');
for(const font of fonts)for(const embedded of font.file.endsWith('.ttf')?[false,true]:[false])for(const prefix of ['', '/GS gs','/Mask gs','/Pattern cs /P scn']){
  const bytes=fixture(font,embedded,prefix),old=prepare(bytes,false),next=prepare(bytes,true);
  assert.equal(next.canvas.version,3,font.name+' uses shared outlines');
  assert(next.canvas.glyph_resources.length>=2,'Distinct encodings retain their own glyph identities');
  const expanded=expandPdfCanvasProgram(next.canvas);
  assert.deepEqual(expanded.items.map(item=>contourSpacing(item.paint.fill_path)),old.canvas.items.map(item=>contourSpacing(item.paint.fill_path)),'Exact commands and decimal coordinates, including TrueType normalization and affine arithmetic');
  for(const key of ['layer','editor','annotations','accessibility'])assert.deepEqual(next[key],old[key],font.name+' '+key);
  quadratics+=expanded.items.filter(item=>item.paint.fill_path.includes(' Q ')).length;
  if(!prefix){
    const native=prepareNativePdfProgram(next.canvas,{returnPixels:false},prepareNativeCanvasItems);
    assert(native,'Compact native consumption');
    const paths=native.items.flatMap(item=>{const run=nativePdfGlyphRun(item);return Array.from({length:run.glyphs},(_,i)=>nativePdfGlyphPath(run,i*7));});
    assert.deepEqual(paths,expanded.items.map(item=>item.paint.fill_path));
  }
  for(const retained of [false,true]){
    const a=createCanvas(1,1),b=createCanvas(1,1),options={createCanvas,Path2D,loadImage,width:400,height:320,matrix:[1.7,.13,-.1,1.6,3,2],returnPixels:retained,nativeCanvas:!retained};
    await renderPdfPage(a,old.canvas,options);await renderPdfPage(b,next.canvas,options);
    assert.deepEqual(b.getContext('2d').getImageData(0,0,400,320).data,a.getContext('2d').getImageData(0,0,400,320).data,font.name+' '+embedded+' '+prefix+' '+retained);
    checks++;
  }
}
assert(quadratics>0,'Exercise actual quadratic curves, not only line contours');
const quadratic=prepare(fixture(fonts.find(font=>font.name==='Helvetica'),false,''),true).canvas;
const owned=prepareNativePdfProgram(quadratic,{returnPixels:false},prepareNativeCanvasItems);
const paths=owned.items.flatMap(item=>{const run=nativePdfGlyphRun(item);return Array.from({length:run.glyphs},(_,i)=>nativePdfGlyphPath(run,i*7));});
quadratic.glyph_resources.forEach(resource=>resource.commands.fill(999));
assert.deepEqual(owned.items.flatMap(item=>{const run=nativePdfGlyphRun(item);return Array.from({length:run.glyphs},(_,i)=>nativePdfGlyphPath(run,i*7));}),paths,'Quadratic coordinates are render-owned snapshots');
for(const commands of [[4,1,2,3],[4,0,NaN,0,0],[4,0,0,Infinity,0]]){
  const bad=prepare(fixture(fonts.find(font=>font.name==='Helvetica'),false,''),true).canvas;
  bad.glyph_resources[0].commands=commands;
  assert.throws(()=>expandPdfCanvasProgram(bad));
  assert.throws(()=>prepareNativePdfProgram(bad,{returnPixels:false},prepareNativeCanvasItems));
}
for(const mode of [1,2,3,4,5,6,7]){
  const bytes=fixture(fonts.find(font=>font.name==='Helvetica'),false,'',mode);
  assert.deepEqual(prepare(bytes,true).canvas,prepare(bytes,false).canvas,'Stroked, clipped and invisible modes keep the complete public path');
}
console.log(`PASS ${checks} Standard 14 / embedded TrueType native and retained pixel comparisons; exact commands and coordinates, quadratic curves, encodings, Unicode, clipping, masks, patterns and translucency`);

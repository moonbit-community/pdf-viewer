// Regressions from PR #1, exercised through the public PDF bridge and renderer.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync} from 'node:fs';
import * as bridge from '../../web/_generated/pdf.js';
import {renderPdfPage} from '../../web/pdf-runtime.mjs';
import {createPdfIccEngine} from '../../web/pdf-icc.mjs';
import {annotationFixture,makePdf} from './readonly_fixtures.mjs';
const require=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url);
const {createCanvas,Path2D,loadImage,GlobalFonts}=require('@napi-rs/canvas');
const options={createCanvas,Path2D,loadImage,convertProcess:v=>bridge.process_cmyk_to_rgb(...v)};
const stream=(dict,body)=>`<< ${dict} /Length ${body.length} >>\nstream\n${body}\nendstream`;
function pdf(objects){
 let text='%PDF-1.7\n',offsets=[];
 for(const [i,object] of objects.entries()){offsets.push(text.length);text+=`${i+1} 0 obj\n${object}\nendobj\n`;}
 const position=text.length;
 return new TextEncoder().encode(text+`xref\n0 ${objects.length+1}\n0000000000 65535 f \n`+offsets.map(v=>`${String(v).padStart(10,'0')} 00000 n \n`).join('')+`trailer << /Size ${objects.length+1} /Root 1 0 R >>\nstartxref\n${position}\n%%EOF\n`);
}
function page(content,resources='',extra=[],group='',size='20 20'){
 const bytes=pdf(['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>',`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${size}] /Resources << ${resources} >> ${group} /Contents 4 0 R >>`,stream('',content),...extra]);
 const opened=JSON.parse(bridge.open_pdf(bytes));assert.equal(opened.ok,true,opened.error);
 const result=JSON.parse(bridge.render_page(1,1,0));assert.equal(result.ok,true,result.error);return result.canvas;
}
const sample=(result,x,y)=>Array.from(result.data.slice((y*result.width+x)*4,(y*result.width+x)*4+4));
const near=(actual,expected)=>expected.forEach((v,i)=>assert.ok(Math.abs(actual[i]-v)<=2,`${actual} != ${expected}`));
delete globalThis.__moonbit_pdf_icc;
const profile=readFileSync(new URL('../../assets/icc/rgb-gamma22.icc',import.meta.url));
const ordinary=page('/C cs .2 .5 .8 scn 0 0 20 20 re f','/ColorSpace << /C [/ICCBased 5 0 R] >>',[stream('/N 3 /Alternate /DeviceRGB /Filter /ASCIIHexDecode',profile.toString('hex')+'>')]);
assert.equal(ordinary.icc_profiles.length,1);
near(sample(await renderPdfPage(createCanvas(1,1),ordinary,options),10,10),[51,128,204,255]);
const engine=await createPdfIccEngine();globalThis.__moonbit_pdf_icc=engine;
try{
 // A repeated-colour ICC image must decode once for painting and semantics,
 // and successful CMM results must be reused without changing output colours.
 const rgb=Buffer.alloc(32*32*3);
 for(let i=0;i<32*32;i++)rgb.set(i%2?[32,96,160]:[255,255,255],i*3);
 const binaryStream=(dict,bytes)=>Buffer.concat([Buffer.from(`<< ${dict} /Length ${bytes.length} >>\nstream\n`),bytes,Buffer.from('\nendstream')]);
 const imagePdf=makePdf(['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
  '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 32 32] /Resources << /XObject << /I 5 0 R >> >> /Contents 4 0 R >>',
  stream('','32 0 0 32 0 0 cm /I Do'),binaryStream('/Type /XObject /Subtype /Image /Width 32 /Height 32 /BitsPerComponent 8 /ColorSpace [/ICCBased 6 0 R]',rgb),binaryStream('/N 3 /Alternate /DeviceRGB',profile)]);
 assert.equal(JSON.parse(bridge.open_pdf(imagePdf)).ok,true);
 const samplesBefore=engine.statistics.samples;
 const imagePlan=JSON.parse(bridge.render_page(1,1,0)).canvas;
 assert.equal(engine.statistics.samples-samplesBefore,2,'Two source colours need exactly two CMM conversions, including accessibility');
 const painted=await renderPdfPage(createCanvas(1,1),imagePlan,options);
 const handle=engine.open(profile,3,1),converted=new Float64Array(3);
 handle.convert(32/255,96/255,160/255,0,converted);handle.close();
 for(let y=0;y<32;y++)for(let x=0;x<32;x++)near(sample(painted,x,y),x%2?[...converted].map(v=>Math.round(v*255)).concat(255):[255,255,255,255]);
 const group='/Group << /S /Transparency /CS /DeviceCMYK >>';
 const invalid=page('/C cs .2 .5 .8 scn 0 0 20 20 re f','/ColorSpace << /C [/ICCBased 5 0 R] >>',[stream('/N 3 /Alternate /DeviceRGB','bad')],group);
 const alternate=page('.2 .5 .8 rg 0 0 20 20 re f','',[],group);
 const [a,b]=await Promise.all([renderPdfPage(createCanvas(1,1),invalid,options),renderPdfPage(createCanvas(1,1),alternate,options)]);
 assert.deepEqual(a.data,b.data,'An invalid source profile must retain its legal Alternate in a CMYK group');
}finally{delete globalThis.__moonbit_pdf_icc;engine.dispose();}
for(const [matrix,width,height,axis] of [['1 0 0 16 0 0',16,16,'y'],['16 0 0 1 0 0',16,16,'x']]){
 const body=axis==='y'?'1 g 0 0 1 1 re f 1 0 0 rg 0 .5 1 .5 re f':'1 g 0 0 1 1 re f 1 0 0 rg 0 0 .5 1 re f';
 const plan=page('/Pattern cs /P scn 0 0 16 16 re f','/Pattern << /P 5 0 R >>',[stream(`/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 1 1] /XStep 1 /YStep 1 /Matrix [${matrix}] /Resources << >>`,body)],'',`${width} ${height}`);
 const rendered=await renderPdfPage(createCanvas(1,1),plan,options);
 for(let y=2;y<14;y++)for(let x=2;x<14;x++){
  if((axis==='y'?y:x)===7||(axis==='y'?y:x)===8)continue;
  near(sample(rendered,x,y),(axis==='y'?y:x)<8?[255,0,0,255]:[255,255,255,255]);
 }
 assert.deepEqual(rendered.diagnostics,[]);
}
const logical=page('1 0 0 rg 0 0 10 20 re f');
for(const scale of [1,2,150/72]){
 const surface=createCanvas(1,1),rendered=await renderPdfPage(surface,logical,{...options,outputScale:scale});
 assert.equal(surface.width,Math.ceil(20*scale));assert.equal(surface.height,Math.ceil(20*scale));
 near(sample(rendered,Math.floor(4*scale),Math.floor(8*scale)),[255,0,0,255]);
 near(sample(rendered,Math.floor(16*scale),Math.floor(8*scale)),[255,255,255,255]);
 assert.equal(logical.viewport.width,20);
}
await assert.rejects(()=>renderPdfPage(createCanvas(1,1),logical,{...options,outputScale:NaN}),RangeError);
const full=await renderPdfPage(createCanvas(1,1),logical,options);
const tiled=await renderPdfPage(createCanvas(1,1),logical,{...options,tileSize:7});
assert.deepEqual(tiled.data,full.data);assert.deepEqual(tiled.shape,full.shape);assert.deepEqual(tiled.premultiplied,full.premultiplied);
const complex=page('0.8 0.5 0.2 rg 0 0 20 20 re f q 2 2 16 16 re W n /S gs /Pattern cs /P scn 0 0 20 20 re f Q q /M gs 0 0 1 rg 0 0 20 20 re f Q',
  '/ExtGState << /S << /ca .5 /BM /Multiply >> /M << /SMask << /S /Alpha /G 6 0 R >> >> >> /Pattern << /P 5 0 R >>',
  [stream('/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 4 4] /XStep 4 /YStep 4 /Resources << >>','1 0 0 rg 0 0 2 4 re f'),
   stream('/Type /XObject /Subtype /Form /BBox [0 0 20 20] /Group << /S /Transparency /I true >> /Resources << >>','1 g 3 3 14 14 re f')]);
assert.deepEqual((await renderPdfPage(createCanvas(1,1),complex,{...options,tileSize:7})).data,(await renderPdfPage(createCanvas(1,1),complex,options)).data,'Clips, pattern phase, alpha blending and masks remain continuous across tiles');
assert.equal(JSON.parse(bridge.open_pdf(annotationFixture())).ok,true);
const annotations=JSON.parse(bridge.render_page(1,1,0)).canvas;
const annotationFull=await renderPdfPage(createCanvas(1,1),annotations,options),annotationTiles=await renderPdfPage(createCanvas(1,1),annotations,{...options,tileSize:64});
assert.deepEqual(annotationTiles.data,annotationFull.data,'Annotation fragments preserve anchors and opacity at tile boundaries');
GlobalFonts.register(readFileSync(require.resolve('pdfjs-dist/standard_fonts/LiberationSans-Regular.ttf')),'Liberation Sans');
page('/G gs 2 w 0 g 0 G BT /F1 40 Tf 2 Tr 5 5 Td (A) Tj ET','/Font << /F1 5 0 R >> /ExtGState << /G << /CA .25 /ca .5 >> >>',['<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'],'','40 50');
assert.equal(JSON.parse(bridge.set_font_fallbacks(JSON.stringify([{pdf_name:'/F1',family:'Liberation Sans'}]))).ok,true);
const plan=JSON.parse(bridge.render_page(1,1,0)).canvas;
const actual=await renderPdfPage(createCanvas(1,1),plan,options);
// Composite two independent SVG masks with the PDF's explicit ca/CA as a
// control, without the Canvas coverage/compositing conversion.
const item=plan.items[0],control=createCanvas(40,50),ctx=control.getContext('2d');
ctx.fillStyle='white';ctx.fillRect(0,0,40,50);
for(const [svg,alpha] of [[item.text_fill_svg,.5],[item.text_stroke_svg,.25]]){
 ctx.globalAlpha=alpha;
 const mask=svg.replace(/\b(?:fill-opacity|stroke-opacity|opacity)="[^"]*"/g,'');
 ctx.drawImage(await loadImage(`data:image/svg+xml;base64,${Buffer.from(mask).toString('base64')}`),0,0);
}
const expected=ctx.getImageData(0,0,40,50).data;
let ink=0,minimum=255;
for(let i=0;i<actual.data.length;i+=4){
 if(actual.data[i]<240)ink++;
 minimum=Math.min(minimum,actual.data[i]);
 // ca=.5 followed by CA=.25 cannot darken white below 255*.5*.75.
 assert.ok(actual.data[i]>=95,`host stroke lost CA at pixel ${i/4}`);
 assert.equal(actual.data[i],actual.data[i+1]);assert.equal(actual.data[i],actual.data[i+2]);
 assert.equal(actual.data[i+3],255);
}
assert.ok(minimum<160,'The fill must remain visible');
assert.ok(expected.some((v,i)=>i%4===0&&v<=100),'The independent SVG control must have an overlapping fill and stroke');
assert.ok(ink>200);bridge.close_pdf();
console.log('ICC Alternate, anisotropic pattern axes, output density and host text alpha: passed');

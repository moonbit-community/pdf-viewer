// Original Apache-2.0 authored PDFs. A failed ICC source must forward every
// current image/shading sample through its legal Alternate in a valid target.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync,existsSync} from 'node:fs';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {installPdfIccEngine} from '../../web/pdf-icc.mjs';
import {renderPdfCanvas} from '../../web/pdf-canvas.mjs';
import {createShadingPainter} from '../../web/pdf-shading.mjs';
const require=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url);
const {createCanvas,Path2D,loadImage}=require('@napi-rs/canvas');
const bridge=await import(pathToFileURL(resolve(process.argv[2]||'_build/pixel-plan.mjs')));
const output=resolve(process.env.PDF_PIXEL_OUTPUT||'_build/icc-alternate-acceptance');mkdirSync(output,{recursive:true});
const engine=await installPdfIccEngine();
const rgb=readFileSync(new URL('../../assets/icc/rgb-gamma22.icc',import.meta.url));
const cmykPath='/usr/share/color/icc/ghostscript/default_cmyk.icc';
const cal='[/CalRGB << /WhitePoint [.9642 1 .8249] /Gamma [.5 2 3] /Matrix [.9642 0 0 0 1 0 0 0 .8249] >>]';
const broken=Buffer.alloc(132);broken.writeUInt32BE(132,0);broken.write('RGB ',16);broken.write('acsp',36);
const stream=(dict,data)=>`<< ${dict} /Length ${data.length} >>\nstream\n${data}\nendstream`;
function pdf(objects){let s='%PDF-1.7\n';const offsets=[0];for(const [i,o]of objects.entries()){offsets.push(s.length);s+=`${i+1} 0 obj\n${o}\nendobj\n`;}const start=s.length;s+=`xref\n0 ${objects.length+1}\n0000000000 65535 f \n`+offsets.slice(1).map(n=>`${String(n).padStart(10,'0')} 00000 n \n`).join('');return new TextEncoder().encode(s+`trailer << /Size ${objects.length+1} /Root 1 0 R >>\nstartxref\n${start}\n%%EOF\n`);}
function fixture(kind,alternate,unusable,baseline,target){
 const source=baseline?alternate:'[/ICCBased 7 0 R]',bytes=unusable==='valid'?rgb:unusable?broken:Buffer.from('bad'),profile=target===4?readFileSync(cmykPath):rgb;
 let object,content;
 if(kind==='image'){
  object=stream(`/Type /XObject /Subtype /Image /Width 2 /Height 2 /BitsPerComponent 8 /ColorSpace ${source} /Filter /ASCIIHexDecode`,Buffer.from([10,40,90,200,150,50,60,120,240,230,30,120]).toString('hex')+'>');content='q 32 0 0 32 0 0 cm /X Do Q';
 }else if(kind==='axial'){
  object=`<< /ShadingType 2 /ColorSpace ${source} /Coords [0 0 32 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [.05 .1 .9] /C1 [.9 .8 .1] /N 1 >> >>`;content='/X sh';
 }else{
  object=stream(`/ShadingType 5 /ColorSpace ${source} /BitsPerCoordinate 8 /BitsPerComponent 8 /VerticesPerRow 2 /Decode [0 32 0 32 0 1 0 1 0 1] /Filter /ASCIIHexDecode`,Buffer.from([0,0,20,30,230,255,0,220,30,30,0,255,20,220,230,255,255,220,220,30]).toString('hex')+'>');content='/X sh';
 }
 return pdf(['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>',`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 32 32] ${target==='gray'?'/Group << /S /Transparency /I true /CS /DeviceGray >>':target?'/Group << /S /Transparency /I true /CS [/ICCBased 6 0 R] >>':''} /Resources << /${kind==='image'?'XObject':'Shading'} << /X 5 0 R >> >> /Contents 4 0 R >>`,stream('','/RelativeColorimetric ri '+content),object,stream(`/N ${target===4?4:3} /Filter /ASCIIHexDecode`,profile.toString('hex')+'>'),stream(`/N 3 /Alternate ${alternate} /Filter /ASCIIHexDecode`,bytes.toString('hex')+'>')]);
}
const tests=[['axial','/DeviceRGB',false,3],['axial',cal,false,3],['mesh',cal,false,3],['mesh',cal,true,3],['image',cal,false,3],['image',cal,true,3]];
if(existsSync(cmykPath))tests.push(['mesh',cal,false,4]);
const options={createCanvas,Path2D,loadImage,convertProcess:v=>bridge.process_cmyk_to_rgb(...v)};options.paintShading=createShadingPainter(options);
const reports=[];
try{
 for(const [kind,alternate,unusable,target]of tests){
  const name=`${kind}-${alternate===cal?'cal':'rgb'}-${unusable?'unusable':'malformed'}-target${target}`,images=[],hashes=[];
  for(const baseline of [false,true]){
   const bytes=fixture(kind,alternate,unusable,baseline,target);hashes.push(createHash('sha256').update(bytes).digest('hex'));
   const parsed=JSON.parse(bridge.render_plan(bytes,1,1,0));assert.equal(parsed.ok,true,parsed.error);assert.equal(parsed.canvas.diagnostics?.length||0,0,`${name}: ${JSON.stringify(parsed.canvas.diagnostics)}`);
   const canvas=createCanvas(1,1),result=await renderPdfCanvas(canvas,parsed.canvas,options);assert.equal(result.diagnostics.length,0);
   images.push(canvas.getContext('2d').getImageData(0,0,32,32).data);writeFileSync(`${output}/${name}${baseline?'-direct':''}.png`,canvas.toBuffer('image/png'));canvas.width=1;
  }
  let maximum=0,changed=0;const colours=new Set();for(let i=0;i<images[0].length;i+=4){let d=0;for(let c=0;c<3;c++)d=Math.max(d,Math.abs(images[0][i+c]-images[1][i+c]));maximum=Math.max(maximum,d);if(d>1)changed++;colours.add(Array.from(images[0].slice(i,i+3)).join(','));}
  assert.equal(changed,0,`${name}: max ${maximum}`);assert.ok(colours.size>1,`${name}: constant zero alternate`);reports.push({name,pixels:1024,maximumRgbError:maximum,aboveOneByte:changed,distinctColours:colours.size,pdfSha256:hashes});
 }
 // A valid real input profile in an ordinary display page must resolve its
 // local catalog ID through the page-owned scope, never use DeviceRGB Alternate.
 for(const displayTarget of [0,'gray']){
 const bytes=fixture('mesh','/DeviceRGB','valid',false,displayTarget),parsed=JSON.parse(bridge.render_plan(bytes,1,1,0));
 assert.equal(parsed.ok,true,parsed.error);assert.equal(parsed.canvas.diagnostics?.length||0,0);
 const canvas=createCanvas(1,1);await renderPdfCanvas(canvas,parsed.canvas,options);
 const actual=canvas.getContext('2d').getImageData(0,0,32,32).data,transform=engine.open(rgb,3,1),expected=new Float64Array(3);
 let maximum=0,differentFromAlternate=0;
 for(let y=0;y<32;y++)for(let x=0;x<32;x++){
  const u=(x+.5)/32,v=1-(y+.5)/32,values=[(20+200*u)/255,(30+190*v)/255,(230-200*u)/255];
  assert.ok(transform.convert(...values,0,expected));if(displayTarget==='gray')expected.fill(expected[0]*.3+expected[1]*.59+expected[2]*.11);const index=(y*32+x)*4;
  for(let c=0;c<3;c++){maximum=Math.max(maximum,Math.abs(actual[index+c]-Math.round(Math.max(0,Math.min(1,expected[c]))*255)));if(Math.abs(actual[index+c]-Math.round(values[c]*255))>2)differentFromAlternate++;}
 }
 transform.close();assert.ok(maximum<=1,`valid ICC scoped display: ${maximum}`);assert.ok(differentFromAlternate>0);
 writeFileSync(`${output}/valid-icc-scoped-display-${displayTarget||'rgb'}.png`,canvas.toBuffer('image/png'));canvas.width=1;
 reports.push({name:`valid-icc-raw-mesh-scoped-display-${displayTarget||'rgb'}`,pixels:1024,maximumRgbError:maximum,channelsDifferentFromDeviceRgbAlternate:differentFromAlternate,pdfSha256:createHash('sha256').update(bytes).digest('hex')});
 }
}finally{engine.dispose();}
writeFileSync(`${output}/report.json`,JSON.stringify(reports,null,2)+'\n');console.log(JSON.stringify(reports));

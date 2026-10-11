import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createPdfIccEngine} from '../../web/pdf-icc.mjs';
import {renderPdfCanvas} from '../../web/pdf-canvas.mjs';
import {createPatternPainter} from '../../web/pdf-patterns.mjs';
import {createShadingPainter} from '../../web/pdf-shading.mjs';
const {createCanvas,Path2D,loadImage}=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url)('@napi-rs/canvas');
const rgb=readFileSync(new URL('../../assets/icc/rgb-gamma22.icc',import.meta.url)),cmyk=readFileSync(new URL('../../assets/icc/CGATS001Compat-v2-micro.icc',import.meta.url));
const engine=await createPdfIccEngine(),options={createCanvas,Path2D,loadImage,iccEngine:engine};
const profile=(bytes,n)=>({id:'same-id',components:n,data_base64:bytes.toString('base64')});
const source=(values)=>({space:'ICCBased',components:values,icc_profile_id:'same-id',paints:true});
const paint=(values,alpha=1,blend='normal')=>({kind:'path',paint:{svg_path:'M0 0L20 0L20 20L0 20Z',filled:true,stroked:false,fill_source:source(values),fill_color:'#ff0000',fill_alpha:alpha,blend_mode:blend,clips:[]}});
const plan=(space,bytes,n,items)=>({version:1,icc_profiles:[profile(bytes,n)],blend_profile_id:'same-id',page:{number:1,blend_space:space,origin_x:0,origin_y:0,width:20,height:20},viewport:{width:20,height:20,matrix:[1,0,0,-1,0,20]},items});
const expected=(bytes,n,values)=>{const handle=engine.open(bytes,n),out=new Float64Array(3);assert.ok(handle.convert(...[...values,...Array(4-values.length).fill(0)],out));handle.close();return [...out].map(v=>Math.round(v*255));};
const near=(actual,want,tolerance=2)=>want.forEach((v,c)=>assert.ok(Math.abs(actual[c]-v)<=tolerance,`${actual} differs from ${want}`));
const rgbPlan=plan('DeviceRGB',rgb,3,[paint([.2,.4,.8]),paint([.8,.2,.1],.5,'multiply')]);
const rgbExpected=expected(rgb,3,[.18,.24,.44]);
const cmykPlan=plan('DeviceCMYK',cmyk,4,[paint([.2,.3,.4,.1])]);
const cmykExpected=expected(cmyk,4,[.2,.3,.4,.1]);
const [a,b]=await Promise.all([renderPdfCanvas(createCanvas(1,1),rgbPlan,options),renderPdfCanvas(createCanvas(1,1),cmykPlan,options)]);
near(a.data.slice(0,3),rgbExpected);near(b.data.slice(0,3),cmykExpected);assert.equal(engine.statistics.registeredProfileBytes,0,'concurrent render scopes must release only their own profiles');
const gray=readFileSync(new URL('../../assets/icc/gray-gamma22.icc',import.meta.url));
const grayPlan=plan('DeviceGray',gray,1,[paint([.2]),paint([.8],.5,'multiply')]);
const grayResult=await renderPdfCanvas(createCanvas(1,1),grayPlan,options);near(grayResult.data.slice(0,3),expected(gray,1,[.18]));
const raw=await renderPdfCanvas(createCanvas(1,1),rgbPlan,{...options,transparent:true,outputGroupComponents:true});near(raw.data.slice(0,3),[.18,.24,.44].map(v=>v*255));
const bad={...rgbPlan,items:[paint([.2,.4,.8]),{kind:'bad',paint:{clips:[]}}]};await assert.rejects(()=>renderPdfCanvas(createCanvas(1,1),bad,options),/Unknown PDF/);assert.equal(engine.statistics.registeredProfileBytes,0,'failed replay must release its ICC scope');
function fixture(objects){let text='%PDF-1.7\n',offset=[0];objects.forEach((o,i)=>{offset.push(text.length);text+=`${i+1} 0 obj\n${o}\nendobj\n`;});const xref=text.length;text+=`xref\n0 ${objects.length+1}\n0000000000 65535 f \n`+offset.slice(1).map(v=>`${String(v).padStart(10,'0')} 00000 n \n`).join('')+`trailer << /Size ${objects.length+1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;return Buffer.from(text,'ascii');}
const content='/C cs .2 .4 .8 scn 0 0 20 20 re f /Half gs .8 .2 .1 scn 0 0 20 20 re f',hex=rgb.toString('hex')+'>';
const pdf=fixture(['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>','<< /Type /Page /Parent 2 0 R /MediaBox [0 0 20 20] /Group << /S /Transparency /CS [/ICCBased 5 0 R] >> /Resources << /ColorSpace << /C [/ICCBased 5 0 R] >> /ExtGState << /Half << /ca .5 /BM /Multiply >> >> >> /Contents 4 0 R >>',`<< /Length ${content.length} >>\nstream\n${content}\nendstream`,`<< /N 3 /Alternate /DeviceRGB /Filter /ASCIIHexDecode /Length ${hex.length} >>\nstream\n${hex}\nendstream`]);
mkdirSync('_build/group-colour',{recursive:true});writeFileSync('_build/group-colour/icc-rgb-multiply.pdf',pdf);
if(process.argv[2]){
 const bridge=await import(pathToFileURL(resolve(process.argv[2])));globalThis.__moonbit_pdf_icc=engine;
 const parsed=JSON.parse(bridge.render_plan(pdf,1,1,0));assert.ok(parsed.ok,parsed.error);assert.ok(parsed.canvas.blend_profile_id);assert.equal(parsed.canvas.icc_profiles.length,1);
 const canvas=createCanvas(1,1),result=await renderPdfCanvas(canvas,parsed.canvas,options);near(result.data.slice(0,3),rgbExpected);writeFileSync('_build/group-colour/icc-rgb-multiply.canvas.png',canvas.toBuffer('image/png'));
 const stream=(dict,body)=>`<< ${dict} /Length ${body.length} >>\nstream\n${body}\nendstream`;
 const profileObject=stream('/N 3 /Alternate /DeviceRGB /Filter /ASCIIHexDecode',hex);
 const resources='/ColorSpace << /C [/ICCBased 5 0 R] >> /ExtGState << /Half << /ca .5 /BM /Multiply >> >>';
 const background='/C cs .2 .4 .8 scn 0 0 20 20 re f ';
 const variants=[
  {name:'icc-image',content:background+'/Half gs 20 0 0 20 0 0 cm /Im Do',resources:resources+' /XObject << /Im 6 0 R >>',extra:[stream('/Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace [/ICCBased 5 0 R] /Filter /ASCIIHexDecode','cc331a>')],expected:expected(rgb,3,[.18,.24,.8*(.5+.5*26/255)])},
  {name:'icc-stencil',content:background+'/Half gs .8 .2 .1 scn 20 0 0 20 0 0 cm /Im Do',resources:resources+' /XObject << /Im 6 0 R >>',extra:[stream('/Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 1 /ImageMask true /Filter /ASCIIHexDecode','00>')],expected:rgbExpected},
  {name:'icc-pattern',content:background+'/Half gs /Pattern cs /P scn 0 0 20 20 re f',resources:resources+' /Pattern << /P 6 0 R >>',extra:[stream('/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 5 5] /XStep 5 /YStep 5 /Resources << /ColorSpace << /C [/ICCBased 5 0 R] >> >>','/C cs .8 .2 .1 scn 0 0 5 5 re f')],expected:rgbExpected},
  {name:'icc-shading',content:background+'/Half gs /S sh',resources:resources+' /Shading << /S 6 0 R >>',extra:['<< /ShadingType 2 /ColorSpace [/ICCBased 5 0 R] /Coords [0 0 20 0] /Function << /FunctionType 2 /Domain [0 1] /C0 [.8 .2 .1] /C1 [.8 .2 .1] /N 1 >> /Extend [true true] >>'],expected:rgbExpected},
  {name:'icc-mask-bc',content:'/M gs 0 g 0 0 20 20 re f',resources:'/ExtGState << /M << /SMask << /S /Luminosity /BC [.2 .4 .8] /G 6 0 R >> >> >>',extra:[stream('/Type /XObject /Subtype /Form /BBox [0 0 20 20] /Group << /S /Transparency /I true /CS [/ICCBased 5 0 R] >> /Resources << /ColorSpace << /C [/ICCBased 5 0 R] >> /ExtGState << /H << /ca .5 >> >> >>','/H gs /C cs .8 .2 .1 scn 0 0 20 20 re f')],expected:Array(3).fill(255-expected(rgb,3,[.5,.3,.45]).reduce((a,v,c)=>a+v*[.3,.59,.11][c],0)),rootICC:false},
  {name:'icc-isolated-form',content:'/F Do',resources:'/XObject << /F 6 0 R >>',extra:[stream('/Type /XObject /Subtype /Form /BBox [0 0 20 20] /Group << /S /Transparency /I true /CS [/ICCBased 5 0 R] >> /Resources << '+resources+' >>',background+'/Half gs .8 .2 .1 scn 0 0 20 20 re f')],expected:rgbExpected,rootICC:false},
 ];
 for(const variant of variants){
  const bytes=fixture(['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>',`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 20 20] ${variant.rootICC===false?'':'/Group << /S /Transparency /CS [/ICCBased 5 0 R] >>'} /Resources << ${variant.resources} >> /Contents 4 0 R >>`,stream('',variant.content),profileObject,...variant.extra]);
  writeFileSync(`_build/group-colour/${variant.name}.pdf`,bytes);
  const parsed=JSON.parse(bridge.render_plan(bytes,1,1,0));assert.ok(parsed.ok,parsed.error);
  const target=createCanvas(1,1),opts={...options};opts.paintShading=createShadingPainter(opts);opts.paintPattern=createPatternPainter(opts);
  const rendered=await renderPdfCanvas(target,parsed.canvas,opts);near(rendered.data.slice((10*20+10)*4,(10*20+10)*4+3),variant.expected,3);
  writeFileSync(`_build/group-colour/${variant.name}.canvas.png`,target.toBuffer('image/png'));
 }
 for(const [name,space,components,background,foreground,want] of [
  ['cal-rgb','[/CalRGB << /WhitePoint [.95047 1 1.08883] /Gamma [2.2 1.8 2.4] /Matrix [.4124564 .2126729 .0193339 .3575761 .7151522 .119192 .1804375 .072175  .9503041] >>]',3,'.2 .4 .8','.8 .2 .1',[.18,.24,.44]],
  ['cal-gray','[/CalGray << /WhitePoint [.95047 1 1.08883] /Gamma 2.2 >>]',1,'.2','.8',[.18]],
 ]){
  const content=`/C cs ${background} scn 0 0 20 20 re f /H gs ${foreground} scn 0 0 20 20 re f`;
  const bytes=fixture(['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>',`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 20 20] /Group << /S /Transparency /CS ${space} >> /Resources << /ColorSpace << /C ${space} >> /ExtGState << /H << /ca .5 /BM /Multiply >> >> >> /Contents 4 0 R >>`,stream('',content)]);
  writeFileSync(`_build/group-colour/${name}.pdf`,bytes);
  const parsed=JSON.parse(bridge.render_plan(bytes,1,1,0));assert.ok(parsed.ok,parsed.error);assert.equal(parsed.canvas.blend_calibration.components,components);
  const target=createCanvas(1,1),rendered=await renderPdfCanvas(target,parsed.canvas,options),scope=engine.createProfileScope(parsed.canvas.icc_profiles);
  const expected=scope.groupToRgb(want,{calibration:parsed.canvas.blend_calibration,components});scope.dispose();near(rendered.data.slice(0,3),expected.map(v=>v*255),3);
  writeFileSync(`_build/group-colour/${name}.canvas.png`,target.toBuffer('image/png'));
  for(const variant of ['image','pattern','stencil']){
   const resource=variant!=='pattern'?`/XObject << /Im 5 0 R >>`:`/Pattern << /P 5 0 R >>`;
   const inner=variant==='stencil'?stream('/Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 1 /ImageMask true /Filter /ASCIIHexDecode','00>'):variant==='image'?stream(`/Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace ${space} /Filter /ASCIIHexDecode`,components===1?'cc>':'cc331a>'):stream(`/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 5 5] /XStep 5 /YStep 5 /Resources << /ColorSpace << /C ${space} >> >>`,`/C cs ${foreground} scn 0 0 5 5 re f`);
   const content=`/C cs ${background} scn 0 0 20 20 re f /H gs `+(variant!=='pattern'?`${foreground} scn 20 0 0 20 0 0 cm /Im Do`:'/Pattern cs /P scn 0 0 20 20 re f');
   const bytes=fixture(['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>',`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 20 20] /Group << /S /Transparency /CS ${space} >> /Resources << /ColorSpace << /C ${space} >> /ExtGState << /H << /ca .5 /BM /Multiply >> >> ${resource} >> /Contents 4 0 R >>`,stream('',content),inner]);
   const label=`${name}-${variant}`;writeFileSync(`_build/group-colour/${label}.pdf`,bytes);
   const parsed=JSON.parse(bridge.render_plan(bytes,1,1,0));assert.ok(parsed.ok,parsed.error);
   const target=createCanvas(1,1),opts={...options};opts.paintShading=createShadingPainter(opts);opts.paintPattern=createPatternPainter(opts);
   const rendered=await renderPdfCanvas(target,parsed.canvas,opts),scope=engine.createProfileScope(parsed.canvas.icc_profiles);
   const values=variant==='image'&&components===3?[.18,.24,.8*(.5+.5*26/255)]:want;
   const expected=scope.groupToRgb(values,{calibration:parsed.canvas.blend_calibration,components});scope.dispose();near(rendered.data.slice((10*20+10)*4,(10*20+10)*4+3),expected.map(v=>v*255),3);
   writeFileSync(`_build/group-colour/${label}.canvas.png`,target.toBuffer('image/png'));
  }
 }
 delete globalThis.__moonbit_pdf_icc;
}
engine.dispose();console.log('ICC group component blending, output conversion, async scope isolation and cleanup: passed');

if(process.argv.includes('--ghostscript')){
 const cases=[];
 for(const name of ['icc-rgb-multiply','icc-image','icc-stencil','icc-pattern','icc-shading','icc-mask-bc','icc-isolated-form','cal-rgb','cal-gray','cal-rgb-image','cal-rgb-pattern','cal-gray-image','cal-gray-pattern','cal-rgb-stencil','cal-gray-stencil']){
  const base=`_build/group-colour/${name}`;
  execFileSync('gs',['-q','-dSAFER','-dBATCH','-dNOPAUSE','-sDEVICE=png16m','-r72',`-sOutputFile=${base}.gs.png`,`${base}.pdf`]);
  const pixels=async file=>{const image=await loadImage(file),c=createCanvas(image.width,image.height);c.getContext('2d').drawImage(image,0,0);return c.getContext('2d').getImageData(0,0,c.width,c.height).data;};
  const actual=await pixels(`${base}.canvas.png`),reference=await pixels(`${base}.gs.png`);assert.equal(actual.length,reference.length);
  let maximum=0,absolute=0,above2=0;
  for(let i=0;i<actual.length;i+=4){let error=0;for(let c=0;c<3;c++){const e=Math.abs(actual[i+c]-reference[i+c]);absolute+=e;maximum=Math.max(maximum,e);error=Math.max(error,e);}above2+=Number(error>2);}
  assert.ok(maximum<=2,`${name} differs from Ghostscript by ${maximum}`);
  cases.push({name,sha256:createHash('sha256').update(readFileSync(`${base}.pdf`)).digest('hex'),pixels:actual.length/4,maximum,meanAbsoluteError:absolute/(actual.length/4*3),changedAbove2:above2});
 }
 const report={ghostscript:execFileSync('gs',['--version'],{encoding:'utf8'}).trim(),cases};
 writeFileSync('_build/group-colour/report.json',JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report,null,2));
}

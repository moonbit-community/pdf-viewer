// Original Apache-2.0 fixtures: complete PDF -> JS/native public Canvas plan ->
// shipped Canvas adapter. The oracle evaluates PDF gamma, XYZ and Bradford
// independently, then gives those XYZ values to LittleCMS (never source metadata
// or the renderer's calibration descriptor). No preconverted RGB interpolation.
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { installPdfIccEngine } from '../../web/pdf-icc.mjs';
import { renderPdfCanvas } from '../../web/pdf-canvas.mjs';
import { createShadingPainter } from '../../web/pdf-shading.mjs';
const require = createRequire(process.env.PDF_CANVAS_PACKAGE || import.meta.url);
const { createCanvas, Path2D, loadImage } = require('@napi-rs/canvas');
const bridge = await import(pathToFileURL(resolve(process.argv[2] || '_build/pixel-plan.mjs')));
const native = process.env.PDF_NATIVE_PLAN;
const output = resolve(process.env.PDF_PIXEL_OUTPUT || '_build/shading-calrgb-acceptance');
mkdirSync(output, { recursive: true });
const engine = await installPdfIccEngine();
const rgb = readFileSync(new URL('../../assets/icc/rgb-gamma22.icc', import.meta.url));
const cmykPath = process.env.PDF_CMYK_PROFILE || '/usr/share/color/icc/ghostscript/default_cmyk.icc';
const cmyk = existsSync(cmykPath) ? readFileSync(cmykPath) : null;
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const d50 = [0.9642, 1, 0.8249], diagonal = [0.9642, 0, 0, 0, 1, 0, 0, 0, 0.8249];
const calibrated = { white: d50, gamma: [0.5, 2, 3], matrix: diagonal };
const extended = { white: d50, gamma: [0.5, 2, 3], matrix: [-0.2, 0.1, 0, 0.9, 0.9, 0.8, 0.2642, 0, 0.0249] };
const d65 = { white: [0.95047, 1, 1.08883], gamma: [2.2, 0.75, 3], matrix: [0.4124564, 0.2126729, 0.0193339, 0.3575761, 0.7151522, 0.119192, 0.1804375, 0.072175, 0.9503041] };
const singular = { white: d50, gamma: [.5, 2, 3], matrix: [.3214,1/3,.8249/3,.3214,1/3,.8249/3,.3214,1/3,.8249/3] };
const stream = (dict, bytes) => `<< ${dict} /Length ${bytes.length} >>\nstream\n${bytes}\nendstream`;
const calSpace = c => `[/CalRGB << /WhitePoint [${c.white.join(' ')}] /Gamma [${c.gamma.join(' ')}] /Matrix [${c.matrix.join(' ')}] >>]`;
function pdf(objects) {
  let text = '%PDF-1.7\n'; const offsets = [0];
  for (const [i, object] of objects.entries()) { offsets.push(text.length); text += `${i + 1} 0 obj\n${object}\nendobj\n`; }
  const xref = text.length;
  text += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n` + offsets.slice(1).map(n => `${String(n).padStart(10, '0')} 00000 n \n`).join('');
  return new TextEncoder().encode(text + `trailer << /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`);
}
const ring = [[0,0],[0,85],[0,170],[0,255],[85,255],[170,255],[255,255],[255,170],[255,85],[255,0],[170,0],[85,0]];
const interiors = [[85,85],[85,170],[170,170],[170,85]];
function fixture(type, source, target) {
  const colour = ([x,y]) => [x, y, 255-x];
  let data;
  if (type === 4) data = [[0,0],[255,0],[0,255],[255,255],[255,0],[0,255]].flatMap(p => [0,...p,...colour(p)]);
  else if (type === 5) data = [[0,0],[255,0],[0,255],[255,255]].flatMap(p => [...p,...colour(p)]);
  else data = [0,...ring.flat(),...(type === 7 ? interiors.flat() : []),...[[0,0],[0,255],[255,255],[255,0]].flatMap(colour)];
  const profile = target === 'icc-rgb' ? rgb : target === 'icc-cmyk' ? cmyk : null;
  const group = target === 'display' ? '' : `/Group << /S /Transparency /I true /CS ${target === 'calrgb' ? calSpace({white:d50,gamma:[1,1,1],matrix:diagonal}) : '[/ICCBased 6 0 R]'} >>`;
  return pdf([
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] ${group} /Resources << /Shading << /S 5 0 R >> >> /Contents 4 0 R >>`,
    stream('', '/RelativeColorimetric ri /S sh'),
    stream(`/ShadingType ${type} /ColorSpace ${calSpace(source)} /BitsPerCoordinate 8 /BitsPerComponent 8 /BitsPerFlag 8 /VerticesPerRow 2 /Decode [0 100 0 100 0 1 0 1 0 1] /Filter /ASCIIHexDecode`, Buffer.from(data).toString('hex')+'>'),
    ...(profile ? [stream(`/N ${target === 'icc-cmyk' ? 4 : 3} /Filter /ASCIIHexDecode`, profile.toString('hex')+'>')] : []),
  ]);
}
// Row-major matrix and independent Gaussian elimination avoid copying the
// descriptor builder's truncated inverse coefficients into this oracle.
const bradford = [[.8951,.2664,-.1614],[-.7502,1.7135,.0367],[.0389,-.0685,1.0296]];
const mul = (m,v) => m.map(row=>row.reduce((s,n,i)=>s+n*v[i],0));
function solve(m,v) {
  const a=m.map((row,i)=>[...row,v[i]]);
  for(let k=0;k<3;k++) { const t=a[k][k]; for(let j=k;j<4;j++)a[k][j]/=t; for(let i=0;i<3;i++)if(i!==k){const q=a[i][k];for(let j=k;j<4;j++)a[i][j]-=q*a[k][j];} }
  return a.map(row=>row[3]);
}
function oraclePcs(source, x, y) {
  const linear=[x,y,1-x].map((v,i)=>v**source.gamma[i]);
  const xyz=[0,1,2].map(row=>linear.reduce((s,v,i)=>s+v*source.matrix[i*3+row],0));
  if(source.white===d50)return xyz;
  const sourceWhite=mul(bradford,source.white), targetWhite=mul(bradford,d50);
  return solve(bradford,mul(bradford,xyz).map((v,i)=>v*targetWhite[i]/sourceWhite[i]));
}
const tests = [
  {name:'type4-gamma-display', type:4, source:calibrated, target:'display'},
  {name:'type5-gamma-icc-rgb', type:5, source:calibrated, target:'icc-rgb'},
  {name:'type6-gamma-calrgb-group', type:6, source:calibrated, target:'calrgb'},
  {name:'type7-signed-xyz-display', type:7, source:extended, target:'display'},
  {name:'type4-d65-adaptation', type:4, source:d65, target:'icc-rgb'},
  {name:'type5-singular-source-matrix', type:5, source:singular, target:'display'},
  ...(cmyk ? [{name:'type7-signed-xyz-icc-cmyk',type:7,source:extended,target:'icc-cmyk'}] : []),
];
const cases=[];
for(const item of tests) {
  const bytes=fixture(item.type,item.source,item.target), filename=resolve(output,item.name+'.pdf');
  writeFileSync(filename,bytes);
  const js=JSON.parse(bridge.render_plan(bytes,1,1,0)); assert.ok(js.ok,js.error);
  const plans=[['js',js.canvas]];
  if(native){const destination=resolve(output,item.name+'.canvas.json');const run=spawnSync(resolve(native),[filename,destination],{encoding:'utf8'});assert.equal(run.status,0,run.stdout+run.stderr);plans.push(['native',JSON.parse(readFileSync(destination,'utf8'))]);}
  let baseline;
  for(const [producer,plan] of plans) {
    const raster=plan.items[0].paint.shading.raster;
    assert.ok(raster.error==null);assert.ok(raster.source_error==null);assert.equal(raster.source_direct,true);
    assert.equal(raster.samples,'');assert.ok(raster.source_samples==null);assert.equal(raster.source_colour.space,'CalRGB');
    assert.ok(raster.source_colour.pcs_xyz==null);assert.deepEqual(raster.source_colour.calibration.gamma,item.source.gamma);
    const scope=engine.createProfileScope(plan.icc_profiles||[]);
    const count=item.target==='icc-cmyk'?4:3, stride=count===4?5:4;
    const options={createCanvas,Path2D,loadImage,iccEngine:engine,returnGroupComponents:true};
    options.paintShading=createShadingPainter(options);
    const canvas=createCanvas(100,100),result=await renderPdfCanvas(canvas,plan,options);
    if(baseline)assert.deepEqual(result.data,baseline,'native and JS producers must render identical bytes');else baseline=result.data;
    let maximum=0, negativePcs=0, extendedPcs=0;
    try {
      for(let y=0;y<100;y++)for(let x=0;x<100;x++){
        const xyz=oraclePcs(item.source,(x+.5)/100,(99.5-y)/100);
        if(xyz.some(v=>v<0))negativePcs++;if(xyz.some(v=>v>1))extendedPcs++;
        const expected=item.target==='calrgb'?xyz.map((v,i)=>Math.max(0,Math.min(1,v/d50[i]))):scope.sourceToGroup({space:'PCSXYZ',components:xyz,rendering_intent:'/RelativeColorimetric'},{profileId:plan.blend_profile_id,components:count});
        assert.ok(expected,'the real target CMM must support conversion');
        const offset=(y*100+x)*stride;
        assert.equal(result.groupProof.pixels[offset+stride-1],1);
        for(let c=0;c<count;c++) maximum=Math.max(maximum,Math.abs(255*result.groupProof.pixels[offset+c]-255*expected[c]));
      }
    }finally{scope.dispose();}
    assert.ok(maximum<.51,`${item.name}/${producer}: independent XYZ oracle error ${maximum}`);
    writeFileSync(resolve(output,`${item.name}.${producer}.png`),canvas.toBuffer('image/png'));
    const record={name:item.name,producer,target:item.target,pixels:10000,maximumByteError:maximum,negativePcsPixels:negativePcs,extendedPcsPixels:extendedPcs,pdfSha256:sha(bytes)};
    cases.push(record);console.log(JSON.stringify(record));
  }
}
const report={oracle:'Independent PDF gamma/XYZ and Gaussian-solved Bradford, then real LittleCMS XYZ-to-target',rgbProfileSha256:sha(rgb),cmykProfileSha256:cmyk?sha(cmyk):null,nativeSkipped:native?null:'Set PDF_NATIVE_PLAN to the release cmd/main executable',cmykSkipped:cmyk?null:'Provide a genuine output profile with PDF_CMYK_PROFILE',cases};
writeFileSync(resolve(output,'report.json'),JSON.stringify(report,null,2)+'\n');
console.log(`${cases.length} complete CalRGB PDF-to-Canvas cases passed`);

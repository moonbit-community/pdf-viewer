import assert from 'node:assert/strict';
import test from 'node:test';
import {createRequire} from 'node:module';
import {readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {renderPdfCanvas} from '../../web/pdf-canvas.mjs';
import {createShadingPainter} from '../../web/pdf-shading.mjs';
import {createPatternPainter} from '../../web/pdf-patterns.mjs';
import {createPdfIccEngine} from '../../web/pdf-icc.mjs';

const {createCanvas,Path2D,loadImage}=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url)('@napi-rs/canvas');
const width=96,height=72,identity=[1,0,0,1,0,0];
const rect='M 19.25 16.75 L 32.4 16.75 L 32.4 33.2 L 19.25 33.2 Z';
const curve='M 18 15 C 8 10 45 8 34 24 C 50 48 3 44 18 15 Z';
const raster={domain:[0,1],size:[2],samples:[12,47,180,245,160,20],tree:[-1,0,0],triangles:[],patches:[],bbox:[],function_matrix:[]};
const shading=(kind='axial',extra={})=>({kind,coords:kind==='radial'?[20,20,2,35,29,29]:[12,10,62,42],matrix:[1,0,0,-1,0,height],extend_start:true,extend_end:true,raster,...extra});
const item=(resource,clips=[{svg_path:rect}],extra={})=>({kind:'shading',paint:{shading:resource,fill_alpha:.63,blend_mode:'normal',clips,
  // Deliberately unrelated: a shading's model bounds cannot bound its paint.
  bounds:{min_x:0,min_y:0,max_x:.0001,max_y:.0001},...extra}});
const plan=items=>({version:1,page:{origin_x:0,origin_y:0,width,height,blend_space:'DeviceRGB'},viewport:{width,height,matrix:[1,0,0,-1,0,height]},items});
const convertProcess=([c,m,y,k])=>[1-Math.min(1,c+k),1-Math.min(1,m+k),1-Math.min(1,y+k)];
async function render(input,fullShadingReplay=false,extra={}){
  const options={createCanvas,Path2D,loadImage,convertProcess,fullShadingReplay,...extra},metrics={calls:0,visits:0,regions:[]};
  const painter=createShadingPainter(options);
  options.paintShading=(context,resource,paint,env)=>{
    const region=env.operation==null&&resource.kind!=='mesh'&&!resource.pattern_plan?env.shadingBounds:null;
    metrics.calls++;metrics.visits+=region?region.width*region.height:env.width*env.height;metrics.regions.push(region);
    return painter(context,resource,paint,env);
  };
  options.paintPattern=createPatternPainter(options);
  const start=performance.now(),rssStart=process.memoryUsage().rss;
  const result=await renderPdfCanvas(createCanvas(1,1),input,options);
  return {result,metrics,milliseconds:performance.now()-start,rssStart,rssEnd:process.memoryUsage().rss};
}
async function exact(input,extra={}){
  const full=await render(input,true,extra),cropped=await render(input,false,extra);
  assert.deepEqual(cropped.result.data,full.result.data,'RGBA bytes');
  assert.deepEqual(cropped.result.shape,full.result.shape,'retained shape');
  assert.deepEqual(cropped.result.premultiplied,full.result.premultiplied,'retained colour');
  assert.deepEqual(cropped.result.inkProof?.premultiplied,full.result.inkProof?.premultiplied,'retained CMYK');
  return {full,cropped};
}

test('clipped axial/radial/function samples retain exact device coordinates, Extend, BBox and AA',async()=>{
  const resources=[shading(),shading('radial'),shading('function',{coords:[],raster:{...raster,domain:[0,96,0,72],size:[2,2],tree:[],samples:[0,0,0,255,0,0,0,255,0,255,255,255],function_matrix:[1,.1,.2,1,0,0]}})];
  for(const resource of resources)for(const matrix of [identity,[0,1,-1,0,80,0],[.9,.25,.3,.85,2,1],[-.8,0,0,.9,85,1]])for(const extend of [false,true]){
    const value={...resource,extend_start:extend,extend_end:!extend,raster:{...resource.raster,bbox:[10,8,60,49]}};
    const {full,cropped}=await exact(plan([item(value,[{svg_path:curve,even_odd:true},{svg_path:rect}])]),{matrix});
    assert(full.result.data.some((value,index)=>index%4!==3&&value<255),'control must contain visible shading');
    assert(cropped.metrics.visits<full.metrics.visits/3,'clip must actually reduce visits');
  }
});
test('unknown/implicit/relative SVG clips and absent clips keep full replay',async()=>{
  for(const clips of [[],[{svg_path:'M19 16H33V34H19Z'}],[{svg_path:'m19 16l14 0l0 18l-14 0z'}],[{svg_path:'M19 16 33 16 33 34 19 34Z'}]]){
    const {full,cropped}=await exact(plan([item(shading(),clips)]));
    assert.equal(cropped.metrics.visits,full.metrics.visits);
    assert(cropped.metrics.regions.every(region=>region==null));
  }
});
test('multiple disjoint, offscreen and scientific-notation clips remain conservative',async()=>{
  for(const clips of [
    [{svg_path:rect},{svg_path:'M70 60L80 60L80 65L70 65Z'}],
    [{svg_path:'M-20 -20L-10 -20L-10 -10L-20 -10Z'}],
    [{svg_path:'M1.925e1 1.675e1L3.24e1 1.675e1L3.24e1 3.32e1L1.925e1 3.32e1Z'}],
  ])await exact(plan([item(shading(),clips)]));
});
test('soft masks, knockout groups, transparency and CMYK component planes are byte-identical',async()=>{
  const mask=plan([{kind:'path',paint:{svg_path:'M0 0L96 0L96 72L0 72Z',filled:true,stroked:false,fill_color:'#777777',fill_source:{space:'DeviceRGB',components:[.47,.47,.47],paints:true},fill_alpha:.56,blend_mode:'normal'}}]);
  const group={id:'cropped',isolated:true,knockout:true,alpha:.73,blend_mode:'normal',color_space:'DeviceRGB',bounds:{min_x:14,min_y:20,max_x:44,max_y:60}};
  await exact(plan([item(shading(),[{svg_path:curve}],{group_path:[group],soft_mask:{plan:mask,luminosity:true,matrix:identity,backdrop:[0,0,0]},alpha_is_shape:true})]));
  const cmyk=plan([item(shading('axial',{raster:{...raster,process_samples:[0,20,40,60,255,180,80,30]}}))]);
  cmyk.page.blend_space='DeviceCMYK';
  const {full,cropped}=await exact(cmyk,{returnInks:true});
  assert.equal(cropped.metrics.calls,8);assert(cropped.metrics.visits<full.metrics.visits/10);
});
test('path-painted Background and stroke-mask shadings keep full shading replay',async()=>{
  for(const stroke of [false,true]){
    const resource=shading('radial',{raster:{...raster,background:'#f01234',bbox:[7,5,75,65]}});
    const p={svg_path:curve,bounds:{min_x:0,min_y:0,max_x:96,max_y:72},filled:!stroke,stroked:stroke,fill_color:'#000000',stroke_color:'#000000',fill_alpha:.6,stroke_alpha:.8,blend_mode:'normal',clips:[{svg_path:rect}],line_width:7,
      ...(stroke?{stroke_pattern:{shading:resource}}:{shading_pattern:resource})};
    const {full,cropped}=await exact(plan([{kind:'path',paint:p}]));
    assert.equal(cropped.metrics.visits,full.metrics.visits);assert(cropped.metrics.regions.every(region=>region==null));
  }
});
test('mesh and retained PatternType2 scenes preserve their existing full shading route',async()=>{
  const mesh=shading('mesh',{raster:{...raster,triangles:[{points:[{x:0,y:0},{x:96,y:0},{x:0,y:72}],components:[[0],[1],[.4]]}]}});
  const child=plan([{kind:'path',paint:{svg_path:curve,filled:true,stroked:false,fill_color:'#204080',fill_source:{space:'DeviceRGB',components:[.125,.25,.5],paints:true},fill_alpha:.7,blend_mode:'normal'}}]);
  for(const resource of [mesh,{pattern_plan:child}]){
    const {full,cropped}=await exact(plan([item(resource)]));
    assert.equal(cropped.metrics.visits,full.metrics.visits);
    assert(cropped.metrics.regions.every(region=>region==null));
  }
});
test('actual ICC target conversion receives only visible shading inputs with identical bytes',async()=>{
  const engine=await createPdfIccEngine();
  try{
    const profile=readFileSync(new URL('../../assets/icc/rgb-gamma22.icc',import.meta.url));
    const resource=shading('axial',{raster:{...raster,source_colour:{space:'ICCBased',components:[0,0,0],icc_profile_id:'source',component_ranges:[0,1,0,1,0,1],paints:true},source_samples:[10,40,180,245,150,20]}});
    const input=plan([item(resource)]);input.icc_profiles=['source','target'].map(id=>({id,components:3,data_base64:profile.toString('base64')}));input.blend_profile_id='target';
    const before=engine.statistics.samples,full=await render(input,true,{iccEngine:engine}),middle=engine.statistics.samples,cropped=await render(input,false,{iccEngine:engine}),after=engine.statistics.samples;
    assert.deepEqual(cropped.result.data,full.result.data);assert(after-middle<middle-before,'crop must reduce actual CMM sample calls');
  }finally{engine.dispose();}
});
test('saved real-page full/cropped replay and existing baseline are byte-identical',{skip:!process.env.PDF_SHADING_REAL_PLAN},async()=>{
  const input=JSON.parse(readFileSync(process.env.PDF_SHADING_REAL_PLAN,'utf8')),engine=await createPdfIccEngine();
  try{
    const {full,cropped}=await exact(input,{iccEngine:engine});
    if(process.env.PDF_SHADING_BASELINE_PNG){
      const image=await loadImage(process.env.PDF_SHADING_BASELINE_PNG),canvas=createCanvas(image.width,image.height);canvas.getContext('2d').drawImage(image,0,0);
      assert.deepEqual(cropped.result.data,canvas.getContext('2d').getImageData(0,0,image.width,image.height).data,'saved pre-change Canvas PNG');
    }
    const summarize=({result,metrics,...timing})=>({...timing,visits:metrics.visits,calls:metrics.calls,sha256:createHash('sha256').update(result.data).digest('hex')});
    const report={full:summarize(full),cropped:summarize(cropped)};
    if(process.env.PDF_SHADING_PROFILE_OUTPUT)writeFileSync(process.env.PDF_SHADING_PROFILE_OUTPUT,JSON.stringify(report,null,2)+'\n');
    console.log(JSON.stringify(report));
  }finally{engine.dispose();}
});

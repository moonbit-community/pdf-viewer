import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {renderPdfPage} from '../../web/pdf-runtime.mjs';
import {renderPdfCanvas} from '../../web/pdf-canvas.mjs';
import {createShadingPainter} from '../../web/pdf-shading.mjs';
import {createPatternPainter} from '../../web/pdf-patterns.mjs';

const {createCanvas,Path2D,loadImage}=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url)('@napi-rs/canvas');
const width=48,height=40,identity=[1,0,0,1,0,0];
const page={number:1,origin_x:0,origin_y:0,width,height,blend_space:'DeviceRGB'};
const viewport={width,height,matrix:[1,0,0,-1,0,height]};
const plan=items=>({version:1,page,viewport,items});
const resource={kind:'axial',coords:[2,4,43,33],matrix:[1,0,0,-1,0,height],extend_start:false,extend_end:true,
 raster:{domain:[0,1],size:[2],samples:[16,40,170,250,150,20],tree:[-1,0,0],triangles:[],patches:[],bbox:[3.25,2.5,43.75,37.25],function_matrix:[]}};
const shading=(extra={})=>({kind:'shading',paint:{shading:resource,fill_alpha:1,blend_mode:'normal',clips:[{svg_path:'M4.25 5.5L42 7L39 35L5 34Z'}],...extra}});
const path=(colour,extra={})=>({kind:'path',paint:{svg_path:'M4.25 3.5H43.75V36.25H4.25Z',filled:true,stroked:false,fill_color:colour,fill_alpha:1,blend_mode:'normal',clips:[],...extra}});
const pattern={kind:'axial',pattern_plan:plan([shading({group_path:[{id:'shading-pattern',isolated:false,knockout:true,alpha:1,blend_mode:'normal'}]})])};

function host(){
 const metrics={reads:0,uploads:0,readPixels:0},seen=new WeakSet();
 const tracked=(w,h)=>{
  const canvas=createCanvas(w,h),context=canvas.getContext('2d');
  if(!seen.has(context)){
   seen.add(context);
   for(const [name,key] of [['getImageData','reads'],['putImageData','uploads']]){
    const original=context[name];context[name]=function(...args){metrics[key]++;if(name==='getImageData')metrics.readPixels+=args[2]*args[3];return original.apply(this,args);};
   }
  }
  return canvas;
 };
 return {options:{createCanvas:tracked,Path2D,loadImage,nativeCanvas:false},metrics};
}
async function render(input,extra={}){
 const {options,metrics}=host(),canvas=options.createCanvas(1,1);
 const result=await renderPdfPage(canvas,input,{...options,...extra});
 return {result,metrics};
}
async function exact(input,extra={}){
 const fast=await render(input,extra),control=await render(input,{...extra,fullShapeReplay:true,fullShadingReplay:true});
 for(const key of ['data','premultiplied','shape'])assert.deepEqual(fast.result[key],control.result[key],key);
 assert.deepEqual(fast.result.inkProof?.premultiplied,control.result.inkProof?.premultiplied);
 return {fast,control};
}

let count=0;
for(const matrix of [identity,[0,1,-1,0,43,0],[.9,.2,.15,.85,1,2]]){
 for(const kind of ['axial','radial','function','mesh']){
  const item=shading();item.paint.shading=structuredClone(resource);item.paint.shading.kind=kind;
  if(kind==='radial')item.paint.shading.coords=[15,15,2,24,23,25];
  if(kind==='function')Object.assign(item.paint.shading,{coords:[],raster:{...resource.raster,domain:[0,48,0,40],size:[2,2],tree:[],samples:[0,0,0,255,0,0,0,255,0,255,255,255],function_matrix:identity}});
  if(kind==='mesh')Object.assign(item.paint.shading,{coords:[],raster:{...resource.raster,triangles:[{points:[{x:3,y:3},{x:43,y:6},{x:12,y:37}],components:[[0],[1],[.2]]}]}});
  const {fast,control}=await exact(plan([item]),{matrix,transparent:true});
  assert.equal(fast.metrics.reads,1);assert.equal(control.metrics.reads,2);assert.equal(fast.metrics.uploads,2);assert.equal(control.metrics.uploads,3);count++;
 }
 const {fast,control}=await exact(plan([path('#000',{pattern})]),{matrix,transparent:true});
 assert(fast.metrics.reads<control.metrics.reads,'Independent shading patterns reduce actual pixel reads');
 assert(fast.metrics.uploads<control.metrics.uploads,'Independent shading patterns reduce actual uploads');count++;
 for(const shading_pattern of [resource,pattern]){
  const {fast,control}=await exact(plan([path('#000',{shading_pattern})]),{matrix,transparent:true});
  assert(fast.metrics.reads<control.metrics.reads,'Direct shading aliases use the same coverage proof');count++;
 }
}
for(const input of [
 plan([path('#a0c060'),path('#000',{pattern})]),
 plan([path('#000',{pattern,fill_alpha:.43})]),
 plan([path('#000',{pattern,group_path:[{id:'outer',isolated:true,knockout:true,alpha:.7,blend_mode:'normal',bounds:{min_x:7.25,min_y:6.5,max_x:36.75,max_y:33.25}}]})]),
 plan([shading({fill_alpha:.43})]),
 plan([shading({alpha_is_shape:true,fill_alpha:.43})]),
 plan([shading({soft_mask:{plan:plan([path('#777',{fill_alpha:.6})]),luminosity:true,matrix:identity,backdrop:[0,0,0]}})]),
]){await exact(input,{transparent:true});count++;}
const cmyk=plan([shading()]);cmyk.page={...page,blend_space:'DeviceCMYK'};
cmyk.items[0].paint.shading={...resource,raster:{...resource.raster,process_samples:[0,20,40,60,255,180,80,30]}};
await exact(cmyk,{returnInks:true,convertProcess:([c,m,y,k])=>[1-Math.min(1,c+k),1-Math.min(1,m+k),1-Math.min(1,y+k)]});count++;
const annotatedPattern=structuredClone(pattern);
annotatedPattern.pattern_plan.annotation_svg='<svg xmlns="http://www.w3.org/2000/svg" width="48" height="40"><rect width="10" height="10" fill="red"/></svg>';
await exact(plan([path('#000',{pattern:annotatedPattern})]),{transparent:true});count++;
const backdrop=new Float32Array(width*height*4);for(let p=0;p<width*height;p++)backdrop.set([.2,.3,.4,1],p*4);
await exact(plan([path('#000',{pattern})]),{backdrop,transparent:true});count++;
await exact(plan([path('#000',{pattern})]),{_maskBackdrop:[.2,.3,.4],transparent:true});count++;
const patternMask={plan:plan([path('#000',{pattern})]),luminosity:true,matrix:identity,backdrop:[.2,.3,.4]};
await exact(plan([path('#ff0000',{soft_mask:patternMask})]),{transparent:true});count++;

// Small clipped gradients must retain their exact shape without transferring
// page-sized rows for every paint. Alternate disjoint clips to expose stale
// source buffers, and keep unsupported host-authored syntax on full replay.
for(const clips of [
 [{svg_path:'M5.25 7.5L17.75 7.5L17.75 20.25L5.25 20.25Z'}],
 [{svg_path:'M5.25 7.5C22 2 29 26 17.75 20.25L5.25 20.25Z'}],
 [{svg_path:'M5 7L18 7L18 21L5 21Z'},{svg_path:'M8 9L15 9L15 19L8 19Z'}],
]){
 const large=plan([shading({clips}),shading({clips:[{svg_path:'M25 10L35 10L35 20L25 20Z'}]})]);
 large.page={...page,width:400,height:320};large.viewport={width:400,height:320,matrix:[1,0,0,-1,0,320]};
 const {fast,control}=await exact(large,{transparent:true});
 assert(fast.metrics.readPixels<control.metrics.readPixels/3,'Clip bounds must also constrain actual source readback');count++;
}
const unknownClip=plan([shading({clips:[{svg_path:'M5 7H18V21H5Z'}]})]);
const unknownFast=await render(unknownClip),unknownControl=await render(unknownClip,{fullShadingReplay:true});
assert.deepEqual(unknownFast.result.data,unknownControl.result.data);
assert.equal(unknownFast.metrics.readPixels,unknownControl.metrics.readPixels,'Unknown clip syntax keeps full readback');count++;

const custom=(context,_resource,_paint,env)=>{context.setTransform(...identity);context.fillStyle=env.shapeOnly?'#000':'rgba(255,0,0,.5)';context.fillRect(0,0,width,height);};
const external=await render(plan([shading({clips:[]})]),{paintShading:custom,transparent:true});
assert.equal(external.metrics.reads,2,'Custom shading adapters retain their independent shape pass');
assert.equal(external.result.shape[0],1);assert(external.result.premultiplied[3]<1);count++;
const customPattern=(context,_resource,_path,_operation,env)=>custom(context,null,null,env);
const externalPattern=await render(plan([path('#000',{pattern})]),{paintPattern:customPattern,transparent:true});
assert.equal(externalPattern.metrics.reads,2,'Custom pattern adapters retain their independent shape pass');
assert.equal(externalPattern.result.shape[width+1],1);assert(externalPattern.result.premultiplied[(width+1)*4+3]<1);count++;

for(const annotations of [false,true]){
 const input=plan([shading()]);if(annotations)input.annotation_svg='<svg xmlns="http://www.w3.org/2000/svg" width="48" height="40"><rect width="9" height="8" fill="red"/></svg>';
 const opts={createCanvas,Path2D,loadImage,nativeCanvas:false,paintShading:createShadingPainter()};
 const control=await renderPdfCanvas(createCanvas(1,1),input,opts),canvas=createCanvas(3,4);
 const samples=await renderPdfCanvas(canvas,input,{...opts,_samplesOnly:true});
 for(const key of ['premultiplied','shape'])assert.deepEqual(samples[key],control[key]);
 if(annotations)assert.deepEqual(samples.data,control.data);else assert.equal(samples.data,null);
 assert.equal(canvas.width,annotations?width:3,'Only scenes with Canvas annotation work publish the unused target');count++;
}
const tiled={...plan([path('#ff0000')]),page:{...page,width:48,height:40}};
const tile={name:'P',bbox:{min_x:0,min_y:0,max_x:48,max_y:40},x_step:48,y_step:40,matrix:identity,tile_plan:tiled};
const opts={createCanvas,Path2D,loadImage,nativeCanvas:false,transparent:true},painter=createPatternPainter(opts);
try{
 const input=plan([path('#000',{pattern:tile})]);
 const output=await renderPdfCanvas(createCanvas(1,1),input,{...opts,paintPattern:painter,_samplesOnly:true});
 assert(output.premultiplied.some((value,index)=>index%4===0&&value===1),'A samples-only parent must still paint nested pattern bitmaps');count++;
}finally{painter.dispose();}
console.log(`${count} shading pass checks: exact RGBA/shape/components, reduced transfers, backdrop/opacity/mask/CMYK/custom fallbacks and samples-only nesting passed`);

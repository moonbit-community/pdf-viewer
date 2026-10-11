import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {renderPdfCanvas} from '../../web/pdf-canvas.mjs';
import {createPatternPainter} from '../../web/pdf-patterns.mjs';
const {createCanvas,Path2D,loadImage}=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url)('@napi-rs/canvas');
const source=components=>({space:'DeviceCMYK',components,paints:true});
const path=(svg_path,components,extra={})=>({kind:'path',paint:{svg_path,filled:true,stroked:false,fill_color:'#8040c0',fill_source:source(components),fill_alpha:1,blend_mode:'normal',clips:[],...extra}});
const page={number:1,origin_x:0,origin_y:0,width:48,height:48,blend_space:'DeviceRGB'};
const plan=items=>({version:1,page,viewport:{width:48,height:48,matrix:[1,0,0,-1,0,48]},items});
const tile={...plan([path('M0 0H4V4H0Z',[.3,.1,.5,.1],{fill_alpha:.6,blend_mode:'multiply'})]),page:{...page,width:4,height:4},viewport:{width:4,height:4,matrix:[1,0,0,-1,0,4]}};
let count=0;
for(const space of ['DeviceRGB','DeviceCMYK'])for(const matrix of [[1,0,0,1,0,0],[0,1,-1,0,48,0],[-1,0,0,1,48,0],[1,.15,.2,1,-6,-3]]){
 const resource={name:'P',bbox:{min_x:0,min_y:0,max_x:4,max_y:4},x_step:4,y_step:4,matrix:[1,.15,.1,1,.3,.7],tile_plan:tile};
 const glyph=path('M12 14L30 15L26 32L17 30Z',[0,0,0,0],{pattern:resource,bounds:{min_x:12,min_y:16,max_x:30,max_y:34},fill_alpha:.7,clips:[{svg_path:'M10 10H28V34H10Z'}]});
 const input={...plan([path('M0 0H48V48H0Z',[.1,.4,.2,.1]),glyph]),page:{...page,blend_space:space}};
 const render=async full=>{
  const options={createCanvas,Path2D,loadImage,matrix,convertProcess:([c,m,y,k])=>[1-Math.min(1,c+k),1-Math.min(1,m+k),1-Math.min(1,y+k)]};
  const painter=createPatternPainter(options);
  const wrapped=(context,resource,path,operation,env)=>painter(context,resource,path,operation,full?{...env,paintBounds:undefined}:env);
  wrapped.releasePaint=painter.releasePaint;options.paintPattern=wrapped;
  try{return await renderPdfCanvas(createCanvas(48,48),input,options);}finally{painter.dispose();}
 };
 const bounded=await render(false),full=await render(true);
 assert.deepEqual(bounded.data,full.data,`${space} affine pattern region pixels`);
 assert.deepEqual(bounded.shape,full.shape,`${space} affine pattern region shape`);count++;
}
console.log(`${count} RGB/CMYK affine pattern-region results match full-page cell replay exactly`);

import assert from 'node:assert/strict';import {createRequire} from 'node:module';
import {renderPdfCanvas} from '../../web/pdf-canvas.mjs';
const {createCanvas,Path2D,loadImage}=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url)('@napi-rs/canvas');
const page={number:1,origin_x:0,origin_y:0,width:48,height:48,blend_space:'DeviceRGB'},plan=items=>({version:1,page,viewport:{width:48,height:48,matrix:[1,0,0,-1,0,48]},items});
const source=c=>({space:'DeviceCMYK',components:c,paints:true});
const path=(svg_path,bounds,color,extra={})=>({kind:'path',paint:{svg_path,bounds,filled:true,stroked:false,fill_color:'#8844cc',fill_source:source(color),fill_alpha:1,blend_mode:'normal',...extra}});
const region={min_x:12,min_y:16,max_x:32,max_y:36};
const mask={luminosity:false,matrix:[1,0,0,1,2,1],plan:plan([path('M8 0H30V48H8Z',{min_x:8,min_y:0,max_x:30,max_y:48},[0,0,0,0],{fill_alpha:.7})])};
const child=plan([path('M12 12L32 14L26 32L16 29Z',region,[.2,.4,.1,.2],{fill_alpha:.6,blend_mode:'multiply',soft_mask:mask}),path('M16 17L30 29',region,[.4,.1,.3,0],{filled:false,stroked:true,stroke_source:source([.4,.1,.3,0]),stroke_color:'#cc2244',stroke_alpha:.5,line_width:3,line_cap:1,line_join:0,dash_array:[],dash_phase:0,stroke:{svg_path:'M16 17L30 29',transform:[1,0,0,1,0,0],line_width:3,miter_limit:10,dash_array:[],dash_phase:0}})]);
const glyph={kind:'text',paint:{fill_alpha:1,blend_mode:'normal',bounds:{min_x:0,min_y:0,max_x:1,max_y:1}},type3_plan:child};
let count=0;
for(const space of ['DeviceRGB','DeviceCMYK'])for(const matrix of [[1,0,0,1,0,0],[0,1,-1,0,48,0],[-1,0,0,1,48,0],[1,.2,.15,1,-5,-5]]){
 const input={...plan([path('M0 0H48V48H0Z',null,[.1,.2,.3,.1]),{...glyph,type3_plan:plan([glyph])}]),page:{...page,blend_space:space}};
 const options={createCanvas,Path2D,loadImage,matrix,convertProcess:([c,m,y,k])=>[1-Math.min(1,c+k),1-Math.min(1,m+k),1-Math.min(1,y+k)]};
 const bounded=await renderPdfCanvas(createCanvas(1,1),input,options),full=await renderPdfCanvas(createCanvas(1,1),input,{...options,fullSceneReplay:true});
 assert.deepEqual(bounded.data,full.data);assert.deepEqual(bounded.shape,full.shape);count++;
}
console.log(`${count} RGB/CMYK affine nested-scene crops match full-page replay exactly`);

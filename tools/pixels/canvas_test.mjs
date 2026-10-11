import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { renderPdfCanvas } from '../../web/pdf-canvas.mjs';
import {createPatternPainter} from '../../web/pdf-patterns.mjs';
import {renderPdfPage} from '../../web/pdf-runtime.mjs';
const require=createRequire(process.env.PDF_CANVAS_PACKAGE || import.meta.url);
const {createCanvas,Path2D,loadImage}=require('@napi-rs/canvas');
const options={createCanvas,Path2D,loadImage};
const page={origin_x:0,origin_y:0,width:20,height:20,user_unit:1,rotation:0};
const plan=items=>({version:1,page,viewport:{width:20,height:20,matrix:[1,0,0,-1,0,20]},items});
const path=(svg_path,color,other={})=>({kind:'path',paint:{svg_path,filled:true,stroked:false,fill_color:color,fill_alpha:1,stroke_alpha:1,blend_mode:'normal',clips:[],group_path:[],...other}});
const rect='M 0 0 L 20 0 L 20 20 L 0 20 Z';
const pixel=(result,x,y)=>Array.from(result.data.slice((y*20+x)*4,(y*20+x)*4+4));
const near=(value,expected,tolerance=2)=>value.forEach((v,i)=>assert.ok(Math.abs(v-expected[i])<=tolerance,`${value} != ${expected}`));
let count=0;
async function test(name,fn){await fn();count++;console.log(`ok ${name}`);}
await test('cropped tiles skip invisible sources and groups without changing pixels',async()=>{
 const image=createCanvas(1,1);image.getContext('2d').fillRect(0,0,1,1);
 const group={id:'outside',isolated:true,knockout:false,alpha:1,blend_mode:'normal'};
 const source={kind:'image',paint:{quad:{p0:{x:100,y:100},p1:{x:100,y:101},p2:{x:101,y:101},p3:{x:101,y:100}},bounds:{min_x:100,min_y:100,max_x:101,max_y:101},resource:{data_uri:image.toDataURL(),width:1,height:1},fill_alpha:1,blend_mode:'normal',group_path:[group]}};
 const input=plan([path(rect,'#ff0000'),source]);
 let loads=0;
 const opts={...options,loadImage:async uri=>{loads++;return loadImage(uri);}};
 const control=await renderPdfCanvas(createCanvas(1,1),input,{...opts,fullSurfaceReplay:true});
 assert.equal(loads,1,'The control replays the off-tile image');loads=0;
 const actual=await renderPdfCanvas(createCanvas(1,1),input,opts);
 assert.equal(loads,0,'The image is never decoded for an invisible group');
 assert.deepEqual(actual.data,control.data);assert.deepEqual(actual.shape,control.shape);
});
await test('cancelled tiled paint stops before another tile and frees its output',async()=>{
 const controller=new AbortController(),canvas=createCanvas(1,1);let loads=0,yields=0,closed=0;
 const source=createCanvas(1,1);source.getContext('2d').fillRect(0,0,1,1);
 const input=plan([{kind:'image',paint:{quad:{p0:{x:0,y:0},p1:{x:0,y:20},p2:{x:20,y:20},p3:{x:20,y:0}},bounds:{min_x:0,min_y:0,max_x:20,max_y:20},resource:{data_uri:source.toDataURL(),width:1,height:1},fill_alpha:1,blend_mode:'normal'}}]);
 await assert.rejects(renderPdfPage(canvas,input,{...options,returnPixels:false,tileSize:10,signal:controller.signal,
  loadImage:async uri=>{loads++;const image=await loadImage(uri);image.close=()=>closed++;return image;},yieldToHost:async()=>{if(++yields===2)controller.abort();}}),{name:'AbortError'});
 assert.equal(loads,1);assert.equal(yields,2);assert.equal(closed,1);assert.equal(canvas.width,1);assert.equal(canvas.height,1);
});
await test('page tiles share image decoding and release the bitmap after the page',async()=>{
 const source=createCanvas(1,1);source.getContext('2d').fillRect(0,0,1,1);
 const input=plan([{kind:'image',paint:{quad:{p0:{x:0,y:0},p1:{x:0,y:20},p2:{x:20,y:20},p3:{x:20,y:0}},bounds:{min_x:0,min_y:0,max_x:20,max_y:20},resource:{data_uri:source.toDataURL(),width:1,height:1},fill_alpha:1,blend_mode:'normal'}}]);
 const control=await renderPdfCanvas(createCanvas(1,1),input,options);
 let loads=0,closed=0;
 const actual=await renderPdfPage(createCanvas(1,1),input,{...options,tileSize:10,loadImage:async uri=>{
  loads++;const image=await loadImage(uri);image.close=()=>closed++;return image;
 }});
 assert.equal(loads,1,'All four tiles use the same decoded image');assert.equal(closed,1,'The page owns and releases the image exactly once');
 assert.deepEqual(actual.data,control.data);assert.deepEqual(actual.shape,control.shape);
});
await test('page tiles share annotation appearance rasters without changing their pixels',async()=>{
 const input=plan([path(rect,'#0000ff')]);
 input.annotation_fragments=[{svg:'<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20"><rect width="20" height="20" fill="red" fill-opacity="0.5"/></svg>',x:0,y:0,width:20,height:20}];
 const control=await renderPdfCanvas(createCanvas(1,1),input,options);
 let loads=0,closed=0;
 const actual=await renderPdfPage(createCanvas(1,1),input,{...options,tileSize:10,loadImage:async uri=>{
  loads++;const image=await loadImage(uri);image.close=()=>closed++;return image;
 }});
 assert.equal(loads,1);assert.equal(closed,1);assert.deepEqual(actual.data,control.data);assert.deepEqual(actual.premultiplied,control.premultiplied);
});
await test('structured geometry, separate clip stack and evenodd rule',async()=>{
 const result=await renderPdfCanvas(createCanvas(20,20),plan([path(rect,'#ff0000',{clips:[{svg_path:'M 2 2H18V18H2Z M 6 6H14V14H6Z',even_odd:true}]})]),options);
 near(pixel(result,3,3),[255,0,0,255]);near(pixel(result,9,9),[255,255,255,255]);near(pixel(result,0,0),[255,255,255,255]);
});
await test('nonisolated group sees external backdrop',async()=>{
 const g={id:'1',isolated:false,knockout:false,alpha:1,blend_mode:'normal',color_space:'DeviceRGB'};
 const result=await renderPdfCanvas(createCanvas(20,20),plan([path(rect,'#cc8033'),path(rect,'#3366cc',{fill_alpha:0.5,blend_mode:'multiply',group_path:[g]})]),options);
 near(pixel(result,10,10),[122,90,46,255]);
});
await test('group invocation ids preserve separate repeated form paints',async()=>{
 const g={id:'a',isolated:true,knockout:false,alpha:0.5,blend_mode:'normal'};
 const result=await renderPdfCanvas(createCanvas(20,20),plan([path(rect,'#ff0000',{group_path:[g]}),path(rect,'#0000ff',{group_path:[{...g,id:'b'}]})]),options);
 near(pixel(result,10,10),[128,64,191,255]);
});
await test('knockout group distinguishes opaque shape from partial alpha',async()=>{
 const g={id:'k',isolated:true,knockout:true,alpha:1,blend_mode:'normal'};
 const result=await renderPdfCanvas(createCanvas(20,20),plan([path(rect,'#ff0000',{fill_alpha:0.5,group_path:[g]}),path(rect,'#0000ff',{fill_alpha:0.5,group_path:[g]})]),options);
 near(pixel(result,10,10),[127,127,255,255]);
});
await test('group bounds clip child paints',async()=>{
 const g={id:'b',isolated:true,knockout:false,alpha:1,blend_mode:'normal',bounds:{min_x:5,min_y:5,max_x:15,max_y:15}};
 const result=await renderPdfCanvas(createCanvas(20,20),plan([path(rect,'#ff0000',{group_path:[g]})]),options);
 near(pixel(result,10,10),[255,0,0,255]);near(pixel(result,2,2),[255,255,255,255]);
});
await test('soft mask form matrix and TR evaluated on complete mask group',async()=>{
 const mask={luminosity:false,backdrop:[0,0,0],matrix:[1,0,0,1,5,0],plan:plan([path('M0 0H5V20H0Z','#ff0000',{fill_alpha:0.5})]),transfer_map:Array.from({length:256},(_,i)=>i)};
 const result=await renderPdfCanvas(createCanvas(20,20),plan([path(rect,'#ff0000',{soft_mask:mask})]),options);
 near(pixel(result,7,10),[255,127,127,255]);near(pixel(result,2,10),[255,255,255,255]);
});
await test('zero-alpha paint still knocks out prior sibling unless AIS',async()=>{
 const g={id:'a',isolated:true,knockout:true,alpha:1,blend_mode:'normal'};
 const result=await renderPdfCanvas(createCanvas(20,20),plan([path(rect,'#ff0000',{group_path:[g]}),path(rect,'#0000ff',{fill_alpha:0,group_path:[g]})]),options);
 near(pixel(result,10,10),[255,255,255,255]);
});
await test('AIS changes a constant alpha into knockout shape',async()=>{
 const g={id:'a',isolated:true,knockout:true,alpha:1,blend_mode:'normal'};
 const result=await renderPdfCanvas(createCanvas(20,20),plan([path(rect,'#ff0000',{group_path:[g]}),path(rect,'#0000ff',{fill_alpha:0.5,alpha_is_shape:true,group_path:[g]})]),options);
 near(pixel(result,10,10),[127,0,128,255]);
});


const cmyk=components=>({space:'DeviceCMYK',components,colorants:['Cyan','Magenta','Yellow','Black'],paints:true});
const convertProcess=([c,m,y,k])=>[1-Math.min(1,c+k),1-Math.min(1,m+k),1-Math.min(1,y+k)];
await test('root process overprint preserves original ink planes',async()=>{
 const result=await renderPdfCanvas(createCanvas(20,20),plan([
  path(rect,'#00ffff',{fill_source:cmyk([1,0,0,0])}),
  path(rect,'#ff00ff',{fill_source:cmyk([0,1,0,0]),fill_overprint:true,overprint_mode:1}),
 ]),{...options,convertProcess,proof:true});
 near(pixel(result,10,10),[0,0,255,255]);assert.deepEqual(result.diagnostics,[]);
});
await test('OPM0 clears explicitly painted zero process components',async()=>{
 const result=await renderPdfCanvas(createCanvas(20,20),plan([
  path(rect,'#00ffff',{fill_source:cmyk([1,0,0,0])}),
  path(rect,'#ff00ff',{fill_source:cmyk([0,1,0,0]),fill_overprint:true,overprint_mode:0}),
 ]),{...options,convertProcess,proof:true});
 near(pixel(result,10,10),[255,0,255,255]);
});
await test('mixed RGB overprint is strict by default and labels explicit preview',async()=>{
 const input=plan([path(rect,'#00ffff',{fill_source:{space:'DeviceRGB',components:[0,1,1],paints:true}}),path(rect,'#ff00ff',{index:2,fill_source:cmyk([0,1,0,0]),fill_overprint:true,overprint_mode:1})]);
 await assert.rejects(()=>renderPdfCanvas(createCanvas(20,20),input,{...options,convertProcess,proof:true}),/backdrop/);
 const preview=await renderPdfCanvas(createCanvas(20,20),input,{...options,convertProcess,proof:true,unsupported:'warn'});
 assert.equal(preview.diagnostics[0].code,'PDF_OVERPRINT_UNSUPPORTED');assert.equal(preview.diagnostics[0].item,2);
});
await test('isolated CMYK group blends before display conversion',async()=>{
 const group={id:'cmyk',isolated:true,knockout:false,alpha:1,blend_mode:'normal',color_space:'DeviceCMYK'};
 const result=await renderPdfCanvas(createCanvas(20,20),plan([
 path(rect,'#00ffff',{fill_source:cmyk([1,0,0,0]),fill_alpha:.5,group_path:[group]}),
 path(rect,'#ff00ff',{fill_source:cmyk([0,1,0,0]),fill_alpha:.5,fill_overprint:true,overprint_mode:1,group_path:[group]}),
 ]),{...options,convertProcess});
 near(pixel(result,10,10),[128,128,255,255]);
});
await test('nonisolated groups inherit parent colour space',async()=>{
 const g={id:'inherit',isolated:false,knockout:false,alpha:1,blend_mode:'normal',color_space:'DeviceCMYK'};
 const result=await renderPdfCanvas(createCanvas(20,20),plan([path(rect,'#ff0000',{group_path:[g]})]),options);
 near(pixel(result,10,10),[255,0,0,255]);
});
await test('pattern replay can use a borrowed initial backdrop',async()=>{
 const backdrop=new Float32Array(20*20*4);for(let p=0;p<backdrop.length;p+=4){backdrop[p]=.8;backdrop[p+1]=.5;backdrop[p+2]=.2;backdrop[p+3]=1;}
 const result=await renderPdfCanvas(createCanvas(20,20),plan([path(rect,'#3366cc',{fill_alpha:.5,blend_mode:'multiply'})]),{...options,backdrop,transparent:true});
 near(pixel(result,10,10),[41,51,41,128]);assert.equal(backdrop[3],1);
});
await test('gray group converts sources before multiplying',async()=>{
 const group={id:'gray',isolated:true,knockout:false,alpha:1,blend_mode:'normal',color_space:'DeviceGray'};
 const result=await renderPdfCanvas(createCanvas(20,20),plan([path(rect,'#ff0000',{group_path:[group]}),path(rect,'#00ff00',{group_path:[group],blend_mode:'multiply'})]),options);
 near(pixel(result,10,10),[45,45,45,255]);
});
await test('CMYK luminosity mask composites BC before nonlinear output conversion',async()=>{
 const maskPlan=plan([path(rect,'#00ffff',{fill_source:cmyk([1,0,0,0]),fill_alpha:.5})]);maskPlan.page={...page,blend_space:'DeviceCMYK'};
 const nonlinear=([c,m,y])=>[(1-c)**2,(1-m)**2,(1-y)**2];
 const mask={luminosity:true,backdrop:[1,0,0],backdrop_components:[0,1,1,0],plan:maskPlan};
 const result=await renderPdfCanvas(createCanvas(20,20),plan([path(rect,'#000000',{soft_mask:mask})]),{...options,convertProcess:nonlinear});
 near(pixel(result,10,10),[191,191,191,255]);
});
await test('direct A1 text pen carries stroke alpha and combined knockout',async()=>{
 const item={kind:'text',paint:{rendering_mode:2,fill_color:'#ff0000',fill_alpha:.75,stroke_color:'#0000ff',blend_mode:'normal',clips:[],stroke:{svg_path:'M5 5 L15 5 L15 15 L5 15 Z',transform:[1,0,0,1,0,0],line_width:4,line_cap:0,line_join:0,dash_array:[],dash_phase:0,miter_limit:10,stroke_alpha:.4}}};
 const result=await renderPdfCanvas(createCanvas(20,20),plan([item]),options);
 near(pixel(result,6,10),[153,153,255,255]);near(pixel(result,10,10),[255,64,64,255]);
});
await test('TK true groups overlapping glyphs while TK false composites them',async()=>{
 const glyph=tk=>({kind:'text',paint:{text_object_id:'page/text/1',text_knockout:tk,rendering_mode:1,fill_alpha:1,stroke_color:'#0000ff',blend_mode:'normal',clips:[],stroke:{svg_path:'M5 5 L15 5 L15 15 L5 15 Z',transform:[1,0,0,1,0,0],line_width:20,line_cap:0,line_join:0,dash_array:[],dash_phase:0,miter_limit:10,stroke_alpha:.5}}});
 for(const [tk,expected] of [[true,128],[false,64]]){
  const result=await renderPdfCanvas(createCanvas(20,20),plan([glyph(tk),glyph(tk)]),options);
  near(pixel(result,10,10),[expected,expected,255,255]);
 }
});
const imageQuad={p0:{x:0,y:0},p1:{x:0,y:20},p2:{x:20,y:20},p3:{x:20,y:0}};
const sampleCanvas=createCanvas(1,1),sampleContext=sampleCanvas.getContext('2d');
sampleContext.fillStyle='rgba(255,0,255,.5)';sampleContext.fillRect(0,0,1,1);
const sampleUri=sampleCanvas.toDataURL();
await test('sampled CMYK marks zero components despite OPM1',async()=>{
 const image={kind:'image',paint:{name:'Im',quad:imageQuad,fill_alpha:1,fill_overprint:true,overprint_mode:1,blend_mode:'normal',resource:{data_uri:sampleUri,width:1,height:1,has_local_mask:true,alpha_is_explicit_shape:false,ink_samples:{width:1,height:1,components:4,bits:16,row_bytes:8,data_base64:Buffer.from([0,0,255,255,0,0,0,0]).toString('base64'),alpha_base64:Buffer.from([128]).toString('base64'),source_colour:cmyk([0,0,0,0])}}}};
 const input=plan([path(rect,'#00ffff',{fill_source:cmyk([1,0,0,0])}),image]);input.page={...page,blend_space:'DeviceCMYK'};
 const result=await renderPdfCanvas(createCanvas(20,20),input,{...options,convertProcess});
 near(pixel(result,10,10),[128,127,255,255]);
});
await test('image-local soft mask overrides graphics-state mask',async()=>{
 const image={kind:'image',paint:{name:'Im',quad:imageQuad,fill_alpha:1,blend_mode:'normal',soft_mask:{plan:plan([]),luminosity:false},resource:{data_uri:sampleUri,width:1,height:1,has_local_mask:true,alpha_is_explicit_shape:false}}};
 const result=await renderPdfCanvas(createCanvas(20,20),plan([image]),options);
 near(pixel(result,10,10),[255,128,255,255]);
});
await test('explicit image mask changes knockout shape, unlike opacity mask',async()=>{
 const g={id:'image-shape',isolated:true,knockout:true,alpha:1,blend_mode:'normal'};
 for(const [shape,red] of [[true,255],[false,255]]){
  const image={kind:'image',paint:{name:'Im',quad:imageQuad,fill_alpha:1,blend_mode:'normal',group_path:[g],resource:{data_uri:sampleUri,width:1,height:1,has_local_mask:true,alpha_is_explicit_shape:shape}}};
  const result=await renderPdfCanvas(createCanvas(20,20),plan([path(rect,'#ff0000',{group_path:[g]}),image]),options);
  near(pixel(result,10,10),shape?[red,0,127,255]:[red,128,255,255]);
 }
});
await test('retained elementary scene uses live backdrop and independent outer alpha',async()=>{
 const scene=plan([path(rect,'#3366cc',{fill_alpha:.5,blend_mode:'multiply'})]);
 const opts={...options,paintShading:async(context,resource,paint,env)=>env.paintScene(context,resource.scene,{shapeOnly:env.shapeOnly,component:env.component})};
 const item=path(rect,'#000',{fill_alpha:.5,shading_pattern:{scene}});
 const result=await renderPdfCanvas(createCanvas(20,20),plan([path(rect,'#cc8033'),item]),opts);
 near(pixel(result,10,10),[163,109,48,255]);
});
await test('path pen inherits cap and join fields from the outer path item',async()=>{
 const item=path('M10 10L10 10','#000',{filled:false,stroked:true,stroke_color:'#000',stroke_alpha:1,line_cap:1,line_join:2,stroke:{svg_path:'M10 10L10 10',transform:[1,0,0,1,0,0],line_width:8,dash_array:[],dash_phase:0,miter_limit:10}});
 const result=await renderPdfCanvas(createCanvas(20,20),plan([item]),options);
 near(pixel(result,10,10),[0,0,0,255]);near(pixel(result,4,10),[255,255,255,255]);
 for(const cap of [0,2]){const empty=await renderPdfCanvas(createCanvas(20,20),plan([{...item,paint:{...item.paint,line_cap:cap}}]),options);near(pixel(empty,10,10),[255,255,255,255]);}
 const closed=await renderPdfCanvas(createCanvas(20,20),plan([{...item,paint:{...item.paint,stroke:{...item.paint.stroke,svg_path:'M10 10Z'}}}]),options);near(pixel(closed,10,10),[0,0,0,255]);
 const vertex='M3 15L10 3L17 15',pen={...item.paint.stroke,svg_path:vertex,line_width:6};
 const bevel=await renderPdfCanvas(createCanvas(20,20),plan([{...item,paint:{...item.paint,svg_path:vertex,stroke:pen,line_cap:0,line_join:2}}]),options);
 const miter=await renderPdfCanvas(createCanvas(20,20),plan([{...item,paint:{...item.paint,svg_path:vertex,stroke:pen,line_cap:0,line_join:0}}]),options);
 assert.ok(pixel(bevel,10,0)[0]>240&&pixel(miter,10,0)[0]<40,'bevel and miter must retain distinct join geometry');
});
await test('decoded image cache is bounded and releases resources on success and failure',async()=>{
 let alive=0,peak=0,closed=0;
 const opts={...options,loadImage:async()=>{const value=await loadImage(sampleUri);alive++;peak=Math.max(peak,alive);value.close=()=>{alive--;closed++;};return value;}};
 const items=Array.from({length:70},(_,i)=>({kind:'image',paint:{name:'Im'+i,quad:imageQuad,fill_alpha:1,blend_mode:'normal',resource:{data_uri:'test-image:'+i,width:1,height:1}}}));
 await renderPdfCanvas(createCanvas(20,20),plan(items),opts);
 assert.equal(alive,0);assert.equal(closed,70);assert.ok(peak<=65,'at most 64 cached images plus the arriving image');
 await assert.rejects(()=>renderPdfCanvas(createCanvas(20,20),plan([items[0],{kind:'invalid',paint:{}}]),opts),/Unknown PDF/);
 assert.equal(alive,0,'failed replay also releases cached images');
});
await test('Type3 retained scenes do not crop to text selection bounds',async()=>{
 const glyph={kind:'text',paint:{fill_alpha:.25,blend_mode:'multiply',font_size:1,bounds:{min_x:0,min_y:0,max_x:1,max_y:1}},type3_plan:plan([path('M15 0L20 0L20 5L15 5Z','#ff0000')])};
 const result=await renderPdfCanvas(createCanvas(20,20),plan([glyph]),options);
 near(pixel(result,17,2),[255,0,0,255]);
});
await test('additive proof planes reserve the shared memory budget before allocation',async()=>{
 const item=path(rect,'#000',{fill_overprint:true,fill_source:{space:'DeviceN',components:Array(32).fill(.5),colorants:Array.from({length:32},(_,i)=>'Spot'+i),paints:true}});
 await assert.rejects(()=>renderPdfCanvas(createCanvas(20,20),plan([item]),{...options,proof:true,maxWorkingBytes:30000}),/proof planes.*budget/);
});
await test('glyph raster padding uses transformed em rather than raw PDF font size',async()=>{
 let largest=0;
 const opts={...options,loadImage:async uri=>{const value=await loadImage(uri);largest=Math.max(largest,value.width,value.height);return value;}};
 const text={kind:'text',paint:{bounds:{min_x:5,min_y:5,max_x:10,max_y:15},font_size:200,glyph_transform:[10,0,0,10,5,5],fill_alpha:1,blend_mode:'normal'},text_svg:'<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><path d="M5 5H10V15H5Z" fill="#000"/></svg>'};
 const result=await renderPdfCanvas(createCanvas(20,20),plan([text]),opts);near(pixel(result,7,7),[0,0,0,255]);assert.ok(largest<=32,'glyph SVG must not expand to the untransformed 200-unit font size');
});
const stripePlan={...plan([path('M0 0H5V20H0Z','#ff0000'),path('M5 0H10V20H5Z','#0000ff')]),page:{...page,width:10},viewport:{width:10,height:20,matrix:[1,0,0,-1,0,20]}};
const stripes={name:'stripes',bbox:{min_x:0,min_y:0,max_x:10,max_y:20},x_step:10,y_step:20,matrix:[1,0,0,1,0,0],tile_plan:stripePlan};
const patternOptions={...options};patternOptions.paintPattern=createPatternPainter(patternOptions);
const textBase={bounds:{min_x:0,min_y:0,max_x:20,max_y:20},font_size:10,fill_alpha:.5,stroke_alpha:.4,fill_color:'#000',stroke_color:'#000',blend_mode:'normal',clips:[]};
await test('fill-only A1 glyph paths use native geometry and page-anchored patterns',async()=>{
 const item={kind:'text',paint:{...textBase,rendering_mode:0,fill_path:'M2 2H18V18H2Z'},pattern:stripes};
 const result=await renderPdfCanvas(createCanvas(20,20),plan([item]),{...patternOptions,loadImage:()=>{throw new Error('native glyph must not load an SVG');}});
 near(pixel(result,3,10),[255,128,128,255]);near(pixel(result,7,10),[128,128,255,255]);near(pixel(result,0,0),[255,255,255,255]);
});
await test('fallback text split masks preserve independent patterns and knockout alpha',async()=>{
 const svg=(color,opacity)=>`<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><path d="M2 2H18V18H2Z" fill="${color}" fill-opacity="${opacity}"/></svg>`;
 const item={kind:'text',paint:{...textBase,rendering_mode:2},pattern:stripes,text_fill_svg:svg('#000',.5),text_stroke_svg:svg('#00ff00',.4),text_svg:null};
 const result=await renderPdfCanvas(createCanvas(20,20),plan([item]),patternOptions);
 near(pixel(result,7,10),[153,255,153,255]);
 const fill={...item,paint:{...item.paint,rendering_mode:0},text_stroke_svg:null};
 const painted=await renderPdfCanvas(createCanvas(20,20),plan([fill]),patternOptions);
 near(pixel(painted,3,10),[255,128,128,255]);near(pixel(painted,7,10),[128,128,255,255]);
});
const stencilCanvas=createCanvas(1,1);stencilCanvas.getContext('2d').fillStyle='#fff';stencilCanvas.getContext('2d').fillRect(0,0,1,1);
const stencil={kind:'image',paint:{name:'stencil',quad:imageQuad,fill_color:'#000',fill_alpha:.5,blend_mode:'normal',resource:{mask_data_uri:stencilCanvas.toDataURL(),width:1,height:1}}};
await test('image stencils retain pattern anchoring, shape and None suppression',async()=>{
 const painted=await renderPdfCanvas(createCanvas(20,20),plan([{...stencil,pattern:stripes}]),patternOptions);
 near(pixel(painted,3,10),[255,128,128,255]);near(pixel(painted,7,10),[128,128,255,255]);
 const none=await renderPdfCanvas(createCanvas(20,20),plan([{...stencil,paint:{...stencil.paint,fill_source:{paints:false}}}]),options);
 near(pixel(none,3,10),[255,255,255,255]);assert.ok(none.shape.every(v=>v===0));
});
await test('ICC and calibrated stencil colours use the same target components as paths',async()=>{
 const source={space:'ICCBased',components:[.05,.2,.6],icc_profile_id:'same',paints:true};
 const scope={sourceToGroup:source=>source.components,groupToRgb:values=>values.map(v=>Math.sqrt(v))};
 for(const target of [{blend_profile_id:'same'},{blend_calibration:{components:3,gamma:[1,1,1],pcs_matrix:[1,0,0,0,1,0,0,0,1],pcs_offset:[0,0,0]}}]){
  const input={...plan([{...stencil,paint:{...stencil.paint,fill_alpha:1,fill_source:source}}]),...target};
  const painted=await renderPdfCanvas(createCanvas(20,20),input,{...options,_profileScope:scope});
  near(pixel(painted,7,10),[...source.components.map(v=>Math.sqrt(v)*255),255]);
 }
});
await test('native text shading fills remain clipped to the glyph path',async()=>{
 const item={kind:'text',paint:{...textBase,fill_alpha:1,rendering_mode:0,fill_path:'M5 5H15V15H5Z'},pattern:{shading:{kind:'test'}}};
 const opts={...options,paintShading:context=>{context.fillStyle='#ff0000';context.fillRect(0,0,20,20);}};
 const result=await renderPdfCanvas(createCanvas(20,20),plan([item]),opts);
 near(pixel(result,10,10),[255,0,0,255]);near(pixel(result,2,10),[255,255,255,255]);
});
await test('per-paint resources release after the final shape pass and on errors',async()=>{
 const keys=[],released=[],allocated=[];
 const painter=async(context,resource,p,operation,env)=>{keys.push(env.paintKey);context.fillStyle='#ff0000';context.fill(new Path2D(p.svg_path));};
 painter.releasePaint=key=>released.push(key);
 await renderPdfCanvas(createCanvas(20,20),plan([path(rect,'#000',{pattern:stripes})]),{...options,paintPattern:painter});
 assert.equal(keys.length,2);assert.equal(released.length,1);assert.equal(keys[0],keys[1]);assert.equal(keys[0],released[0]);
 const failing=async()=>{throw new Error('pattern failed');};failing.releasePaint=painter.releasePaint;
 await assert.rejects(()=>renderPdfCanvas(createCanvas(20,20),plan([path(rect,'#000',{pattern:stripes})]),{...options,paintPattern:failing}),/pattern failed/);assert.equal(released.length,2);
 const tracked=(w,h)=>{const canvas=createCanvas(w,h);allocated.push(canvas);return canvas;};
 const glyph={kind:'text',paint:{fill_alpha:1,blend_mode:'normal'},type3_plan:plan([path(rect,'#ff0000')])};
 await renderPdfCanvas(createCanvas(20,20),plan([glyph]),{...options,createCanvas:tracked});
 assert.equal(allocated.filter(canvas=>canvas.width===20&&canvas.height===20).length,0,'scene bitmap surfaces must release without waiting for host GC');
});
await test('fallback pattern replay uses exact existing mask coverage rather than font em',async()=>{
 const bounds=[];
 const painter=async(context,resource,p,operation,env)=>{bounds.push(env.paintBounds);context.fillStyle='#ff0000';context.fillRect(0,0,20,20);};
 const item={kind:'text',paint:{...textBase,rendering_mode:0,fill_alpha:1,glyph_transform:[100,0,0,100,0,0]},pattern:stripes,text_svg:'<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><path d="M8 8H12V12H8Z" fill="#000"/></svg>'};
 const result=await renderPdfCanvas(createCanvas(20,20),plan([item]),{...options,paintPattern:painter});
 near(pixel(result,10,10),[255,0,0,255]);assert.equal(bounds.length,2);
 for(const b of bounds)assert.deepEqual(b,{x:8,y:8,width:4,height:4});
});
await test('identical fallback glyph rasters share a bounded cache across nested scenes',async()=>{
 let loads=0,closed=0;
 const opts={...options,loadImage:async source=>{loads++;const value=await loadImage(source);value.close=()=>closed++;return value;}};
 const text={kind:'text',paint:{...textBase,fill_alpha:1,rendering_mode:0},text_svg:'<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><path d="M8 8H12V12H8Z" fill="#000"/></svg>'};
 const scene={kind:'text',paint:{fill_alpha:1,blend_mode:'normal'},type3_plan:plan([text])};
 await renderPdfCanvas(createCanvas(20,20),plan(Array(12).fill(scene)),opts);
 assert.equal(loads,1);assert.equal(closed,1,'root completion releases borrowed nested glyph images');
 const tiny={...text,paint:{...text.paint,bounds:{min_x:0,min_y:0,max_x:4,max_y:4},font_size:1},text_svg:'<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"><path d="M1 1H3V3H1Z" fill="#000"/></svg>'};
 const tile={...plan([tiny]),page:{...page,width:4,height:4},viewport:{width:4,height:4,matrix:[1,0,0,-1,0,4]}};
 const resource={...stripes,bbox:{min_x:0,min_y:0,max_x:4,max_y:4},x_step:4,y_step:4,tile_plan:tile};
 const painter=createPatternPainter(opts);
 await renderPdfCanvas(createCanvas(20,20),plan([path(rect,'#000',{pattern:resource})]),{...opts,paintPattern:painter});painter.dispose();
 assert.equal(loads,2,'all backdrop-dependent pattern cells share one glyph raster');assert.equal(closed,2);

 await assert.rejects(()=>renderPdfCanvas(createCanvas(20,20),plan([text,{kind:'bad',paint:{}}]),opts),/Unknown PDF/);assert.equal(closed,3);
 loads=0;closed=0;
 await renderPdfCanvas(createCanvas(20,20),plan([text,text]),{...opts,maxGlyphCacheBytes:1});assert.equal(loads,4);assert.equal(closed,4,'uncacheable images release immediately');
 const large={...text,paint:{...text.paint,glyph_transform:[100000,0,0,100000,0,0]}};
 await assert.rejects(()=>renderPdfCanvas(createCanvas(20,20),plan([large]),opts),/glyph raster.*limit/);assert.equal(loads,4,'oversized glyph rejects before host allocation');
});
await test('RGB and CMYK blend scratch releases on failure and isolated group exit',async()=>{
 for(const ink of [false,true]){
  const canvases=[];const opts={...options,convertProcess,createCanvas:(w,h)=>{const c=createCanvas(w,h);canvases.push(c);return c;}};
  const items=[path(rect,'#ff0000',{fill_source:cmyk([0,1,1,0])}),path(rect,'#00ff00',{fill_source:cmyk([1,0,1,0]),blend_mode:'multiply'}),{kind:'bad',paint:{}}];
  const input={...plan(items),page:{...page,blend_space:ink?'DeviceCMYK':'DeviceRGB'}};
  await assert.rejects(()=>renderPdfCanvas(createCanvas(20,20),input,opts),/Unknown PDF/);
  assert.ok(canvases.every(c=>c.width===1),'failed compositor must release all full-size host scratch');
 }
});
await test('optional host text outlines resolve only successful ordinary glyph diagnostics',async()=>{
 const text={kind:'text',paint:{...textBase,index:7,rendering_mode:1,stroke_color:'#0000ff',stroke:{svg_path:null,transform:[1,0,0,1,5,5],line_width:2,line_cap:0,line_join:0,dash_array:[],dash_phase:0,miter_limit:10,stroke_alpha:1,unresolved:'missing-outline'}},text_svg:'<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><text x="5" y="15">A</text></svg>'};
 const diagnostic={code:'PDF_TEXT_STROKE_GEOMETRY',item:7,message:'missing-outline'},input={...plan([text]),diagnostics:[diagnostic]};
 await assert.rejects(()=>renderPdfCanvas(createCanvas(20,20),input,options),/PDF_TEXT_STROKE_GEOMETRY/);
 let calls=0;
 const resolveTextOutline=async(svg,{paint,page:targetPage})=>{calls++;assert.equal(svg,text.text_svg);assert.equal(paint,text.paint);assert.equal(targetPage,page);return {fill_path:'M5 5H15V15H5Z',stroke_path:'M0 0H10V10H0Z'};};
 const result=await renderPdfCanvas(createCanvas(20,20),input,{...options,resolveTextOutline});
 near(pixel(result,5,10),[0,0,255,255]);near(pixel(result,10,10),[255,255,255,255]);assert.equal(calls,1);assert.deepEqual(result.diagnostics,[]);assert.equal(text.paint.stroke.svg_path,null,'resolving does not mutate the input plan');assert.equal(input.diagnostics.length,1);
 await assert.rejects(()=>renderPdfCanvas(createCanvas(20,20),input,{...options,resolveTextOutline:()=>null}),/PDF_TEXT_STROKE_GEOMETRY/);
 await assert.rejects(()=>renderPdfCanvas(createCanvas(20,20),{...input,diagnostics:[diagnostic,{code:'OTHER',item:7,message:'still unsupported'}]},{...options,resolveTextOutline}),/OTHER/);
 await assert.rejects(()=>renderPdfCanvas(createCanvas(20,20),input,{...options,resolveTextOutline:()=>({fill_path:'M0 0'})}),/pen-local stroke_path/);
 const type3={...text,type3_plan:plan([])};
 await renderPdfCanvas(createCanvas(20,20),plan([type3]),{...options,resolveTextOutline:()=>{throw new Error('Type3 must not call host glyph resolution');}});
});
patternOptions.paintPattern.dispose();
console.log(`${count} Canvas replay tests passed`);

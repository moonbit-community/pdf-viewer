import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {PdfRenderTask,yieldPdfTask} from '../../web/pdf-render-task.mjs';
import {renderPdfCanvas} from '../../web/pdf-canvas.mjs';
import {renderPdfPage} from '../../web/pdf-runtime.mjs';
import {createPatternPainter} from '../../web/pdf-patterns.mjs';

let clock=0,calls=0,release;
const task=new PdfRenderTask(()=>{calls++;return new Promise(resolve=>release=resolve);},()=>clock);
assert.equal(task.due(),false);clock=12;assert(task.due());
const first=task.yield(),joined=task.yield();assert.equal(first,joined,'Concurrent scene continuations share the pending host task');
await Promise.resolve();assert.equal(calls,1);clock=100;release();await first;
assert.equal(task.deadline,112,'Waiting time does not consume the next compute budget');
assert.equal(task.due(),false,'A parent does not immediately yield after its child');clock=112;assert(task.due());
let failures=0;
const failing=new PdfRenderTask(()=>{if(!failures++)throw Error('Host failed');},()=>clock);
await assert.rejects(failing.yield(),/Host failed/);assert.equal(failing.pending,null);await failing.yield();

const descriptors=Object.fromEntries(['scheduler','MessageChannel'].map(k=>[k,Object.getOwnPropertyDescriptor(globalThis,k)]));
const set=(key,value)=>Object.defineProperty(globalThis,key,{configurable:true,writable:true,value});
try{
 const scheduler={yield(){assert.equal(this,scheduler);calls++;return Promise.resolve();}};
 set('scheduler',scheduler);const before=calls;await yieldPdfTask();assert.equal(calls,before+1);
 set('scheduler',undefined);let complete=false;const pending=yieldPdfTask().then(()=>complete=true);
 await Promise.resolve();assert.equal(complete,false,'MessageChannel yields to a host task, not only to a microtask');await pending;assert(complete);
 let closed=0;
 set('MessageChannel',class{constructor(){this.port1={close(){closed++;}};this.port2={close(){closed++;},postMessage(){throw Error('Port failed');}};}});
 await assert.rejects(yieldPdfTask(),/Port failed/);assert.equal(closed,2,'A failed send closes both ports');
 set('MessageChannel',undefined);await yieldPdfTask();
}finally{
 for(const [key,descriptor] of Object.entries(descriptors)){if(descriptor)Object.defineProperty(globalThis,key,descriptor);else delete globalThis[key];}
}

const {createCanvas,Path2D,loadImage}=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url)('@napi-rs/canvas');
const host={createCanvas,Path2D,loadImage},page={origin_x:0,origin_y:0,width:20,height:20,user_unit:1,rotation:0,blend_space:'DeviceRGB'};
const plan=items=>({version:1,page,viewport:{width:20,height:20,matrix:[1,0,0,-1,0,20]},items});
const path=extra=>({kind:'path',paint:{svg_path:'M0 0H20V20H0Z',filled:true,stroked:false,fill_color:'#800000',fill_alpha:1,stroke_alpha:1,blend_mode:'normal',clips:[],group_path:[],...extra}});
const cell={name:'cell',paint_type:1,tiling_type:1,bbox:{min_x:0,min_y:0,max_x:20,max_y:20},x_step:20,y_step:20,matrix:[1,0,0,1,0,0],tile_plan:plan([path()])};
const patterned=plan([path({pattern:cell})]),nested=plan([{kind:'text',paint:{rendering_mode:0,fill_alpha:1,blend_mode:'normal',text_object_id:1,text_knockout:false},type3_plan:plan([path()])}]);
const seen=new Set(),due=PdfRenderTask.prototype.due;
PdfRenderTask.prototype.due=function(){seen.add(this);return due.call(this);};
try{
 for(const [name,input,render,extra] of [
  ['nested retained',nested,renderPdfCanvas,{nativeCanvas:false}],
  ['tiled',plan([path()]),renderPdfPage,{nativeCanvas:false,tileSize:8}],
  ['runtime pattern',patterned,renderPdfPage,{}],
  ['external pattern',patterned,renderPdfCanvas,{nativeCanvas:false}],
 ]){
  seen.clear();const options={...host,yieldToHost:yieldPdfTask,returnPixels:false,...extra};
  if(name==='external pattern')options.paintPattern=createPatternPainter(options);
  try{await render(createCanvas(1,1),input,options);assert.equal(seen.size,1,name+' must share one task through all nested renderers');}
  finally{options.paintPattern?.dispose();}
 }
 const controller=new AbortController(),cancelTask=new PdfRenderTask(async()=>controller.abort());cancelTask.deadline=-1;
 await assert.rejects(renderPdfPage(createCanvas(1,1),plan([path()]),{...host,returnPixels:false,yieldToHost:yieldPdfTask,_renderTask:cancelTask,signal:controller.signal}),{name:'AbortError'});
}finally{PdfRenderTask.prototype.due=due;}
console.log('PASS cooperative task budget, pending joins, host failures, browser-task/timer fallback, nested scenes, tiled/external patterns and cancellation');

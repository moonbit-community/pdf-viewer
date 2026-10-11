import assert from 'node:assert/strict';import {createRequire} from 'node:module';
import {PdfCompositor} from '../../web/pdf-compositor.mjs';import {PdfInkCompositor} from '../../web/pdf-ink-compositor.mjs';
const {createCanvas}=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url)('@napi-rs/canvas');
for(const [Engine,stride,frameBytes,scratchBytes] of [[PdfCompositor,4,40,40],[PdfInkCompositor,5,48,112]]){
 const budget=6*(frameBytes*2+scratchBytes),engine=new Engine(3,2,createCanvas,{maxWorkingBytes:budget});
 const root=engine.beginGroup({isolated:true}),input=new Float32Array(6*stride),shape=new Float32Array(6);input[0]=.25;input[stride-1]=.5;shape[0]=1;
 engine.paint(input,shape);const child=engine.beginGroup({isolated:false},root.pixels);engine.paint(input,shape,{dirty:{x:0,y:0,width:1,height:1}});
 const result=engine.endGroup({recycle:true});assert.ok(result.pixels.slice(stride).every(x=>x===0));assert.equal(engine.recyclingFrames.size,1);
 assert.throws(()=>engine.beginGroup(),/memory limit/,'leased frame remains in the working budget');
 engine.paint(result.pixels,result.shape,{dirty:result.dirty});engine.releaseGroup(result);
 assert.equal(engine.beginGroup(),child,'released child reuses the same pixel and shape arrays');const owned=engine.endGroup();const copy=owned.pixels.slice();
 engine.beginGroup();engine.paint(input,shape);engine.endGroup();assert.deepEqual(owned.pixels,copy,'default exported results stay owned');
}
const ink=new PdfInkCompositor(3,2,createCanvas),shape=Float32Array.from([1,0,0,0,0,1]);ink.beginGroup({isolated:true});
const a=ink.borrowSource({x:0,y:0,width:1,height:1});a.pixels[4]=1;a.shape[0]=1;
const b=ink.borrowSource({x:2,y:1,width:1,height:1});assert.equal(a,b);assert.ok(b.pixels.every(x=>x===0));assert.ok(b.shape.every(x=>x===0));
console.log('Recycled frame ownership, leased-buffer budgets and zero-outside source reuse: passed');

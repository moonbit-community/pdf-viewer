import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createPdfIccEngine} from '../web/pdf-icc.mjs';
const engine=await createPdfIccEngine({maxActiveTransforms:1});
const profiles=[['rgb-gamma22.icc',3],['gray-gamma22.icc',1],['CGATS001Compat-v2-micro.icc',4]];
try{
 // The compact CMYK fixture has an input LUT only; use the reversible matrix
 // RGB and gray profiles for destinations, plus the engine's sRGB default.
 for(const [file,components]of profiles)for(const [target,outputComponents]of [[null,3],...profiles.slice(0,2)])for(const intent of [0,1,2,3]){
  const bytes=readFileSync(new URL('../assets/icc/'+file,import.meta.url));
  const destination=target?readFileSync(new URL('../assets/icc/'+target,import.meta.url)):null;
  const handle=engine.open(bytes,components,intent,destination,outputComponents);assert(handle,`${file}/${target}/${intent}`);
  for(const count of [1,2,9,53,64]){
   const values=new Float64Array(count*4),expected=new Float64Array(count*outputComponents),actual=new Float64Array(count*outputComponents),one=new Float64Array(outputComponents);
   for(let row=0;row<count;row++){
    for(let c=0;c<4;c++)values[row*4+c]=row===0?0:row===count-1?1:((row*37+c*71)%257)/256;
    assert(handle.convert(...values.subarray(row*4,row*4+4),one));expected.set(one,row*outputComponents);
   }
   engine.clearActiveTransforms(); // The retained batch handle must reopen.
   assert(handle.convertMany(values,count,actual));assert.deepEqual(actual,expected,`${file}/${target}/${intent}/${count}`);
   // Interleave scalar calls with batches: neither may retain another call's
   // input or output buffers, including a caller-owned result array.
   assert(handle.convert(...values.subarray(0,4),one));assert.deepEqual(one,expected.subarray(0,outputComponents));
  }
  assert.equal(handle.convertMany([],0,[]),false);
  assert.equal(handle.convertMany(new Float64Array(260),65,new Float64Array(65*outputComponents)),false);
  assert.equal(handle.convertMany([0,0,0],1,new Float64Array(outputComponents)),false);
  assert.equal(handle.convertMany([0,0,0,0],1,[]),false);
  handle.close();const out=new Float64Array(outputComponents);assert.equal(handle.convertMany([0,0,0,0],1,out),false);assert(out.every(Number.isNaN));
 }
 assert(engine.statistics.batches>=180);
 console.log('ICC batches match scalar results exactly for 180 source/target profile, intent and batch-size combinations, plus reopen and disposal.');
}finally{engine.dispose();}

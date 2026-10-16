import assert from 'node:assert/strict';
import {PdfImageResourceCache} from '../../web/pdf-image-resource-cache.mjs';
import {PdfRasterStore} from '../../web/pdf-raster-store.mjs';

for(const limit of [-1,257,NaN,Infinity,undefined])assert.throws(()=>new PdfImageResourceCache(limit),RangeError);

const cache=new PdfImageResourceCache(2),document={},resources={},object={},bg={},ucr={};
const keys=[document,resources,'/Image',object,true,'/RelativeColorimetric',bg,ucr];
const first=Object.freeze({opaque:true}),second=Object.freeze({opaque:false});
assert.equal(cache.get(...keys),undefined);
cache.set(keys,first);
assert.equal(cache.get(...keys),first);
// Each caller-visible binding and colour policy must distinguish entries.
for(const [index,value] of [[0,{}],[1,{}],[2,'/Other'],[3,{}],[4,false],[5,'/Perceptual'],[6,{}],[7,{}]]){
 const changed=keys.slice();changed[index]=value;
 assert.equal(cache.get(...changed),undefined);
}
const alternate=keys.slice();alternate[2]='/Second';cache.set(alternate,second);
assert.equal(cache.entries,2);
const excess=keys.slice();excess[2]='/Excess';cache.set(excess,{});
assert.equal(cache.entries,2);assert.equal(cache.get(...excess),undefined);
assert.equal(cache.get(...keys),first);
cache.set(keys,second);assert.equal(cache.entries,2);assert.equal(cache.get(...keys),second);
cache.reset();assert.equal(cache.entries,0);assert.equal(cache.get(...keys),undefined);
for(const index of [0,1,3]){const invalid=keys.slice();invalid[index]=null;cache.set(invalid,first);assert.equal(cache.get(...invalid),undefined);}
assert.equal(cache.entries,0);
for(const [index,value] of [[2,'A'.repeat(257)],[5,'A'.repeat(97)]]){
 const oversized=keys.slice();oversized[index]=value;
 cache.set(oversized,first);assert.equal(cache.get(...oversized),undefined);
}
assert.equal(cache.entries,0);

const canvas=(width,height)=>({width,height,getContext(){return{}},transferToImageBitmap(){return{close(){}}}});
const store=new PdfRasterStore({maxBytes:516,maxEntries:1,createCanvas:canvas});
assert(store.initialize());store.enabled=true;
const marker=store.capture(1,1,2,new Uint8Array([0,10,20,30]),()=>new Uint8Array(8)),uri=store.uri(marker);
store.resourceSet(...keys,first,uri);
assert.equal(store.resourceGet(...keys),first);
assert.equal(store.bytes,516);
assert.equal(store.capture(1,1,2,new Uint8Array([0,10,20,30]),()=>new Uint8Array(8)),null);
assert.equal(store.resourceGet(...keys),first,'A saturated source store must retain reusable earlier resources');
store.resourceSet(...alternate,second,'pdf-raster:expired');
assert.equal(store.resourceGet(...alternate),undefined);
store.enabled=false;assert.equal(store.resourceGet(...keys),undefined);
store.enabled=true;store.reset();store.enabled=true;
assert.equal(store.resourceGet(...keys),undefined);
assert.equal(store.resources.entries,0);
store.resourceSet(...keys,first,uri);
assert.equal(store.resourceGet(...keys),undefined,'Invalidation must reject an old raster owner');
assert.equal(store.bytes,0);
console.log('Image resource reuse: opaque identities, every policy key, capacity, saturation and raster lifetime passed.');

import assert from 'node:assert/strict';
import {createColourPlaneSurface,cloneColourPlaneSurface,paintColourPlaneSurface,resolveColourPlaneSurface} from '../web/pdf-colour-planes.mjs';
const coverage=new Uint8ClampedArray([0,0,0,255]);
const cmyk=components=>({space:'DeviceCMYK',components,colorants:['Cyan','Magenta','Yellow','Black'],paints:true});
function surface(){const s=createColourPlaneSurface(1,1);paintColourPlaneSurface(s,cmyk([1,0,0,0]),coverage);return s;}
const op=surface();paintColourPlaneSurface(op,cmyk([0,1,0,0]),coverage,{overprint:true,mode:1});
assert.equal(op.planes.get('Cyan')[0],1);assert.equal(op.planes.get('Magenta')[0],1);
const op0=surface();paintColourPlaneSurface(op0,cmyk([0,1,0,0]),coverage,{overprint:true,mode:0});assert.equal(op0.planes.get('Cyan')[0],0);
const knockout=surface();paintColourPlaneSurface(knockout,cmyk([0,1,0,0]),coverage,{overprint:false,mode:1});assert.equal(knockout.planes.get('Cyan')[0],0);
const none=cloneColourPlaneSurface(op);paintColourPlaneSurface(none,{space:'Separation',colorants:['None'],components:[1],paints:false},coverage);assert.deepEqual(none,op);
const all=surface();paintColourPlaneSurface(all,{space:'Separation',colorants:['All'],components:[.5],all:true},coverage,{overprint:true});assert.equal(all.planes.get('Cyan')[0],.5);
paintColourPlaneSurface(all,{space:'Separation',colorants:['Spot'],components:[.25]},new Uint8ClampedArray([0,0,0,0]),{overprint:true});assert.equal(all.planes.get('Spot')[0],.5);
const partial=surface();paintColourPlaneSurface(partial,cmyk([0,1,0,0]),coverage,{overprint:false,alpha:.5});assert.equal(partial.planes.get('Cyan')[0],.5);assert.equal(partial.planes.get('Magenta')[0],.5);
const explicitZero=surface();paintColourPlaneSurface(explicitZero,{space:'Separation',colorants:['Cyan'],components:[0]},coverage,{overprint:true,mode:1});assert.equal(explicitZero.planes.get('Cyan')[0],0);
const mixed=surface();assert.equal(paintColourPlaneSurface(mixed,{space:'DeviceRGB',components:[1,0,0]},coverage).supported,false);assert.equal(resolveColourPlaneSurface(mixed,()=>[1,1,1]).unsupportedPixels,1);
paintColourPlaneSurface(mixed,cmyk([0,1,0,0]),coverage);assert.equal(mixed.valid[0],1);
assert.equal(resolveColourPlaneSurface(all,()=>[1,1,1]).unsupportedPixels,1);

assert.throws(()=>createColourPlaneSurface(100,100,[],{maxWorkingBytes:1000}),/memory budget/);
const bounded=createColourPlaneSurface(1,1,[],{maxWorkingBytes:29});
assert.throws(()=>paintColourPlaneSurface(bounded,{space:'Separation',colorants:['NewSpot'],components:[.5]},new Uint8ClampedArray([0,0,0,255])),/growth.*budget/);
console.log('Colour-plane tests: 12 cases passed');

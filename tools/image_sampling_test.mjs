import test from 'node:test';
import assert from 'node:assert/strict';
import {pdfImageSampling,pdfApplyImageSampling,pdfImageScaleSteps,pdfDrawImage} from '../web/pdf-image-sampling.mjs';

test('downscale and Float32 upsample boundary use PDF smoothing policy',()=>{
  assert.equal(pdfImageSampling([50,0,0,50,0,0],100,100).smoothing,true);
  assert.equal(pdfImageSampling([4/3+1e-9,0,0,4/3+1e-9,0,0],1,1).smoothing,true);
  assert.equal(pdfImageSampling([4/3+1e-4,0,0,1,0,0],1,1).smoothing,false);
  assert.equal(pdfImageSampling([20,0,0,20,0,0],1,1,true).smoothing,true);
  assert.equal(pdfImageSampling([2,0,0,2,0,0],1,1,false,2).smoothing,true);
});
test('shear and rotation use full affine singular values, not x/y diagonal terms',()=>{
  assert.equal(pdfImageSampling([1,0,1,1,0,0],1,1).smoothing,false);
  assert.equal(pdfImageSampling([0,1,-1,0,0,0],1,1).smoothing,true);
  assert.deepEqual(pdfImageSampling([1,0.2,0.1,1,0.3,0.4],1,1).matrix,[1,0.2,0.1,1,0.3,0.4]);
});
test('round both device corners for translated, mirrored and quarter-turn images',()=>{
  assert.deepEqual(pdfImageSampling([10.432,0,0,4.4,4.321,2.2],10,10).matrix,[11,0,0,5,4,2]);
  assert.deepEqual(pdfImageSampling([-10.432,0,0,-4.4,14.753,6.6],10,10).matrix,[-11,0,0,-5,15,7]);
  assert.deepEqual(pdfImageSampling([0,10.432,-4.4,0,6.6,4.321],10,10).matrix,[0,11,-5,0,7,4]);
  assert.deepEqual(pdfImageSampling([0.01,0,0,-0.01,4.1,2.1],1,1).matrix,[1,0,0,-1,4,2]);
});
test('context helper applies final CTM and smoothing together without altering alpha',()=>{
  const context={globalAlpha:0.4,getTransform:()=>({a:10.432,b:0,c:0,d:4.4,e:4.321,f:2.2}),setTransform(...m){this.matrix=m;}};
  pdfApplyImageSampling(context,100,100);
  assert.deepEqual(context.matrix,[11,0,0,5,4,2]);assert.equal(context.imageSmoothingEnabled,true);assert.equal(context.globalAlpha,0.4);
});
test('invalid dimensions and nonfinite matrices fail explicitly',()=>{
  assert.throws(()=>pdfImageSampling([1,0,0,1,0,0],0,1));
  assert.throws(()=>pdfImageSampling([1,0,0,1,Infinity,0],1,1));
});

test('large scan minification matches PDF.js bounded ceil-half steps',()=>{
  assert.deepEqual(pdfImageScaleSteps([623,0,0,832,0,0],5188,6930),[
    {width:2594,height:3465},{width:1297,height:1733},{width:649,height:867},
  ]);
  assert.deepEqual(pdfImageScaleSteps([832,0,0,623,0,0],6930,5188),[
    {width:3465,height:2594},{width:1733,height:1297},{width:867,height:649},
  ]);
  assert.deepEqual(pdfImageScaleSteps([100,0,0,10,0,0],100,100),[
    {width:100,height:50},{width:100,height:25},{width:100,height:13},
  ]);
  assert.deepEqual(pdfImageScaleSteps([100,0,0,100,0,0],200,200),[]);
});
test('scratch canvases are bounded, smoothed and released without changing paint state',()=>{
  const calls=[],canvases=[];
  const createCanvas=(width,height)=>{const c={width,height,getContext:()=>({drawImage(...args){calls.push(args);}})};canvases.push(c);return c;};
  const context={globalAlpha:0.3,imageSmoothingEnabled:false,getTransform:()=>[10,0,0,10,0,0],drawImage(...args){calls.push(args);}};
  const original={width:100,height:100};pdfDrawImage(context,original,createCanvas);
  assert.deepEqual(calls.map(c=>c.slice(-4)),[[0,0,50,50],[0,0,25,25],[0,0,13,13],[0,0,1,1]]);
  assert.ok(canvases.every(c=>c.width===1&&c.height===1));
  assert.equal(original.width,100);assert.equal(context.globalAlpha,0.3);assert.equal(context.imageSmoothingEnabled,false);
  assert.throws(()=>pdfDrawImage(context,original,createCanvas,2499),/limit/);
  assert.throws(()=>pdfImageScaleSteps([1,0,0,1,0,0],Infinity,1),/geometry/);
});
test('a failed intermediate or final draw releases all allocated scratch canvases',()=>{
  const canvases=[];const createCanvas=(width,height)=>{const c={width,height,getContext:()=>({drawImage(){if(canvases.length===2)throw Error('test failure');}})};canvases.push(c);return c;};
  const context={getTransform:()=>[10,0,0,10,0,0],drawImage(){throw Error('final failure');}};
  assert.throws(()=>pdfDrawImage(context,{width:100,height:100},createCanvas),/test failure/);
  assert.ok(canvases.every(c=>c.width===1&&c.height===1));
});

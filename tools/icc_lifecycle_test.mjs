import assert from 'node:assert/strict';
import {readFileSync,existsSync} from 'node:fs';
import {createPdfIccEngine,pdfDeviceRgbToCmyk,pdfIccIntent} from '../web/pdf-icc.mjs';
const root=new URL('../assets/icc/',import.meta.url),rgb=readFileSync(new URL('rgb-gamma22.icc',root)),gray=readFileSync(new URL('gray-gamma22.icc',root)),cmyk=readFileSync(new URL('CGATS001Compat-v2-micro.icc',root));
const engine=await createPdfIccEngine({maxActiveTransforms:2,memoryLimitBytes:64*1024*1024});
const held=[];
for(let i=0;i<20;i++){held.push(engine.open(rgb,3,i%4));assert.ok(held.at(-1));assert.ok(engine.statistics.activeTransforms<=2);}
const out=new Float64Array(3);assert.equal(held[0].convert(.2,.5,.8,0,out),true);assert.ok(Math.abs(out[0]-.18627)<.003);assert.ok(engine.statistics.reopens>0);
engine.clearActiveTransforms();assert.equal(engine.statistics.activeTransforms,0);assert.equal(held[0].convert(.2,.5,.8,0,out),true);assert.equal(engine.statistics.activeTransforms,1);
held[0].close();assert.equal(held[0].convert(.2,.5,.8,0,out),false);assert.ok(Number.isNaN(out[0]));
assert.equal(engine.registerProfile('actual-cmyk',cmyk,4),true);assert.equal(engine.registerProfile('actual-rgb',rgb,3),true);
assert.equal(engine.registerProfile('actual-rgb',gray,1),false);
const proof=engine.processToRgb([.2,.3,.4,.1],{profileId:'actual-cmyk'});
assert.ok(proof&&Math.abs(proof[0]-.73129)<.003);
assert.equal(engine.processToRgb([.2,.3,.4],{profileId:'actual-cmyk'}),null);
const source={space:'ICCBased',icc_profile_id:'actual-rgb',components:[.2,.5,.8]};
assert.equal(engine.sourceToProcess(source,{}),null);
// Compact source-only profile cannot be fabricated into an output profile.
assert.equal(engine.sourceToProcess(source,{profileId:'actual-cmyk',intent:1}),null);
const outputPath='/usr/share/color/icc/ghostscript/default_cmyk.icc';
if(existsSync(outputPath)){
 assert.ok(engine.registerProfile('full-output-cmyk',readFileSync(outputPath),4));
 const result=engine.sourceToProcess(source,{profileId:'full-output-cmyk',intent:1});assert.ok(result?.length===4&&result.every(v=>v>=0&&v<=1));
 const limited=await createPdfIccEngine({memoryLimitBytes:16*1024*1024});
 assert.equal(limited.open(rgb,3,1,readFileSync(outputPath),4),null);assert.ok(limited.statistics.memoryLimitFailures>0);assert.equal(limited.statistics.activeTransforms,0);limited.dispose();
}else{console.log('Full system CMYK output profile unavailable; full-profile test not run');}
assert.equal(engine.open(rgb,3,1,gray,4),null);
const grayOut=engine.open(rgb,3,1,gray,1),one=new Float64Array(1);assert.ok(grayOut);assert.ok(grayOut.convert(.2,.5,.8,0,one));assert.ok(Number.isFinite(one[0]));
assert.equal(pdfIccIntent('/AbsoluteColorimetric'),3);
const relative=engine.open(gray,1,1),absolute=engine.open(gray,1,3),rel=new Float64Array(3),abs=new Float64Array(3);
relative.convert(.5,0,0,0,rel);absolute.convert(.5,0,0,0,abs);assert.ok(Math.abs(rel[2]-abs[2])>.05);
const def=pdfDeviceRgbToCmyk([.2,.4,.6]);assert.ok(Math.abs(def[0]-.4)<1e-12);assert.equal(def[3],.4);
const explicit=pdfDeviceRgbToCmyk([.2,.4,.6],{blackGeneration:k=>k/2,undercolourRemoval:()=>-.2});assert.ok(Math.abs(explicit[2]-.6)<1e-12);assert.equal(explicit[3],.2);
const pageA=engine.createProfileScope([{id:'icc-0',components:3,data_base64:rgb.toString('base64')}]);
const pageB=engine.createProfileScope([{id:'icc-0',components:1,data_base64:gray.toString('base64')}]);
const fromA=pageA.processToRgb([.2,.5,.8],{profileId:'icc-0'}),fromB=pageB.processToRgb([.5],{profileId:'icc-0'});
assert.ok(fromA&&Math.abs(fromA[0]-.18627)<.003);assert.ok(fromB&&Math.abs(fromB[0]-.50387)<.003);
const displayA=pageA.sourceToGroup({space:'ICCBased',icc_profile_id:'icc-0',components:[.2,.5,.8]},{components:3});
for(let i=0;i<3;i++)assert.ok(Math.abs(displayA[i]-fromA[i])<1e-6);
const displayXYZ=pageA.sourceToGroup({space:'PCSXYZ',components:[.4821,.5,.41245]},{components:3});assert.ok(displayXYZ?.every(v=>v>.73&&v<.74));
const displayLab=pageA.sourceToGroup({space:'Lab',components:[50,0,0]},{components:3});assert.ok(displayLab?.every(v=>v>.46&&v<.47));
const inRgb=pageA.sourceToGroup({space:'DeviceRGB',components:[.2,.5,.8]},{profileId:'icc-0',components:3});
assert.ok(inRgb?.length===3);const roundtrip=pageA.groupToRgb(inRgb,{profileId:'icc-0',components:3});
for(let i=0;i<3;i++)assert.ok(Math.abs(roundtrip[i]-[.2,.5,.8][i])<.001);
assert.deepEqual(pageA.sourceToGroup({space:'ICCBased',icc_profile_id:'icc-0',components:[.2,.5,.8]},{profileId:'icc-0',components:3}),[.2,.5,.8]);
assert.equal(pageA.sourceToGroup({space:'DeviceCMYK',components:[0,0,0,1]},{profileId:'icc-0',components:4}),null);
assert.equal(pageA.groupToRgb(inRgb,{profileId:'icc-0',components:4}),null);
const inGray=pageB.sourceToGroup({space:'DeviceRGB',components:[.2,.5,.8]},{profileId:'icc-0',components:1});assert.ok(inGray?.length===1);
const alternate={space:'DeviceRGB',components:[.2,.5,.8]};
const missing={space:'ICCBased',icc_profile_id:'not-registered',components:[.2,.5,.8],alternate};
assert.deepEqual(pageA.sourceToGroup(missing,{profileId:'icc-0',components:3}),inRgb);
assert.deepEqual(pageA.sourceToGroup(missing,{components:3}),alternate.components);
assert.deepEqual(pageA.sourceToProcess(missing),pdfDeviceRgbToCmyk(alternate.components));
const badProfile=new Uint8Array(132),badView=new DataView(badProfile.buffer);badView.setUint32(0,132);badView.setUint32(16,0x52474220);badView.setUint32(36,0x61637370);
assert.ok(engine.registerProfile('unusable-source',badProfile,3));
const unusable={...missing,icc_profile_id:'unusable-source'};
const convertedAlternate=engine.sourceToGroup(alternate,{profileId:'actual-rgb',components:3});
assert.deepEqual(engine.sourceToGroup(unusable,{profileId:'actual-rgb',components:3}),convertedAlternate);
const xyzAlternate=engine.sourceToPcs(alternate);
assert.deepEqual(engine.sourceToPcs(unusable),xyzAlternate);
assert.equal(engine.sourceToGroup({...source,alternate},{profileId:'actual-cmyk',components:4}),null);
assert.equal(engine.sourceToGroup(missing,{profileId:'absent-target',components:3}),null);
// Reusable image/shading metadata was built at zero, then receives new samples.
const dynamic={...missing,component_ranges:[0,1,.1,.9,0,1],alternate:{space:'DeviceRGB',components:[0,0,0],process_cmyk:[0,0,0,1]}};
for(const values of [[.1,.2,.3],[.8,.6,.4],[1,.9,0]]){
 dynamic.components=values;
 assert.deepEqual(pageA.sourceToGroup(dynamic,{profileId:'icc-0',components:3}),pageA.sourceToGroup({space:'DeviceRGB',components:values},{profileId:'icc-0',components:3}));
}
const calibration={components:3,gamma:[.5,2,3],pcs_matrix:[.9642,0,0,0,1,0,0,0,.8249],pcs_offset:[0,0,0]};
const dynamicCal={...dynamic,alternate:{space:'CalRGB',components:[0,0,0],pcs_xyz:[0,0,0],calibration}};
for(const values of [[.1,.2,.3],[.8,.6,.4]]){
 dynamicCal.components=values;
 const pcs=[.9642*Math.sqrt(values[0]),values[1]**2,.8249*values[2]**3];
 const result=pageA.sourceToGroup(dynamicCal,{profileId:'icc-0',components:3});
 const expected=pageA.sourceToGroup({space:'PCSXYZ',components:pcs},{profileId:'icc-0',components:3});
 result.forEach((v,i)=>assert.ok(Math.abs(v-expected[i])<1e-12));
}
const catalogBytes=engine.statistics.registeredProfileBytes;
pageA.dispose();assert.equal(engine.statistics.registeredProfileBytes,catalogBytes-rgb.length);
assert.equal(pageA.sourceToProcess({space:'DeviceRGB',components:[1,0,0]}),null);
assert.deepEqual(pageB.sourceToProcess({space:'DeviceRGB',components:[1,0,0]}),[0,1,1,0]);
pageB.dispose();
engine.dispose();assert.equal(engine.statistics.activeTransforms,0);assert.equal(engine.statistics.registeredProfileBytes,0);assert.equal(held[1].convert(.2,.5,.8,0,out),false);
console.log('ICC lifecycle, safe reopen, output profiles and device BG/UCR: passed');

import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {PdfInkCompositor} from '../../web/pdf-ink-compositor.mjs';
const require=createRequire(process.env.PDF_CANVAS_PACKAGE || import.meta.url),{createCanvas}=require('@napi-rs/canvas');
const shape=new Float32Array([1]);
const cmyk=components=>({space:'DeviceCMYK',components,colorants:['Cyan','Magenta','Yellow','Black'],paints:true});
const engine=()=>new PdfInkCompositor(1,1,createCanvas,{convertProcess:([c,m,y,k])=>[1-Math.min(1,c+k),1-Math.min(1,m+k),1-Math.min(1,y+k)]});
const near=(a,b)=>a.forEach((v,i)=>assert.ok(Math.abs(v-b[i])<0.006,`${a} != ${b}`));
let c=engine();c.beginGroup({isolated:true});c.paintColour(cmyk([1,0,0,0]),shape,{alpha:.5});c.paintColour(cmyk([0,1,0,0]),shape,{alpha:.5,overprint:true,overprint_mode:1});near(c.endGroup().pixels,[.5,.5,0,0,.75]);
c=engine();c.beginGroup({isolated:true});c.paintColour(cmyk([1,0,0,0]),shape);c.beginGroup({isolated:false},c.frames.at(-1).pixels);c.paintColour(cmyk([0,1,0,0]),shape,{alpha:.5,overprint:true,overprint_mode:1});let child=c.endGroup();c.paint(child.pixels,child.shape);near(c.endGroup().pixels,[1,.5,0,0,1]);
c=engine();c.beginGroup({isolated:true,knockout:true});c.paintColour(cmyk([1,0,0,0]),shape,{alpha:.5});c.paintColour(cmyk([0,1,0,0]),shape,{alpha:.5,overprint:true,overprint_mode:1});near(c.endGroup().pixels,[0,.5,0,0,.5]);
c=engine();c.beginGroup({isolated:true});c.paintColour(cmyk([1,0,0,0]),shape);c.paintColour(cmyk([0,1,0,0]),shape,{alpha:.5,overprint:true,overprint_mode:1,blend_mode:'multiply'});near(c.endGroup().pixels,[1,.5,0,0,1]);
c=engine();c.beginGroup({isolated:true});c.paintColour(cmyk([.2,.4,.6,.1]),shape);c.paintColour(cmyk([.5,.3,.2,.4]),shape,{blend_mode:'multiply'});near(c.endGroup().pixels,[.6,.58,.68,.46,1]);
for(const mode of ['hue','saturation','color','luminosity']){
 c=engine();c.beginGroup({isolated:true});c.paintColour(cmyk([.2,.4,.6,.1]),shape);c.paintColour(cmyk([.5,.3,.2,.4]),shape,{blend_mode:mode});
 const result=c.endGroup().pixels;assert.ok(Math.abs(result[3]-(mode==='luminosity'?.4:.1))<1e-6,'nonseparable CMYK K selection');
}
c=engine();c.beginGroup({isolated:true});c.paintColour({space:'DeviceN',components:[1],colorants:['Spot'],paints:true,alternate:cmyk([0,.5,0,0])},shape);near(c.endGroup().pixels,[0,.5,0,0,1]);
console.log('10 premultiplied ink-group tests passed');

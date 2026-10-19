import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { PdfCompositor, rgba8ToPremultiplied, premultipliedToRgba8, softMaskSamples, PDF_BLEND_MODES } from '../../web/pdf-compositor.mjs';
const require = createRequire(process.env.PDF_CANVAS_PACKAGE || import.meta.url);
const { createCanvas } = require('@napi-rs/canvas');
const pixel = (r,g,b,a=1) => new Float32Array([r*a,g*a,b*a,a]);
const shape = x => new Float32Array([x]);
const near = (actual, expected, label, tolerance=0.005) => {
  assert.equal(actual.length, expected.length);
  actual.forEach((value,index) => assert.ok(Math.abs(value-expected[index]) <= tolerance, `${label}[${index}] ${value} != ${expected[index]}`));
};
let count = 0;
function test(name, fn) { fn(); count++; console.log(`ok ${name}`); }
test('packed coverage preserves every Float32 sample through nested and recycled groups',()=>{
 const render=packed=>{
  const width=19,height=17,c=new PdfCompositor(width,height,createCanvas);
  c.beginGroup({isolated:true});
  for(let scope=0;scope<8;scope++){
   const parent=c.frames.at(-1);
   c.beginGroup({isolated:scope%3===0,knockout:scope%2===0},parent.knockout?parent.initial:parent.pixels);
   for(let draw=0;draw<5;draw++){
    const dirty={x:draw%3,y:draw%4,width:15,height:12},bytes=new Uint8ClampedArray(dirty.width*dirty.height*4);
    for(let i=0;i<bytes.length;i++)bytes[i]=(i*37+draw*17+scope*73)%256;
    if(packed)c.paintRgba8(bytes,dirty);
    else{
     const source=new Float32Array(width*height*4),coverage=new Float32Array(width*height);
     for(let y=0;y<dirty.height;y++)for(let x=0;x<dirty.width;x++){
      const j=(y*dirty.width+x)*4,p=(y+dirty.y)*width+x+dirty.x,i=p*4,a=bytes[j+3]/255;
      for(let channel=0;channel<3;channel++)source[i+channel]=bytes[j+channel]/255*a;
      source[i+3]=a;coverage[p]=a;
     }
     c.paint(source,coverage,{dirty});
    }
   }
   const result=c.endGroup({recycle:true,regionOnly:true});c.paint(result.pixels,result.shape,{dirty:result.dirty});c.releaseGroup(result);
  }
  const result=c.endGroup();return {pixels:result.pixels,shape:result.shape,result:result.result};
 };
 assert.deepEqual(render(true),render(false));
});
test('nested owned backdrops retain exact snapshot semantics through frame reuse',()=>{
 const render=copy=>{
  const c=new PdfCompositor(1,1,createCanvas);c.beginGroup({isolated:true});c.paint(pixel(.8,.3,.6,.7),shape(.9));
  const backdrop=initial=>{const parent=c.frames.at(-1),data=initial?parent.initial:parent.pixels;return copy?new Float32Array(data):data;};
  for(const colour of [[1,.2,.4],[.1,.7,.9],[.6,.8,.3]]){
   const parent=c.frames.at(-1);c.beginGroup({knockout:true},backdrop(false));
   if(!copy)assert.equal(c.frames.at(-1).initial,parent.pixels,'An open parent owns a stable backdrop until child extraction');
   c.paint(pixel(...colour,.43),shape(.8));
   c.beginGroup({knockout:true},backdrop(true));c.paint(pixel(.2,.5,.9,.6),shape(.7));
   const inner=c.endGroup({recycle:true});c.paint(inner.pixels,inner.shape,{alpha:.55,dirty:inner.dirty});c.releaseGroup(inner);
   c.paint(pixel(.9,.4,.1,.3),shape(.6));
   const group=c.endGroup({recycle:true});c.paint(group.pixels,group.shape,{alpha:.75,dirty:group.dirty});c.releaseGroup(group);
  }
  const bytes=c.workingBytes(),result=c.endGroup();return {pixels:result.pixels,shape:result.shape,result:result.result,bytes};
 };
 assert.deepEqual(render(false),render(true),'Borrowed owned surfaces preserve every Float32 value and the conservative budget charge');
});
test('caller backdrops stay snapshots and recycled isolated frames clear owned storage',()=>{
 const c=new PdfCompositor(1,1,createCanvas),input=pixel(.2,.6,.9,.7),expected=new Float32Array(input);
 c.beginGroup({},input);input.fill(0);assert.deepEqual(c.frames.at(-1).initial,expected);assert.deepEqual(c.frames.at(-1).pixels,expected);
 const group=c.endGroup({recycle:true});c.releaseGroup(group);c.beginGroup({isolated:true});
 assert.deepEqual(c.frames.at(-1).initial,new Float32Array(4));assert.deepEqual(c.frames.at(-1).pixels,new Float32Array(4));c.endGroup();
});
test('bounded internal group leases preserve full results across disjoint reuse',()=>{
 const render=regionOnly=>{
  const c=new PdfCompositor(4,3,createCanvas),solid=new Float32Array(48),coverage=new Float32Array(12).fill(1);
  for(let p=0;p<12;p++)solid.set(pixel(.3,.6,.8,.7),p*4);
  c.beginGroup({isolated:true});c.paint(solid,coverage);
  for(const p of [0,11,5]){
   const source=new Float32Array(48),shape=new Float32Array(12),dirty={x:p%4,y:Math.floor(p/4),width:1,height:1};source.set(pixel(.8,.2,.4,.6),p*4);shape[p]=.8;
   c.beginGroup({knockout:true},c.frames.at(-1).pixels);c.paint(source,shape,{dirty});
   const group=c.endGroup({recycle:true,regionOnly});c.paint(group.pixels,group.shape,{alpha:.65,dirty:group.dirty});c.releaseGroup(group);
  }
  const result=c.endGroup();return {pixels:result.pixels,shape:result.shape,result:result.result};
 };
 assert.deepEqual(render(true),render(false),'Only the leased dirty region is consumed; stale backing pixels never escape');
});
test('RGBA public contract preserves transparent and half-alpha pixels', () => {
  const bytes = new Uint8ClampedArray([255,0,0,128,0,0,0,0]);
  assert.deepEqual(premultipliedToRgba8(rgba8ToPremultiplied(bytes)),bytes);
});
test('normal source over uses independent shape and opacity', () => {
  const c = new PdfCompositor(1,1,createCanvas); c.beginGroup();
  c.paint(pixel(1,0,0,0.5),shape(1)); c.paint(pixel(0,0,1,0.5),shape(1));
  const g = c.endGroup(); near(g.pixels,[0.25,0,0.5,0.75],'normal'); near(g.shape,[1],'shape');
});
test('nonisolated group retains backdrop during multiply then removes it once', () => {
  const c = new PdfCompositor(1,1,createCanvas); c.beginGroup({},pixel(0.8,0.5,0.2));
  c.paint(pixel(0.2,0.4,0.8,0.5),shape(1),{blend_mode:'multiply'});
  const g = c.endGroup(); near(g.pixels,[0.08,0.1,0.08,0.5],'backdrop removal');
});
test('isolated group has no exterior blend backdrop', () => {
  const c = new PdfCompositor(1,1,createCanvas); c.beginGroup({isolated:true},pixel(0.8,0.5,0.2));
  c.paint(pixel(0.2,0.4,0.8,0.5),shape(1),{blend_mode:'multiply'});
  near(c.endGroup().pixels,[0.1,0.2,0.4,0.5],'isolation');
});
test('knockout eliminates previous object by shape, even at half opacity', () => {
  const c = new PdfCompositor(1,1,createCanvas); c.beginGroup({isolated:true,knockout:true});
  c.paint(pixel(1,0,0,0.5),shape(1)); c.paint(pixel(0,0,1,0.5),shape(1));
  near(c.endGroup().pixels,[0,0,0.5,0.5],'knockout');
});
test('nonisolated knockout blends each sibling against initial backdrop', () => {
  const c = new PdfCompositor(1,1,createCanvas); c.beginGroup({knockout:true},pixel(0.8,0.5,0.2));
  c.paint(pixel(1,0,0,0.5),shape(1)); c.paint(pixel(0.2,0.4,0.8,0.5),shape(1),{blend_mode:'multiply'});
  near(c.endGroup().pixels,[0.08,0.1,0.08,0.5],'nonisolated knockout');
});
test('nested group opacity applies once to the whole group', () => {
  const c = new PdfCompositor(1,1,createCanvas); c.beginGroup();
  c.paint(pixel(1,1,1),shape(1)); const parent=c.frames.at(-1);
  c.beginGroup({isolated:true},parent.pixels); c.paint(pixel(1,0,0),shape(1)); c.paint(pixel(0,0,1),shape(1));
  const child=c.endGroup(); c.paint(child.pixels,child.shape,{alpha:0.5});
  near(c.endGroup().pixels,[0.5,0.5,1,1],'nested alpha');
});
test('soft mask alpha ignores color and evaluates TR after compositing', () => {
  const tr=Array.from({length:256},(_,i)=>255-i);
  near(softMaskSamples(pixel(0.8,0.2,0.1,0.25),{transfer_map:tr}),[191/255],'alpha TR');
});
test('luminosity soft mask uses complete RGB backdrop and alpha', () => {
  near(softMaskSamples(pixel(1,0,0,0.5),{luminosity:true,backdrop:[0,0,1]}),[0.205],'luminosity');
});
test('all PDF blend modes accepted and produce bounded deterministic pixels', () => {
  for(const mode of PDF_BLEND_MODES){
    const render=()=>{ const c=new PdfCompositor(1,1,createCanvas); c.beginGroup(); c.paint(pixel(0.2,0.6,0.8),shape(1)); c.paint(pixel(0.8,0.3,0.4,0.7),shape(1),{blend_mode:mode}); return Array.from(c.endGroup().pixels); };
    const a=render(); assert.deepEqual(a,render(),mode); assert.ok(a.every(x=>x>=0&&x<=1),mode);
  }
});
test('unknown blend mode fails explicitly rather than silently becoming normal', () => {
  const c=new PdfCompositor(1,1,createCanvas); c.beginGroup(); assert.throws(()=>c.paint(pixel(1,0,0),shape(1),{blend_mode:'unsupported'}),/support/);
});
test('surface and nested group allocation bounds checked before allocating', () => {
  assert.throws(()=>new PdfCompositor(100,100,createCanvas,{maxPixels:1}),/limit/);
  const c=new PdfCompositor(1,1,createCanvas,{maxDepth:1}); c.beginGroup(); assert.throws(()=>c.beginGroup(),/limit/);
});
console.log(`${count} compositor tests passed`);

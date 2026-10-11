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

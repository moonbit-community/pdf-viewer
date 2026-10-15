import assert from 'node:assert/strict';
import {PdfRasterStore} from '../../web/pdf-raster-store.mjs';
import {PdfRenderAssets} from '../../web/pdf-render-assets.mjs';
import {PdfWorkerClient} from '../../web/pdf-client.js';
let checks=0;
const test=async(name,run)=>{await run();checks++;console.log('ok '+name);};
const canvas=(width,height)=>{
 let pixels;
 return {width,height,getContext(){return {createImageData(w,h){return {data:new Uint8ClampedArray(w*h*4)};},putImageData(data){pixels=data.data.slice();}};},
  transferToImageBitmap(){return {width,height,pixels:pixels?.slice(),closed:0,close(){this.closed++;}};}};
};
const store=options=>{const s=new PdfRasterStore({createCanvas:canvas,...options});assert(s.initialize());s.enabled=true;return s;};
const png=()=>new Uint8Array([137,80,78,71,13,10,26,10]);
const capture=(s,rows=new Uint8Array([0,1,2,3]),width=1,colour=2)=>s.uri(s.capture(width,1,colour,rows,png));
await test('RGB/RGBA rows preserve channels and alpha through independent bitmaps',()=>{
 const s=store(),rgb=capture(s,new Uint8Array([0,1,127,255,254,3,128]),2),rgba=capture(s,new Uint8Array([0,1,2,3,0,128,64,255,127]),2,6);
 const a=s.bitmap(rgb),b=s.bitmap(rgb),c=s.bitmap(rgba);
 assert.deepEqual([...a.bitmap.pixels],[1,127,255,255,254,3,128,255]);assert.deepEqual([...c.bitmap.pixels],[1,2,3,0,128,64,255,127]);
 a.bitmap.close();assert.equal(b.bitmap.closed,0);assert.equal(s.diagnostics().rebuilds,1);
 assert.equal(s.prepare(JSON.stringify([rgb,rgba,rgb]),[rgb]).length,1);
 b.bitmap.close();c.bitmap.close();
});
await test('source admission stays bounded without invalidating earlier IDs',()=>{
 const s=store({maxBytes:516,maxEntries:1}),uri=capture(s);
 assert(uri);assert.equal(capture(s),'');assert.equal(s.entries.size,1);assert.equal(s.bytes,516);assert.equal(s.bitmap(uri).bitmap.width,1);
 assert.equal(s.selfContained(JSON.stringify([uri])),JSON.stringify(['data:image/png;base64,iVBORw0KGgo=']));
 assert.equal(s.embed(uri),s.embed(uri));assert(s.embeddedBytes<=s.diagnostics().embedded_budget_bytes);
 const ordinary=[1,2,3];assert.equal(s.selfContained(ordinary),ordinary);assert.deepEqual(s.prepare(ordinary),[]);
 assert.equal(s.embed('data:image/png;base64,ordinary'),'data:image/png;base64,ordinary');
 s.reset();assert.equal(s.bytes,0);assert.equal(s.entries.size,0);assert.equal(s.embeddedBytes,0);assert.throws(()=>s.bitmap(uri),{code:'raster-expired'});assert.throws(()=>s.embed(uri),{code:'raster-expired'});
});
await test('invalid geometry, unsupported colours and nonzero filters retain PNG fallback',()=>{
 const s=store();
 for(const args of [[0,1,2,new Uint8Array(1)],[1,0,2,new Uint8Array(1)],[1,1,0,new Uint8Array(4)],[1,1,2,new Uint8Array(3)],[1,1,2,new Uint8Array([1,2,3,4])],[16385,1,2,new Uint8Array(1)],[16384,16384,2,new Uint8Array(1)]])assert.equal(s.capture(...args,png),null);
 assert.equal(s.entries.size,0);s.enabled=false;assert.equal(capture(s),'');
 const unsupported=new PdfRasterStore({createCanvas(){throw Error('No OffscreenCanvas');}});assert.equal(unsupported.initialize(),false);assert.equal(capture(unsupported),'');
});
await test('partial bitmap failures close prepared transfers and release scratch surfaces',()=>{
 const created=[];let calls=0;
 const s=store({createCanvas(w,h){const c=canvas(w,h),transfer=c.transferToImageBitmap;c.transferToImageBitmap=()=>{if(++calls===3)throw Error('Transfer failed');const b=transfer();created.push(b);return b;};created.push(c);return c;}});
 const a=capture(s),b=capture(s);assert.throws(()=>s.prepare(JSON.stringify([a,b])),/Transfer failed/);
 assert(created.filter(x=>x.closed!==undefined).every(x=>x.closed===1));assert(created.filter(x=>x.getContext).every(x=>x.width===0&&x.height===0));
});
await test('supplied bitmaps follow LRU budgets and stay leased across disposal',async()=>{
 const closed=[],make=id=>({width:1,height:1,close(){closed.push(id);}}),s=new PdfRenderAssets({maxBytes:100,maxEntries:1});
 const a=make('a');s.supply('pdf-raster:a',a);assert.deepEqual(s.rasterKeys(),['pdf-raster:a']);
 const held=await s.acquire('pdf-raster:a');s.supply('pdf-raster:b',make('b'));assert.deepEqual(closed,['b']);
 s.supply('pdf-raster:a',make('duplicate'));assert.deepEqual(closed,['b','duplicate']);
 s.dispose();assert.equal(closed.includes('a'),false);s.release(held);assert.equal(closed.filter(x=>x==='a').length,1);assert.equal(s.bytes,0);
 const broken=new PdfRenderAssets({estimateBytes(){throw Error('Bad metadata');}});assert.throws(()=>broken.supply('bad',make('bad')),/Bad metadata/);assert(closed.includes('bad'));
});
class WorkerDouble{
 constructor(){this.listeners={};this.sent=[];}
 addEventListener(type,listener){this.listeners[type]=listener;}
 postMessage(data){this.sent.push(data);}
 terminate(){}
 emit(data){this.listeners.message({data});}
 ready(){this.emit({type:'ready',rasterImages:true});}
}
const original=globalThis.Worker;globalThis.Worker=WorkerDouble;
try{
 await test('cancelled, unmatched and stale replies close every transferred bitmap',async()=>{
  const supplied=[],s=new PdfWorkerClient({rasterImages:true,onRaster:(...args)=>supplied.push(args)});s.reset();const w=s.worker;w.ready();
  const controller=new AbortController(),pending=s.call('render_page',[1],{signal:controller.signal});controller.abort();await assert.rejects(pending,{name:'AbortError'});
  const a=canvas(1,1).transferToImageBitmap();w.emit({id:w.sent[0].id,result:'{}',rasterEpoch:1,rasterImages:[{uri:'a',bitmap:a}]});assert.equal(a.closed,1);assert.equal(supplied.length,0);
  const b=canvas(1,1).transferToImageBitmap();w.emit({id:-1,rasterImages:[{uri:'b',bitmap:b}]});assert.equal(b.closed,1);
  s.reset();const c=canvas(1,1).transferToImageBitmap();w.emit({id:1,rasterImages:[{uri:'c',bitmap:c}]});assert.equal(c.closed,1);s.close();
 });
 await test('live transfer ownership, bounded known IDs and on-demand rebuilding remain separate',async()=>{
  const assets=new PdfRenderAssets(),s=new PdfWorkerClient({rasterImages:true,onRaster:(uri,b)=>assets.supply(uri,b),onRasterReset:()=>assets.dispose(),rasterKeys:()=>Array(300).fill('known')});s.reset();const w=s.worker;w.ready();
  const p=s.call('render_page',[1]);assert.equal(w.sent[0].rasterKeys.length,256);const a=canvas(1,1).transferToImageBitmap();w.emit({id:w.sent[0].id,result:'{"ok":true}',rasterEpoch:1,rasterImages:[{uri:'pdf-raster:a',bitmap:a}]});assert.equal(await p,'{"ok":true}');assert.equal(a.closed,0);
  const load=s.loadRaster('pdf-raster:a'),b=canvas(1,1).transferToImageBitmap();w.emit({id:w.sent[1].id,result:null,rasterEpoch:1,rasterImages:[{uri:'pdf-raster:a',bitmap:b}]});assert.equal(await load,b);b.close();
  const fallback=s.loadRaster('pdf-raster:a');w.emit({id:w.sent[2].id,result:'data:image/png;base64,fallback',rasterEpoch:1});assert.equal(await fallback,'data:image/png;base64,fallback');
  s.close();assert.equal(a.closed,1);assert.equal(assets.bytes,0);
 });
 await test('callback and Worker errors settle the queue and dispose unclaimed transfers',async()=>{
  const s=new PdfWorkerClient({rasterImages:true,onRaster(uri,b){b.close();throw Error('Receiver failed');}});s.reset();const w=s.worker;w.ready();
  const p=s.call('render_page',[1]),a=canvas(1,1).transferToImageBitmap(),b=canvas(1,1).transferToImageBitmap();w.emit({id:w.sent[0].id,result:'{}',rasterImages:[{uri:'a',bitmap:a},{uri:'b',bitmap:b}]});await assert.rejects(p,/Receiver failed/);assert.equal(a.closed,1);assert.equal(b.closed,1);
  const next=s.call('cache_info'),c=canvas(1,1).transferToImageBitmap();w.emit({id:w.sent[1].id,error:{message:'Failed'},rasterImages:[{uri:'c',bitmap:c}]});await assert.rejects(next,/Failed/);assert.equal(c.closed,1);s.close();
 });
 await test('reader and legacy bridge functions retain the same Worker document',async()=>{
  const bridge=await import('../../web/pdf-client.js'),{viewerHost}=await import('../../web/viewer-host.mjs');
  assert.equal(viewerHost.pdf,bridge.pdf);bridge.pdf.reset();const w=bridge.pdf.worker;w.ready();
  const result=bridge.set_font_fallbacks('[]');assert.equal(w.sent[0].method,'set_font_fallbacks');
  w.emit({id:w.sent[0].id,result:'{"ok":true}',rasterEpoch:1});assert.equal(await result,'{"ok":true}');
  viewerHost.pdf.close();assert.equal(bridge.pdf.worker,null);
 });
}finally{globalThis.Worker=original;}
console.log(checks+' raster transport tests passed');

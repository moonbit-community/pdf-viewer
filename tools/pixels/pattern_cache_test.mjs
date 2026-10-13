import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {createPatternPainter,createPatternTileCache} from '../../web/pdf-patterns.mjs';
import {renderPdfPage} from '../../web/pdf-runtime.mjs';
const {createCanvas,Path2D,loadImage}=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url)('@napi-rs/canvas');
const allocated=[];
const trackedCanvas=(w,h)=>{const c=createCanvas(w,h);allocated.push(c);return c;};
const options={createCanvas:trackedCanvas,Path2D,loadImage,maxPatternCacheBytes:6400};
const painter=createPatternPainter(options),target=createCanvas(20,20),context=target.getContext('2d');
const path={svg_path:'M0 0H20V20H0Z',fill_even_odd:false};
const resource=()=>({name:'P',bbox:{min_x:0,min_y:0,max_x:20,max_y:20},x_step:20,y_step:20,matrix:[1,0,0,1,0,0],tile_plan:{version:1,page:{number:1,origin_x:0,origin_y:0,width:20,height:20,blend_space:'DeviceRGB'},viewport:{width:20,height:20,matrix:[1,0,0,-1,0,20]},items:[{kind:'path',paint:{...path,filled:true,stroked:false,fill_color:'#ff0000',fill_alpha:1,blend_mode:'normal',clips:[]}}]}});
const env={...options,page:{origin_x:0,origin_y:0,width:20,height:20},matrix:[1,0,0,1,0,0],width:20,height:20,blendSpace:'DeviceRGB',diagnostics:[]};
const r=resource();await painter(context,r,path,'fill',env);
const first=allocated.length;await painter(context,r,path,'fill',env);assert.equal(allocated.length,first,'unchanged opaque tile must reuse cache');
for(let i=0;i<10;i++)await painter(context,resource(),path,'fill',env);
const beforeDispose=allocated.filter(c=>c.width===20&&c.height===20).length;
painter.dispose();const afterDispose=allocated.filter(c=>c.width===20&&c.height===20).length;
assert.equal(beforeDispose-afterDispose,4,'6400 bytes retain at most two color+shape tile pairs');
const before=allocated.length;await painter(context,r,path,'fill',env);assert.ok(allocated.length>before,'evicted tile must safely recreate');
painter.dispose();
const pixel=context.getImageData(10,10,1,1).data;assert.deepEqual([...pixel],[255,0,0,255]);
console.log('Pattern cache reuse, bounded eviction, explicit disposal and redraw: passed');

const tiles=createPatternTileCache({maxBytes:20000,maxEntries:2});
const pooled={...options,returnPixels:false,patternTileCache:tiles};
async function draw(cell,matrix=[1,0,0,1,0,0],cache=tiles){
 const canvas=createCanvas(20,20),opts={...pooled,patternTileCache:cache},paint=createPatternPainter(opts);
 try{await paint(canvas.getContext('2d'),cell,path,'fill',{...env,matrix});}
 finally{paint.dispose();}
 return [...canvas.getContext('2d').getImageData(0,0,20,20).data];
}
const original=resource();
const red=await draw(original);
assert.deepEqual(await draw(JSON.parse(JSON.stringify(original))),red,'New JSON viewport objects reuse identical pixels');
assert.equal(tiles.loads,1);assert.equal(tiles.hits,1);assert.equal(tiles.diagnostics().leased_entries,0);
for(const matrix of [[0,1,-1,0,20,0],[-1,0,0,1,20,0],[1,.2,.1,1,0,0]]){
 const cell=JSON.parse(JSON.stringify(original));
 assert.deepEqual(await draw(cell,matrix),await draw(cell,matrix,null),'Cached affine lattice pixels match uncached replay exactly');
}
const green=JSON.parse(JSON.stringify(original));green.tile_plan.items[0].paint.fill_color='#00ff00';
const changed=await draw(green);assert.notDeepEqual(changed,red,'Identically named resources must retain changed cell contents');
assert.deepEqual(changed,await draw(green,[1,0,0,1,0,0],null));
assert.ok(tiles.entries.size<=2&&tiles.bytes<=tiles.limit);
const oldLoads=tiles.loads;tiles.dispose();assert.equal(tiles.bytes,0);assert.equal(tiles.entries.size,0);
assert.deepEqual(await draw(original),red);assert.equal(tiles.loads,oldLoads+1,'Document invalidation rebuilds the cell');
tiles.dispose();

const transparent=resource();transparent.tile_plan.items[0].paint.svg_path='M0 0H18V20H0Z';
const markers=createPatternTileCache({maxBytes:20000});
assert.deepEqual(await draw(transparent,[1,0,0,1,0,0],markers),await draw(transparent,[1,0,0,1,0,0],null));
assert.deepEqual(await draw(JSON.parse(JSON.stringify(transparent)),[1,0,0,1,0,0],markers),await draw(transparent,[1,0,0,1,0,0],null));
assert.equal(markers.loads,1);assert.ok(markers.bytes<4000,'Coverage replay markers do not retain unused colour/shape textures');markers.dispose();
const disabled=createPatternTileCache({maxBytes:0});
assert.deepEqual(await draw(original,[1,0,0,1,0,0],disabled),red);assert.equal(disabled.entries.size,0);assert.equal(disabled.bytes,0);
console.log('Document pattern tiles: cloned viewports, affine placement, content changes, byte/entry eviction, reset and transparent markers passed');

const imageCell=size=>{
 const source=createCanvas(size,size),ctx=source.getContext('2d');
 for(let y=0;y<size;y++)for(let x=0;x<size;x++){ctx.fillStyle=(x+y)%2?'#000':'#fff';ctx.fillRect(x,y,1,1);}
 const cell=resource();
 cell.tile_plan.items=[{kind:'image',paint:{
  quad:{p0:{x:0,y:0},p1:{x:0,y:20},p2:{x:20,y:20},p3:{x:20,y:0}},
  bounds:{min_x:0,min_y:0,max_x:20,max_y:20},fill_alpha:1,blend_mode:'normal',
  resource:{data_uri:source.toDataURL(),width:size,height:size},
 }}];
 return cell;
};
const policyTiles=createPatternTileCache({maxBytes:200000});
async function drawImageCell(cell,extra={},cache=policyTiles){
 const canvas=createCanvas(20,20),plan={...cell.tile_plan,items:[{
  kind:'path',paint:{...path,filled:true,stroked:false,fill_alpha:1,blend_mode:'normal',pattern:cell},
 }]};
 await renderPdfPage(canvas,plan,{...options,returnPixels:false,patternTileCache:cache,...extra});
 return [...canvas.getContext('2d').getImageData(0,0,20,20).data];
}
const checker=imageCell(10),lowDpr=await drawImageCell(checker,{devicePixelRatio:1});
const highDpr=await drawImageCell(checker,{devicePixelRatio:2});
assert.notDeepEqual(highDpr,lowDpr,'This checker exercises the DPR-dependent smoothing policy');
assert.deepEqual(highDpr,await drawImageCell(checker,{devicePixelRatio:2},null),'A changed DPR matches a fresh render');
assert.equal(policyTiles.hits,0,'Different sampling policies cannot share prepared tiles');
await drawImageCell(JSON.parse(JSON.stringify(checker)),{devicePixelRatio:2});assert.equal(policyTiles.hits,1);
const largeImage=imageCell(100);await drawImageCell(largeImage);
for(const cache of [policyTiles,null])await assert.rejects(drawImageCell(largeImage,{maxPixels:500},cache),/Decoded PDF image surface exceeds/);
assert.equal(policyTiles.diagnostics().leased_entries,0);policyTiles.dispose();
console.log('Prepared image tiles preserve changed DPR sampling and decoded-image pixel limits');

const small=createPatternTileCache({maxBytes:512,maxEntries:1});
let disposed=0;
const bitmap=()=>({bytes:160,color:createCanvas(2,2),shape:createCanvas(2,2),dispose(){disposed++;this.color.width=this.color.height=this.shape.width=this.shape.height=1;}});
const a=await small.acquire('a',{loadImage:async()=>bitmap(),sharePending:false});
const b=await small.acquire('b',{loadImage:async()=>bitmap(),sharePending:false});
small.release(a);assert.equal(a.color.width,1);assert.equal(b.color.width,2,'Eviction retains an active tile');
small.dispose();assert.equal(b.color.width,2,'Document close retains the active lease');small.release(b);assert.equal(disposed,2);
let rejectFirst;
const cancelled=small.acquire('same',{loadImage:()=>new Promise((_,reject)=>rejectFirst=reject),sharePending:false});
const fresh=small.acquire('same',{loadImage:async()=>bitmap(),sharePending:false});
rejectFirst(new DOMException('Cancelled render','AbortError'));await assert.rejects(cancelled,{name:'AbortError'});
const active=await fresh;assert.equal(active.color.width,2,'A cancelled builder cannot poison a concurrent render');small.release(active);
assert.equal(active.color.width,1);assert.equal(small.entries.size,0);assert.equal(small.bytes,0);
const retry=await small.acquire('same',{loadImage:async()=>bitmap(),sharePending:false});small.release(retry);small.dispose();
assert.equal(disposed,4);
console.log('Prepared tile leases: active eviction, document replacement, concurrent cancellation and retry passed');

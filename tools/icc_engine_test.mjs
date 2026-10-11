// Companion to colour_icc.mbtx; verifies the actual bundled CMM, not metadata.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {performance} from 'node:perf_hooks';
import {installPdfIccEngine} from '../web/pdf-icc.mjs';
const root=new URL('../',import.meta.url);
const engine=await installPdfIccEngine();
const cases=[
 ['assets/icc/rgb-gamma22.icc',3,[.2,.5,.8],[.18627,.50387,.80491]],
 ['assets/icc/gray-gamma22.icc',1,[.5],[.50387,.50387,.50387]],
 ['assets/icc/CGATS001Compat-v2-micro.icc',4,[.2,.3,.4,.1],[.73129,.63175,.54293]],
];
const report=[];
for(const [file,components,values,expected] of cases){
 const bytes=readFileSync(new URL(file,root)),start=performance.now(),handle=engine.open(bytes,components);
 assert.ok(handle,file);const open_ms=performance.now()-start,out=new Float64Array(3);
 const input=[...values,0,0,0,0].slice(0,4);handle.convert(...input,out);
 for(let c=0;c<3;c++)assert.ok(Math.abs(out[c]-expected[c])<.003,`${file} channel ${c}: ${out[c]}`);
 const item={file,components,bytes:bytes.length,output:Array.from(out),open_ms};
 if(process.argv.includes('--bench')){
  for(let i=0;i<1000;i++)handle.convert(...input,out);
  const rss=process.memoryUsage().rss,t0=performance.now();
  for(let i=0;i<1_000_000;i++)handle.convert((i%256)/255,input[1],input[2],input[3],out);
  Object.assign(item,{samples:1_000_000,elapsed_ms:performance.now()-t0,rss_delta_bytes:process.memoryUsage().rss-rss});
 }
 report.push(item);
}
assert.equal(engine.open(readFileSync(new URL('assets/icc/rgb-gamma22.icc',root)),4),null);
assert.equal(engine.open(new Uint8Array(132),3),null);
console.log(JSON.stringify({engine:engine.name,node:process.version,profiles:report},null,2));

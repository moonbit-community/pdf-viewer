// Diagnostic counterfactuals for the readable release bridge. Reuse a stage's
// exact results on fresh documents to measure how much work it contributes.
// These are warmed Node measurements, not browser latency or a product cache.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {installJbig2Decoder} from '../../codecs/jbig2/decoder.mjs';
import {installPdfIccEngine} from '../../web/pdf-icc.mjs';

const [pdfPath,reportPath,pageText='1',stage='images']=process.argv.slice(2);
assert(pdfPath&&reportPath,'Usage: node tools/pixels/profile_prepare_work.mjs <PDF> <report.json> [page] [stage]');
const page=Number(pageText);
assert(Number.isInteger(page)&&page>0,'Page must be a positive integer');
const stages={
  images:/pdf__image__resource__of__object_2einner$/,
  png:/pdf__png__of__scanline__bytes$/,
  icc:/pdf__image__icc__rgb__rows$/,
  fonts:/pdf__read__font__for__viewer_2einner$/,
  type3:/pdf__type3__(?:outline|scene)__of__glyph(?:_2einner)?$/,
  flate:/pdf__flate__decode__prefix__limited$/,
  imageflate:/pdf__image__inflate__limited_2einner$/,
};
assert(Object.hasOwn(stages,stage),'Unknown stage: '+stage);
const data=new Uint8Array(await readFile(resolve(pdfPath)));
const original=await readFile(resolve('web/_generated/pdf.js'),'utf8');
const names=[...original.matchAll(/^function ([$\w]+)\(/gm)].map(m=>m[1]).filter(name=>stages[stage].test(name));
assert(names.length,'Compiler stage names changed: update the counterfactual profiler');
let source=original+'\n';
for(const [index,name]of names.entries())source+=`
const __prepareOriginal${index}=${name};
${name}=function(...args){
 const s=globalThis.pdfPrepareCounterfactual;
 if(!s)return __prepareOriginal${index}(...args);
 const key=${JSON.stringify(name)},index=s.index[key]||0;s.index[key]=index+1;
 if(s.mode==='reuse'){
  if(index>=(s.recorded[key]?.length||0))throw Error('Counterfactual call order changed');
  return s.recorded[key][index];
 }
 const value=__prepareOriginal${index}(...args);
 if(s.mode==='record')(s.recorded[key]||=[]).push(value);
 return value;
};\n`;
const output=resolve(reportPath);
await mkdir(dirname(output),{recursive:true});
const generated=output+'.bridge.mjs';await writeFile(generated,source);
await installPdfIccEngine({wasmBinary:await readFile(new URL('../../web/vendor/lcms-wasm/lcms.wasm',import.meta.url))});
await installJbig2Decoder({wasmBytes:await readFile(new URL('../../vendor/jbig2/jbig2.wasm',import.meta.url))});
const bridge=await import(pathToFileURL(generated));
const state=globalThis.pdfPrepareCounterfactual={mode:'record',recorded:{},index:{}};
const sha256=value=>createHash('sha256').update(value).digest('hex');
function measure(mode){
  state.mode=mode;state.index={};
  assert(JSON.parse(bridge.open_pdf(data)).ok,'PDF must open');
  try{
    const start=performance.now(),payload=bridge.render_page(page,1,0,true),ms=performance.now()-start;
    assert(JSON.parse(payload).ok,'Page must render');
    return {mode,ms,payloadSha256:sha256(payload),calls:state.index};
  }finally{bridge.close_pdf();}
}
try{
  const recorded=measure('record'),samples=[];
  for(let pair=0;pair<7;pair++)for(const mode of pair%2?['reuse','ordinary']:['ordinary','reuse'])samples.push({pair,...measure(mode)});
  const median=mode=>samples.filter(s=>s.mode===mode).map(s=>s.ms).sort((a,b)=>a-b)[3];
  const identical=samples.every(s=>s.payloadSha256===recorded.payloadSha256);
  const report={host:'Node',scope:'Diagnostic only: stage results recorded once, then seven alternating pairs of fresh documents with ordinary work or exact result reuse. JIT and adapters are warmed. Timings overlap across stages and must not be added or compared with browser latency.',
    stage,page,sourceSha256:sha256(data),bridgeSha256:sha256(original),calls:recorded.calls,byteIdentical:identical,
    ordinaryMs:identical?median('ordinary'):null,reusedMs:identical?median('reuse'):null,samples};
  await writeFile(output,JSON.stringify(report,null,2));
  assert(identical,'Counterfactual changed output; these timings do not represent equivalent work. See report.');
  console.log(JSON.stringify({stage,page,ordinaryMs:report.ordinaryMs,reusedMs:report.reusedMs,byteIdentical:identical}));
  console.log('REPORT '+output);
}finally{delete globalThis.pdfPrepareCounterfactual;}

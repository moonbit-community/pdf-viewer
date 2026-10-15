// Profile the readable release bridge on Node, separately from browser timings.
// Inclusive stages overlap; self time subtracts instrumented child stages.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve,dirname} from 'node:path';
import {pathToFileURL} from 'node:url';
import {installJbig2Decoder} from '../../codecs/jbig2/decoder.mjs';
import {installPdfIccEngine} from '../../web/pdf-icc.mjs';
import {installPdfFlate} from '../../web/pdf-flate.mjs';

const [pdfPath,reportPath,pageList='1,2,12']=process.argv.slice(2);
assert(pdfPath&&reportPath,'Usage: node tools/pixels/profile_page_stages.mjs <PDF> <report.json> [pages]');
const pages=pageList.split(',').map(Number);
assert(pages.every(n=>Number.isInteger(n)&&n>0),'Pages must be positive integers');
const original=await readFile(resolve('web/_generated/pdf.js'),'utf8');
const patterns=[
 ['page model',/pdf__page__model_2einner$/],
 ['page cache accounting',/browser__cache__page(?:_2einner)?$/],
 ['page lookup',/browser__page$/],
 ['content collection',/pdf__collected__entries__of__ops_2einner$/],
 ['items and resources',/pdf__items__of__collected_2einner$/],
 ['image colour and PNG',/pdf__image__colour__png_2einner$/],
 ['image resources',/pdf__image__resource__of__object_2einner$/],
 ['encoded image decoding',/pdf__image__encoded__samples$/],
 ['PNG encoding',/pdf__png__of__scanline__bytes$/],
 ['Flate decoding',/pdf__flate__decode__prefix__limited$/],
 ['font loading',/pdf__read__font__for__viewer(?:_2einner)?$/],
 ['Type3 lowering',/pdf__type3__outline__of__glyph$/],
 ['glyph resource compilation',/pdf__canvas__compile__glyph(?:_2einner)?$/],
 ['glyph instances',/pdf__canvas__glyph__call$/],
 ['Canvas plan',/pdf__canvas__plan(?:_2einner)?$/],
 ['text layer',/PdfPageModel\d+text__layer_2einner$/],
 ['page model JSON',/PdfPageModelPB6ToJson\d+to__json$/],
 ['text layer JSON',/PdfTextLayerPB6ToJson\d+to__json$/],
 ['render payload',/browser__render__page(?:_2einner)?$/],
 ['editor manifest',/PdfViewerDocument\d+editor__page__json$/],
 ['annotation layer',/PdfViewerDocument\d+annotation__layer__json$/],
 ['accessibility manifest',/PdfViewerDocument\d+accessibility__page__json_2einner$/],
 ['accessibility content scan',/pdf__accessibility__scan$/],
 ['JSON stringify',/Json\d+stringify_2einner$/],
];
const names=[...original.matchAll(/^function ([$\w]+)\(/gm)].map(m=>m[1]);
// Prefer the throwing implementation when the compiler emits a result wrapper;
// internal callers can bypass that wrapper, and timing both double-counts work.
const matched=names.flatMap(name=>patterns.filter(([,pattern])=>pattern.test(name)).map(([stage])=>({name,stage})));
const selected=matched.filter(({name,stage})=>name.endsWith('_2einner')||
 !matched.some(candidate=>candidate.stage===stage&&candidate.name.endsWith('_2einner')));
assert(selected.some(x=>x.stage==='page model')&&selected.some(x=>x.stage==='Canvas plan'),'Compiler names changed: update profiler');
const unmatched=patterns.filter(([stage])=>!selected.some(x=>x.stage===stage)).map(([stage])=>stage);
assert.deepEqual(unmatched,[],'Compiler stage names changed: update the profiler before interpreting missing calls');
let source=original+'\n';
for(const [index,{name,stage}] of selected.entries())source+=`
const __profileOriginal${index}=${name};
${name}=function(...args){
 const p=globalThis.pdfStageProfile;if(!p?.active)return __profileOriginal${index}.apply(this,args);
 const frame={start:performance.now(),children:0};p.stack.push(frame);
 try{return __profileOriginal${index}.apply(this,args);}
 finally{const ms=performance.now()-frame.start;p.stack.pop();if(p.stack.length)p.stack.at(-1).children+=ms;
  const row=p.stages[${JSON.stringify(stage)}]||={calls:0,inclusiveMs:0,selfMs:0};row.calls++;row.inclusiveMs+=ms;row.selfMs+=ms-frame.children;}
};\n`;
const output=resolve(reportPath);await mkdir(dirname(output),{recursive:true});
const generated=output+'.bridge.mjs';await writeFile(generated,source);
await installPdfIccEngine({wasmBinary:await readFile(new URL('../../web/vendor/lcms-wasm/lcms.wasm',import.meta.url))});
await installJbig2Decoder({wasmBytes:await readFile(new URL('../../vendor/jbig2/jbig2.wasm',import.meta.url))});
installPdfFlate();
const bridge=await import(pathToFileURL(generated));
const data=await readFile(resolve(pdfPath)),sha256=value=>createHash('sha256').update(value).digest('hex');
const profile=globalThis.pdfStageProfile={active:false,stack:[],stages:{}};
const measure=fn=>{
 profile.stack=[];profile.stages={};profile.active=true;const start=performance.now();
 try{const value=fn();return {value,milliseconds:performance.now()-start};}
 finally{profile.active=false;}
};
const opened=measure(()=>bridge.open_pdf(new Uint8Array(data)));
assert(JSON.parse(opened.value).ok,'PDF must open');
const report={host:'Node',scope:'Readable release bridge, inclusive and exclusive instrumented stages; browser timings are measured separately',
 sourceSha256:sha256(data),bridgeSha256:sha256(original),unmatched,open:{ms:opened.milliseconds,stages:profile.stages},pages:[]};
for(const page of pages){
 const timings=[];
 for(let repeat=0;repeat<2;repeat++){
  const result=measure(()=>bridge.render_page(page,1,0,true,true));
  const ms=result.milliseconds,stages=profile.stages,parseStart=performance.now(),parsed=JSON.parse(result.value);
  assert(parsed.ok,'Page must render');
  const parseMs=performance.now()-parseStart;
  timings.push({ms,jsonParseMs:parseMs,jsonChars:result.value.length,canvasItems:parsed.canvas.items.length,
   canvasSha256:sha256(JSON.stringify(parsed.canvas)),accessibilitySha256:sha256(JSON.stringify(parsed.accessibility)),stages});
 }
 report.pages.push({page,cold:timings[0],cached:timings[1]});
 assert.equal(timings[0].canvasSha256,timings[1].canvasSha256,'Cached Canvas plan must retain its original data');
 assert.equal(timings[0].accessibilitySha256,timings[1].accessibilitySha256,'Cached semantics must retain their original data');
 console.log(JSON.stringify({page,coldMs:timings[0].ms,cachedMs:timings[1].ms,stages:timings[0].stages}));
}
bridge.close_pdf();delete globalThis.pdfStageProfile;
await writeFile(output,JSON.stringify(report,null,2));console.log('REPORT '+output);

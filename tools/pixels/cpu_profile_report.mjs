// Convert real CDP samples to phase-filtered folded stacks and a self-contained
// flame graph/heatmap. Raw profiles stay available for Chrome DevTools import.
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
const [directory,mapFilename]=process.argv.slice(2);assert(directory&&mapFilename,'Usage: node tools/pixels/cpu_profile_report.mjs <profile directory> <verified Worker source map>');
const root=resolve(directory),report=JSON.parse(await readFile(resolve(root,'sampled.json')));assert(report.complete);
assert.equal(report.fixtureSha256,'3662ff519e485810520552bf301d8c3b2b917fd2f83303f4965d7abed367e113');
assert(report.rows.every(row=>row.pages.length===14));
const require=createRequire(resolve('reference/pdf.js/package.json'));
const {TraceMap,originalPositionFor}=require('@jridgewell/trace-mapping');
const acorn=createRequire(resolve('tools/web-assets/package.json'))('acorn');
const mapping=mapFilename?new TraceMap(JSON.parse(await readFile(mapFilename))):null;
if(mapping){const manifest=JSON.parse(await readFile(mapFilename+'.verified.json'));assert.equal(manifest.workerSha256,report.artifacts.ours);assert.equal(manifest.mapSha256,createHash('sha256').update(await readFile(mapFilename)).digest('hex'));}
const sourceIndices=new Map();
if(mapping)for(let i=0;i<mapping.sources.length;i++){
 const source=mapping.sourcesContent[i];if(!source)continue;
 const lines=[0];for(const m of source.matchAll(/\r\n|[\n\r\u2028\u2029]/g))lines.push(m.index+m[0].length);
 const functions=[];
 const visit=(node,parent=null)=>{
  if(!node||typeof node.type!=='string')return;
  if(['FunctionDeclaration','FunctionExpression','ArrowFunctionExpression'].includes(node.type))functions.push({start:node.start,end:node.end,name:node.id?.name||(parent?.type==='VariableDeclarator'?parent.id.name:parent?.type==='Property'?parent.key.name:null)});
  for(const child of Object.values(node)){if(Array.isArray(child))for(const c of child)visit(c,node);else if(child&&typeof child==='object')visit(child,node);}
 };
 visit(acorn.parse(source,{ecmaVersion:'latest',sourceType:'module'}));
 functions.sort((a,b)=>a.start-b.start);sourceIndices.set(mapping.resolvedSources[i],{lines,functions});
}
function original(frame){
 if(!mapping||!frame.url.endsWith('/ours/pdf-worker.js')||frame.lineNumber<0)return null;
 const position=originalPositionFor(mapping,{line:frame.lineNumber+1,column:frame.columnNumber});
 if(position.name?.startsWith('_M0'))return position;
 const index=sourceIndices.get(position.source);if(!index||!position.line)return position;
 const offset=index.lines[position.line-1]+position.column;
 // The call-frame location is the start of the function, not its hot statement.
 // Find its own declaration/arrow binding instead of using a parameter name
 // from the nearest source-map segment.
 let low=0,high=index.functions.length;while(low<high){const mid=(low+high)>>1;if(index.functions[mid].start<=offset)low=mid+1;else high=mid;}
 for(let j=low-1;j>=Math.max(0,low-12);j--){const f=index.functions[j];if(offset<=f.end&&f.name)return {...position,name:f.name};}
 return position;
}
function friendly(name){
 return name.replace(/^_M0FP419moonbit_2dcommunity12pdf_2dviewer8internal6engine\d+/,'engine.').replace(/^_M0MP419moonbit_2dcommunity12pdf_2dviewer8internal6engine\d+(\w+?)\d+([a-z_])/,'engine.$1.$2').replace(/^_M0FP419moonbit_2dcommunity12pdf_2dviewer3cmd7browser\d+/,'browser.').replace(/^_M0FP211moonbitlang7pdflite\d+/,'pdflite.').replace(/_2einner$/,'.inner').replaceAll('__','_');
}
const frames=[],frameIds=new Map();
function intern(frame){
 const key=JSON.stringify([frame.functionName,frame.url.replace(/127\.0\.0\.1:\d+/,'localhost'),frame.lineNumber,frame.columnNumber]);
 if(frameIds.has(key))return frameIds.get(key);
 const o=original(frame),name=friendly(o?.name||frame.functionName||'(anonymous)');
 const id=frames.length;frames.push({id,name,generatedName:frame.functionName,url:frame.url.replace(/127\.0\.0\.1:\d+/,'localhost'),line:frame.lineNumber+1,column:frame.columnNumber,original:o});frameIds.set(key,id);return id;
}
function category(stack,phase){
 const names=stack.map(id=>frames[id].name),text=names.join(' ');
 if(text.includes('(garbage collector)'))return 'GC';
 if(phase==='flush')return 'Final RGBA readback';
 if(/pdf_model_cache|browser_cache_|model_cache_(size|walk)/.test(text))return 'Cache accounting';
 if(/pdf_shading_|paintShading|prepareAxial|paintAxial|sampler|Shading|Pattern/.test(text))return 'Shading / patterns';
 if(/pdf_image_|ImageData|PDFImage|drawImage|createBitmap/.test(text))return 'Images';
 if(/flate|zlib|Decompression|Inflater|inflate/i.test(text))return 'Flate decoding';
 if(/reading_order|reading_blocks|pdf_text_(line|lines|block)|accessibility|text_layer|buildTextContentItem|getTextContent/.test(text))return 'Text semantics / layout';
 if(/nativePdfGlyphPath|fillScope|outline_run/.test(text))return 'Positioned outline replay';
 if(/pdf-compositor|composite|premultiplied|sourcePixels|raster/.test(text)||stack.some(id=>frames[id].url.endsWith('pdf-compositor.mjs')))return 'Software raster / composition';
 if(stack.some(id=>frames[id].url.endsWith('pdf-canvas-native.mjs')))return 'Native Canvas replay';
 if(/showText|paintChar|fillText/.test(text))return 'Browser font text';
 if(/font|glyph|type1|truetype|cff_|CFF|Font|Glyph/.test(text))return 'Fonts / glyph preparation';
 if(/pdf_collected_|pdf_apply_op|EvaluatorPreprocessor|promiseBody/.test(text))return 'Content interpretation';
 if(/canvas_plan|browser_page_(?:copy|finish|stringify|layer|numbers)|decodePdfPageData/.test(text))return 'Canvas / transport';
 if(/pdf_items_of_collected|pdf_page_model|PdfTextItem|pdf_bounds_of_quad/.test(text))return 'Rich model construction';
 return 'Other';
}
const records=[];
for(const row of report.rows)for(const thread of ['main','worker']){
 const filename=`sampled-${row.sample}-${row.variant}-${thread}.cpuprofile`,profile=JSON.parse(await readFile(resolve(root,filename)));
 assert.equal(profile.samples.length,profile.timeDeltas.length);
 const nodes=new Map(profile.nodes.map(n=>[n.id,n])),parents=new Map();for(const n of profile.nodes)for(const child of n.children||[])parents.set(child,n.id);
 const paths=new Map();function path(id){if(paths.has(id))return paths.get(id);const n=nodes.get(id),parent=parents.get(id),result=[...(parent?path(parent):[]),intern(n.callFrame)];paths.set(id,result);return result;}
 const windows=[];
 for(const page of row.pages){
  let cursor=page.start;
  for(const phase of row.intervals.filter(i=>i.page===page.page)){
   if(phase.start>cursor)windows.push({page:page.page,phase:'setup',start:cursor,end:phase.start});
   windows.push(phase);cursor=phase.end;
  }
  if(cursor<page.end)windows.push({page:page.page,phase:'setup',start:cursor,end:page.end});
 }
 const intervals=windows.map(i=>({...i,start:row.clock.navigationStartUs+i.start*1000,end:row.clock.navigationStartUs+i.end*1000}));
 const groups=new Map();let timestamp=profile.startTime,index=0;
 for(let s=0;s<profile.samples.length;s++){
  const previous=timestamp;timestamp+=profile.timeDeltas[s];while(index<intervals.length&&intervals[index].end<=previous)index++;
  for(let j=index;j<intervals.length&&intervals[j].start<timestamp;j++){
   const interval=intervals[j],us=Math.max(0,Math.min(timestamp,interval.end)-Math.max(previous,interval.start));if(!us)continue;
   const key=`${interval.page}:${interval.phase}`;let group=groups.get(key);if(!group){group={sample:row.sample,variant:row.variant,thread,page:interval.page,phase:interval.phase,wallMs:(interval.end-interval.start)/1000,activeMs:0,idleMs:0,unattributedMs:0,boundaryHarnessMs:0,stacks:new Map(),categories:{}};groups.set(key,group);}
   const stack=path(profile.samples[s]),leaf=frames[stack.at(-1)].name,ms=us/1000;
   if(leaf==='(idle)'){group.idleMs+=ms;continue;}
   if(leaf==='(program)'||leaf==='(root)'){group.unattributedMs+=ms;continue;}
   if(stack.some(id=>frames[id].name==='digest'&&!frames[id].url)){group.boundaryHarnessMs+=ms;continue;}
   group.activeMs+=ms;const clean=stack.filter(id=>frames[id].name!=='(root)'),k=clean.join(',');group.stacks.set(k,(group.stacks.get(k)||0)+ms);
   const c=category(clean,interval.phase);group.categories[c]=(group.categories[c]||0)+ms;
  }
 }
 for(const g of groups.values()){g.stacks=[...g.stacks].map(([key,ms])=>({frames:key.split(',').map(Number),ms}));records.push(g);}
}
const summaries=[];
for(const variant of report.variants)for(const thread of ['main','worker']){
 const selected=records.filter(r=>r.variant===variant&&r.thread===thread),self=new Map(),inclusive=new Map(),categories={};
 for(const r of selected){for(const [k,v]of Object.entries(r.categories))categories[k]=(categories[k]||0)+v;for(const stack of r.stacks){const leaf=stack.frames.at(-1);self.set(leaf,(self.get(leaf)||0)+stack.ms);for(const id of new Set(stack.frames))inclusive.set(id,(inclusive.get(id)||0)+stack.ms);}}
 summaries.push({variant,thread,samples:report.samples,activeMs:selected.reduce((s,r)=>s+r.activeMs,0),idleMs:selected.reduce((s,r)=>s+r.idleMs,0),unattributedMs:selected.reduce((s,r)=>s+r.unattributedMs,0),boundaryHarnessMs:selected.reduce((s,r)=>s+r.boundaryHarnessMs,0),categories,self:[...self].sort((a,b)=>b[1]-a[1]).slice(0,60).map(([id,ms])=>({id,name:frames[id].name,ms})),inclusive:[...inclusive].sort((a,b)=>b[1]-a[1]).slice(0,60).map(([id,ms])=>({id,name:frames[id].name,ms}))});
}
let timing=null;try{timing=JSON.parse(await readFile(resolve(root,'timing.json')));assert(timing.complete);assert.equal(timing.fixtureSha256,report.fixtureSha256);assert.deepEqual(timing.artifacts,report.artifacts);}catch(e){if(e.code!=='ENOENT')throw e;}
const data={fixtureSha256:report.fixtureSha256,commit:report.commit,pdfjsRevision:report.pdfjsRevision,samples:report.samples,scope:report.scope,frames,records,summaries};
await writeFile(resolve(root,'analysis.json'),JSON.stringify(data,null,2)+'\n');
for(const variant of report.variants)for(const thread of ['main','worker']){
 const folded=new Map();for(const r of records.filter(r=>r.variant===variant&&r.thread===thread))for(const stack of r.stacks){const key=stack.frames.map(id=>frames[id].name.replaceAll(';',':')).join(';');folded.set(key,(folded.get(key)||0)+stack.ms);}
 await writeFile(resolve(root,`${variant}-${thread}.folded`),[...folded].map(([stack,ms])=>`${stack} ${Math.round(ms*1000)}`).join('\n')+'\n');
}
const escaped=JSON.stringify(data).replaceAll('<','\\u003c');
const html=`<!doctype html><html lang="en"><meta charset="utf-8"><title>tracemonkey: PDF.js vs pdf-viewer CPU profiles</title>
<style>body{font:14px system-ui;margin:28px;color:#17252d;background:#f6f8fa}h1{font-size:24px}h2{font-size:18px}p{max-width:1100px;line-height:1.55}.controls{display:flex;gap:18px;flex-wrap:wrap;margin:18px 0}select,input,button{font:inherit;padding:5px}canvas{background:white;border:1px solid #ccd6dd;display:block;width:100%}#tooltip{white-space:pre-wrap;padding:12px;background:white;min-height:42px;border:1px solid #ccd6dd}table{border-collapse:collapse;background:white;width:100%;font-variant-numeric:tabular-nums}td,th{padding:7px 10px;text-align:left;border-bottom:1px solid #ddd}td.num,th.num{text-align:right}.heat{font-variant-numeric:tabular-nums}a{color:#0066aa}.muted{color:#52636f}code{font-size:12px}</style>
<h1>tracemonkey.pdf · actual browser sampling</h1><p>Original 14-page document · CSS 1216 / DPR 2 · ${report.samples} fresh sweeps per variant · main thread and real dedicated Worker · Chromium ${report.browser}. Published Worker is unchanged. Functions are restored using a source map verified against its exact bytes.</p>
<p class="muted">Flame graph width is sampled active time, aggregated by call stack; it is not an execution timeline. Idle and unresolved program samples are excluded and reported separately. Only page preparation, paint and final RGBA readback windows are included. Hashing, opening and teardown are excluded. Synchronous browser API time is charged to its JS caller; this is not a C++/GPU profile. Phase times overlap between threads and must not be added as wall latency.</p>
<h2>CPU hotspot heatmap · ms per sweep</h2><p class="muted">Disjoint categories inferred from sampled call stacks; use the flame graph to inspect exact functions. Same absolute color scale for every cell. Values are means across ${report.samples} profiled sweeps and exclude harness boundary samples.</p><div style="overflow:auto"><table id="cpuheat"></table></div>
<div class="controls"><label>Variant <select id="variant">${report.variants.map(v=>`<option>${v}</option>`).join('')}</select></label><label>Thread <select id="thread"><option>main</option><option>worker</option></select></label><label>Page <select id="page"><option value="all">All 14</option>${Array.from({length:14},(_,i)=>`<option>${i+1}</option>`).join('')}</select></label><label>Phase <select id="phase"><option value="all">All phases</option><option>prepare</option><option>paint</option><option>flush</option><option>render+semantics</option><option>setup</option></select></label><label>Highlight <input id="search" placeholder="Function or source file"></label><button id="reset">Reset zoom</button></div>
<p id="stats"></p><canvas id="flame"></canvas><div id="tooltip">Hover a frame for its location and sampled time. Click to zoom.</div><h2>Self time · selected samples</h2><table id="hot"></table><h2>Per-page wall-time heatmap · ${timing?'uninstrumented timing runs':'profiled diagnostic runs'}</h2><p class="muted">Median per page, in milliseconds. The reference preparation column includes the extra OPLIST request; reference-streaming is the production-shaped flow and overlaps semantics with rendering. Colors compare absolute milliseconds across all cells.</p><table id="heat"></table><p class="muted">Fixture SHA-256 <code>${report.fixtureSha256}</code><br>pdf-viewer <code>${report.commit}</code> · PDF.js <code>${report.pdfjsRevision}</code></p>
<script>const D=${escaped},R=${JSON.stringify(timing?.rows||report.rows)},$=id=>document.getElementById(id),canvas=$('flame'),ctx=canvas.getContext('2d');let hits=[],zoom=null;
const fmt=x=>x.toFixed(1),median=a=>{a=[...a].sort((a,b)=>a-b);return a.length%2?a[a.length>>1]:(a[a.length/2-1]+a[a.length/2])/2},escape=s=>s.replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
function color(id){let h=0;for(const c of D.frames[id].name)h=(h*31+c.charCodeAt(0))>>>0;return 'hsl('+((h%65)+8)+' 76% '+(67+h%14)+'%)'}
function render(){const rows=D.records.filter(r=>r.variant===$('variant').value&&r.thread===$('thread').value&&($('page').value==='all'||r.page===+$('page').value)&&($('phase').value==='all'||r.phase===$('phase').value)),tree={id:-1,ms:0,children:new Map()},self=new Map();
for(const r of rows)for(const s of r.stacks){let path=s.frames;if(zoom){const i=path.indexOf(zoom);if(i<0)continue;path=path.slice(i)}let n=tree;n.ms+=s.ms;for(const id of path){if(!n.children.has(id))n.children.set(id,{id,ms:0,children:new Map()});n=n.children.get(id);n.ms+=s.ms}const id=path.at(-1);self.set(id,(self.get(id)||0)+s.ms)}
$('stats').textContent='Sampled active '+fmt(tree.ms/D.samples)+' ms per sweep · excluded idle '+fmt(rows.reduce((a,r)=>a+r.idleMs,0)/D.samples)+' ms · unresolved program '+fmt(rows.reduce((a,r)=>a+r.unattributedMs,0)/D.samples)+' ms · harness boundary '+fmt(rows.reduce((a,r)=>a+r.boundaryHarnessMs,0)/D.samples)+' ms. Samples across '+D.samples+' fresh sweeps.';
const depth=n=>n.children.size?1+Math.max(...[...n.children.values()].map(depth)):1;const height=Math.max(70,depth(tree)*23),width=canvas.clientWidth,dpr=devicePixelRatio;canvas.width=width*dpr;canvas.height=height*dpr;canvas.style.height=height+'px';ctx.setTransform(dpr,0,0,dpr,0,0);ctx.clearRect(0,0,width,height);hits=[];const search=$('search').value.toLowerCase();
function draw(n,x,y,w){if(n.id>=0&&w>.3){const f=D.frames[n.id];ctx.fillStyle=search&&(f.name+' '+f.url).toLowerCase().includes(search)?'#ff3070':color(n.id);ctx.fillRect(x,y,w-1,21);if(w>35){ctx.save();ctx.beginPath();ctx.rect(x+3,y,w-6,21);ctx.clip();ctx.fillStyle='#18232a';ctx.font='12px system-ui';ctx.fillText(f.name,x+4,y+15);ctx.restore()}hits.push({x,y,w,n})}let at=x;for(const c of [...n.children.values()].sort((a,b)=>b.ms-a.ms)){const cw=w*c.ms/n.ms;draw(c,at,y+23,cw);at+=cw}}
draw(tree,0,-23,width);$('hot').innerHTML='<tr><th>Function</th><th>Source</th><th class="num">Self ms/sweep</th></tr>'+[...self].sort((a,b)=>b[1]-a[1]).slice(0,20).map(([id,ms])=>{const f=D.frames[id];return '<tr><td>'+escape(f.name)+'</td><td>'+escape((f.original?.source||f.url).split('/').at(-1)||'browser/profiler')+':'+(f.original?.line||f.line)+'</td><td class="num">'+fmt(ms/D.samples)+'</td></tr>'}).join('')}
canvas.onmousemove=e=>{const rect=canvas.getBoundingClientRect(),x=e.clientX-rect.left,y=e.clientY-rect.top,h=hits.findLast(h=>x>=h.x&&x<h.x+h.w&&y>=h.y&&y<h.y+21);if(!h)return;const f=D.frames[h.n.id];$('tooltip').textContent=f.name+' · inclusive '+fmt(h.n.ms/D.samples)+' ms/sweep\\n'+f.url+':'+f.line+':'+f.column+(f.original?'\\nOriginal '+f.original.source+':'+f.original.line+':'+f.original.column:'')};canvas.onclick=e=>{const rect=canvas.getBoundingClientRect(),h=hits.findLast(h=>e.clientX-rect.left>=h.x&&e.clientX-rect.left<h.x+h.w&&e.clientY-rect.top>=h.y&&e.clientY-rect.top<h.y+21);if(h){zoom=h.n.id;render()}};$('reset').onclick=()=>{zoom=null;render()};for(const id of ['variant','thread','page','phase'])$(id).onchange=()=>{zoom=null;render()};$('search').oninput=render;window.onresize=render;
const categories=[...new Set(D.summaries.flatMap(s=>Object.keys(s.categories)))].sort(),cpuMax=Math.max(...D.summaries.flatMap(s=>categories.map(c=>(s.categories[c]||0)/D.samples)));$('cpuheat').innerHTML='<tr><th>Target</th>'+categories.map(c=>'<th class="num">'+escape(c)+'</th>').join('')+'<th class="num">Active total</th></tr>'+D.summaries.map(s=>'<tr><th>'+escape(s.variant)+'<br>'+s.thread+'</th>'+categories.map(c=>{const v=(s.categories[c]||0)/D.samples;return '<td class="num" style="background:hsl(12 85% '+(99-40*Math.sqrt(v/cpuMax))+'%)">'+fmt(v)+'</td>'}).join('')+'<td class="num">'+fmt(s.activeMs/D.samples)+'</td></tr>').join('');
const columns=[];for(const variant of [...new Set(R.map(r=>r.variant))])for(const phase of ['prepareMs','paintMs','totalMs'])if(!(variant==='reference-streaming'&&phase==='prepareMs'))columns.push({variant,phase});const cells=Array.from({length:14},(_,i)=>columns.map(c=>median(R.filter(r=>r.variant===c.variant).map(r=>r.pages[i][c.phase])))),max=Math.max(...cells.flat());$('heat').innerHTML='<tr><th>Page</th>'+columns.map(c=>'<th class="num">'+escape(c.variant)+'<br>'+c.phase+'</th>').join('')+'</tr>'+cells.map((a,i)=>'<tr><th>'+(i+1)+'</th>'+a.map(v=>'<td class="num heat" style="background:hsl(12 85% '+(99-40*Math.sqrt(v/max))+'%)">'+fmt(v)+'</td>').join('')+'</tr>').join('');render();</script></html>`;
await writeFile(resolve(root,'flamegraphs.html'),html);
console.log(JSON.stringify({output:resolve(root,'flamegraphs.html'),frames:frames.length,records:records.length,summaries:summaries.map(s=>({variant:s.variant,thread:s.thread,activeMsPerSweep:s.activeMs/report.samples,top:s.self.slice(0,8).map(r=>({name:r.name,ms:r.ms/report.samples}))}))}));

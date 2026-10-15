import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import * as bridge from '../../web/_generated/pdf.js';
import {PdfRangeSource,PdfRangeDocument} from '../../web/pdf-range.mjs';
import {rangeFixture,taggedRangeFixture,makePdf,stream} from './readonly_fixtures.mjs';
const parse=value=>{const result=JSON.parse(value);assert.equal(result.ok,true,result.error);return result;};
const bytes=rangeFixture();
function mockFetch(data,{range=true,etag='"fixture-v1"',truncate=false,badRange=false}={}){
  const requests=[];
  const fetch=async (url,options={})=>{
    const request=options.headers?.Range;requests.push(request||'full');
    if(!range||!request)return new Response(data,{headers:{etag,'content-length':String(data.length)}});
    const [,a,b]=/^bytes=(\d+)-(\d+)$/.exec(request),start=Number(a),end=Math.min(data.length,Number(b)+1);
    const body=data.subarray(start,end-(truncate?1:0));
    return new Response(new ReadableStream({start(controller){for(let offset=0;offset<body.length;offset+=4096)controller.enqueue(body.subarray(offset,offset+4096));controller.close();}}),
      {status:206,headers:{etag,'content-range':`bytes ${badRange?start+1:start}-${end-1}/${data.length}`}});
  };
  return {fetch,requests};
}
parse(bridge.open_pdf(bytes));
const full= parse(bridge.render_page(1,1,0));const expectedSelection=parse(bridge.select_page_text(1,-1,-1,-1,-1));
const mocked=mockFetch(bytes),source=new PdfRangeSource('https://example.test/large.pdf',mocked),reader=new PdfRangeDocument(source,bridge);
const opened=parse(await reader.open());assert.equal(opened.pages,2);assert.equal(source.full,null);
await reader.prepare('render_page',[1]);const partial=parse(bridge.render_page(1,1,0));
assert.deepEqual(partial,full,'Range must preserve the public page model and Canvas plan');
assert.deepEqual(parse(bridge.select_page_text(1,-1,-1,-1,-1)),expectedSelection,'Range retains verified PDF byte provenance');
const cachedFirstPage=parse(bridge.cache_info()).pages;
const first=source.diagnostics();assert.ok(first.received_bytes<bytes.length/10,JSON.stringify(first));assert.ok(!mocked.requests.includes('full'));
await reader.prepare('render_page',[2]);assert.equal(parse(bridge.cache_info()).pages,cachedFirstPage,'Hydrating another page preserves decoded page snapshots');assert.equal(parse(bridge.render_page(2,1,0)).page,2);assert.ok(source.stats.received_bytes>first.received_bytes+7*1024*1024);
assert.ok(source.cacheBytes<=source.diagnostics().cache_budget_bytes);
for(const options of [{range:false},{badRange:true},{truncate:true},{etag:''}]){
  const mock=mockFetch(bytes,options),source=new PdfRangeSource('https://example.test/fallback.pdf',mock);
  await source.initialize();assert.equal(source.full.length,bytes.length);assert.equal(source.stats.mode,'full');
}
const changed=mockFetch(bytes),changing=new PdfRangeSource('https://example.test/changed.pdf',changed);
await changing.initialize();changing.fetcher=mockFetch(bytes,{etag:'"fixture-v2"'}).fetch;
await assert.rejects(()=>changing.get(bytes.length-1024,bytes.length),error=>error.code==='source-changed');
assert.equal(changing.full,null,'Changed response cannot publish mixed source bytes');
const resized=new PdfRangeSource('https://example.test/resized.pdf',mockFetch(bytes));
await resized.initialize();resized.fetcher=mockFetch(Buffer.concat([bytes,Buffer.from('x')])).fetch;
await assert.rejects(()=>resized.get(bytes.length-1024,bytes.length),error=>error.code==='source-changed');
const resizedFull=new PdfRangeSource('https://example.test/resized-full.pdf',mockFetch(bytes));
await resizedFull.initialize();resizedFull.fetcher=mockFetch(Buffer.concat([bytes,Buffer.from('x')]),{range:false}).fetch;
await assert.rejects(()=>resizedFull.get(bytes.length-1024,bytes.length),error=>error.code==='source-changed');
assert.equal(resizedFull.full,null,'A resized full response must not publish bytes over the original range document');
const same=new PdfRangeSource('https://example.test/same.pdf',mockFetch(bytes));
await same.initialize();same.fetcher=mockFetch(bytes,{range:false}).fetch;
assert.deepEqual(await same.get(bytes.length-1024,bytes.length),new Uint8Array(bytes.subarray(bytes.length-1024)),'Same validated source may switch to a complete response');
const fullSearch=parse(bridge.open_pdf(bytes));assert.equal(fullSearch.pages,2);
const expectedSearch=parse(bridge.search_pdf('Range',false,false,false)).results;
const searchReader=new PdfRangeDocument(new PdfRangeSource('https://example.test/search.pdf',mockFetch(bytes)),bridge);
parse(await searchReader.open());assert.deepEqual(parse(await searchReader.search(['Range',false,false,false])).results,expectedSearch);
const aborted=new AbortController();aborted.abort();
const tagged=taggedRangeFixture();parse(bridge.open_pdf(tagged));
const fullAccessibility=parse(bridge.render_page(1,1,0)).accessibility;
assert.equal(fullAccessibility.tagged,true);
const taggedSource=new PdfRangeSource('https://example.test/tagged.pdf',mockFetch(tagged)),taggedReader=new PdfRangeDocument(taggedSource,bridge);
parse(await taggedReader.open());await taggedReader.prepare('render_page',[1]);
assert.deepEqual(parse(bridge.render_page(1,1,0)).accessibility,fullAccessibility,'The first segmented render must include its structure tree before document_info is requested');
assert.ok(taggedSource.stats.received_bytes<tagged.length/10,'Structure links must not hydrate other page contents');
await taggedReader.prepare('document_info',[]);parse(bridge.document_info());
assert.ok(taggedSource.stats.received_bytes<tagged.length/10,'Document metadata must not follow structure backlinks into off-screen streams');
assert.deepEqual(parse(bridge.render_page(1,1,0)).accessibility,fullAccessibility,'Metadata hydration preserves the tagged page snapshot');
const cancelled=new PdfRangeSource('https://example.test/cancelled.pdf',{signal:aborted.signal,fetch:async(url,options)=>{options.signal.throwIfAborted();}});
await assert.rejects(()=>cancelled.initialize(),error=>error.name==='AbortError');
// The prepared page owns its compact resource table across document hydration.
// Unrelated large streams keep metadata outside the initial segment fetches.
const glyphBytes=makePdf([
 '<< /Type /Catalog /Pages 2 0 R /Metadata 8 0 R >>','<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
 '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 80 80] /Contents 4 0 R /Resources << /Font << /F 5 0 R >> >> >>',
 stream('','BT /F 24 Tf 10 10 Td (AAA) Tj ET'),
 '<< /Type /Font /Subtype /Type3 /FontBBox [0 0 600 900] /FontMatrix [.001 0 0 .001 0 0] /FirstChar 65 /LastChar 65 /Widths [600] /Encoding << /Differences [65 /A] >> /CharProcs << /A 6 0 R >> /Resources << >> >>',
 stream('','600 0 0 0 600 900 d1 0 0 600 900 re f'),
 stream('',Buffer.alloc(1024*1024,32)),
 stream('/Type /Metadata /Subtype /XML','<x:xmpmeta xmlns:x="adobe:ns:meta/"/>'),
 stream('',Buffer.alloc(1024*1024,32)),
]);
parse(bridge.open_pdf(glyphBytes));const fullGlyphs=parse(bridge.render_page(1,1,0,true,true));
const glyphSource=new PdfRangeSource('https://example.test/glyphs.pdf',mockFetch(glyphBytes)),glyphReader=new PdfRangeDocument(glyphSource,bridge);
parse(await glyphReader.open());assert.equal(glyphSource.full,null);
await glyphReader.prepare('render_page',[1]);
assert.deepEqual(parse(bridge.render_page(1,1,0,true,true)),fullGlyphs);
assert.equal(fullGlyphs.canvas.version,2);assert.equal(fullGlyphs.canvas.glyph_resources.length,1);
const glyphPageCache=parse(bridge.cache_info()).pages;
const beforeMetadata=glyphSource.stats.received_bytes;
await glyphReader.prepare('document_info',[]);parse(bridge.document_info());
assert.ok(glyphSource.stats.received_bytes>beforeMetadata,'Metadata hydration must fetch new document segments');
assert.equal(parse(bridge.cache_info()).pages,glyphPageCache);
assert.deepEqual(parse(bridge.render_page(1,1.5,90,true,true)).canvas.glyph_resources,fullGlyphs.canvas.glyph_resources);
assert.ok(glyphSource.stats.received_bytes<glyphBytes.length/2);
// Exercise actual classic and compressed xrefs from the pinned PDF.js corpus.
for(const name of ['tracemonkey.pdf','Pages-tree-refs.pdf','xfa_issue14315.pdf']){
  const bytes=readFileSync(new URL(`../../reference/pdf.js/test/pdfs/${name}`,import.meta.url)),mock=mockFetch(bytes);
  const source=new PdfRangeSource('https://example.test/'+name,mock),reader=new PdfRangeDocument(source,bridge);
  const opened=parse(await reader.open());assert.ok(opened.pages>0);if(!source.full)await reader.prepare('render_page',[1]);parse(bridge.render_page(1,1,0));
}
console.log(JSON.stringify({passed:true,first_page_bytes:first.received_bytes,total_bytes:bytes.length,range_requests:mocked.requests.length,checks:['page equality','source provenance','lazy second page','streamed body','full fallback','truncated range','invalid Content-Range','validator change','tagged first render','lazy structure streams','compiled glyphs across metadata hydration','abort','real xrefs']}));

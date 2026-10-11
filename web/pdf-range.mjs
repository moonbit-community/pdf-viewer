// Fetch, ReadableStream and HTTP Range provide transport. pdflite's xref and
// object parsers own the format; this adapter requests their missing objects.
const blockSize=65536, cacheBudget=64*1024*1024, objectBudget=64*1024*1024;
function checked(value){const result=JSON.parse(value);if(!result.ok)throw Object.assign(Error(result.error),{code:result.code});return result;}
function responseValidator(response){const etag=response.headers.get('etag');return etag&&!etag.startsWith('W/')?etag:response.headers.get('last-modified');}
function changedSource(){return Object.assign(Error('PDF source changed during range loading'),{code:'source-changed'});}

async function readBody(response, limit) {
  if(Number(response.headers.get('content-length'))>limit){await response.body?.cancel();throw Error('PDF response exceeds the download budget');}
  const reader=response.body?.getReader();
  if(!reader)throw Error('PDF response has no readable body');
  const chunks=[];let size=0;
  try{for(;;){const {value,done}=await reader.read();if(done)break;size+=value.byteLength;if(size>limit)throw Error('PDF response exceeds the download budget');chunks.push(value);}}
  catch(error){await reader.cancel();throw error;}finally{reader.releaseLock();}
  const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}return bytes;
}

export class PdfRangeSource {
  constructor(url,{fetch:fetcher=globalThis.fetch,signal}={}){
    this.url=url;this.fetcher=fetcher.bind(globalThis);this.signal=signal;this.blocks=new Map();this.cacheBytes=0;this.length=0;this.validator=null;this.full=null;
    this.stats={mode:'range',requests:0,received_bytes:0,cache_evictions:0,first_page_bytes:null,fallback_reason:null};
  }
  async request(start,end){
    this.stats.requests++;
    const headers={Range:`bytes=${start}-${end-1}`};if(this.validator)headers['If-Range']=this.validator;
    const response=await this.fetcher(this.url,{headers,signal:this.signal});
    if(response.status===200){
      if(this.validator&&responseValidator(response)!==this.validator){await response.body?.cancel();throw changedSource();}
      const bytes=await readBody(response,512*1024*1024);if(this.length&&bytes.length!==this.length)throw changedSource();
      this.full=bytes;this.length=this.full.length;this.stats.received_bytes+=this.length;this.stats.mode='full';
      return this.full;
    }
    if(response.status!==206){await response.body?.cancel();throw Error(`PDF Range request failed (${response.status})`);}
    const range=/^bytes (\d+)-(\d+)\/(\d+)$/.exec(response.headers.get('content-range')||'');
    if(!range){await response.body?.cancel();throw Error('PDF server did not expose a valid Content-Range');}
    const first=Number(range[1]),last=Number(range[2]),length=Number(range[3]);
    if(this.length&&length!==this.length){await response.body?.cancel();throw changedSource();}
    if(!Number.isSafeInteger(length)||length<=0||length>2147483647||first!==start||last!==Math.min(end,length)-1){await response.body?.cancel();throw Error('PDF server returned an inconsistent byte range');}
    const validator=responseValidator(response);
    if(this.validator&&validator!==this.validator){await response.body?.cancel();throw Object.assign(Error('PDF source changed during range loading'),{code:'source-changed'});}
    this.validator ||= validator;this.length=length;
    const bytes=await readBody(response,last-first+1);this.stats.received_bytes+=bytes.length;
    if(bytes.length!==last-first+1)throw Error('PDF range body is truncated');
    return bytes;
  }
  store(index,bytes){
    if(this.blocks.has(index)){this.cacheBytes-=this.blocks.get(index).length;this.blocks.delete(index);}
    this.blocks.set(index,bytes);this.cacheBytes+=bytes.length;
    while(this.cacheBytes>cacheBudget){const oldest=this.blocks.keys().next().value;this.cacheBytes-=this.blocks.get(oldest).length;this.blocks.delete(oldest);this.stats.cache_evictions++;}
  }
  async initialize(){
    try{const initial=await this.request(0,blockSize);if(!this.full){this.store(0,initial);if(initial.length===this.length)this.full=initial;else if(!this.validator)await this.complete('Range server did not expose an ETag or Last-Modified validator');}}
    catch(error){if(this.signal?.aborted||error.code==='source-changed')throw error;await this.complete(error.message);}
  }
  async get(start,end){
    if(start<0||end<start||end>this.length||end-start>objectBudget)throw Error('PDF byte range exceeds the object budget');
    if(this.full)return this.full.subarray(start,end);
    const bytes=new Uint8Array(end-start);
    for(let index=Math.floor(start/blockSize);index<Math.ceil(end/blockSize);index++){
      let block=this.blocks.get(index);
      if(!block){block=await this.request(index*blockSize,Math.min(this.length,(index+1)*blockSize));if(this.full)return this.full.subarray(start,end);this.store(index,block);}
      else{this.blocks.delete(index);this.blocks.set(index,block);}
      const from=Math.max(start,index*blockSize),to=Math.min(end,(index+1)*blockSize);
      bytes.set(block.subarray(from-index*blockSize,to-index*blockSize),from-start);
    }
    return bytes;
  }
  async complete(reason){
    this.stats.fallback_reason=reason||null;
    if(!this.full){this.stats.requests++;const headers={};if(this.validator)headers[this.validator.startsWith('"')?'If-Match':'If-Unmodified-Since']=this.validator;
      const response=await this.fetcher(this.url,{signal:this.signal,headers});if(!response.ok)throw Object.assign(Error(`PDF download failed (${response.status})`),{code:response.status===412?'source-changed':'http-error'});
      const validator=responseValidator(response);if(this.validator&&validator!==this.validator){await response.body?.cancel();throw changedSource();}
      const bytes=await readBody(response,512*1024*1024);if(this.length&&bytes.length!==this.length)throw changedSource();
      this.full=bytes;this.length=this.full.length;this.stats.received_bytes+=this.length;}
    this.blocks.clear();this.cacheBytes=0;this.stats.mode='full';return this.full;
  }
  diagnostics(){return {...this.stats,total_bytes:this.length,cache_bytes:this.cacheBytes,cache_budget_bytes:cacheBudget};}
}

export class PdfRangeDocument {
  constructor(source,bridge){this.source=source;this.bridge=bridge;this.active=new Set();this.changed=false;this.structureReady=false;}
  async open(){
    const source=this.source;await source.initialize();
    if(source.full)return this.bridge.open_pdf(source.full);
    checked(this.bridge.range_open(await source.get(0,Math.min(source.length,4096)),await source.get(Math.max(0,source.length-blockSize),source.length),source.length));
    for(;;){const offset=checked(this.bridge.range_next_section()).offset;if(offset===null)break;
      await this.parseRange(offset,source.length,bytes=>checked(this.bridge.range_section(offset,bytes)));
    }
    await this.hydrate('pages',0);this.changed=false;return this.bridge.range_document();
  }
  async parseRange(start,end,parse){
    let length=Math.min(8192,end-start),last;
    while(length>0&&length<=objectBudget){const bytes=await this.source.get(start,start+length);
      try{return await parse(bytes);}catch(error){last=error;if(length===end-start||length===objectBudget)break;length=Math.min(end-start,objectBudget,length*2);}}
    throw last||Error('Empty PDF object range');
  }
  async load(number){
    const request=checked(this.bridge.range_object_request(number));number=request.number;
    if(request.loaded)return;
    if(this.active.has(number)||this.active.size>=64)throw Error('Cyclic PDF range dependencies');
    this.active.add(number);
    try{await this.parseRange(request.start,request.end,async bytes=>{
      for(;;){const deps=checked(this.bridge.range_object_dependencies(bytes)).objects;if(!deps.length)break;for(const dependency of deps)await this.load(dependency);}
      return checked(this.bridge.range_object(number,bytes));
    });this.changed=true;}finally{this.active.delete(number);}
  }
  async hydrate(mode,number){
    for(let pass=0;pass<512;pass++){
      const missing=checked(this.bridge.range_missing(mode,number)).objects;if(!missing.length)return;
      for(const object of missing)await this.load(object);
    }
    throw Error('PDF range graph exceeds the hydration budget');
  }
  async prepare(method,args){
    const pageMethods=['render_page','render_print_page','select_page_text','select_text','search_page'];
    if(pageMethods.includes(method)){
      if(!this.structureReady){await this.hydrate('structure',0);this.structureReady=true;}
      await this.hydrate('page',args[0]);
    }
    else if(['document_info','download_metadata','download_attachment','xfa_data'].includes(method))await this.hydrate('metadata',0);
    if(method!=='cache_info'&&this.changed){checked(this.bridge.range_document());this.changed=false;}
  }
  async search(args){const count=JSON.parse(this.bridge.page_layouts()).layouts.length,results=[];
    for(let page=1;page<=count;page++){await this.prepare('search_page',[page]);results.push(...checked(this.bridge.search_page(page,...args)).results);}
    return JSON.stringify({ok:true,results});}
}

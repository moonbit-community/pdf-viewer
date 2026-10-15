// Document-owned source rows back transferable display bitmaps. Admission is
// bounded: existing IDs remain reproducible until invalidation; excess images
// use the ordinary PNG path instead of retaining an unbounded source registry.
const SOURCE_LIMIT=64*1024*1024,ENTRY_LIMIT=256,PIXEL_LIMIT=16777216,EMBED_LIMIT=8*1024*1024;
const missing=()=>Object.assign(new Error('PDF raster belongs to an expired document'),{code:'raster-expired'});
export class PdfRasterStore{
 constructor({maxBytes=SOURCE_LIMIT,maxEntries=ENTRY_LIMIT,createCanvas=(w,h)=>new OffscreenCanvas(w,h)}={}){
  if(!Number.isSafeInteger(maxBytes)||maxBytes<0||maxBytes>SOURCE_LIMIT||!Number.isInteger(maxEntries)||maxEntries<0||maxEntries>ENTRY_LIMIT)throw new RangeError('Invalid PDF raster source budget');
  this.limit=maxBytes;this.maxEntries=maxEntries;this.createCanvas=createCanvas;
  this.prefix='pdf-raster:'+(globalThis.crypto?.randomUUID?.()||Math.random().toString(16).slice(2)) + ':';
  this.pattern=new RegExp(this.prefix+'[0-9]+:[0-9]+','g');
  this.epoch=0;this.next=0;this.enabled=false;this.supported=false;
  this.entries=new Map();this.markers=new WeakMap();this.bytes=0;
  this.embedded=new Map();this.embeddedBytes=0;
  this.captures=0;this.rejections=0;this.transfers=0;this.rebuilds=0;
 }
 initialize(){
  let canvas,bitmap;
  try{canvas=this.createCanvas(1,1);if(!canvas.getContext('2d')||typeof canvas.transferToImageBitmap!=='function')return false;bitmap=canvas.transferToImageBitmap();this.supported=true;}
  catch{this.supported=false;}
  finally{bitmap?.close?.();if(canvas)canvas.width=canvas.height=0;}
  return this.supported;
 }
 reset(){
  this.enabled=false;this.entries.clear();this.markers=new WeakMap();this.bytes=0;this.next=0;this.epoch++;
  this.embedded.clear();this.embeddedBytes=0;
  this.captures=this.rejections=this.transfers=this.rebuilds=0;
 }
 capture(width,height,colour,rows,encode){
  if(!this.enabled||!this.supported)return null;
  const channels=colour===2?3:colour===6?4:0,pixels=width*height,stride=width*channels+1;
  if(!channels||!Number.isInteger(width)||!Number.isInteger(height)||width<=0||height<=0||width>16384||height>16384||!Number.isSafeInteger(pixels)||pixels>PIXEL_LIMIT||!(rows instanceof Uint8Array)||rows.length!==stride*height||typeof encode!=='function')return null;
  const bytes=rows.buffer.byteLength+512;
  if(bytes>this.limit-this.bytes||this.entries.size>=this.maxEntries){this.rejections++;return null;}
  for(let y=0;y<height;y++)if(rows[y*stride]!==0)return null;
  const uri=this.prefix+this.epoch+':'+(++this.next),marker=new Uint8Array(1);
  this.entries.set(uri,{uri,width,height,channels,rows,encode,sent:0});
  this.markers.set(marker,uri);this.bytes+=bytes;this.captures++;return marker;
 }
 uri(marker){return this.markers.get(marker)||'';}
 embed(uri){
  const entry=this.entries.get(uri);if(!entry){if(typeof uri==='string'&&uri.startsWith(this.prefix))throw missing();return uri;}
  if(this.embedded.has(uri)){const cached=this.embedded.get(uri);this.embedded.delete(uri);this.embedded.set(uri,cached);return cached;}
  const png=entry.encode();if(!(png instanceof Uint8Array)||png.length<8)throw new Error('Unable to encode a PDF raster fallback');
  let binary='';for(let i=0;i<png.length;i+=8192)binary+=String.fromCharCode(...png.subarray(i,i+8192));
  const value='data:image/png;base64,'+btoa(binary),bytes=value.length*2+128;
  if(bytes<=EMBED_LIMIT){
   while(this.embedded.size&&(this.embeddedBytes+bytes>EMBED_LIMIT||this.embedded.size>=ENTRY_LIMIT)){
    const key=this.embedded.keys().next().value;this.embeddedBytes-=this.embedded.get(key).length*2+128;this.embedded.delete(key);
   }
   this.embedded.set(uri,value);this.embeddedBytes+=bytes;
  }
  return value;
 }
 selfContained(result){return typeof result==='string'?result.replace(this.pattern,uri=>this.embed(uri)):result;}
 referenced(result){return typeof result==='string'?[...new Set(result.match(this.pattern)||[])]:[];}
 bitmap(uri){
  const entry=this.entries.get(uri);if(!entry)throw missing();
  const {width,height,channels,rows}=entry,stride=width*channels+1;let canvas,bitmap;
  try{
   canvas=this.createCanvas(width,height);const context=canvas.getContext('2d',{alpha:channels===4});
   if(!context)throw new Error('PDF raster Canvas context unavailable');
   const data=context.createImageData(width,height),rgba=data.data;
   if(channels===4){for(let y=0;y<height;y++)rgba.set(rows.subarray(y*stride+1,(y+1)*stride),y*width*4);}
   else{
    const words=new Uint32Array(rgba.buffer,rgba.byteOffset,rgba.byteLength/4),little=new Uint8Array(new Uint32Array([1]).buffer)[0]===1;
    for(let y=0;y<height;y++){let p=y*stride+1,q=y*width;for(let x=0;x<width;x++,p+=3,q++)words[q]=little?(rows[p]|rows[p+1]<<8|rows[p+2]<<16|0xff000000):(rows[p]<<24|rows[p+1]<<16|rows[p+2]<<8|255);}
   }
   context.putImageData(data,0,0);bitmap=canvas.transferToImageBitmap();
   this.transfers++;if(entry.sent++)this.rebuilds++;
   return {uri,bitmap};
  }catch(error){bitmap?.close?.();throw error;}
  finally{if(canvas)canvas.width=canvas.height=0;}
 }
 prepare(result,known=[]){
  const cached=new Set(Array.isArray(known)?known.slice(0,ENTRY_LIMIT):[]),images=[];
  try{
   for(const uri of this.referenced(result))if(!cached.has(uri))images.push(this.bitmap(uri));
   return images;
  }catch(error){for(const image of images)image.bitmap.close?.();throw error;}
 }
 diagnostics(){return {supported:this.supported,entries:this.entries.size,bytes:this.bytes,budget_bytes:this.limit,max_entries:this.maxEntries,embedded_entries:this.embedded.size,embedded_bytes:this.embeddedBytes,embedded_budget_bytes:EMBED_LIMIT,captures:this.captures,rejections:this.rejections,transfers:this.transfers,rebuilds:this.rebuilds};}
}

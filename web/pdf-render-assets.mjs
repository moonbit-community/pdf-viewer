// Document-owned decoded rasters survive zoom and shared page resources. A
// render leases each bitmap; eviction waits for all active consumers.
import {loadPdfRaster} from './pdf-canvas.mjs';

export class PdfRenderAssets{
 constructor({maxBytes=67108864,maxEntries=256,loadImage=loadPdfRaster,
  estimateBytes=(value,uri)=>Number(value.width)*Number(value.height)*4+uri.length*2,
  disposeValue=value=>value.close?.()}={}){
  this.limit=maxBytes;this.maxEntries=maxEntries;this.loadImage=loadImage;
  this.estimateBytes=estimateBytes;this.disposeValue=disposeValue;
  this.entries=new Map();this.values=new WeakMap();this.bytes=0;this.epoch=0;this.loads=0;this.hits=0;
 }
 async acquire(uri,{loadImage=this.loadImage,sharePending=true}={}){
  let entry=this.entries.get(uri);
  // A prepared tile belongs to its render's cancellation/profile scope.
  // Concurrent renders can reuse completed values, but build pending ones
  // separately so cancelling the first render cannot cancel the second.
  const transient=!!entry&&!sharePending&&!entry.value;
  if(transient)entry=null;
  if(entry){this.hits++;this.entries.delete(uri);this.entries.set(uri,entry);}
  else{
   this.loads++;entry={uri:transient?{}:uri,epoch:this.epoch,leases:0,bytes:0,accounted:false,value:null,retired:transient,pending:null};
   if(!transient)this.entries.set(uri,entry);
   let loaded;
   try{loaded=loadImage(uri);}catch(error){this.retire(entry);throw error;}
   entry.pending=Promise.resolve(loaded).then(value=>{
    entry.value=value;
    this.values.set(value,entry);
    entry.bytes=this.estimateBytes(value,uri);
    if(entry.retired||entry.epoch!==this.epoch||entry.bytes>this.limit||!Number.isSafeInteger(entry.bytes)){
     this.retire(entry);
    }else{this.bytes+=entry.bytes;entry.accounted=true;}
    this.trim();return value;
   }).catch(error=>{this.retire(entry);throw error;});
  }
  entry.leases++;
  try{return await entry.pending;}
  catch(error){entry.leases--;if(entry.retired&&entry.leases===0&&entry.value){this.disposeValue(entry.value);this.values.delete(entry.value);}throw error;}
 }
 release(value){
  const entry=this.values.get(value);if(!entry)return;
  if(entry.leases>0)entry.leases--;
  if(entry.retired&&entry.leases===0){this.disposeValue(value);this.values.delete(value);}
  else this.trim();
 }
 retire(entry){
  if(entry.retired)return;
  if(this.entries.get(entry.uri)===entry){this.entries.delete(entry.uri);if(entry.accounted)this.bytes=Math.max(0,this.bytes-entry.bytes);}
  entry.retired=true;
  if(entry.value&&entry.leases===0){this.disposeValue(entry.value);this.values.delete(entry.value);}
 }
 trim(){
  while(this.bytes>this.limit||this.entries.size>this.maxEntries){
   const candidate=[...this.entries.values()].find(entry=>entry.value&&entry.leases===0);
   if(!candidate)break;this.retire(candidate);
  }
 }
 dispose(){
  const entries=[...this.entries.values()];
  for(const entry of entries)this.retire(entry);
  this.entries.clear();this.bytes=0;this.epoch++;
 }
 diagnostics(){return {entries:this.entries.size,bytes:this.bytes,limit:this.limit,max_entries:this.maxEntries,loads:this.loads,hits:this.hits,
  leased_entries:[...this.entries.values()].filter(entry=>entry.leases>0).length};}
}

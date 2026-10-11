// Mature LittleCMS adapter. Sources and outputs retain their actual profiles;
// no display-RGB inverse or independent spot-ink approximation is used.
import { instantiate, TYPE_GRAY_DBL, TYPE_RGB_DBL, TYPE_CMYK_DBL, TYPE_Lab_DBL, TYPE_XYZ_DBL } from './vendor/lcms-wasm/lcms.mjs';
const MAX_PROFILE = 16 * 1024 * 1024;
const MAX_HEAP = 64 * 1024 * 1024;
const MAX_ACTIVE = 8;
const signatures = {1:'GRAY',3:'RGB',4:'CMYK'};
const formats = {1:TYPE_GRAY_DBL,3:TYPE_RGB_DBL,4:TYPE_CMYK_DBL};
export function pdfIccIntent(intent = 1) {
  if (Number.isInteger(intent) && intent >= 0 && intent <= 3) return intent;
  return ({Perceptual:0,RelativeColorimetric:1,Saturation:2,AbsoluteColorimetric:3})[String(intent).replace(/^\//,'')] ?? 1;
}
// ISO 32000-1 10.3.4. Identity is the explicitly declared reader-default
// BG/UCR policy; callers can supply the document's actual compiled functions.
export function pdfDeviceRgbToCmyk(values,{blackGeneration=k=>k,undercolourRemoval=k=>k}={}) {
  if(!values||values.length<3||!values.slice(0,3).every(Number.isFinite))return null;
  const clamp=x=>Math.max(0,Math.min(1,x)),c=1-clamp(values[0]),m=1-clamp(values[1]),y=1-clamp(values[2]),k=Math.min(c,m,y);
  let bg,ucr;try{bg=blackGeneration(k);ucr=undercolourRemoval(k);}catch{return null;}
  if(!Number.isFinite(bg)||!Number.isFinite(ucr))return null;
  return [clamp(c-ucr),clamp(m-ucr),clamp(y-ucr),clamp(bg)];
}
function validCalibration(c) {
  return c && [1,3].includes(c.components) && c.gamma?.length===c.components && c.gamma.every(v=>Number.isFinite(v)&&v>0) && c.pcs_matrix?.length===3*c.components && c.pcs_matrix.every(Number.isFinite) && c.pcs_offset?.length===3 && c.pcs_offset.every(Number.isFinite);
}
export function pdfCalibrationToPcs(values,c) {
  if(!validCalibration(c)||values?.length!==c.components||!Array.from(values).every(Number.isFinite))return null;
  const xyz=c.pcs_offset.slice();
  for(let column=0;column<c.components;column++){const linear=Math.pow(Math.max(0,Math.min(1,values[column])),c.gamma[column]);for(let row=0;row<3;row++)xyz[row]+=c.pcs_matrix[column*3+row]*linear;}
  return xyz.every(Number.isFinite)?xyz:null;
}
export function pdfCalibrationFromPcs(xyz,c) {
  if(!validCalibration(c)||xyz?.length!==3||!Array.from(xyz).every(Number.isFinite))return null;
  const m=c.pcs_matrix,v=xyz.map((x,i)=>x-c.pcs_offset[i]);let linear;
  if(c.components===1){if(Math.abs(m[1])<1e-12)return null;linear=[v[1]/m[1]];}
  else {
    const a=m[0],b=m[3],d=m[6],e=m[1],f=m[4],g=m[7],h=m[2],i=m[5],j=m[8];
    const det=a*(f*j-g*i)-b*(e*j-g*h)+d*(e*i-f*h),scale=Math.max(1,...m.map(Math.abs));
    if(Math.abs(det)<=1e-12*scale**3)return null;
    linear=[((f*j-g*i)*v[0]+(d*i-b*j)*v[1]+(b*g-d*f)*v[2])/det,((g*h-e*j)*v[0]+(a*j-d*h)*v[1]+(d*e-a*g)*v[2])/det,((e*i-f*h)*v[0]+(b*h-a*i)*v[1]+(a*f-b*e)*v[2])/det];
  }
  return linear.map((x,i)=>Math.pow(Math.max(0,Math.min(1,x)),1/c.gamma[i]));
}

function validProfile(bytes, n) {
  if (!(bytes instanceof Uint8Array) || !signatures[n] || bytes.length < 132 || bytes.length > MAX_PROFILE) return false;
  const v=new DataView(bytes.buffer,bytes.byteOffset,bytes.byteLength),u=i=>v.getUint32(i);
  if(u(36)!==0x61637370 || u(16)!==({1:0x47524159,3:0x52474220,4:0x434d594b})[n])return false;
  const size=u(0),count=u(128);if(size<132||size>bytes.length||count>(size-132)/12)return false;
  for(let i=0;i<count;i++){const offset=u(136+12*i),length=u(140+12*i);if(offset>size||length>size-offset)return false;}
  return true;
}

// ICC Alternate receives the current sample, unlike a Separation tint whose
// alternate components were evaluated by its PDF function. Samplers replace
// source.components after constructing their reusable metadata record.
export function currentIccAlternate(source) {
  const alternate=source?.alternate,values=source?.components;
  if(!alternate||!values||!Array.from(values).every(Number.isFinite))return null;
  const ranges=source.component_ranges;
  const components=Array.from(values,(v,i)=>ranges?.length===2*values.length?Math.max(ranges[i*2],Math.min(ranges[i*2+1],v)):v);
  const unchanged=alternate.components?.length===components.length&&components.every((v,i)=>v===alternate.components[i]);
  return {...alternate,components,process_cmyk:unchanged?alternate.process_cmyk:null,pcs_xyz:unchanged?alternate.pcs_xyz:null};
}

export async function createPdfIccEngine(options = {}) {
  const {maxActiveTransforms=MAX_ACTIVE,memoryLimitBytes=MAX_HEAP,...moduleOptions}=options;
  if(!Number.isInteger(maxActiveTransforms)||maxActiveTransforms<1||maxActiveTransforms>MAX_ACTIVE)throw new RangeError('ICC active transform limit must be 1..8');
  if(!Number.isInteger(memoryLimitBytes)||memoryLimitBytes<16*1024*1024||memoryLimitBytes>MAX_HEAP)throw new RangeError('ICC Wasm heap limit must be 16..64 MiB');
  const statistics={profiles:0,transforms:0,samples:0,failures:0,activeTransforms:0,evictions:0,reopens:0,memoryLimitFailures:0,registeredProfileBytes:0};
  let binary=moduleOptions.wasmBinary;
  if(!binary){
    const location=moduleOptions.locateFile?.('lcms.wasm',new URL('./vendor/lcms-wasm/',import.meta.url).href) || new URL('./vendor/lcms-wasm/lcms.wasm',import.meta.url);
    if(typeof process==='object'&&process.versions?.node && (String(location).startsWith('file:') || !/^[a-z]+:/i.test(String(location)))){
      const {readFile}=await import('node:fs/promises');binary=await readFile(String(location).startsWith('file:')?new URL(location):location);
    }else{const response=await fetch(location);if(!response.ok)throw new Error(`ICC engine fetch failed: ${response.status}`);binary=new Uint8Array(await response.arrayBuffer());}
  }
  const wasmModule=await WebAssembly.compile(binary);
  let memory;
  // This is the documented Emscripten instantiation hook. Bound growth BEFORE
  // allocation; account conservatively for this pinned runtime's 20% growth.
  moduleOptions.instantiateWasm=(imports,receive)=>{
    const original=imports.env.emscripten_resize_heap;
    imports.env.emscripten_resize_heap=requested=>{
      requested>>>=0;
      const predicted=Math.ceil(Math.max(requested,memory.buffer.byteLength*1.2)/65536)*65536;
      if(predicted>memoryLimitBytes){statistics.memoryLimitFailures++;return false;}
      return original(requested);
    };
    const instance=new WebAssembly.Instance(wasmModule,imports);memory=instance.exports.memory;
    if(memory.buffer.byteLength>memoryLimitBytes)throw new Error('ICC initial Wasm memory exceeds its limit');
    receive(instance,wasmModule);return instance.exports;
  };
  const lcms=await instantiate(moduleOptions);
  const active=new Map(), registry=new Map(), helperCache=new Map();
  let disposed=false, nextScope=0;
  const error=()=>{statistics.failures++;return false;};
  function release(descriptor){
    const r=active.get(descriptor);if(!r)return;
    active.delete(descriptor);lcms.cmsDeleteTransform(r.transform);lcms._free(r.input);lcms._free(r.output);
    statistics.activeTransforms=active.size;
  }
  function openProfile(bytes){
    let pointer=0;
    try{pointer=lcms._malloc(bytes.length);if(!pointer)return 0;lcms.HEAPU8.set(bytes,pointer);return lcms._cmsOpenProfileFromMem(pointer,bytes.length);}
    finally{if(pointer)lcms._free(pointer);}
  }
  function activate(d){
    if(disposed||d.closed)return null;
    const cached=active.get(d);if(cached){active.delete(d);active.set(d,cached);return cached;}
    while(active.size>=maxActiveTransforms){release(active.keys().next().value);statistics.evictions++;}
    let src=0,dst=0,transform=0,input=0,output=0;
    try{
      src=d.source ? openProfile(d.source) : d.kind==='Lab' ? lcms.cmsCreateLab4Profile(d.whitepoint) : d.kind==='XYZ' ? lcms.cmsCreateXYZProfile() : lcms.cmsCreate_sRGBProfile();
      if(!src)return null;
      dst=d.destination?openProfile(d.destination):d.outputKind==='XYZ'?lcms.cmsCreateXYZProfile():lcms.cmsCreate_sRGBProfile();
      if(!dst)return null;
      const srcFormat=d.kind==='Lab'?TYPE_Lab_DBL:d.kind==='XYZ'?TYPE_XYZ_DBL:formats[d.components];
      transform=lcms.cmsCreateTransform(src,srcFormat,dst,d.outputKind==='XYZ'?TYPE_XYZ_DBL:formats[d.outputComponents],d.intent,0);
      if(!transform)return null;
      input=lcms._malloc(32);output=lcms._malloc(32);
      if(!input||!output)return null;
      const resource={transform,input,output};active.set(d,resource);statistics.activeTransforms=active.size;statistics.transforms++;
      if(d.opened)statistics.reopens++;d.opened=true;
      transform=input=output=0;
      return resource;
    }catch{return null;}
    finally{
      if(src)lcms.cmsCloseProfile(src);if(dst)lcms.cmsCloseProfile(dst);
      if(transform)lcms.cmsDeleteTransform(transform);if(input)lcms._free(input);if(output)lcms._free(output);
    }
  }
  function handleFor(d){
    if(!activate(d)){error();return null;}
    const handle={
      outputComponents:d.outputComponents,
      convert(a,b,c,e,result){
        const r=activate(d);
        if(!r){for(let i=0;i<d.outputComponents;i++)result[i]=NaN;return error();}
        const k=d.kind==='ICC'&&d.components===4?100:1,p=r.input>>>3;
        lcms.HEAPF64[p]=a*k;lcms.HEAPF64[p+1]=b*k;lcms.HEAPF64[p+2]=c*k;lcms.HEAPF64[p+3]=e*k;
        try{lcms._cmsDoTransform(r.transform,r.input,r.output,1);}catch{release(d);for(let i=0;i<d.outputComponents;i++)result[i]=NaN;return error();}
        const q=r.output>>>3,scale=d.outputComponents===4?100:1;
        for(let i=0;i<d.outputComponents;i++)result[i]=lcms.HEAPF64[q+i]/scale;
        statistics.samples++;return true;
      },
      close(){release(d);d.closed=true;d.source=null;d.destination=null;},
    };
    return handle;
  }
  function make(source,n,intent,destination,outputN,kind='ICC',whitepoint=null,outputKind='RGB'){
    if(disposed || (source&&!validProfile(source,n)) || (!source&&!['sRGB','Lab','XYZ'].includes(kind)) || (destination&&!validProfile(destination,outputN)) || (!destination&&outputN!==3))return null;
    statistics.profiles+=Number(!!source)+Number(!!destination);
    // Copy input bytes once: retained handles can safely lazily reopen after
    // eviction, and caller mutation cannot alter a compiled transform's key.
    return handleFor({source:source?.slice()||null,components:n,intent:pdfIccIntent(intent),destination:destination?.slice()||null,outputComponents:outputN,kind,whitepoint,outputKind,closed:false,opened:false});
  }
  const engine={
    name:'LittleCMS via lcms-wasm 1.0.5',statistics,
    capabilities:{icc:true,inputComponents:[1,3,4],outputComponents:[1,3,4],renderingIntents:[0,1,2,3],maxActiveTransforms,memoryLimitBytes,maxProfileBytes:MAX_PROFILE},
    open(source,n,intent=1,destination=null,outputN=3){return make(source,n,intent,destination,outputN);},
    clearActiveTransforms(){for(const d of [...active.keys()])release(d);},
    dispose(){engine.clearActiveTransforms();for(const h of helperCache.values())h.close();helperCache.clear();registry.clear();statistics.registeredProfileBytes=0;disposed=true;if(globalThis.__moonbit_pdf_icc===engine)delete globalThis.__moonbit_pdf_icc;},
    registerProfile(id,bytes,n){
      if(disposed||typeof id!=='string'||!validProfile(bytes,n))return false;
      const old=registry.get(id),size=statistics.registeredProfileBytes-(old?.bytes.length||0)+bytes.length;
      if(size>32*1024*1024)return false;
      // IDs are immutable within a document catalog. No stale transform cache.
      if(old)return old.n===n && old.bytes.length===bytes.length && old.bytes.every((v,i)=>v===bytes[i]);
      registry.set(id,{bytes:bytes.slice(),n});statistics.registeredProfileBytes=size;return true;
    },
    clearProfiles(){for(const h of helperCache.values())h.close();helperCache.clear();registry.clear();statistics.registeredProfileBytes=0;},
    // Each asynchronous page replay owns its own IDs. Overlapping renders
    // cannot accidentally resolve icc-0 from a different page's catalog.
    createProfileScope(catalog=[]){
      if(!Array.isArray(catalog)||catalog.length>32)throw new RangeError('Invalid ICC profile catalog');
      const prefix=`page-${nextScope++}/`, ids=[];let closed=false;
      const scopedSource=source=>source ? {...source,icc_profile_id:source.icc_profile_id?prefix+source.icc_profile_id:null,alternate:source.alternate?scopedSource(source.alternate):null}:null;
      const scope={
        sourceToGroup(source,options={}){if(closed)return null;return engine.sourceToGroup(scopedSource(source),{...options,profileId:options.profileId?prefix+options.profileId:null});},
        sourceToProcess(source,options={}){return scope.sourceToGroup(source,{...options,components:4});},
        processToRgb(values,options={}){if(closed)return null;return engine.processToRgb(values,{...options,profileId:options.profileId?prefix+options.profileId:null});},
        groupToRgb(values,options={}){if(closed)return null;return engine.groupToRgb(values,{...options,profileId:options.profileId?prefix+options.profileId:null});},
        dispose(){
          if(closed)return;closed=true;
          for(const [key,h]of helperCache){if(JSON.parse(key).slice(0,2).some(id=>typeof id==='string'&&id.startsWith(prefix))){h.close();helperCache.delete(key);}}
          for(const id of ids){const entry=registry.get(id);if(entry){statistics.registeredProfileBytes-=entry.bytes.length;registry.delete(id);}}
        },
      };
      try{
        const seen=new Set();
        for(const entry of catalog){
          if(!entry||typeof entry.id!=='string'||seen.has(entry.id)||typeof entry.data_base64!=='string'||entry.data_base64.length>Math.ceil(MAX_PROFILE/3)*4)throw new Error('Invalid ICC catalog entry');
          seen.add(entry.id);const binary=atob(entry.data_base64),bytes=Uint8Array.from(binary,c=>c.charCodeAt(0)),id=prefix+entry.id;
          if(!engine.registerProfile(id,bytes,entry.components))throw new Error('ICC profile catalog exceeds limits or contains invalid data');
          ids.push(id);
        }
      }catch(error){scope.dispose();throw error;}
      return scope;
    },
    groupToRgb(values,options={}){
      if(options.calibration){const pcs=pdfCalibrationToPcs(values,options.calibration);return pcs?engine.sourceToGroup({space:'PCSXYZ',components:pcs},{components:3,intent:options.intent}):null;}
      return engine.processToRgb(values,options);
    },
    sourceToPcs(source,{intent=source?.rendering_intent??1}={}){
      if(!source)return null;
      if(source.space==='Separation'||source.space==='DeviceN')return source.alternate?engine.sourceToPcs(source.alternate,{intent}):null;
      if(source.calibration)return pdfCalibrationToPcs(source.components,source.calibration);
      if(source.pcs_xyz?.length===3)return source.pcs_xyz.every(Number.isFinite)?source.pcs_xyz.slice():null;
      if(source.space==='PCSXYZ')return source.components?.length===3&&source.components.every(Number.isFinite)?source.components.slice():null;
      let profile=null,n=3,kind='ICC',whitepoint=null,values=source.components;
      if(source.space==='DeviceRGB')kind='sRGB';
      else if(source.space==='DeviceGray'){kind='sRGB';values=Array(3).fill(source.components?.[0]);}
      else if(source.space==='ICCBased'){const item=registry.get(source.icc_profile_id);if(!item)return source.alternate?engine.sourceToPcs(currentIccAlternate(source),{intent}):null;profile=item.bytes;n=item.n;}
      else if(source.space==='Lab'){kind='Lab';whitepoint=source.whitepoint_xyy??null;}
      else return null;
      if(!values||values.length!==n||!values.every(Number.isFinite))return null;
      if(source.component_ranges?.length===2*n)values=values.map((v,i)=>Math.max(source.component_ranges[2*i],Math.min(source.component_ranges[2*i+1],v)));
      const key=JSON.stringify([source.icc_profile_id??kind,'to-pcs-xyz',pdfIccIntent(intent),whitepoint]);let h=helperCache.get(key);
      if(!h){h=make(profile,n,intent,null,3,kind,whitepoint,'XYZ');if(!h)return source.space==='ICCBased'&&source.alternate?engine.sourceToPcs(currentIccAlternate(source),{intent}):null;while(helperCache.size>=8){const key=helperCache.keys().next().value;helperCache.get(key).close();helperCache.delete(key);}helperCache.set(key,h);}
      const output=new Float64Array(3);return h.convert(values[0]??0,values[1]??0,values[2]??0,values[3]??0,output)&&output.every(Number.isFinite)?Array.from(output):null;
    },
    processToRgb(values,{profileId,components,intent=1}={}){
      const profile=registry.get(profileId);
      if(!profile||(components!==undefined&&components!==profile.n)||!values||values.length!==profile.n||!Array.from(values).every(Number.isFinite))return null;
      const key=JSON.stringify([profileId,'profile-to-srgb',pdfIccIntent(intent)]);
      let h=helperCache.get(key);
      if(!h){h=make(profile.bytes,profile.n,intent,null,3);if(!h)return null;while(helperCache.size>=8){const key=helperCache.keys().next().value;helperCache.get(key).close();helperCache.delete(key);}helperCache.set(key,h);}
      const output=new Float64Array(3);
      return h.convert(values[0]??0,values[1]??0,values[2]??0,values[3]??0,output)?Array.from(output,v=>Math.max(0,Math.min(1,v))):null;
    },
    sourceToProcess(source,options={}){return engine.sourceToGroup(source,{...options,components:4});},
    sourceToGroup(source,{profileId,calibration,components=4,intent=source?.rendering_intent??1}={}){
      if(!source||!signatures[components])return null;
      if(source.space==='Separation'||source.space==='DeviceN')return source.alternate?engine.sourceToGroup(source.alternate,{profileId,calibration,components,intent}):null;
      if(source.space==='ICCBased'&&!registry.has(source.icc_profile_id)&&source.alternate)return engine.sourceToGroup(currentIccAlternate(source),{profileId,calibration,components,intent});
      if(calibration){if(profileId||calibration.components!==components)return null;const xyz=engine.sourceToPcs(source,{intent});return xyz?pdfCalibrationFromPcs(xyz,calibration):null;}
      if(source.calibration){const xyz=pdfCalibrationToPcs(source.components,source.calibration);if(!xyz)return null;source={...source,space:'PCSXYZ',components:xyz,pcs_xyz:null,component_ranges:null,calibration:null};}
      const target=registry.get(profileId);
      if(profileId&&(!target||target.n!==components))return null;
      const validValues=(values,n)=>values?.length===n&&Array.from(values).every(Number.isFinite);
      const clampValues=values=>Array.from(values,v=>Math.max(0,Math.min(1,v)));
      // Untagged device components are already native to the matching device
      // group. Device Gray has the prescribed pure-K mapping in CMYK groups.
      if(source.space==='DeviceCMYK'&&components===4)return validValues(source.components,4)?clampValues(source.components):null;
      if(source.space==='DeviceGray'&&(components===1||components===4)){
        if(!validValues(source.components,1))return null;
        const gray=Math.max(0,Math.min(1,source.components[0]));return components===1?[gray]:[0,0,0,1-gray];
      }
      if(!target){
        if(source.space==='DeviceRGB')return components===4?(source.process_cmyk?.slice(0,4)||pdfDeviceRgbToCmyk(source.components)):components===3&&validValues(source.components,3)?clampValues(source.components):null;
        if(source.space==='DeviceGray'&&components===3&&validValues(source.components,1))return Array(3).fill(Math.max(0,Math.min(1,source.components[0])));
        if(components!==3)return null;
      }
      let profile=null,n=3,kind='ICC',whitepoint=null,values=source.components;
      if(source.space==='DeviceRGB'){kind='sRGB';}
      else if(source.space==='DeviceGray'){kind='sRGB';values=Array(3).fill(source.components?.[0]);}
      else if(source.space==='ICCBased'){const item=registry.get(source.icc_profile_id);if(!item)return source.alternate?engine.sourceToGroup(currentIccAlternate(source),{profileId,calibration,components,intent}):null;profile=item.bytes;n=item.n;}
      else if(source.space==='Lab'){kind='Lab';whitepoint=source.whitepoint_xyy??null;}
      else if(source.space==='PCSXYZ'){kind='XYZ';}
      else if(source.pcs_xyz?.length===3){kind='XYZ';values=source.pcs_xyz;}
      else return null;
      if(!values||values.length<n||!values.every(Number.isFinite))return null;
      if(source.component_ranges?.length===2*n)values=values.map((v,i)=>Math.max(source.component_ranges[2*i],Math.min(source.component_ranges[2*i+1],v)));
      if(source.space==='ICCBased'&&source.icc_profile_id===profileId&&n===components)return clampValues(values);
      const key=JSON.stringify([profileId,source.icc_profile_id??kind,pdfIccIntent(intent),whitepoint,components]);
      let h=helperCache.get(key);
      if(!h){h=make(profile,n,intent,target?.bytes??null,components,kind,whitepoint);if(!h){
        // Recovery is for an unavailable source profile, never a failed target.
        // A source->sRGB probe distinguishes those failure directions.
        if(source.space==='ICCBased'&&source.alternate&&!engine.processToRgb(values,{profileId:source.icc_profile_id,intent}))return engine.sourceToGroup(currentIccAlternate(source),{profileId,calibration,components,intent});
        return null;
      }while(helperCache.size>=8){const key=helperCache.keys().next().value;helperCache.get(key).close();helperCache.delete(key);}helperCache.set(key,h);}
      const output=new Float64Array(components);
      return h.convert(values[0]??0,values[1]??0,values[2]??0,values[3]??0,output)?Array.from(output,v=>Math.max(0,Math.min(1,v))):null;
    },
  };
  return engine;
}

export async function installPdfIccEngine(options = {}) {
  if(globalThis.__moonbit_pdf_icc)return globalThis.__moonbit_pdf_icc;
  const engine=await createPdfIccEngine(options);globalThis.__moonbit_pdf_icc=engine;return engine;
}

import {pdfDeviceRgbToCmyk} from './pdf-icc.mjs';
const clamp=x=>Math.max(0,Math.min(1,x));
const channels=space=>space==='DeviceCMYK'?4:['DeviceGray','CalGray'].includes(space)?1:3;
/** One group's original component domain and its explicit output transform. */
export function pdfGroupColour(space,profileId,scope,options={},intent=undefined,calibration=null){
 const n=channels(space),profile=profileId||null;
 const failure=message=>{throw new Error(`PDF group colour: ${message}`);};
 if(!['DeviceRGB','DeviceGray','DeviceCMYK','CalRGB','CalGray'].includes(space))failure(`invalid blending colour space ${space}`);
 if(space.startsWith('Cal')&&!calibration)failure(`calibration is missing for ${space}`);
 const convert=source=>{
  if(!source)return failure('source components are missing');
  if(source.space==='Separation'||source.space==='DeviceN')return source.alternate?convert(source.alternate):failure('whole alternate is missing');
  let values;
  if(profile||calibration){
   values=scope?.sourceToGroup(source,{profileId:profile,calibration,components:n,intent:source.rendering_intent});
  }else if(n===4){
   values=options.convertToProcess?options.convertToProcess(source):scope?.sourceToGroup(source,{components:4});
   if(!values&&source.space==='DeviceCMYK')values=source.components;
   if(!values&&source.space==='DeviceGray')values=[0,0,0,1-clamp(source.components[0])];
   if(!values&&source.space==='DeviceRGB')values=source.process_cmyk||pdfDeviceRgbToCmyk(source.components);
  }else{
   values=scope?.sourceToGroup(source,{components:n});
   if(!values&&source.space==='DeviceRGB')values=n===1?[source.components[0]*.3+source.components[1]*.59+source.components[2]*.11]:source.components;
   if(!values&&source.space==='DeviceGray')values=Array(n).fill(source.components[0]);
   if(!values&&source.space==='DeviceCMYK'){
    const rgb=options.convertProcess?.(source.components);
    if(rgb)values=n===1?[rgb[0]*.3+rgb[1]*.59+rgb[2]*.11]:rgb;
   }
   if(!values&&source.space==='ICCBased'&&source.icc_profile_id){
    const rgb=scope?.groupToRgb(source.components,{profileId:source.icc_profile_id,intent:source.rendering_intent});
    if(rgb)values=n===1?[rgb[0]*.3+rgb[1]*.59+rgb[2]*.11]:rgb;
   }
  }
  if(!values||values.length!==n||!Array.from(values).every(Number.isFinite))return failure(`${source.space} cannot be converted to ${profile||space}`);
  return Array.from(values,clamp);
 };
 const toRgb=values=>{
  const rgb=profile||calibration?scope?.groupToRgb(values,{profileId:profile,calibration,components:n,intent}):n===4?options.convertProcess?.(values):n===1?Array(3).fill(values[0]):values;
  if(!rgb||rgb.length!==3||!Array.from(rgb).every(Number.isFinite))return failure(`output transform unavailable for ${profile||space}`);
  return Array.from(rgb,clamp);
 };
 const source=(values,renderingIntent=intent)=>({space:profile?'ICCBased':space,icc_profile_id:profile,calibration,components:values,rendering_intent:renderingIntent,paints:true});
 return {space,profileId:profile,calibration,components:n,convert,toRgb,source};
}
export function convertGroupSurface(pixels,from,to,intent=undefined){
 const fromStride=from.components===4?5:4,toStride=to.components===4?5:4;
 const result=new Float32Array(pixels.length/fromStride*toStride);
 for(let p=0;p<pixels.length/fromStride;p++){
  const a=pixels[p*fromStride+fromStride-1];if(!a)continue;
  const values=Array.from({length:from.components},(_,c)=>pixels[p*fromStride+c]/a);
  const converted=to.convert(from.source(values,intent));
  for(let c=0;c<toStride-1;c++)result[p*toStride+c]=converted[Math.min(c,to.components-1)]*a;
  result[p*toStride+toStride-1]=a;
 }
 return result;
}
export function groupSurfaceToRgb(pixels,colour){
 const stride=colour.components===4?5:4,result=new Float32Array(pixels.length/stride*4);
 for(let p=0;p<pixels.length/stride;p++){
  const a=pixels[p*stride+stride-1];if(!a)continue;
  const rgb=colour.toRgb(Array.from({length:colour.components},(_,c)=>pixels[p*stride+c]/a));
  for(let c=0;c<3;c++)result[p*4+c]=rgb[c]*a;result[p*4+3]=a;
 }
 return result;
}

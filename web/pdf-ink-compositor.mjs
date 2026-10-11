import {pdfPixelRegion,pdfUnionPixelRegions,clearOutsideRegion} from './pdf-pixel-region.mjs';
import {pdfDeviceRgbToCmyk} from './pdf-icc.mjs';
import {PdfCompositor} from './pdf-compositor.mjs';
const PROCESS=['Cyan','Magenta','Yellow','Black'];
const clamp=x=>Math.max(0,Math.min(1,x));
const NONSEPARABLE=new Set(['hue','saturation','color','luminosity']);

/** PDF DeviceCMYK plus independent spot planes. Working samples are
 * premultiplied subtractive ink values. CompatibleOverprint is a blend
 * function, not an instruction to preserve straight components after alpha
 * changes (PDF Reference 1.4, 7.6.3). Canvas evaluates separable blend kernels
 * on complemented additive samples; it never rasterizes this group for us. */
export class PdfInkCompositor {
 constructor(width,height,createCanvas,{colorants=[],...options}={}){
  this.width=width;this.height=height;this.length=width*height;
  this.names=[...new Set([...PROCESS,...colorants.filter(x=>x!=='None'&&x!=='All')])];
  if(this.names.length>36)throw new RangeError('PDF ink-plane limit exceeded');
  this.channels=this.names.length;this.stride=this.channels+1;
  this.frames=[];this.freeFrames=[];this.recyclingFrames=new Set();this.kernel=new PdfCompositor(width,height,createCanvas,options);
  this.options=options;this.maxDepth=options.maxDepth || 32;this.maxBytes=options.maxWorkingBytes || 536870912;
 }
 workingBytes(){
  return this.length*(this.stride*8+8)*(this.frames.length+this.freeFrames.length+this.recyclingFrames.size)
   +(this.paintScratch?this.paintScratch.pixels.byteLength+this.paintScratch.shape.byteLength:0)
   +(this.blendScratch?this.blendScratch.out.byteLength+this.blendScratch.b.byteLength+this.blendScratch.s.byteLength:0)+this.kernel.workingBytes();
 }
 beginGroup({isolated=false,knockout=false,color_space='DeviceCMYK'}={},backdrop=null){
  if(color_space&&color_space!=='DeviceCMYK')throw new Error(`Ink group conversion requires a profile for ${color_space}`);
  // Reserve simultaneous source, blend-result, complemented kernel buffers,
  // Canvas readback, and group extraction alongside persistent frame planes.
  const scratch=this.length*(this.stride*8+this.channels*4+56);
  const bytes=this.length*((this.frames.length+this.freeFrames.length+this.recyclingFrames.size+(this.freeFrames.length?0:1)))*(this.stride*8+8)+scratch;
  if(this.frames.length>=this.maxDepth||bytes>this.maxBytes)throw new RangeError('PDF ink group memory limit exceeded');
  const frame=this.freeFrames.pop()||{initial:new Float32Array(this.length*this.stride),pixels:new Float32Array(this.length*this.stride),shape:new Float32Array(this.length),alpha:new Float32Array(this.length)};
  frame.initial.fill(0);if(!isolated&&backdrop)frame.initial.set(backdrop);frame.pixels.set(frame.initial);frame.shape.fill(0);frame.alpha.fill(0);
  Object.assign(frame,{isolated,knockout,color_space:'DeviceCMYK',dirty:{x:0,y:0,width:0,height:0}});
  this.frames.push(frame);return frame;
 }
 touch(dirty=null){const r=pdfPixelRegion(this.width,this.height,dirty),frame=this.frames.at(-1);frame.dirty=pdfUnionPixelRegions(frame.dirty,r);return r;}
 colourValues(source){
  if(!source||source.paints===false)return null;
  if(this.options.proof!==true&&['Separation','DeviceN'].includes(source.space)){
   if(!source.alternate)throw new Error('Display spot colour is missing its evaluated whole alternate');
   const alternate=this.colourValues(source.alternate);
   if(alternate)alternate.cmyk=false; // OPM=1 zero suppression is only direct DeviceCMYK.
   return alternate;
  }
  const values=new Float64Array(this.channels),names=source.colorants||[],specified=new Uint8Array(this.channels);
  if(source.all||names.includes('All')){values.fill(clamp(source.components[names.indexOf('All')<0?0:names.indexOf('All')]));specified.fill(1);}
  else if(source.space==='DeviceCMYK')for(let c=0;c<4;c++){values[c]=clamp((source.process_cmyk||source.components)[c]);specified[c]=1;}
  else if(source.space==='DeviceGray'){values[3]=1-clamp(source.components[0]);specified.fill(1,0,4);}
  else if(source.space==='Separation'||source.space==='DeviceN'){
   names.forEach((name,i)=>{if(name==='None')return;const c=this.names.indexOf(name);if(c<0)throw new Error(`Ink plane was not declared: ${name}`);values[c]=clamp(source.components[i]);specified[c]=1;});
  }else{
   const process=this.options.convertToProcess?.(source) || globalThis.__moonbit_pdf_icc?.sourceToProcess(source,{profileId:this.options.processProfileId}) || source.process_cmyk || (source.space==='DeviceRGB'?pdfDeviceRgbToCmyk(source.components):null);
   if(!process||process.length!==4)throw new Error(`Source ${source.space} needs a source-to-DeviceCMYK group transform`);
   for(let c=0;c<4;c++){values[c]=clamp(process[c]);specified[c]=1;}
  }
  return {values,specified,cmyk:source.space==='DeviceCMYK'};
 }
 // Borrowed only by synchronous paint submission. Public source() results
 // remain owned unless this internal reuse flag is explicitly requested.
 borrowSource(dirty=null){
  const scratch=this.paintScratch||={pixels:new Float32Array(this.length*this.stride),shape:new Float32Array(this.length),dirty:null};
  const r=scratch.dirty;
  if(r)for(let y=r.y;y<r.y+r.height;y++){const a=y*this.width+r.x,b=a+r.width;scratch.pixels.fill(0,a*this.stride,b*this.stride);scratch.shape.fill(0,a,b);}
  scratch.dirty=pdfPixelRegion(this.width,this.height,dirty);return scratch;
 }
 source(colour,shape,{alpha=1,mask=null,alpha_is_shape=false,dirty=null,reuse=false}={}){
  const resolved=this.colourValues(colour),scratch=reuse?this.borrowSource(dirty):null,pixels=scratch?.pixels||new Float32Array(this.length*this.stride),effectiveShape=scratch?.shape||new Float32Array(this.length);
  if(!resolved)return {pixels,shape:effectiveShape,resolved:null};
  const r=pdfPixelRegion(this.width,this.height,dirty);
  for(let y=r.y;y<r.y+r.height;y++)for(let x=r.x,p=y*this.width+x,i=p*this.stride;x<r.x+r.width;x++,p++,i+=this.stride){
   const factor=clamp(alpha)*(mask?clamp(mask[p]):1),a=shape[p]*factor;
   effectiveShape[p]=shape[p]*(alpha_is_shape?factor:1);
   for(let c=0;c<this.channels;c++)pixels[i+c]=resolved.values[c]*a;
   pixels[i+this.channels]=a;
  }
  return {pixels,shape:effectiveShape,resolved};
 }
 paintColour(colour,shape,{alpha=1,mask=null,alpha_is_shape=false,overprint=false,overprint_mode=0,blend_mode='normal',dirty=null}={}){
  const source=this.source(colour,shape,{alpha,mask,alpha_is_shape,dirty,reuse:true});if(!source.resolved)return;
  const unmarked=new Uint8Array(this.channels);
  if(overprint)for(let c=0;c<this.channels;c++)unmarked[c]=!source.resolved.specified[c]||(overprint_mode===1&&source.resolved.cmyk&&source.resolved.values[c]===0)?1:0;
  if(overprint&&blend_mode!=='normal'&&blend_mode!=='compatible'){
   const parent=this.frames.at(-1);this.beginGroup({isolated:false,knockout:false},parent.knockout?parent.initial:parent.pixels);
   this.paint(source.pixels,source.shape,{unmarked,dirty});const result=this.endGroup({recycle:true});
   this.paint(result.pixels,result.shape,{blend_mode,dirty:result.dirty});this.releaseGroup(result);
  }else this.paint(source.pixels,source.shape,{blend_mode,unmarked:overprint?unmarked:null,dirty});
 }
 paintProcess(pixels,shape,{overprint=false,...state}={}){
  // Sampled images/shadings mark every process component, even at zero ink.
  // OPM=1 zero suppression applies only to direct graphics-state DeviceCMYK.
  const unmarked=overprint?new Uint8Array(this.channels):null;
  if(unmarked)unmarked.fill(1,4);
  this.paint(pixels,shape,{...state,unmarked});
 }
 blend(backdrop,source,mode,dirty=null,reuse=false){
  if(mode==='normal'||mode==='compatible')return null;
  const nonseparable=NONSEPARABLE.has(mode),r=pdfPixelRegion(this.width,this.height,dirty);
  const scratch=reuse?(this.blendScratch||={out:new Float32Array(this.length*this.channels),b:new Float32Array(this.length*4),s:new Float32Array(this.length*4)}):null;
  const out=scratch?.out||new Float32Array(this.length*this.channels),b=scratch?.b||new Float32Array(this.length*4),s=scratch?.s||new Float32Array(this.length*4);
  for(let offset=0;offset<this.channels;offset+=3){
   if(nonseparable&&offset>=3){
    for(let y=r.y;y<r.y+r.height;y++)for(let x=r.x,p=y*this.width+x,i=p*this.stride;x<r.x+r.width;x++,p++,i+=this.stride)for(let c=offset;c<Math.min(offset+3,this.channels);c++){
     const input=c===3&&mode!=='luminosity'?backdrop:source,a=input[i+this.channels];
     out[p*this.channels+c]=a?input[i+c]/a:0;
    }
    continue;
   }
   for(let y=r.y;y<r.y+r.height;y++)for(let x=r.x,p=y*this.width+x,i=p*this.stride;x<r.x+r.width;x++,p++,i+=this.stride){
    const ab=backdrop[i+this.channels],as=source[i+this.channels];
    for(let c=0;c<3;c++){const ch=Math.min(offset+c,this.channels-1);b[p*4+c]=ab-backdrop[i+ch];s[p*4+c]=as-source[i+ch];}
    b[p*4+3]=ab;s[p*4+3]=as;
   }
   const blended=this.kernel.blendColours(b,s,mode,r);
   for(let y=r.y;y<r.y+r.height;y++)for(let x=r.x,p=y*this.width+x;x<r.x+r.width;x++,p++)for(let c=0;c<3&&offset+c<this.channels;c++){
    // Difference/Exclusion are not white-preserving; spots use Normal.
    const ch=offset+c;
    out[p*this.channels+ch]=ch>=4&&(mode==='difference'||mode==='exclusion')
     ?(source[p*this.stride+this.channels]?source[p*this.stride+ch]/source[p*this.stride+this.channels]:0)
     :1-blended[((y-r.y)*r.width+x-r.x)*4+c]/255;
   }
  }
  return out;
 }
 paint(source,shape,{alpha=1,mask=null,alpha_is_shape=false,blend_mode='normal',unmarked=null,dirty=null}={}){
  const frame=this.frames.at(-1);if(!frame)throw new Error('No ink group is open');
  if(source.length!==frame.pixels.length||shape.length!==this.length)throw new RangeError('Ink source dimensions differ');
  const base=frame.knockout?frame.initial:frame.pixels,r=this.touch(dirty),blended=this.blend(base,source,blend_mode,r,true);
  for(let y=r.y;y<r.y+r.height;y++)for(let x=r.x,p=y*this.width+x,i=p*this.stride;x<r.x+r.width;x++,p++,i+=this.stride){
   const opacity=clamp(alpha)*(mask?clamp(mask[p]):1),fs=clamp(shape[p])*(alpha_is_shape?opacity:1),as=source[i+this.channels]*opacity,ab=base[i+this.channels];
   if(fs===0&&as===0)continue;
   for(let c=0;c<this.channels;c++){
    const cs=source[i+this.channels]?source[i+c]/source[i+this.channels]:0,cb=ab?base[i+c]/ab:0;
    const blend=unmarked?.[c]?cb:(blended?blended[p*this.channels+c]:cs);
    const value=(1-as)*base[i+c]+as*((1-ab)*cs+ab*blend);
    frame.pixels[i+c]=frame.knockout?frame.pixels[i+c]*(1-fs)+value-base[i+c]*(1-fs):value;
   }
   const ar=as+ab*(1-as);
   frame.pixels[i+this.channels]=frame.knockout?frame.pixels[i+this.channels]*(1-fs)+ar-ab*(1-fs):ar;
   frame.alpha[p]=as+frame.alpha[p]*(1-(frame.knockout?fs:as));frame.shape[p]=fs+frame.shape[p]*(1-fs);
  }
 }
 endGroup({recycle=false}={}){
  const frame=this.frames.pop();if(!frame)throw new Error('Ink group stack underflow');
  const source=recycle?frame.pixels:new Float32Array(frame.pixels.length);
  const r=frame.dirty;
  for(let y=r.y;y<r.y+r.height;y++)for(let x=r.x,p=y*this.width+x,i=p*this.stride;x<r.x+r.width;x++,p++,i+=this.stride){const ag=clamp(frame.alpha[p]);for(let c=0;c<this.channels;c++)source[i+c]=Math.max(0,Math.min(ag,frame.pixels[i+c]-frame.initial[i+c]*(1-ag)));source[i+this.channels]=ag;}
  if(recycle){clearOutsideRegion(source,this.stride,this.width,this.height,r);this.recyclingFrames.add(frame);}
  return {pixels:source,shape:frame.shape,result:frame.pixels,dirty:frame.dirty,_recycleFrame:recycle?frame:null};
 }
 releaseGroup(result){const frame=result._recycleFrame;if(!frame)return;result._recycleFrame=null;this.recyclingFrames.delete(frame);this.freeFrames.push(frame);
 }
 fromRgb(pixels){
  const output=new Float32Array(this.length*this.stride);
  for(let p=0;p<this.length;p++){
   const a=pixels[p*4+3];if(!a)continue;
   const source={space:'DeviceRGB',components:[pixels[p*4]/a,pixels[p*4+1]/a,pixels[p*4+2]/a],paints:true};
   const converted=this.colourValues(source);
   for(let c=0;c<this.channels;c++)output[p*this.stride+c]=converted.values[c]*a;
   output[p*this.stride+this.channels]=a;
  }
  return output;
 }
 toRgb(pixels){
  if(!this.options.convertProcess)throw new Error('DeviceCMYK output needs the shared process colour transform');
  const output=new Float32Array(this.length*4),values=new Float64Array(this.channels);
  for(let p=0,i=0;p<this.length;p++,i+=this.stride){
   const a=pixels[i+this.channels];if(!a)continue;
   for(let c=0;c<this.channels;c++)values[c]=clamp(pixels[i+c]/a);
   const activeSpots=this.names.length>4&&values.subarray(4).some(v=>v!==0);
   const rgb=activeSpots?this.options.convertAllColorants?.(this.names,values):this.options.convertProcess(values.subarray(0,4));
   if(!rgb||rgb.length!==3)throw new Error('Spot ink output needs a transform for the complete colorant vector');
   for(let c=0;c<3;c++)output[p*4+c]=clamp(rgb[c])*a;output[p*4+3]=a;
  }
  return output;
 }
}

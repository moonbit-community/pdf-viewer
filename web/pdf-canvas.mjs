import {pdfApplyImageSampling,pdfDrawImage} from './pdf-image-sampling.mjs';
import {pdfGroupColour,convertGroupSurface,groupSurfaceToRgb} from './pdf-group-colour.mjs';
import { PdfInkCompositor } from './pdf-ink-compositor.mjs';
import { pdfDashedHairlinePath,pdfStrokeGeometry } from './pdf-hairline.mjs';
import { createColourPlaneSurface, paintColourPlaneSurface, resolveColourPlaneSurface, invalidateColourPlaneSurface } from './pdf-colour-planes.mjs';
import { PdfCompositor, rgba8ToPremultiplied, premultipliedToRgba8, softMaskSamples } from './pdf-compositor.mjs';
import { pdfPixelRegion } from './pdf-pixel-region.mjs';
import {prepareNativeCanvasItems,singleType3Path} from './pdf-canvas-native.mjs';

export const multiplyMatrix = (a,b) => [
  a[0]*b[0]+a[2]*b[1], a[1]*b[0]+a[3]*b[1],
  a[0]*b[2]+a[2]*b[3], a[1]*b[2]+a[3]*b[3],
  a[0]*b[4]+a[2]*b[5]+a[4], a[1]*b[4]+a[3]*b[5]+a[5],
];
const pageFlip = page => [1,0,0,-1,page.origin_x,page.origin_y+page.height];
const defaultCanvas = (width,height) => {
  if (typeof OffscreenCanvas !== 'undefined') return new OffscreenCanvas(width,height);
  if (typeof document !== 'undefined') return Object.assign(document.createElement('canvas'),{width,height});
  throw new Error('PDF Canvas renderer needs a host createCanvas implementation');
};
export const loadPdfRaster = async uri => {
  const blob=await (await fetch(uri)).blob();
  if (typeof createImageBitmap !== 'undefined' && blob.type !== 'image/svg+xml') return createImageBitmap(blob);
  const image=new Image(); image.src=uri; await image.decode(); return image;
};
const svgUri = svg => {
  const bytes=new TextEncoder().encode(svg);let binary='';
  for(let offset=0;offset<bytes.length;offset+=8192) binary+=String.fromCharCode(...bytes.subarray(offset,offset+8192));
  return `data:image/svg+xml;base64,${btoa(binary)}`;
};
// Clips emitted by the collector use absolute M/L/C/Z geometry. An affine
// image of a cubic lies in its control-point hull, so these bounds can skip
// invisible shading samples without approximating the Canvas clip itself.
// Host-authored SVG syntax outside this subset keeps the full-page replay.
const shadingClipRegion=(clips,matrix,width,height)=>{
  if(!clips?.length)return null;
  let left=0,top=0,right=width,bottom=height;
  for(const clip of clips){
    const text=clip.svg_path;
    if(typeof text!=='string')return null;
    const token=/[MLCZ]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?/g;
    if(text.replace(token,'').replace(/[\s,]/g,''))return null;
    const tokens=text.match(token)||[];
    if(tokens.length>1000000||tokens[0]!=='M')return null;
    let minX=Infinity,minY=Infinity,maxX=-Infinity,maxY=-Infinity;
    for(let i=0;i<tokens.length;){
      const command=tokens[i++],count=command==='C'?6:command==='M'||command==='L'?2:command==='Z'?0:-1;
      if(count<0||i+count>tokens.length)return null;
      for(let j=0;j<count;j+=2){
        const x=Number(tokens[i++]),y=Number(tokens[i++]);
        const dx=matrix[0]*x+matrix[2]*y+matrix[4],dy=matrix[1]*x+matrix[3]*y+matrix[5];
        if(!Number.isFinite(dx)||!Number.isFinite(dy))return null;
        minX=Math.min(minX,dx);minY=Math.min(minY,dy);maxX=Math.max(maxX,dx);maxY=Math.max(maxY,dy);
      }
    }
    if(!Number.isFinite(minX))return null;
    // Include the complete antialias fringe, even at fractional clip edges.
    left=Math.max(left,Math.floor(minX)-1);top=Math.max(top,Math.floor(minY)-1);
    right=Math.min(right,Math.ceil(maxX)+1);bottom=Math.min(bottom,Math.ceil(maxY)+1);
  }
  return pdfPixelRegion(width,height,{x:left,y:top,width:Math.max(0,right-left),height:Math.max(0,bottom-top)});
};
const textPaintPadding=paint=>{
 const g=paint.glyph_transform,b=paint.bounds,s=paint.stroke;
 const em=g?Math.max(Math.hypot(g[0],g[1]),Math.hypot(g[2],g[3])):b?Math.max(b.max_x-b.min_x,b.max_y-b.min_y):0;
 const m=s?.transform||[1,0,0,1,0,0],pen=s?Math.abs(s.line_width)*Math.max(Math.hypot(m[0],m[1]),Math.hypot(m[2],m[3]))*(s.miter_limit||10):0;
 return Math.max(2,em,pen);
};
const groupAt = (item,depth) => (item.groups || item.paint.group_path)?.[depth];

export function checkPdfRender(options) {
  if(options.signal?.aborted || options.isCurrent?.()===false)
    throw new DOMException('PDF page rendering cancelled','AbortError');
}

/** Render a MoonBit PdfPageModel.canvas_plan into a Canvas2D target.
 * The plan contains source paints and explicit group/clip state. Only A1's
 * individual glyph primitives use SVG; paths, images and transparency are
 * replayed independently. A Canvas2D host is required on every target. */
export async function renderPdfCanvas(canvas, plan, options = {}) {
  checkPdfRender(options);
  let scope=options._profileScope,owned=null;
  const ownedGlyphCache=!options._glyphCache;
  const glyphCache=options._glyphCache||{entries:new Map(),bytes:0,limit:Math.max(0,Math.min(options.maxGlyphCacheBytes??16777216,(options.maxWorkingBytes||536870912)/32))};
  const ownedImageCache=!options._imageCache;
  const imageCache=options._imageCache||{entries:new Map(),bytes:0,limit:Math.max(0,Math.min(options.maxImageCacheBytes??67108864,(options.maxWorkingBytes||536870912)/8))};
  if(!scope&&(plan.icc_profiles?.length||plan.blend_calibration||plan.page.blend_calibration||plan.items.some(item=>(item.groups||item.paint.group_path||[]).some(group=>group.calibration)))){
    const engine=options.iccEngine||globalThis.__moonbit_pdf_icc;
    // Ordinary ICC paints retain their legal PDF Alternate. A catalog alone
    // does not require CMM support; ICC/calibrated blend groups still enforce
    // their output-transform capability at the group boundary below.
    if(engine?.createProfileScope)owned=scope=engine.createProfileScope(plan.icc_profiles||[]);
  }
  try{return await renderPdfCanvasScoped(canvas,plan,{...options,_profileScope:scope,_glyphCache:glyphCache,_imageCache:imageCache});}
  finally{
    owned?.dispose();
    if(ownedGlyphCache){for(const entry of glyphCache.entries.values()){if(options.releaseImage)options.releaseImage(entry.value);else entry.value.close?.();}glyphCache.entries.clear();glyphCache.bytes=0;}
    if(ownedImageCache){for(const entry of imageCache.entries.values()){if(options.releaseImage)options.releaseImage(entry.value);else entry.value.close?.();}imageCache.entries.clear();imageCache.bytes=0;}
  }
}

async function renderPdfCanvasScoped(canvas, plan, options = {}) {
  const createCanvas=options.createCanvas || defaultCanvas;
  const loadImage=options.loadImage || loadPdfRaster;
  const Path=options.Path2D || globalThis.Path2D;
  if (!Path) throw new Error('PDF Canvas renderer needs a host Path2D implementation');
  if (plan.version !== 1) throw new Error(`Unsupported PDF Canvas plan version: ${plan.version}`);
  if(typeof options.resolveTextOutline==='function'){
    const resolved=new Set(),items=[];
    for(const item of plan.items){
      const p=item.paint,pen=p.stroke;
      if(item.kind!=='text'||item.type3_plan||!pen||pen.svg_path!=null||![1,2,5,6].includes(p.rendering_mode)){items.push(item);continue;}
      const svg=item.text_fill_svg||item.text_stroke_svg||item.text_svg;
      if(!svg){items.push(item);continue;}
      const outline=await options.resolveTextOutline(svg,{paint:p,page:plan.page});
      if(outline==null){items.push(item);continue;}
      if(typeof outline.fill_path!=='string'||typeof outline.stroke_path!=='string')throw new TypeError('PDF host text outline must provide page fill_path and pen-local stroke_path strings');
      // Validate the host adapter's geometry before removing its capability
      // diagnostic. Other diagnostics on the same item remain untouched.
      new Path(outline.fill_path);new Path(outline.stroke_path);
      items.push({...item,paint:{...p,fill_path:outline.fill_path,stroke:{...pen,svg_path:outline.stroke_path,unresolved:null}}});resolved.add(p.index);
    }
    if(resolved.size)plan={...plan,items,diagnostics:(plan.diagnostics||[]).filter(d=>d.code!=='PDF_TEXT_STROKE_GEOMETRY'||!resolved.has(d.item))};
  }

  const width=options.width || Math.ceil(plan.viewport.width), height=options.height || Math.ceil(plan.viewport.height);
  const matrix=options.matrix || multiplyMatrix(plan.viewport.matrix,pageFlip(plan.page));
  const nativeItems=prepareNativeCanvasItems(plan,options);
  const resourceDepth=options._resourceDepth || 0;
  if(resourceDepth>16) throw new RangeError('PDF raster resource recursion limit exceeded');
  const inheritedWorkingBytes=options._inheritedWorkingBytes || 0;
  const glyphCache=options._glyphCache;
  const glyphReservation=options._glyphCacheReserved?0:glyphCache.limit;
  const imageReservation=options._imageCache&&!options._imageCacheReserved?options._imageCache.limit:0;
  let availableBytes=(options.maxWorkingBytes || 536870912)-inheritedWorkingBytes-glyphReservation-imageReservation;
  let inkMode=plan.page.blend_space==='DeviceCMYK';
  const colorants=options.proof!==true?[]:plan.items.flatMap(item=>[item.paint.fill_source,item.paint.stroke_source].flatMap(source=>source&&['Separation','DeviceN'].includes(source.space)?(source.colorants||[]):[]));
  const hasOverprint=options.proof===true&&plan.items.some(item=>item.paint.fill_overprint || item.paint.stroke_overprint);
  const proofNames=[...new Set(['Cyan','Magenta','Yellow','Black',...colorants.filter(name=>name!=='None'&&name!=='All')])];
  const proofBytes=hasOverprint&&!inkMode?width*height*(proofNames.length*4+21):0;
  if(!Number.isSafeInteger(proofBytes)||proofBytes>availableBytes)throw new RangeError('PDF proof planes exceed the shared working-memory budget');
  const rasterBytes=width*height*(nativeItems?4:40);
  if(!Number.isSafeInteger(rasterBytes)||proofBytes+rasterBytes>=availableBytes)throw new RangeError('PDF raster surfaces exceed the shared working-memory budget');
  availableBytes-=proofBytes+rasterBytes;
  const liveCompositors=new Set();
  const releaseCompositor=engine=>{
    const kernel=engine.kernel||engine;
    if(kernel.blendCanvas)kernel.blendCanvas.width=1;
    if(kernel.blendSourceCanvas)kernel.blendSourceCanvas.width=1;
    kernel.blendCanvas=kernel.blendSourceCanvas=kernel.blendBackdropData=kernel.blendSourceData=null;
    engine.frames.length=0;engine.freeFrames.length=0;engine.recyclingFrames.clear();engine.paintScratch=engine.blendScratch=null;liveCompositors.delete(engine);
  };
  const createCompositor=(space='DeviceRGB',budget=availableBytes,profileId=null,intent=undefined,calibration=null)=>{
    const colour=pdfGroupColour(space,profileId,options._profileScope,options,intent,calibration);
    const engine=space==='DeviceCMYK'
      ?new PdfInkCompositor(width,height,createCanvas,{...options,maxWorkingBytes:budget,colorants,convertToProcess:colour.convert,convertProcess:colour.toRgb})
      :new PdfCompositor(width,height,createCanvas,{...options,maxWorkingBytes:budget});
    engine.colour=colour;liveCompositors.add(engine);return engine;
  };
  let compositor=createCompositor(plan.page.blend_space,availableBytes,plan.blend_profile_id||plan.page.blend_profile_id,undefined,plan.blend_calibration||plan.page.blend_calibration);
  const plates=hasOverprint&&!inkMode?createColourPlaneSurface(width,height,colorants,{maxWorkingBytes:proofBytes}):null;
  const plateCoverage=plates?new Uint8ClampedArray(width*height*4):null;
  const markCoverage=shape=>{for(let p=0;p<shape.length;p++)plateCoverage[p*4+3]=Math.round(shape[p]*255);};
  const diagnostics=[...(plan.diagnostics || [])];
  if(diagnostics.length&&options.unsupported!=='warn')throw new Error(diagnostics.map(d=>`${d.code}: ${d.message || d.reason}`).join('; '));
  let maskCacheBytes=0,inkImageCache=null,layer=null,shapeLayer=null;
  const imageCache=options._imageCache;
  const images=imageCache.entries,uncachedImages=new Set(),imageLimit=imageCache.limit;
  const releaseImage=value=>{if(options.releaseImage)options.releaseImage(value);else value?.close?.();};
  const glyphImage=async(svg,w,h)=>{
    const key=svg;
    if(glyphCache.entries.has(key)){const entry=glyphCache.entries.get(key);glyphCache.entries.delete(key);glyphCache.entries.set(key,entry);return {value:entry.value,cached:true};}
    const pixels=Math.ceil(w)*Math.ceil(h);
    if(!Number.isSafeInteger(pixels)||pixels<=0||pixels>(options.maxPixels||16777216))throw new RangeError('PDF fallback glyph raster exceeds the configured size limit');
    const value=await loadImage(svgUri(svg)),bytes=Number(value.width)*Number(value.height)*4+svg.length*2;
    while(glyphCache.entries.size&&(glyphCache.bytes+bytes>glyphCache.limit||glyphCache.entries.size>=64)){const oldest=glyphCache.entries.keys().next().value,entry=glyphCache.entries.get(oldest);glyphCache.entries.delete(oldest);glyphCache.bytes-=entry.bytes;releaseImage(entry.value);}
    if(bytes<=glyphCache.limit){glyphCache.entries.set(key,{value,bytes});glyphCache.bytes+=bytes;return {value,cached:true};}
    return {value,cached:false};
  };
  const image=async uri => {
    if(images.has(uri)){const cached=images.get(uri);images.delete(uri);images.set(uri,cached);return cached.value;}
    const value=await loadImage(uri),pixels=Number(value.width)*Number(value.height),bytes=pixels*4;
    if(!Number.isSafeInteger(pixels)||pixels<=0||pixels>(options.maxPixels||16777216)){releaseImage(value);throw new RangeError('Decoded PDF image surface exceeds the configured size limit');}
    while(images.size&&(imageCache.bytes+bytes>imageLimit||images.size>=64)){const oldest=images.keys().next().value,cached=images.get(oldest);images.delete(oldest);imageCache.bytes-=cached.bytes;releaseImage(cached.value);}
    if(bytes<=imageLimit){images.set(uri,{value,bytes});imageCache.bytes+=bytes;}
    else uncachedImages.add(value);
    return value;
  };
  try {
  if(!nativeItems){layer=createCanvas(width,height);shapeLayer=createCanvas(width,height);}
  const ctx=layer?.getContext('2d',{willReadFrequently:true}), shapeCtx=shapeLayer?.getContext('2d',{willReadFrequently:true});
  const sourcePixels=nativeItems?null:new Float32Array(width*height*4),sourceShape=nativeItems?null:new Float32Array(width*height);
  let previousSourceRegion=null;
  const environments={createCanvas,loadImage,Path2D:Path,image,width,height,matrix,page:plan.page,diagnostics,resourceDepth,glyphCache,imageCache,nativeCanvas:!!nativeItems};
  const retainedWorkingBytes=()=>inheritedWorkingBytes+glyphReservation+imageReservation+proofBytes+maskCacheBytes+(options._imageCache?0:imageCache.bytes)+(inkImageCache?inkImageCache.data.byteLength+inkImageCache.alpha.byteLength+inkImageCache.canvas.width*inkImageCache.canvas.height*4:0)+availableBytes-(inkMode?compositor.maxBytes:compositor.maxWorkingBytes)+compositor.workingBytes()+rasterBytes;
  const imageComponent=(resource,component)=>{
    const samples=resource.ink_samples;
    if(!samples||!Number.isInteger(samples.components)||samples.components<1||samples.components>32||samples.bits!==16)throw new Error('Image is missing retained source component samples');
    const count=samples.width*samples.height,expected=samples.row_bytes*samples.height;
    if(!Number.isSafeInteger(count)||count<=0||count>(options.maxPixels||16777216)||expected+count>67108864||samples.row_bytes!==samples.width*samples.components*2)throw new RangeError('PDF image component buffer exceeds limits');
    if(inkImageCache?.resource!==resource){
      if(inkImageCache)inkImageCache.canvas.width=1;
      const decode=(text,length)=>{
        if(text.length>Math.ceil(length/3)*4)throw new RangeError('Oversized image component encoding');
        const binary=atob(text);if(binary.length!==length)throw new Error('Image component buffer has invalid length');
        return Uint8Array.from(binary,c=>c.charCodeAt(0));
      };
      inkImageCache={resource,data:decode(samples.data_base64,expected),alpha:decode(samples.alpha_base64,count),canvas:createCanvas(samples.width,samples.height),component:-1};
    }
    const cached=inkImageCache;
    const key=`${component}:${compositor.colour.space}:${compositor.colour.profileId}:${JSON.stringify(compositor.colour.calibration)}`;
    if(cached.component!==key){
      const target=cached.canvas.getContext('2d'),rgba=target.createImageData(samples.width,samples.height);
      for(let p=0;p<count;p++){
        const values=Array.from({length:samples.components},(_,c)=>{
          const i=(p*samples.components+c)*2,value=(cached.data[i]*256+cached.data[i+1])/65535;
          const range=!samples.process_cmyk&&samples.source_colour?.component_ranges;
          return range?.length===samples.components*2?range[c*2]+value*(range[c*2+1]-range[c*2]):value;
        });
        const source=samples.process_cmyk?{space:'DeviceCMYK',components:values,paints:true}:{...samples.source_colour,components:values,process_cmyk:null};
        const converted=compositor.colour.convert(source);
        for(let c=0;c<3;c++)rgba.data[p*4+c]=converted[component??Math.min(c,converted.length-1)]*255;
        rgba.data[p*4+3]=cached.alpha[p];
      }
      target.putImageData(rgba,0,0);cached.component=key;
    }
    return cached.canvas;
  };
  const clips=(context,paint,groupBounds=[])=>{
    context.setTransform(...matrix);
    // A cropped/affine resource surface still has its own page/Form BBox;
    // the axis-aligned device allocation alone is not that clipping polygon.
    context.beginPath();context.rect(0,0,plan.page.width,plan.page.height);context.clip();
    for (const clip of paint.clips || []) context.clip(new Path(clip.svg_path),clip.even_odd?'evenodd':'nonzero');
    for (const bounds of [...(options._nativeClipBounds||[]),...groupBounds]) {
      context.beginPath();
      context.rect(bounds.min_x-plan.page.origin_x,plan.page.origin_y+plan.page.height-bounds.max_y,bounds.max_x-bounds.min_x,bounds.max_y-bounds.min_y);
      context.clip();
    }
  };
  const drawPath=async (context,p,shapeOnly)=>{
    const path=new Path(p.svg_path);
    if (p.filled && p.fill_source?.paints !== false) {
      context.save();
      if(p.fill_transform) context.transform(...p.fill_transform);
      context.globalAlpha=environments.component!==undefined||shapeOnly&&(!p.alpha_is_shape||inkMode)?1:p.fill_alpha;
      if (p.pattern || p.shading_pattern) {
        const shading=p.shading_pattern||p.pattern?.shading;
        if (shading) {
          if(!options.paintShading) throw new Error('Canvas shading paint requires the shading adapter');
          context.save();context.clip(path,p.fill_even_odd?'evenodd':'nonzero');
          await options.paintShading(context,shading,environments.component===undefined?p:{...p,fill_alpha:1,stroke_alpha:1},{...environments,operation:'fill',shapeOnly});context.restore();
        }
        else if (options.paintPattern) await options.paintPattern(context,p.pattern,p,'fill',{...environments,shapeOnly});
        else throw new Error('Canvas pattern paint requires the pattern/shading adapter');
      } else { context.fillStyle=shapeOnly?'#000':p.fill_color; context.fill(path,p.fill_even_odd?'evenodd':'nonzero'); }
      context.restore();
    }
    if (p.stroked && p.stroke_source?.paints !== false) {
      context.save();
      const s=p.stroke;
      if (s) context.transform(...s.transform);
      const strokeSvg=pdfStrokeGeometry(s?s.svg_path:p.svg_path,s?.line_cap??p.line_cap??0);
      const strokePath=new Path(strokeSvg);
      context.globalAlpha=environments.component!==undefined||shapeOnly&&(!p.alpha_is_shape||inkMode)?1:p.stroke_alpha;
      context.strokeStyle=shapeOnly?'#000':p.stroke_color;
      context.lineWidth=s?s.line_width:p.line_width;
      context.miterLimit=s?s.miter_limit:(p.miter_limit || 10);
      context.lineCap=['butt','round','square'][s?.line_cap??p.line_cap] || 'butt';
      context.lineJoin=['miter','round','bevel'][s?.line_join??p.line_join] || 'miter';
      context.setLineDash(s?s.dash_array:p.dash_array);
      context.lineDashOffset=s?s.dash_phase:p.dash_phase;
      if (context.lineWidth === 0 || (s?s.line_width:p.line_width) === 0) {
        // Hairlines are one device pixel. Geometry retains the full path CTM;
        // the pen itself is transformed back to device space.
        const t=context.getTransform(),devicePath=pdfDashedHairlinePath(strokeSvg,s?s.dash_array:p.dash_array,s?s.dash_phase:p.dash_phase,t,Path);
        context.setTransform(1,0,0,1,0,0); context.lineWidth=1;context.setLineDash([]);context.lineDashOffset=0;
        if(p.stroke_pattern){
          if(!options.paintPattern)throw new Error('Canvas pattern hairline requires the pattern adapter');
          await options.paintPattern(context,p.stroke_pattern,p,'stroke',{...environments,strokePath:devicePath,shapeOnly});
        }else context.stroke(devicePath);
      } else if (p.stroke_pattern) {
        if (!options.paintPattern) throw new Error('Canvas stroke pattern requires the pattern adapter');
        await options.paintPattern(context,p.stroke_pattern,p,'stroke',{...environments,strokePath,shapeOnly});
      } else context.stroke(strokePath);
      context.restore();
    }
  };
  // Text fallbacks and image stencils already contain their A1/decoded shape.
  // Paint the existing page-anchored pattern through that alpha once. The
  // destination retains the outer paint opacity, clip and stencil coverage.
  const patternThroughMask=async(context,resource,shapeOnly)=>{
    if(!options.paintPattern)throw new Error('Canvas patterned stencil requires the pattern adapter');
    // The decoded/A1 mask is already rasterized, so its nonzero device
    // coverage is a tighter proven bound than font selection/em padding.
    const r=environments.paintBounds||{x:0,y:0,width,height};
    if(!r.width||!r.height)return;
    const data=context.getImageData(r.x,r.y,r.width,r.height).data;
    let left=r.width,top=r.height,right=-1,bottom=-1;
    for(let y=0;y<r.height;y++)for(let x=0;x<r.width;x++)if(data[(y*r.width+x)*4+3]){left=Math.min(left,x);right=Math.max(right,x);top=Math.min(top,y);bottom=Math.max(bottom,y);}
    if(right<left)return;
    const paintBounds={x:r.x+left,y:r.y+top,width:right-left+1,height:bottom-top+1};
    context.save();
    context.setTransform(...matrix);context.globalAlpha=1;context.globalCompositeOperation='source-in';
    const p={svg_path:`M0 0H${plan.page.width}V${plan.page.height}H0Z`,filled:true,stroked:false,fill_even_odd:false,fill_alpha:1,stroke_alpha:1};
    try{await options.paintPattern(context,resource,p,'fill',{...environments,shapeOnly,paintBounds});}
    finally{context.restore();}
  };
  const drawText=async(context,item,shapeOnly)=>{
    const p=item.paint,stroke=p.filled===false||p.rendering_mode===1||p.rendering_mode===5;
    if((stroke?p.stroke_source:p.fill_source)?.paints===false)return;
    const fragment=stroke?item.text_stroke_svg:item.text_fill_svg;
    const resource=stroke?p.stroke_pattern:p.pattern;
    let svg=fragment||item.text_svg;
    if(!svg)throw new Error('Text paint is missing its A1 source fragment');
    if(fragment||resource){
      svg=svg.replace(/((?:fill-|stroke-)?opacity)="[^"]*"/g,'$1="1"');
      context.globalAlpha=environments.component!==undefined||shapeOnly&&(!p.alpha_is_shape||inkMode)?1:(stroke?p.stroke_alpha:p.fill_alpha);
    }else if(shapeOnly&&(!p.alpha_is_shape||inkMode))svg=svg.replace(/((?:fill-|stroke-)?opacity)="[^"]*"/g,'$1="1"');
    const bounds=p.bounds,pad=textPaintPadding(p);
    const x=bounds.min_x-plan.page.origin_x-pad,y=plan.page.origin_y+plan.page.height-bounds.max_y-pad;
    const w=Math.max(1,bounds.max_x-bounds.min_x+2*pad),h=Math.max(1,bounds.max_y-bounds.min_y+2*pad);
    svg=svg.replace(/<svg[^>]*>/,`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="${x} ${y} ${w} ${h}">`);
    const glyph=await glyphImage(svg,w,h);
    try{context.drawImage(glyph.value,x,y,w,h);}finally{if(!glyph.cached)releaseImage(glyph.value);}
    if(resource)await patternThroughMask(context,resource,shapeOnly);
  };
  const drawImage=async(context,p,shapeOnly)=>{
    const r=p.resource;
    if(r?.ink_samples?.source_colour?.paints===false||r?.mask_data_uri&&p.fill_source?.paints===false)return;
    if(r?.error) throw new Error(`Image ${p.name}: ${r.error}`);
    if (!r?.data_uri && !r?.mask_data_uri) throw new Error(`Image ${p.name} has no decoded source`);
    const q=p.quad, x=q.p1.x-plan.page.origin_x,y=plan.page.origin_y+plan.page.height-q.p1.y;
    context.transform(q.p2.x-q.p1.x,q.p1.y-q.p2.y,q.p0.x-q.p1.x,q.p1.y-q.p0.y,x,y);
    pdfApplyImageSampling(context,Math.max(r.width||1,r.alpha_mask_width||0),Math.max(r.height||1,r.alpha_mask_height||0),r.interpolate,options.devicePixelRatio||1);
    context.globalAlpha=environments.component!==undefined||shapeOnly&&(!p.alpha_is_shape||inkMode)?1:p.fill_alpha;
    if (r.mask_data_uri) {
      const maskImage=await image(r.mask_data_uri),iw=r.width || maskImage.width,ih=r.height || maskImage.height;
      const local=createCanvas(iw,ih),lc=local.getContext('2d',{willReadFrequently:true});
      lc.drawImage(maskImage,0,0,iw,ih); const mask=lc.getImageData(0,0,iw,ih);
      lc.fillStyle=shapeOnly?'#000':p.fill_color;lc.fillRect(0,0,iw,ih);const color=lc.getImageData(0,0,iw,ih);
      for(let i=0;i<color.data.length;i+=4) color.data[i+3]=mask.data[i]*mask.data[i+3]/255;
      lc.putImageData(color,0,0);
      try{pdfDrawImage(context,local,createCanvas);if(p.pattern)await patternThroughMask(context,p.pattern,shapeOnly);}
      finally{local.width=1;}
      return;
    }
    if(shapeOnly&&!r.alpha_is_explicit_shape&&!p.alpha_is_shape){context.fillStyle='#000';context.fillRect(0,0,1,1);return;}

    const retained=environments.component!==undefined||compositor.colour.profileId||compositor.colour.calibration;
    const decoded=retained?imageComponent(r,environments.component):await image(r.data_uri);
    if(retained){pdfDrawImage(context,decoded,createCanvas);return;}
    if (r.alpha_mask_data_uri || r.mask_data_uri) {
      const iw=r.width || decoded.width,ih=r.height || decoded.height;
      const local=createCanvas(iw,ih),lc=local.getContext('2d',{willReadFrequently:true});
      lc.drawImage(decoded,0,0,iw,ih);
      // Image-local masks are handled here only when they were not already
      // integrated into decoded RGBA by MoonBit. ExtGState masks stay separate.
      for (const uri of [r.alpha_mask_data_uri,r.mask_data_uri].filter(Boolean)) {
        const maskImage=await image(uri),mc=createCanvas(iw,ih),mx=mc.getContext('2d',{willReadFrequently:true});
        mx.drawImage(maskImage,0,0,iw,ih); const m=mx.getImageData(0,0,iw,ih),s=lc.getImageData(0,0,iw,ih);
        for(let i=0;i<s.data.length;i+=4) s.data[i+3]*=(m.data[i]*0.3+m.data[i+1]*0.59+m.data[i+2]*0.11)/255*m.data[i+3]/255;
        lc.putImageData(s,0,0);
      }
      pdfDrawImage(context,local,createCanvas);
    } else pdfDrawImage(context,decoded,createCanvas);
  };
  const paintRegion=item=>{
    if(item.type3_plan&&!options.fullSceneReplay)return sceneRegion(item.type3_plan);
    let x=0,y=0,w=width,h=height;
    const b=item.paint.bounds;
    if(b && item.kind!=='shading' && !item.type3_plan) {
      const points=[[b.min_x,b.min_y],[b.min_x,b.max_y],[b.max_x,b.min_y],[b.max_x,b.max_y]].map(([px,py])=>{
        const lx=px-plan.page.origin_x,ly=plan.page.origin_y+plan.page.height-py;
        return [matrix[0]*lx+matrix[2]*ly+matrix[4],matrix[1]*lx+matrix[3]*ly+matrix[5]];
      });
      const stroke=item.paint.stroke,t=stroke?.transform || [1,0,0,1,0,0];
      const strokeScale=Math.max(Math.hypot(t[0],t[1]),Math.hypot(t[2],t[3]));
      const scale=Math.max(Math.hypot(matrix[0],matrix[1]),Math.hypot(matrix[2],matrix[3]));
      const pad=3+scale*Math.max(item.paint.glyph_transform?textPaintPadding(item.paint):0,item.paint.stroked?(stroke?.line_width || item.paint.line_width || 1)*strokeScale*(stroke?.miter_limit || 10):0);
      x=Math.max(0,Math.floor(Math.min(...points.map(p=>p[0]))-pad));y=Math.max(0,Math.floor(Math.min(...points.map(p=>p[1]))-pad));
      w=Math.max(0,Math.min(width,Math.ceil(Math.max(...points.map(p=>p[0]))+pad))-x);h=Math.max(0,Math.min(height,Math.ceil(Math.max(...points.map(p=>p[1]))+pad))-y);
    }
    return {x,y,width:w,height:h};
  };
  const raster=async(item,bounds,component=undefined,paintKey={})=>{
    const region=paintRegion(item);environments.paintBounds=region;
    environments.shadingBounds=!options.fullShadingReplay&&item.kind==='shading'&&!item.paint.shading?.pattern_plan
      ?shadingClipRegion(item.paint.clips,matrix,width,height):null;
    environments.component=component;environments.colourSpace=compositor.colour.space;environments.paintKey=paintKey;
    const frame=compositor.frames.at(-1);
    environments.backdrop=frame.knockout?frame.initial:frame.pixels;
    environments.blendSpace=frame.color_space;
    environments.backdropFormat=inkMode?'ink-premultiplied':'rgba-premultiplied';
    environments.inheritedWorkingBytes=retainedWorkingBytes();
    environments.calibration=compositor.colour.calibration;environments.iccProfileId=compositor.colour.profileId;environments.convertToGroup=compositor.colour.convert;environments.profileScope=options._profileScope;
    environments.convertFromGroup=compositor.colour.toRgb;
    // Shape first gives per-paint pattern/scene caches a bound that includes
    // low-opacity antialias fringes which may round to zero in the colour pass.
    for(const [context,shapeOnly] of [[shapeCtx,true],[ctx,false]]) {
      context.setTransform(1,0,0,1,0,0); context.clearRect(0,0,width,height); context.save();
      clips(context,item.paint,bounds);
      if(item.kind==='path') await drawPath(context,item.paint,shapeOnly);
      else if(item.kind==='image') await drawImage(context,item.paint,shapeOnly);
      else if(item.kind==='text'&&item.type3_plan){
        context.globalAlpha=component!==undefined||shapeOnly&&(!item.paint.alpha_is_shape||inkMode)?1:item.paint.fill_alpha;
        await environments.paintScene(context,item.type3_plan,{shapeOnly,component});
      }
      else if(item.kind==='text') {
        await drawText(context,item,shapeOnly);
      } else if(item.kind==='shading') {
        if(!options.paintShading) throw new Error('Canvas shading paint requires the shading adapter');
        const paint=component===undefined?item.paint:{...item.paint,fill_alpha:1,stroke_alpha:1};
        await options.paintShading(context,item.paint.shading,paint,{...environments,shapeOnly});
      } else throw new Error(`Unknown PDF source paint: ${item.kind}`);
      context.restore();
      for(const value of uncachedImages)releaseImage(value);uncachedImages.clear();
    }
    const {x,y,width:w,height:h}=region;
    if(previousSourceRegion){const r=previousSourceRegion;for(let y=r.y;y<r.y+r.height;y++){const a=y*width+r.x,b=a+r.width;sourcePixels.fill(0,a*4,b*4);sourceShape.fill(0,a,b);}}
    previousSourceRegion={x,y,width:w,height:h};
    if(w&&h){
      const color=ctx.getImageData(x,y,w,h).data,shape=shapeCtx.getImageData(x,y,w,h).data;
      for(let yy=0;yy<h;yy++)for(let xx=0;xx<w;xx++){
        const src=(yy*w+xx)*4,p=(y+yy)*width+x+xx,dst=p*4,a=color[src+3]/255;
        sourcePixels[dst]=color[src]/255*a;sourcePixels[dst+1]=color[src+1]/255*a;sourcePixels[dst+2]=color[src+2]/255*a;sourcePixels[dst+3]=a;
        sourceShape[p]=shape[src+3]/255;
      }
    }
    return {pixels:sourcePixels,shape:sourceShape,dirty:options.fullSurfaceReplay?{x:0,y:0,width,height}:previousSourceRegion};
  };
  // PatternType2 and other retained elementary scenes use the same backend,
  // with the active source backdrop and original group component domain.
  const sceneFields=new WeakMap();
  const sceneRegion=(scene,depth=0)=>{
    const full={x:0,y:0,width,height},page=scene.page;
    if(depth>16||scene.annotation_svg||scene.diagnostics?.length||['origin_x','origin_y','width','height'].some(key=>page[key]!==plan.page[key]))return full;
    let left=width,top=height,right=0,bottom=0;
    for(const item of scene.items){
      const r=item.type3_plan?sceneRegion(item.type3_plan,depth+1):paintRegion(item);
      if(!r.width||!r.height)continue;
      left=Math.min(left,r.x);top=Math.min(top,r.y);right=Math.max(right,r.x+r.width);bottom=Math.max(bottom,r.y+r.height);
    }
    return right>left&&bottom>top?{x:left,y:top,width:right-left,height:bottom-top}:{x:0,y:0,width:0,height:0};
  };
  environments.paintScene=async(context,scenePlan,{shapeOnly=false,component=environments.component}={})=>{
    const key=environments.paintKey;
    let scenes=sceneFields.get(key);if(!scenes){scenes=new Map();sceneFields.set(key,scenes);}
    let field=scenes.get(scenePlan);
    if(!field){
      const colour=compositor.colour,ink=colour.components===4,stride=ink?compositor.stride:4;
      if(ink&&stride!==5)throw new Error('Retained scenes with spot proof need a full colorant-vector transform');
      const region=options.fullSceneReplay?{x:0,y:0,width,height}:sceneRegion(scenePlan),w=region.width,h=region.height;
      if(!w||!h)return;
      const nested={...scenePlan,blend_profile_id:colour.profileId,blend_calibration:colour.calibration,page:{...scenePlan.page,blend_space:colour.space}};
      const backdrop=new Float32Array(w*h*stride);
      for(let y=0;y<h;y++)backdrop.set(environments.backdrop.subarray(((y+region.y)*width+region.x)*stride,((y+region.y)*width+region.x+w)*stride),y*w*stride);
      const localMatrix=[...matrix];localMatrix[4]-=region.x;localMatrix[5]-=region.y;
      const target=createCanvas(w,h);
      const rendered=await renderPdfCanvas(target,nested,{...options,_nativeClipBounds:[],_glyphCacheReserved:true,_imageCacheReserved:true,createCanvas,loadImage,Path2D:Path,width:w,height:h,matrix:localMatrix,transparent:true,backdrop,returnInks:ink,outputGroupComponents:true,_profileScope:options._profileScope,_resourceDepth:resourceDepth+1,_inheritedWorkingBytes:retainedWorkingBytes()+w*h*(stride*4+24)});
      diagnostics.push(...rendered.diagnostics);target.width=1;
      const pixels=ink?rendered.inkProof?.premultiplied:rendered.premultiplied;
      if(!pixels||pixels.length!==w*h*stride)throw new Error('Retained scene lost its group component samples');
      field={pixels,shape:rendered.shape,stride,region,bitmaps:new Map()};scenes.set(scenePlan,field);
    }
    const name=shapeOnly?'shape':component??'colour';
    let bitmap=field.bitmaps.get(name);
    if(!bitmap){
      const {width:w,height:h}=field.region;
      bitmap=createCanvas(w,h);const target=bitmap.getContext('2d'),data=target.createImageData(w,h);
      if(shapeOnly){for(let p=0;p<w*h;p++)data.data[p*4+3]=field.shape[p]*255;}
      else if(component!==undefined){
        for(let p=0;p<w*h;p++){const i=p*field.stride,a=field.pixels[i+field.stride-1],v=a?field.pixels[i+component]/a*255:0;data.data[p*4]=data.data[p*4+1]=data.data[p*4+2]=v;data.data[p*4+3]=a*255;}
      }else data.data.set(premultipliedToRgba8(field.pixels));
      target.putImageData(data,0,0);field.bitmaps.set(name,bitmap);
    }
    context.save();context.setTransform(1,0,0,1,0,0);context.drawImage(bitmap,field.region.x,field.region.y);context.restore();
  };
  const maskCache=new Map();
  const maskSamples=async mask=>{
    if(!mask) return null;
    if(maskCache.has(mask)){const cached=maskCache.get(mask);maskCache.delete(mask);maskCache.set(mask,cached);return cached;}
    if(!mask.plan) throw new Error('ExtGState soft mask is missing its structured form paint plan');
    const target=createCanvas(width,height);
    const pdfMatrix=multiplyMatrix(matrix,[1,0,0,-1,-plan.page.origin_x,plan.page.origin_y+plan.page.height]);
    const maskMatrix=multiplyMatrix(pdfMatrix,multiplyMatrix(mask.matrix || [1,0,0,1,0,0],pageFlip(mask.plan.page)));
    const rendered=await renderPdfCanvas(target,mask.plan,{...options,_nativeClipBounds:[],_glyphCacheReserved:true,_imageCacheReserved:true,createCanvas,loadImage,Path2D:Path,width,height,matrix:maskMatrix,transparent:true,returnInks:true,backdrop:null,outputGroupComponents:false,_maskBackdrop:mask.luminosity?(mask.backdrop_components||mask.backdrop):null,_resourceDepth:resourceDepth+1,_inheritedWorkingBytes:retainedWorkingBytes()});
    diagnostics.push(...rendered.diagnostics);
    const samples=softMaskSamples(rendered.premultiplied,mask);
    target.width=1;
    const cacheLimit=Math.min(67108864,Math.max(0,Math.floor(availableBytes/4)));
    while(maskCache.size&&maskCacheBytes+samples.byteLength>cacheLimit){const oldest=maskCache.keys().next().value;maskCacheBytes-=maskCache.get(oldest).byteLength;maskCache.delete(oldest);}
    if(samples.byteLength<=cacheLimit){maskCache.set(mask,samples);maskCacheBytes+=samples.byteLength;}
    return samples;
  };
  const updatePlates=(item,source,mask,depth)=>{
    if(!plates)return false;
    const p=item.paint,overprint=p.filled===false?p.stroke_overprint:p.fill_overprint;
    if(overprint&&(depth!==0 || p.blend_mode!=='normal' || mask || item.pattern || item.stroke_pattern || p.shading_pattern)) {
      throw new Error('Overprint with transparency groups, masks, patterns, or non-Normal blending needs an ink-space group transform');
    }
    if(depth!==0)return false;
    markCoverage(source.shape);
    const color=p.filled===false?p.stroke_source:p.fill_source;
    const alpha=p.filled===false?p.stroke_alpha:p.fill_alpha;
    if(item.kind==='image'||item.kind==='shading'||item.pattern||item.stroke_pattern||p.shading_pattern||mask||p.blend_mode!=='normal'||alpha!==1){
      if(overprint)throw new Error('Overprint with partial opacity or a raster source needs retained per-pixel ink samples');
      invalidateColourPlaneSurface(plates,plateCoverage,'paint has no compatible opaque ink-space source');return false;
    }
    const status=paintColourPlaneSurface(plates,color,plateCoverage,{overprint,mode:p.overprint_mode,alpha,convertToProcess:options.convertToProcess});
    if(!overprint)return false;
    if(!status.supported)throw new Error(status.reason);
    if(!options.convertProcess)throw new Error('Process overprint requires the shared CMYK colour conversion callback');
    for(let q=0;q<source.shape.length;q++)if(source.shape[q]>0&&!plates.valid[q])throw new Error('Overprint backdrop contains colours without a source-to-process transform');
    const resolved=resolveColourPlaneSurface(plates,options.convertProcess,options.convertAllColorants);
    if(resolved.unsupportedPixels) {
      for(let q=0;q<source.shape.length;q++)if(source.shape[q]>0&&resolved.rgba[q*4+3]===0&&plates.alpha[q]>0)throw new Error('Spot overprint needs an output transform for the complete colorant vector');
    }
    const frame=compositor.frames.at(-1);compositor.touch(source.dirty);
    for(let q=0,i=0;q<source.shape.length;q++,i+=4)if(source.shape[q]>0){
      const a=resolved.rgba[i+3]/255;
      for(let c=0;c<3;c++)frame.pixels[i+c]=resolved.rgba[i+c]/255*a;
      frame.pixels[i+3]=a;frame.alpha[q]=a;frame.shape[q]=plates.shape[q];
    }
    return true;
  };
  const paintSource=async(part,bounds,depth,overrideMask=undefined)=>{
    // Tiled replay keeps the complete group hierarchy, but a source outside
    // this tile has no colour or shape coverage and needs no raster or mask.
    if(!options.fullSurfaceReplay){const r=paintRegion(part);if(!r.width||!r.height)return;}
    const p=part.paint,stroke=p.filled===false||(part.kind==='text'&&(p.rendering_mode===1||p.rendering_mode===5));
    const patterned=stroke?p.stroke_pattern:p.pattern||p.shading_pattern;
    const sampled=inkMode&&(part.type3_plan||part.kind==='shading'||part.kind==='image'&&!p.resource?.mask_data_uri||patterned);
    const paintKey={};
    try {
    const source=await raster(part,bounds,sampled?0:undefined,paintKey);
    // An image's own explicit/soft mask replaces the graphics-state SMask.
    const mask=part.kind==='image'&&part.paint.resource?.has_local_mask?null:overrideMask===undefined?await maskSamples(part.mask || part.paint.soft_mask):overrideMask;
    if(inkMode){
      if(sampled){
        const pixels=compositor.borrowSource(source.dirty).pixels;
        for(let c=0;c<4;c++){
          if(c)await raster(part,bounds,c,paintKey);
          const r=source.dirty;
          for(let y=r.y;y<r.y+r.height;y++)for(let x=r.x,q=y*width+x;x<r.x+r.width;x++,q++){
            pixels[q*compositor.stride+c]=source.pixels[q*4];
            if(c===0)pixels[q*compositor.stride+compositor.channels]=source.pixels[q*4+3];
          }
        }
        compositor.paintProcess(pixels,source.shape,{alpha:stroke?p.stroke_alpha:p.fill_alpha,mask,alpha_is_shape:p.alpha_is_shape,overprint:stroke?p.stroke_overprint:p.fill_overprint,blend_mode:p.blend_mode,dirty:source.dirty});return;
      }
      compositor.paintColour(stroke?p.stroke_source:p.fill_source,source.shape,{alpha:stroke?p.stroke_alpha:p.fill_alpha,mask,alpha_is_shape:p.alpha_is_shape,overprint:stroke?p.stroke_overprint:p.fill_overprint,overprint_mode:p.overprint_mode,blend_mode:p.blend_mode,dirty:source.dirty});return;
    }
    if((compositor.colour.profileId||compositor.colour.calibration)&&(['path','text'].includes(part.kind)||part.kind==='image'&&part.paint.resource?.mask_data_uri)&&!patterned&&!part.type3_plan){
      const values=compositor.colour.convert(stroke?p.stroke_source:p.fill_source);
      const r=source.dirty;
      for(let y=r.y;y<r.y+r.height;y++)for(let x=r.x,i=(y*width+x)*4;x<r.x+r.width;x++,i+=4)for(let c=0;c<3;c++)source.pixels[i+c]=values[Math.min(c,values.length-1)]*source.pixels[i+3];
    }
    let handled=false;
    try { handled=updatePlates(part,source,mask,depth); }
    catch(error){
      if(options.unsupported!=='warn')throw error;
      diagnostics.push({code:'PDF_OVERPRINT_UNSUPPORTED',page:plan.page.number,item:part.paint.index,reason:String(error.message || error)});
    }
    if(!handled){
      if(compositor.colour.components===1) {const r=source.dirty;for(let y=r.y;y<r.y+r.height;y++)for(let x=r.x,p=(y*width+x)*4;x<r.x+r.width;x++,p+=4){const gray=source.pixels[p]*.3+source.pixels[p+1]*.59+source.pixels[p+2]*.11;source.pixels[p]=source.pixels[p+1]=source.pixels[p+2]=gray;}}
      compositor.paint(source.pixels,source.shape,{blend_mode:part.paint.blend_mode,mask,alpha_is_shape:part.paint.alpha_is_shape,dirty:source.dirty});
    }
    } finally {
      const scenes=sceneFields.get(paintKey);
      if(scenes){for(const field of scenes.values())for(const bitmap of field.bitmaps.values())bitmap.width=1;sceneFields.delete(paintKey);}
      options.paintPattern?.releasePaint?.(paintKey);
    }
  };
  const visibleSources=(items,start,end)=>{
    if(options.fullSurfaceReplay)return true;
    for(let i=start;i<end;i++){const r=paintRegion(items[i]);if(r.width&&r.height)return true;}
    return false;
  };
  const drawAnnotations=async output=>{
    if(!plan.annotation_svg&&!plan.annotation_fragments?.length)return;
    // Rasterize annotation vectors at the output density before placing them
    // in logical page space, so AP text and edges retain their print/DPR detail.
    const fragments=plan.annotation_fragments || [{svg:plan.annotation_svg,x:0,y:0,width:plan.page.width,height:plan.page.height}];
    for(const fragment of fragments){
      let placement=matrix;
      if(fragment.no_zoom||fragment.no_rotate){
        const anchor=fragment.anchor,logicalScale=plan.viewport.scale*(plan.page.user_unit||1);
        let a=matrix[0],b=matrix[1],c=matrix[2],d=matrix[3];
        if(fragment.no_rotate){const sx=Math.hypot(a,b),sy=Math.hypot(c,d);a=sx;b=0;c=0;d=sy;}
        if(fragment.no_zoom){a/=logicalScale;b/=logicalScale;c/=logicalScale;d/=logicalScale;}
        placement=[a,b,c,d,matrix[0]*anchor[0]+matrix[2]*anchor[1]+matrix[4]-a*anchor[0]-c*anchor[1],matrix[1]*anchor[0]+matrix[3]*anchor[1]+matrix[5]-b*anchor[0]-d*anchor[1]];
      }
      const aw=Math.max(1,Math.ceil(fragment.width*Math.hypot(placement[0],placement[1])));
      const ah=Math.max(1,Math.ceil(fragment.height*Math.hypot(placement[2],placement[3])));
      if(aw*ah*4>availableBytes)throw new RangeError('PDF annotation raster exceeds the working memory budget');
      const svg=fragment.svg.replace(/(<svg\b[^>]*\bwidth=")[^"]*(")/,`$1${aw}$2`).replace(/(<svg\b[^>]*\bheight=")[^"]*(")/,`$1${ah}$2`);
      output.save();output.setTransform(...placement);output.globalCompositeOperation=fragment.blend||'source-over';
      const uri=svgUri(svg);
      const raster=options._imageCache&&aw*ah<=(options.maxPixels||16777216)?await image(uri):await loadImage(uri);
      try{output.drawImage(raster,fragment.x,fragment.y,fragment.width,fragment.height);}
      finally{if(!options._imageCache||images.get(uri)?.value!==raster){uncachedImages.delete(raster);releaseImage(raster);}output.restore();}
    }
  };
  let yieldDeadline=performance.now()+12;
  const walk=async(items,depth,bounds=[],textScope=null)=>{
    for(let i=0;i<items.length;){
      checkPdfRender(options);
      if(options.yieldToHost&&performance.now()>=yieldDeadline){
        await options.yieldToHost();checkPdfRender(options);yieldDeadline=performance.now()+12;
      }
      const group=groupAt(items[i],depth);
      if(group){
        let end=i+1; while(end<items.length&&groupAt(items[end],depth)?.id===group.id)end++;
        if(!visibleSources(items,i,end)){i=end;continue;}
        const parentEngine=compositor,parentInkMode=inkMode,parent=compositor.frames.at(-1);
        // Nonisolated groups inherit their parent's blend space (ISO 11.7.2).
        const space=(group.isolated?(group.color_space||parent.color_space):parent.color_space).replace(/^\//,'');
        const profileId=group.isolated&&group.color_space?(group.icc_profile_id||null):parentEngine.colour.profileId;
        const calibration=group.isolated&&group.color_space?(group.calibration||null):parentEngine.colour.calibration;
        const separate=group.isolated&&(space!==parent.color_space||profileId!==parentEngine.colour.profileId||JSON.stringify(calibration)!==JSON.stringify(parentEngine.colour.calibration));
        if(separate){
          const retained=parentEngine.workingBytes();
          compositor=createCompositor(space,(parentInkMode?parentEngine.maxBytes:parentEngine.maxWorkingBytes)-retained,profileId,group.rendering_intent,calibration);inkMode=space==='DeviceCMYK';
        }
        compositor.beginGroup({...group,color_space:space},separate?null:(parent.knockout?parent.initial:parent.pixels));
        await walk(items.slice(i,end),depth+1,group.bounds?[...bounds,group.bounds]:bounds);
        const result=compositor.endGroup({recycle:!separate});
        if(separate){
          if((inkMode&&compositor.channels!==4)||(parentInkMode&&parentEngine.channels!==4))throw new Error('Cross-space spot proof groups require a complete colorant-vector transform');
          result.pixels=convertGroupSurface(result.pixels,compositor.colour,parentEngine.colour,group.rendering_intent);
          releaseCompositor(compositor);compositor=parentEngine;inkMode=parentInkMode;
          if(parentEngine.colour.components===1)for(let p=0;p<result.pixels.length;p+=4){const gray=result.pixels[p]*.3+result.pixels[p+1]*.59+result.pixels[p+2]*.11;result.pixels[p]=result.pixels[p+1]=result.pixels[p+2]=gray;}
        }
        compositor.paint(result.pixels,result.shape,{...group,mask:await maskSamples(group.soft_mask),dirty:result.dirty});compositor.releaseGroup(result);
        if(plates&&depth===0){markCoverage(result.shape);invalidateColourPlaneSurface(plates,plateCoverage,'group has no retained ink-space result');}
        i=end;
      } else {
        const candidate=items[i],textId=candidate.kind==='text'&&candidate.paint.text_object_id;
        if(textId&&candidate.paint.text_knockout!==false&&textScope!==textId){
          let end=i+1;
          while(end<items.length&&items[end].kind==='text'&&items[end].paint.text_object_id===textId&&!groupAt(items[end],depth))end++;
          if(!visibleSources(items,i,end)){i=end;continue;}
          const parent=compositor.frames.at(-1);
          compositor.beginGroup({isolated:false,knockout:true,color_space:parent.color_space},parent.knockout?parent.initial:parent.pixels);
          await walk(items.slice(i,end),depth,bounds,textId);
          const result=compositor.endGroup({recycle:true});
          compositor.paint(result.pixels,result.shape,{dirty:result.dirty});compositor.releaseGroup(result);
          i=end;continue;
        }
        const raw=items[i++];
        let item={...raw,paint:{...raw.paint,pattern:raw.pattern || raw.paint.pattern,stroke_pattern:raw.stroke_pattern || raw.paint.stroke_pattern}};
        // A retained Type3 charproc inherits the complete graphics state;
        // internal gs operators replace it, so it must not be applied again
        // as an outer glyph opacity/blend/mask after extracting the scene.
        if(item.kind==='text'&&item.type3_plan&&options.returnPixels===false&&options.nativeCanvas!==false&&!options.fullSceneReplay&&!inkMode&&!compositor.colour.profileId&&!compositor.colour.calibration)item=singleType3Path(item,plan.page)||item;
        if(item.kind==='text'&&item.type3_plan)item={...item,mask:null,paint:{...item.paint,fill_alpha:1,stroke_alpha:1,blend_mode:'normal',soft_mask:null,alpha_is_shape:false,fill_overprint:false,stroke_overprint:false}};
        // A1 provides the glyph outline with only the graphics CTM removed.
        // Replay that same geometry directly, avoiding an SVG bitmap resample.
        const pen=item.kind==='text'&&item.paint.stroke;
        if(item.kind==='text'&&!item.type3_plan){
          const mode=item.paint.rendering_mode,filled=[0,2,4,6].includes(mode),stroked=[1,2,5,6].includes(mode);
          if(item.paint.fill_path!==null&&item.paint.fill_path!==undefined)item={...item,kind:'path',paint:{...item.paint,svg_path:item.paint.fill_path,filled,stroked,stroke_alpha:pen?.stroke_alpha??item.paint.stroke_alpha,line_cap:pen?.line_cap,line_join:pen?.line_join}};
          else if(pen?.svg_path!==null&&pen?.svg_path!==undefined)item={...item,kind:'path',paint:{...item.paint,svg_path:pen.svg_path,fill_transform:pen.transform,filled,stroked,stroke_alpha:pen.stroke_alpha,line_cap:pen.line_cap,line_join:pen.line_join}};
          else if(item.text_fill_svg&&item.text_stroke_svg)item={...item,paint:{...item.paint,filled,stroked,stroke_alpha:pen?.stroke_alpha??item.paint.stroke_alpha}};
        }
        if((item.kind==='path'||item.kind==='text'&&item.text_fill_svg&&item.text_stroke_svg)&&item.paint.filled&&item.paint.stroked){
          const p=item.paint,equalOverprint=p.fill_overprint&&p.stroke_overprint&&p.fill_alpha===p.stroke_alpha;
          // PDF B/B*/b/b*: fill and stroke form one elementary object. Their
          // overlap must not accumulate alpha twice (PDF 1.4, 7.6.3).
          const parent=compositor.frames.at(-1);
          compositor.beginGroup({isolated:false,knockout:!equalOverprint,color_space:parent.color_space},parent.knockout?parent.initial:parent.pixels);
          const inner=equalOverprint?{...p,fill_alpha:1,stroke_alpha:1,blend_mode:'normal',alpha_is_shape:false}:p;
          await paintSource({...item,paint:{...inner,stroked:false}},bounds,depth+1,equalOverprint?null:undefined);
          await paintSource({...item,paint:{...inner,filled:false}},bounds,depth+1,equalOverprint?null:undefined);
          const joined=compositor.endGroup({recycle:true});
          compositor.paint(joined.pixels,joined.shape,{alpha:equalOverprint?p.fill_alpha:1,blend_mode:equalOverprint?p.blend_mode:'normal',mask:equalOverprint?await maskSamples(item.mask || p.soft_mask):null,alpha_is_shape:equalOverprint?p.alpha_is_shape:false,dirty:joined.dirty});compositor.releaseGroup(joined);
        }else await paintSource(item,bounds,depth);
      }
    }
  };
  if(nativeItems){
    canvas.width=width;canvas.height=height;
    const output=canvas.getContext('2d');
    if(!options.transparent){output.fillStyle='#fff';output.fillRect(0,0,width,height);}
    for(const item of nativeItems){
      checkPdfRender(options);
      if(options.yieldToHost&&performance.now()>=yieldDeadline){await options.yieldToHost();checkPdfRender(options);yieldDeadline=performance.now()+12;}
      output.save();
      try{
        if(item.kind==='retained'){
          const r=sceneRegion(item.scene);
          if(r.width&&r.height){
            const target=createCanvas(r.width,r.height),localMatrix=[...matrix];localMatrix[4]-=r.x;localMatrix[5]-=r.y;
            try{
              const rendered=await renderPdfCanvas(target,item.scene,{...options,_nativePageDisabled:!item.native,width:r.width,height:r.height,matrix:localMatrix,
                maxDepth:(options.maxDepth??32)-(item.native?1:0),
                _nativeClipBounds:[...(options._nativeClipBounds||[]),...(item.nativeClipBounds||[]),...(item.native&&item.bounds?[item.bounds]:[])],
                transparent:true,_glyphCacheReserved:true,_imageCacheReserved:true,_inheritedWorkingBytes:retainedWorkingBytes()});
              diagnostics.push(...rendered.diagnostics);checkPdfRender(options);
              output.setTransform(1,0,0,1,0,0);output.globalAlpha=item.alpha??1;output.drawImage(target,r.x,r.y);
            }finally{target.width=target.height=1;}
          }
        }else{
          environments.paintBounds=paintRegion(item);
          environments.inheritedWorkingBytes=retainedWorkingBytes();
          clips(output,item.paint,item.nativeClipBounds||[]);
          if(item.kind==='path')await drawPath(output,item.paint,false);
          else if(item.kind==='image')await drawImage(output,item.paint,false);
          else await drawText(output,item,false);
        }
      }finally{output.restore();}
      for(const value of uncachedImages)releaseImage(value);uncachedImages.clear();
    }
    checkPdfRender(options);await drawAnnotations(output);checkPdfRender(options);
    return {width,height,diagnostics,native:true,blendCapabilities:compositor.capabilities};
  }
  if(options.backdrop&&options.backdrop.length!==width*height*(inkMode?compositor.stride:4))throw new RangeError('PDF initial backdrop dimensions differ');
  compositor.beginGroup({isolated:!options.backdrop,color_space:plan.page.blend_space || 'DeviceRGB'},options.backdrop || null);
  // The PDF page is an isolated group. A viewer's white paper belongs below
  // the completed page, not in the backdrop of its internal blend functions.
  await walk(plan.items,0);
  const result=compositor.endGroup(),inkProof=inkMode&&options.returnInks?{names:compositor.names,stride:compositor.stride,premultiplied:result.pixels}:null;
  const groupProof=options.returnGroupComponents?{colour:compositor.colour,pixels:result.pixels}:null;
  if(options._maskBackdrop){
    const bc=options._maskBackdrop,n=compositor.colour.components,stride=inkMode?compositor.stride:4;
    if(bc.length!==n)throw new Error('Soft-mask BC does not match its group colour space');
    result.pixels=result.pixels.slice();
    for(let p=0;p<width*height;p++){
      const a=result.pixels[p*stride+stride-1];
      for(let c=0;c<stride-1;c++)result.pixels[p*stride+c]+=(c<n?bc[c]:inkMode?0:bc[0])*(1-a);
      result.pixels[p*stride+stride-1]=1;
    }
  }
  if(inkMode)result.pixels=compositor.toRgb(result.pixels);
  else if((compositor.colour.profileId||compositor.colour.calibration)&&!options.outputGroupComponents)result.pixels=groupSurfaceToRgb(result.pixels,compositor.colour);
  if(!options.transparent) for(let i=0;i<result.pixels.length;i+=4){
    const white=1-result.pixels[i+3];
    for(let c=0;c<3;c++)result.pixels[i+c]+=white;
    result.pixels[i+3]=1;
  }
  let bytes=premultipliedToRgba8(result.pixels);
  canvas.width=width;canvas.height=height;
  const output=canvas.getContext('2d'),data=output.createImageData(width,height);data.data.set(bytes);output.putImageData(data,0,0);
  if(plan.annotation_svg||plan.annotation_fragments?.length){
    await drawAnnotations(output);
    bytes=output.getImageData(0,0,width,height).data;
    rgba8ToPremultiplied(bytes,result.pixels);
  }
  layer.width=shapeLayer.width=1;
  if(inkImageCache)inkImageCache.canvas.width=1;
  if(compositor.blendCanvas) compositor.blendCanvas.width=1;
  if(compositor.blendSourceCanvas) compositor.blendSourceCanvas.width=1;
  return {width,height,stride:width*4,format:'rgba8-straight',data:bytes,premultiplied:result.pixels,shape:result.shape,blendCapabilities:(inkMode?compositor.kernel:compositor).capabilities,diagnostics,inkProof,groupProof};
  } finally {
    for(const engine of liveCompositors)releaseCompositor(engine);
    if(layer)layer.width=1;if(shapeLayer)shapeLayer.width=1;if(inkImageCache)inkImageCache.canvas.width=1;
    for(const value of uncachedImages)releaseImage(value);
    uncachedImages.clear();
  }
}

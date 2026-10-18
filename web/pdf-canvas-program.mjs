// Compiled glyph resources stay in font coordinates. Reproduce the existing
// positioned path arithmetic at the host boundary, including its bounds map.
// Only the browser compiler emits versions 2/3; public model plans remain 1.
import {expandPdfTextRuns,pdfTextRunStates,pdfTextRunOperands} from './pdf-canvas-text-runs.mjs';
function programResources(plan){
  if(!Array.isArray(plan.glyph_resources)||plan.glyph_resources.length>16384)throw new Error('Invalid PDF glyph resource table');
  const resources=new Map();
  for(const resource of plan.glyph_resources){
    if(!Number.isInteger(resource.id)||resources.has(resource.id)||!Array.isArray(resource.commands)||resource.commands.length>32768||(resource.kind!==undefined&&resource.kind!=='outline'))throw new Error('Invalid PDF glyph resource');
    resources.set(resource.id,resource);
  }
  const shadings=new Map();
  if(plan.shading_resources!==undefined){
    if(!Array.isArray(plan.shading_resources)||plan.shading_resources.length>64)throw new Error('Invalid PDF shading resource table');
    for(const resource of plan.shading_resources){
      if(!Number.isInteger(resource.id)||shadings.has(resource.id)||!resource.raster||typeof resource.raster!=='object'||Array.isArray(resource.raster))throw new Error('Invalid PDF shading resource');
      shadings.set(resource.id,resource.raster);
    }
  }
  return {resources,shadings};
}
export function expandPdfCanvasProgram(plan) {
  if(plan?.version!==2&&plan?.version!==3)return plan;
  const {resources,shadings}=programResources(plan);
  const items=expandPdfTextRuns(plan).map(item=>{
    const shading=item.paint?.shading;
    if(shading?.raster_resource!==undefined){
      if(item.kind!=='shading'||!Number.isInteger(shading.raster_resource)||!shadings.has(shading.raster_resource))throw new Error('Invalid PDF shading invocation');
      const {raster_resource,...resource}=shading;
      item={...item,paint:{...item.paint,shading:{...resource,raster:shadings.get(raster_resource)}}};
    }
    if(!item.glyph)return item;
    const resource=resources.get(item.glyph.resource),m=item.glyph.matrix;
    if(item.kind!=='text'||!resource||!Array.isArray(m)||m.length!==6||!m.every(v=>Number.isFinite(v)&&Math.abs(v)<=1e12))throw new Error('Invalid PDF glyph invocation');
    if(resource.kind==='outline'){
      // Ordinary CFF/Type1/TrueType paths use the font transform directly. Type3's
      // elementary scene applies an additional bounds map below.
      const parts=[],commands=resource.commands;
      for(let i=0;i<commands.length;){
        const op=commands[i++],count=op===0||op===1?2:op===2?6:op===4?4:op===3?0:-1;
        if(count<0||i+count>commands.length)throw new Error('Invalid PDF glyph path');
        parts.push(['M','L','C','Z','Q'][op]);
        for(let end=i+count;i<end;i+=2){
          const x=commands[i],y=commands[i+1];
          if(!Number.isFinite(x)||!Number.isFinite(y)||Math.abs(x)>1e12||Math.abs(y)>1e12)throw new Error('Invalid PDF glyph coordinate');
          parts.push(String(x*m[0]+y*m[2]+m[4]-plan.page.origin_x),String(plan.page.origin_y+plan.page.height-(x*m[1]+y*m[3]+m[5])));
        }
      }
      const {glyph,...expanded}=item;
      return {...expanded,paint:{...item.paint,fill_path:parts.join(' ')}};
    }
    const commands=resource.commands,points=[],ops=[];let minX=Infinity,minY=Infinity,maxX=-Infinity,maxY=-Infinity;
    for(let i=0;i<commands.length;){
      const op=commands[i++],count=op===0||op===1?2:op===2?6:op===3?0:-1;
      if(count<0||i+count>commands.length)throw new Error('Invalid PDF glyph path');
      ops.push(op);
      for(let end=i+count;i<end;i+=2){
        const x=commands[i],y=commands[i+1];
        if(!Number.isFinite(x)||!Number.isFinite(y)||Math.abs(x)>1e12||Math.abs(y)>1e12)throw new Error('Invalid PDF glyph coordinate');
        const px=m[0]*x+m[2]*y+m[4],py=m[1]*x+m[3]*y+m[5];
        points.push([px,py]);minX=Math.min(minX,px);minY=Math.min(minY,py);maxX=Math.max(maxX,px);maxY=Math.max(maxY,py);
      }
    }
    const parts=[];let point=0;
    for(const op of ops){
      parts.push(['M','L','C','Z'][op]);
      for(let count=op===2?3:op===3?0:1;count>0;count--){
        const [px,py]=points[point++],rx=maxX>minX?(px-minX)/(maxX-minX):0,ry=maxY>minY?(py-minY)/(maxY-minY):0;
        const x=minX+rx*(maxX-minX)+ry*0,y=minY+rx*0+ry*(maxY-minY);
        parts.push(String(x-plan.page.origin_x),String(plan.page.origin_y+plan.page.height-y));
      }
    }
    const paint={...item.paint,svg_path:parts.join(' '),stroke:null,filled:true,stroked:false,fill_even_odd:resource.even_odd,
      group:null,group_path:[],bounds:points.length?{min_x:minX,min_y:minY,max_x:maxX,max_y:maxY}:item.paint.bounds};
    delete paint.glyph_transform;
    // Preserve the existing elementary-scene boundary for retained/proof replay.
    // Native replay can flatten the same opaque path through nativeType3Paths.
    const type3_plan={version:1,diagnostics:[],annotation_svg:null,annotation_fragments:[],surface:'rgba8-straight',
      icc_profiles:[],blend_space:'',blend_profile_id:null,blend_calibration:null,
      page:{...plan.page,number:0,blend_space:'',user_unit:1,rotation:0},viewport:plan.viewport,
      items:points.length?[{kind:'path',paint,groups:[],mask:null,pattern:null,stroke_pattern:null}]:[]};
    const {glyph,...expanded}=item;
    return {...expanded,type3_plan};
  });
  const {glyph_resources,shading_resources,text_states,...expanded}=plan;
  return {...expanded,version:1,items};
}

// Native consumers retain the operation/state boundary. Only invoked outline
// coordinates and seven numeric operands per glyph need a render-owned copy.
// Ordinary expansion remains the public, fully materialized version-1 API.
const nativeGlyphRuns=new WeakMap();
export const nativePdfGlyphRun=item=>nativeGlyphRuns.get(item);
export function prepareNativePdfProgram(source,options,selectNative){
  if(source?.version!==3||options.fullGlyphExpansion||options.nativeFillRuns===false||typeof options.resolveTextOutline==='function')return null;
  const {resources}=programResources(source),states=pdfTextRunStates(source),items=[],pending=[];
  for(const item of source.items){
    if(item.kind!=='text_run'){
      if(item.glyph||item.paint?.shading?.raster_resource!==undefined)return null;
      items.push(item);continue;
    }
    const operands=pdfTextRunOperands(item,states),{state,text}=operands;
    const next={...state,kind:'outline_run',paint:{...state.paint}};
    nativeGlyphRuns.set(next,{glyphs:text.length});
    pending.push({item:next,...operands});items.push(next);
  }
  if(!pending.length)return null;
  const {glyph_resources,shading_resources,text_states,...base}=source,plan={...base,version:1,items};
  const native=selectNative(plan,options);if(!native)return null;
  const budget=options.maxWorkingBytes||536870912;
  const width=options.width||Math.ceil(source.viewport.width),height=options.height||Math.ceil(source.viewport.height);
  const glyphBytes=options._glyphCacheReserved?0:options._glyphCache?.limit??Math.max(0,Math.min(options.maxGlyphCacheBytes??16777216,budget/32));
  const imageBytes=options._imageCacheReserved?0:options._imageCache?.limit??Math.max(0,Math.min(options.maxImageCacheBytes??67108864,budget/8));
  const limit=Math.min(8388608,budget/16,budget-(options._inheritedWorkingBytes||0)-glyphBytes-imageBytes-width*height*4),outlines=[],indices=new Map();
  if(!Number.isFinite(limit)||limit<=0)return null;
  let bytes=0;
  for(const {item,data,text}of pending){
    bytes+=1024+text.length*7*8+((item.paint.clips?.length||0)+(options._nativeClipBounds?.length||0))*64;if(bytes>limit)return null;
    const draws=new Float64Array(text.length*7);
    for(let p=0,g=0;p<data.length;p+=29,g+=7){
      const id=data[p+22],resource=resources.get(id);
      if(!resource)throw new Error('Invalid PDF glyph invocation');
      if(resource.kind!=='outline')return null;
      let index=indices.get(id);
      if(index===undefined){
        const commands=resource.commands;
        bytes+=128+commands.length*8;if(bytes>limit)return null;
        const snapshot=new Float64Array(commands.length);
        for(let i=0;i<commands.length;){
          const op=commands[i++],count=op===0||op===1?2:op===2?6:op===4?4:op===3?0:-1;
          if(count<0||i+count>commands.length)throw new Error('Invalid PDF glyph path');
          snapshot[i-1]=op;
          for(let end=i+count;i<end;i++){
            const value=commands[i];
            if(!Number.isFinite(value)||Math.abs(value)>1e12)throw new Error('Invalid PDF glyph coordinate');
            snapshot[i]=value;
          }
        }
        index=outlines.length;indices.set(id,index);outlines.push(snapshot);
      }
      draws[g]=index;
      for(let m=0;m<6;m++){
        const value=data[p+23+m];
        if(!Number.isFinite(value)||Math.abs(value)>1e12)throw new Error('Invalid PDF glyph invocation');
        draws[g+1+m]=value;
      }
    }
    nativeGlyphRuns.set(item,{glyphs:text.length,draws,outlines,originX:source.page.origin_x,flipY:source.page.origin_y+source.page.height});
  }
  return {plan,items:native,bytes};
}

// Keep the legacy positioned-path arithmetic and decimal conversion exactly.
// Paths are consumed one at a time rather than retained for the entire page.
export function nativePdfGlyphPath(run,offset){
  const data=run.draws,commands=run.outlines[data[offset]],parts=[];
  const a=data[offset+1],b=data[offset+2],c=data[offset+3],d=data[offset+4],e=data[offset+5],f=data[offset+6];
  for(let i=0;i<commands.length;){
    const op=commands[i++],count=op===0||op===1?2:op===2?6:op===4?4:0;
    parts.push(['M','L','C','Z','Q'][op]);
    for(let end=i+count;i<end;i+=2){
      const x=commands[i],y=commands[i+1];
      parts.push(String(x*a+y*c+e-run.originX),String(run.flipY-(x*b+y*d+f)));
    }
  }
  return parts.join(' ');
}

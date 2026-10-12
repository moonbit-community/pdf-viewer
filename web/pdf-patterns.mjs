import { renderPdfCanvas, multiplyMatrix } from './pdf-canvas.mjs';
import { PdfCompositor, premultipliedToRgba8 } from './pdf-compositor.mjs';
import { PdfInkCompositor } from './pdf-ink-compositor.mjs';

const inverse = m => {
  const d=m[0]*m[3]-m[1]*m[2];
  if (!Number.isFinite(d) || Math.abs(d)<1e-14) throw new Error('Singular PDF pattern matrix');
  return [m[3]/d,-m[1]/d,-m[2]/d,m[0]/d,(m[2]*m[5]-m[3]*m[4])/d,(m[1]*m[4]-m[0]*m[5])/d];
};
const values=m=>[m.a,m.b,m.c,m.d,m.e,m.f];
const dom=m=>({a:m[0],b:m[1],c:m[2],d:m[3],e:m[4],f:m[5]});

/** Replay complete pattern-cell plans through the same graphics backend.
 * The lattice is anchored in its content stream's base coordinate system,
 * independent from the CTM used to construct/stroke the selected path. */
export function createPatternPainter(options={}) {
  const cache=new WeakMap(), fields=new WeakMap(), cacheOrder=new Map();
  const cacheLimit=Math.max(0,Math.min(options.maxPatternCacheBytes??67108864,(options.maxWorkingBytes??536870912)/4));
  let cacheBytes=0;
  const release=bitmap=>{bitmap.color.width=1;bitmap.shape.width=1;};
  const remember=(sizes,key,bitmap)=>{
    const bytes=bitmap.replay?0:bitmap.color.width*bitmap.color.height*8;
    if(bitmap.replay)release(bitmap);
    while(cacheOrder.size&&(cacheBytes+bytes>cacheLimit||cacheOrder.size>=32)){
      const oldest=cacheOrder.keys().next().value,entry=cacheOrder.get(oldest);
      cacheOrder.delete(oldest);entry.sizes.delete(entry.key);cacheBytes-=entry.bytes;release(oldest);
    }
    bitmap.cached=bytes<=cacheLimit;
    if(bitmap.cached){sizes.set(key,bitmap);cacheOrder.set(bitmap,{sizes,key,bytes});cacheBytes+=bytes;}
  };
  const point=(m,x,y)=>[m[0]*x+m[2]*y+m[4],m[1]*x+m[3]*y+m[5]];
  const shapeCanvas=(shape,width,height,env)=>{
    const canvas=env.createCanvas(width,height),ctx=canvas.getContext('2d'),data=ctx.createImageData(width,height);
    for(let p=0;p<shape.length;p++)data.data[p*4+3]=Math.round(shape[p]*255);
    ctx.putImageData(data,0,0);return canvas;
  };
  const drawField=(context,surface,path,operation,env)=>{
    context.save();
    if(operation==='stroke'){
      const masked=env.createCanvas(env.width,env.height),mask=masked.getContext('2d');
      mask.setTransform(...values(context.getTransform()));
      for(const property of ['lineWidth','lineCap','lineJoin','miterLimit','lineDashOffset'])mask[property]=context[property];
      mask.setLineDash(context.getLineDash());mask.strokeStyle='#000';mask.stroke(env.strokePath||new env.Path2D(path.svg_path));
      mask.setTransform(1,0,0,1,0,0);mask.globalCompositeOperation='source-in';mask.drawImage(surface,0,0);
      context.setTransform(1,0,0,1,0,0);context.drawImage(masked,0,0);masked.width=1;
    }else{
      context.clip(new env.Path2D(path.svg_path),path.fill_even_odd?'evenodd':'nonzero');
      context.setTransform(1,0,0,1,0,0);context.drawImage(surface,0,0);
    }
    context.restore();
  };
  const usesBackdrop=plan=>plan.items.some(item=>{
    const p=item.paint;
    return (p.blend_mode&&p.blend_mode!=='normal')||(item.groups||[]).some(g=>!g.isolated)||
      [item.pattern,item.stroke_pattern,p.pattern,p.stroke_pattern].some(resource=>resource?.tile_plan&&usesBackdrop(resource.tile_plan));
  });
  // Re-evaluate non-isolated cells against the actual device backdrop. A
  // cached transparent tile is not equivalent when a cell uses a blend mode.
  const field=async(resource,patternToDevice,env)=>{
    let resources=env.paintKey&&fields.get(env.paintKey);
    if(!resources&&env.paintKey){resources=new Map();fields.set(env.paintKey,resources);}
    if(resources?.has(resource))return resources.get(resource);
    const {width,height}=env,b=resource.bbox,stepX=Math.abs(resource.x_step),stepY=Math.abs(resource.y_step);
    const ink=env.blendSpace==='DeviceCMYK',stride=ink?5:4;
    if(ink&&env.backdropFormat!=='ink-premultiplied')throw new Error('CMYK pattern needs retained ink backdrop');
    const budget=options.maxWorkingBytes ?? 536870912;
    if(width*height*(stride*12+24)>budget)throw new RangeError('PDF pattern backdrop exceeds working-memory budget');
    const compositor=ink?new PdfInkCompositor(width,height,env.createCanvas,{...options,convertProcess:env.convertFromGroup||options.convertProcess}):new PdfCompositor(width,height,env.createCanvas,options);
    compositor.beginGroup({isolated:!env.backdrop,color_space:ink?'DeviceCMYK':'DeviceRGB'},env.backdrop);
    // Only cells that can affect this paint are needed. In particular a small
    // glyph must not enumerate a fine pattern across its enclosing page.
    const bounds=env.paintBounds||{x:0,y:0,width,height};
    const left=Math.max(0,Math.floor(bounds.x)),top=Math.max(0,Math.floor(bounds.y));
    const right=Math.min(width,Math.ceil(bounds.x+bounds.width)),bottom=Math.min(height,Math.ceil(bounds.y+bounds.height));
    const deviceToPattern=inverse(patternToDevice),corners=[[left,top],[right,top],[left,bottom],[right,bottom]].map(([x,y])=>point(deviceToPattern,x,y));
    const minX=Math.min(...corners.map(p=>p[0])),maxX=Math.max(...corners.map(p=>p[0]));
    const minY=Math.min(...corners.map(p=>p[1])),maxY=Math.max(...corners.map(p=>p[1]));
    const nx0=Math.floor((minX-b.max_x)/stepX)+1,nx1=Math.ceil((maxX-b.min_x)/stepX)-1;
    const ny0=Math.floor((minY-b.max_y)/stepY)+1,ny1=Math.ceil((maxY-b.min_y)/stepY)-1;
    if((nx1-nx0+1)*(ny1-ny0+1)>4096)throw new RangeError('PDF backdrop-dependent pattern cell budget exceeded');
    const plan={...resource.tile_plan,blend_profile_id:env.iccProfileId||null,blend_calibration:env.calibration||null,page:{...resource.tile_plan.page,blend_space:ink?'DeviceCMYK':env.blendSpace||'DeviceRGB'}};
    for(let ny=ny0;ny<=ny1;ny++)for(let nx=nx0;nx<=nx1;nx++){
      const matrix=multiplyMatrix(patternToDevice,[1,0,0,-1,b.min_x+nx*stepX,b.max_y+ny*stepY]);
      const corners=[[0,0],[b.max_x-b.min_x,0],[0,b.max_y-b.min_y],[b.max_x-b.min_x,b.max_y-b.min_y]].map(([x,y])=>point(matrix,x,y));
      const x0=Math.max(left,Math.floor(Math.min(...corners.map(p=>p[0])))),x1=Math.min(right,Math.ceil(Math.max(...corners.map(p=>p[0]))));
      const y0=Math.max(top,Math.floor(Math.min(...corners.map(p=>p[1])))),y1=Math.min(bottom,Math.ceil(Math.max(...corners.map(p=>p[1]))));
      const cw=x1-x0,ch=y1-y0;if(cw<=0||ch<=0)continue;
      const backdrop=new Float32Array(cw*ch*stride),frame=compositor.frames.at(-1);
      for(let y=0;y<ch;y++)backdrop.set(frame.pixels.subarray(((y+y0)*width+x0)*stride,((y+y0)*width+x1)*stride),y*cw*stride);
      const tile=env.createCanvas(cw,ch),localMatrix=[...matrix];localMatrix[4]-=x0;localMatrix[5]-=y0;
      const rendered=await renderPdfCanvas(tile,plan,{...options,createCanvas:env.createCanvas,loadImage:env.loadImage,Path2D:env.Path2D,width:cw,height:ch,matrix:localMatrix,transparent:true,backdrop,returnInks:ink,outputGroupComponents:true,_profileScope:env.profileScope,_glyphCache:env.glyphCache,_glyphCacheReserved:!!env.glyphCache,_imageCache:env.imageCache,_imageCacheReserved:!!env.imageCache,paintPattern,_resourceDepth:(env.resourceDepth||0)+1,_inheritedWorkingBytes:(env.inheritedWorkingBytes||0)+width*height*(stride*12+24)});
      env.diagnostics?.push(...rendered.diagnostics);
      const samples=ink?rendered.inkProof?.premultiplied:rendered.premultiplied;
      if(!samples||samples.length!==cw*ch*stride)throw new Error('Pattern cell did not retain its blend-space samples');
      // Cells are an implicit non-knockout group with a Normal boundary.
      // Apply the same premultiplied source-over equations as PdfCompositor,
      // limited to the cell rectangle instead of scanning the whole page.
      for(let y=0;y<ch;y++)for(let x=0;x<cw;x++){
        const local=y*cw+x,p=(y+y0)*width+x+x0,i=p*stride,j=local*stride;
        const alpha=samples[j+stride-1],shape=rendered.shape[local];
        for(let c=0;c<stride;c++)frame.pixels[i+c]=samples[j+c]+frame.pixels[i+c]*(1-alpha);
        frame.alpha[p]=alpha+frame.alpha[p]*(1-alpha);
        frame.shape[p]=shape+frame.shape[p]*(1-shape);
      }
      compositor.touch({x:x0,y:y0,width:cw,height:ch});
      tile.width=1;
    }
    const result=compositor.endGroup(),canvases=new Map();
    const bitmap=component=>{
      const key=component??'rgb';if(canvases.has(key))return canvases.get(key);
      const canvas=env.createCanvas(width,height),ctx=canvas.getContext('2d'),data=ctx.createImageData(width,height);
      if(component!=null){if(!ink)throw new Error('Pattern source has no retained process planes');
        for(let p=0;p<width*height;p++){const a=result.pixels[p*stride+stride-1],v=a?result.pixels[p*stride+component]/a*255:0;data.data[p*4]=data.data[p*4+1]=data.data[p*4+2]=v;data.data[p*4+3]=a*255;}
      }else data.data.set(premultipliedToRgba8(ink?compositor.toRgb(result.pixels):result.pixels));
      ctx.putImageData(data,0,0);canvases.set(key,canvas);return canvas;
    };
    const shape=shapeCanvas(result.shape,width,height,env);
    const value={bitmap,shape,dispose(){for(const canvas of canvases.values())canvas.width=1;canvases.clear();shape.width=1;}};
    resources?.set(resource,value);return value;
  };
  const paintPattern=async(context,resource,path,operation,env)=>{
    if (resource.kind || resource.shading) {
      if (!options.paintShading) throw new Error('PDF shading adapter is not installed');
      return options.paintShading(context,resource.shading || resource,path,{...env,operation});
    }
    if (!resource.tile_plan) throw new Error(`Pattern ${resource.name} has no structured cell`);
    const flip=[1,0,0,-1,-env.page.origin_x,env.page.origin_y+env.page.height];
    const patternToDevice=multiplyMatrix(env.matrix,multiplyMatrix(flip,resource.matrix));
    if(env.blendSpace==='DeviceCMYK'||env.iccProfileId||env.calibration||usesBackdrop(resource.tile_plan)){
      const result=await field(resource,patternToDevice,env);
      const bitmap=env.shapeOnly?result.shape:result.bitmap(env.component);
      drawField(context,bitmap,path,operation,env);
      return;
    }
    // Sample each cell axis using its own device-space footprint. Sorted
    // singular values exchange the axes when Y is stretched more than X.
    const sx=Math.max(1e-6,Math.hypot(patternToDevice[0],patternToDevice[1]));
    const sy=Math.max(1e-6,Math.hypot(patternToDevice[2],patternToDevice[3]));
    const stepX=Math.abs(resource.x_step),stepY=Math.abs(resource.y_step),b=resource.bbox;
    if (!(stepX>0&&stepY>0)) throw new Error('Invalid PDF pattern lattice');
    const width=Math.max(1,Math.ceil(stepX*sx)),height=Math.max(1,Math.ceil(stepY*sy));
    const tileWidth=Math.max(1,Math.ceil((b.max_x-b.min_x)*sx));
    const tileHeight=Math.max(1,Math.ceil((b.max_y-b.min_y)*sy));
    const limit=options.maxPatternPixels ?? 16777216;
    if (width*height>limit || tileWidth*tileHeight>limit) throw new RangeError('PDF pattern surface exceeds pixel budget');
    const rx=width/stepX,ry=height/stepY;
    let sizes=cache.get(resource);if(!sizes){sizes=new Map();cache.set(resource,sizes);}
    const key=`${width}x${height}:${tileWidth}x${tileHeight}`;
    let bitmap=sizes.get(key);
    if(bitmap){const entry=cacheOrder.get(bitmap);cacheOrder.delete(bitmap);cacheOrder.set(bitmap,entry);}
    if(!bitmap){
      const tile=env.createCanvas(tileWidth,tileHeight);
      const rendered=await renderPdfCanvas(tile,resource.tile_plan,{...options,createCanvas:env.createCanvas,loadImage:env.loadImage,Path2D:env.Path2D,width:tileWidth,height:tileHeight,matrix:[tileWidth/(b.max_x-b.min_x),0,0,tileHeight/(b.max_y-b.min_y),0,0],transparent:true,outputGroupComponents:true,_profileScope:env.profileScope,_glyphCache:env.glyphCache,_glyphCacheReserved:!!env.glyphCache,_imageCache:env.imageCache,_imageCacheReserved:!!env.imageCache,paintPattern,_resourceDepth:(env.resourceDepth||0)+1,_inheritedWorkingBytes:env.inheritedWorkingBytes||0});
      env.diagnostics?.push(...rendered.diagnostics);
      const tileShape=shapeCanvas(rendered.shape,tileWidth,tileHeight,env);
      bitmap={color:env.createCanvas(width,height),shape:env.createCanvas(width,height),replay:rendered.shape.some(value=>value<1)};const target=bitmap.color.getContext('2d'),shapeTarget=bitmap.shape.getContext('2d');
      target.imageSmoothingEnabled=true;
      const nx0=Math.floor(-b.max_x/stepX)+1,nx1=Math.ceil((stepX-b.min_x)/stepX)-1;
      const ny0=Math.floor(-b.max_y/stepY)+1,ny1=Math.ceil((stepY-b.min_y)/stepY)-1;
      if((nx1-nx0+1)*(ny1-ny0+1)>4096)throw new RangeError('PDF overlapping pattern cell budget exceeded');
      for(let ny=ny0;ny<=ny1;ny++)for(let nx=nx0;nx<=nx1;nx++){
        const args=[(b.min_x+nx*stepX)*rx,(stepY-b.max_y-ny*stepY)*ry,(b.max_x-b.min_x)*rx,(b.max_y-b.min_y)*ry];
        target.drawImage(tile,...args);shapeTarget.drawImage(tileShape,...args);
      }
      tile.width=1;tileShape.width=1;
      remember(sizes,key,bitmap);
    }
    // Transparent cell edges need one device-space coverage evaluation. A
    // resampled repeating alpha texture would filter both shape and opacity.
    if(bitmap.replay){
      const result=await field(resource,patternToDevice,env),surface=env.shapeOnly?result.shape:result.bitmap(env.component);
      drawField(context,surface,path,operation,env);
      return;
    }
    const paint=context.createPattern(env.shapeOnly?bitmap.shape:bitmap.color,'repeat');
    const bitmapToDevice=multiplyMatrix(patternToDevice,[1/rx,0,0,-1/ry,0,stepY]);
    paint.setTransform(dom(multiplyMatrix(inverse(values(context.getTransform())),bitmapToDevice)));
    if(operation==='stroke') {context.strokeStyle=paint;context.stroke(env.strokePath || new env.Path2D(path.svg_path));}
    else {context.fillStyle=paint;context.fill(new env.Path2D(path.svg_path),path.fill_even_odd?'evenodd':'nonzero');}
    if(!bitmap.cached)release(bitmap);
  };
  paintPattern.releasePaint=key=>{
    const resources=fields.get(key);
    if(resources){for(const value of resources.values())value.dispose();fields.delete(key);}
  };
  paintPattern.dispose=()=>{
    for(const [bitmap,entry] of cacheOrder){entry.sizes.delete(entry.key);release(bitmap);}
    cacheOrder.clear();cacheBytes=0;
  };
  return paintPattern;
}

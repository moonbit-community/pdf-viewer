import {createShadingPainter} from './pdf-shading.mjs';
import { renderPdfCanvas, multiplyMatrix, checkPdfRender } from './pdf-canvas.mjs';
import { createPatternPainter } from './pdf-patterns.mjs';
import {prepareNativeCanvasItems} from './pdf-canvas-native.mjs';
import {expandPdfCanvasProgram} from './pdf-canvas-program.mjs';

export {initializePdfGraphics} from './pdf-graphics.mjs';

export async function renderPdfPage(canvas,plan,options={}) {
  checkPdfRender(options);
  plan=expandPdfCanvasProgram(plan);
  const configured={...options};
  const scale=options.outputScale ?? 1;
  if(!Number.isFinite(scale)||scale<=0)throw new RangeError('PDF output scale must be finite and positive');
  if(scale!==1){
    const page=plan.page;
    const logical=options.matrix || multiplyMatrix(plan.viewport.matrix,[1,0,0,-1,-page.origin_x,page.origin_y+page.height]);
    configured.width=options.width ?? Math.ceil(plan.viewport.width*scale);
    configured.height=options.height ?? Math.ceil(plan.viewport.height*scale);
    configured.matrix=multiplyMatrix([scale,0,0,scale,0,0],logical);
  }
  // One render owns decoded lookup tables across placements and tiles. An
  // independently reused painter retains its mutable host-plan semantics.
  const samplerBytes=!options.paintShading&&plan.items.some(item=>item.kind==='shading')
    ?Math.min(8388608,Math.floor((options.maxWorkingBytes||536870912)/16)):0;
  if(samplerBytes)configured._inheritedWorkingBytes=(options._inheritedWorkingBytes||0)+samplerBytes;
  configured.paintShading=options.paintShading || createShadingPainter({...configured,
    _samplerCache:samplerBytes?{entries:new WeakMap(),bytes:0,limit:samplerBytes}:null});
  // Only the built-in adapters guarantee opaque sample coverage. External
  // painters keep their separate shape pass, even when they wrap this engine.
  configured._builtinShading=!options.paintShading;
  configured._builtinPattern=!options.paintPattern;
  configured.paintPattern=options.paintPattern || createPatternPainter(configured);
  const nativeItems=prepareNativeCanvasItems(plan,configured);
  try {
    const width=configured.width||Math.ceil(plan.viewport.width),height=configured.height||Math.ceil(plan.viewport.height);
    const budget=options.maxWorkingBytes||536870912;
    const tileSize=options.tileSize ?? (width*height>(options.maxPixels||16777216)||width*height*(nativeItems?4:256)>budget?1024:0);
    if(tileSize&& !options.returnInks&&!options.returnGroupComponents&&!options.outputGroupComponents&&!options.backdrop){
      return await renderTiledPage(canvas,plan,configured,width,height,tileSize);
    }
    const result=await renderPdfCanvas(canvas,plan,configured);
    return options.returnPixels===false?{width:result.width,height:result.height,diagnostics:result.diagnostics}:result;
  }
  catch(error){
    if(error.name==='AbortError')canvas.width=canvas.height=1;
    throw error;
  }
  finally { if(!options.paintPattern)configured.paintPattern.dispose?.(); }
}

async function renderTiledPage(canvas,plan,options,width,height,tileSize){
  if(!Number.isInteger(tileSize)||tileSize<1||tileSize>2048)throw new RangeError('PDF tile size must be an integer in 1..2048');
  const count=width*height,returnPixels=options.returnPixels!==false;
  const outputBytes=count*(returnPixels?28:4);
  if(!Number.isSafeInteger(count)||count>67108864||outputBytes>= (options.maxWorkingBytes||536870912))throw new RangeError('PDF output surface exceeds the working memory budget');
  const createCanvas=options.createCanvas||((w,h)=>{if(typeof OffscreenCanvas==='function')return new OffscreenCanvas(w,h);const c=document.createElement('canvas');c.width=w;c.height=h;return c;});
  const target=createCanvas(1,1),glyphCache={entries:new Map(),bytes:0,limit:16777216};
  const imageCache={entries:new Map(),bytes:0,limit:Math.min(67108864,(options.maxWorkingBytes||536870912)/8)};
  const pixels=returnPixels?new Uint8ClampedArray(count*4):null;
  const shape=returnPixels?new Float32Array(count):null;
  const premultiplied=returnPixels?new Float32Array(count*4):null;
  const p=plan.page,matrix=options.matrix||multiplyMatrix(plan.viewport.matrix,[1,0,0,-1,-p.origin_x,p.origin_y+p.height]);
  const engine=options.iccEngine||globalThis.__moonbit_pdf_icc;
  const scope=options._profileScope||engine?.createProfileScope?.(plan.icc_profiles||[]);
  const diagnostics=new Map();let blendCapabilities;
  canvas.width=width;canvas.height=height;const context=canvas.getContext('2d');
  try{
    for(let y=0;y<height;y+=tileSize)for(let x=0;x<width;x+=tileSize){
      checkPdfRender(options);
      if(options.yieldToHost){await options.yieldToHost();checkPdfRender(options);}
      const w=Math.min(tileSize,width-x),h=Math.min(tileSize,height-y);
      const tile=await renderPdfCanvas(target,plan,{...options,width:w,height:h,
        matrix:multiplyMatrix([1,0,0,1,-x,-y],matrix),_profileScope:scope,
        _glyphCache:glyphCache,_glyphCacheReserved:true,
        _imageCache:imageCache,_imageCacheReserved:true,
        _inheritedWorkingBytes:(options._inheritedWorkingBytes||0)+outputBytes+glyphCache.limit+imageCache.limit});
      checkPdfRender(options);
      context.drawImage(target,x,y);
      blendCapabilities ||= tile.blendCapabilities;
      for(const diagnostic of tile.diagnostics||[])diagnostics.set(JSON.stringify(diagnostic),diagnostic);
      if(returnPixels)for(let row=0;row<h;row++){
        const offset=(y+row)*width+x,source=row*w;
        pixels.set(tile.data.subarray(source*4,(source+w)*4),offset*4);
        shape.set(tile.shape.subarray(source,source+w),offset);
        premultiplied.set(tile.premultiplied.subarray(source*4,(source+w)*4),offset*4);
      }
    }
    return {width,height,stride:width*4,format:'rgba8-straight',data:pixels,shape,premultiplied,blendCapabilities,diagnostics:[...diagnostics.values()]};
  }finally{
    target.width=target.height=1;
    if(scope&&scope!==options._profileScope)scope.dispose();
    for(const entry of glyphCache.entries.values()){if(options.releaseImage)options.releaseImage(entry.value);else entry.value.close?.();}glyphCache.entries.clear();glyphCache.bytes=0;glyphCache.pathBounds?.entries.clear();if(glyphCache.pathBounds)glyphCache.pathBounds.bytes=0;
    for(const entry of imageCache.entries.values()){if(options.releaseImage)options.releaseImage(entry.value);else entry.value.close?.();}imageCache.entries.clear();imageCache.bytes=0;
  }
}

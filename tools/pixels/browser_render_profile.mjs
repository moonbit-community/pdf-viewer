// Optional diagnostic replay only. Instrumented times are not benchmark times.
// Keep input plans, decoded text and images out of the summary report.
export function instrumentCanvasModule(source){
  const declaration='export async function renderPdfCanvas(canvas, plan, options = {}) {';
  if(!source.includes(declaration))throw Error('Canvas entry point changed: update the browser profiler');
  return source.replace(declaration,`export async function renderPdfCanvas(canvas, plan, options = {}) {
  const profile=globalThis.pdfRenderProfile;
  if(!profile?.active)return renderPdfCanvasProfiled(canvas,plan,options);
  const frame=profile.enter(plan,options);
  const task=options._renderTask;
  if(task&&!task._profileYield&&!task.yieldToHost._profileYield){
    const yieldToHost=task.yieldToHost;task._profileYield=true;
    task.yieldToHost=async()=>{
      if(!profile.active)return yieldToHost();
      const start=performance.now();
      try{return await yieldToHost();}
      finally{profile.yields.calls++;profile.yields.ms+=performance.now()-start;}
    };
  }
  let configured=options;
  if(options.yieldToHost&&!options._profileYield&&!task){
    const yieldToHost=async()=>{
      const start=performance.now();
      try{return await options.yieldToHost();}
      finally{profile.yields.calls++;profile.yields.ms+=performance.now()-start;}
    };
    yieldToHost._profileYield=true;
    configured={...options,_profileYield:true,yieldToHost};
  }
  try{return await renderPdfCanvasProfiled(canvas,plan,configured);}
  finally{profile.leave(frame);}
}
async function renderPdfCanvasProfiled(canvas, plan, options = {}) {`);
}

// Playwright serializes this function into the browser; it must be self-contained.
export function installBrowserRenderProfile(){
  const profile=globalThis.pdfRenderProfile={active:false,stack:[],scenes:[],operations:{},yields:{calls:0,ms:0}};
  profile.enter=(plan,options)=>{
    const frame={start:performance.now(),childrenMs:0,parent:profile.stack.at(-1),depth:profile.stack.length,
      items:plan.items.length,kinds:{},groups:[],nativeDisabled:!!options._nativePageDisabled,
      backdrop:!!options.backdrop,components:!!options.outputGroupComponents,
      width:options.width||Math.ceil(plan.viewport.width),height:options.height||Math.ceil(plan.viewport.height),operations:{}};
    const groups=new Map();
    for(const item of plan.items){
      frame.kinds[item.kind]=(frame.kinds[item.kind]||0)+1;
      for(const group of item.groups||item.paint.group_path||[])groups.set(group.id,{
        id:group.id,isolated:group.isolated,knockout:group.knockout,alpha:group.alpha,
        space:group.color_space,blend:group.blend_mode,mask:!!group.soft_mask});
    }
    frame.groups=[...groups.values()];profile.stack.push(frame);return frame;
  };
  profile.leave=frame=>{
    frame.ms=performance.now()-frame.start;frame.selfMs=frame.ms-frame.childrenMs;
    if(frame.parent)frame.parent.childrenMs+=frame.ms;
    profile.stack.pop();delete frame.parent;delete frame.start;profile.scenes.push(frame);
  };
  profile.record=(name,ms,pixels=0,frame=profile.stack.at(-1),site=null)=>{
    for(const table of [profile.operations,frame?.operations].filter(Boolean)){
      const row=table[name]||={calls:0,ms:0,pixels:0};row.calls++;row.ms+=ms;row.pixels+=pixels;
      if(site){const sites=row.sites||={};const cost=sites[site]||={calls:0,ms:0,pixels:0};cost.calls++;cost.ms+=ms;cost.pixels+=pixels;}
    }
  };
  const Path=globalThis.Path2D;
  if(Path)globalThis.Path2D=new Proxy(Path,{construct(Target,args){
    if(!profile.active)return Reflect.construct(Target,args,Target);
    const start=performance.now();
    try{return Reflect.construct(Target,args,Target);}
    finally{profile.record('Path2D',performance.now()-start);}
  }});
  const prototypes=new Set([globalThis.CanvasRenderingContext2D?.prototype,globalThis.OffscreenCanvasRenderingContext2D?.prototype].filter(Boolean));
  for(const proto of prototypes)for(const name of ['getImageData','putImageData','clearRect','drawImage','createImageData','fill','stroke','clip']){
    const original=proto[name];if(typeof original!=='function')continue;
    proto[name]=function(...args){
      if(!profile.active)return original.apply(this,args);
      const start=performance.now();
      try{return original.apply(this,args);}
      finally{
        const pixels=name==='getImageData'||name==='clearRect'?Math.abs(args[2]*args[3]):name==='putImageData'?(args.length>=7?args[5]*args[6]:args[0].width*args[0].height):0;
        const ms=performance.now()-start;
        const site=['getImageData','putImageData'].includes(name)?new Error().stack?.split('\n').find(line=>/pdf-(?:canvas|shading|pattern|compositor)/.test(line))?.trim():null;
        profile.record(name,ms,pixels,undefined,site);
      }
    };
  }
  for(const [object,name,label] of [[globalThis.Image?.prototype,'decode','Image.decode'],[globalThis,'createImageBitmap','createImageBitmap']]){
    const original=object?.[name];if(typeof original!=='function')continue;
    object[name]=async function(...args){
      if(!profile.active)return original.apply(this,args);
      const start=performance.now(),frame=profile.stack.at(-1);
      try{return await original.apply(this,args);}
      finally{profile.record(label,performance.now()-start,0,frame);}
    };
  }
  profile.begin=()=>{profile.stack=[];profile.scenes=[];profile.operations={};profile.yields={calls:0,ms:0};profile.active=true;};
  profile.finish=()=>{profile.active=false;return {scenes:profile.scenes,operations:profile.operations,yields:profile.yields};};
}

export function summarizeRenderPlan(plan,prepare,options){
  const native=prepare(plan,options);
  const summary={items:plan.items.length,kinds:{},native:!!native,branches:[]};
  if(!options._profileNested){
    const strings={},unique=new Set();let uriChars=0,uniqueUriChars=0;
    const visit=value=>{
      if(!value||typeof value!=='object')return;
      for(const [key,child] of Object.entries(value)){
        if(typeof child==='string'){
          strings[key]=(strings[key]||0)+child.length;
          if(child.startsWith('data:')){uriChars+=child.length;if(!unique.has(child)){unique.add(child);uniqueUriChars+=child.length;}}
        }else if(Array.isArray(child))for(const item of child)visit(item);
        else visit(child);
      }
    };
    visit(plan);summary.strings={characters:strings,dataUriChars:uriChars,uniqueDataUriChars:uniqueUriChars};
  }
  for(const item of plan.items)summary.kinds[item.kind]=(summary.kinds[item.kind]||0)+1;
  for(const item of native||[])if(item.kind==='retained'){
    summary.branches.push({native:!!item.native,alpha:item.alpha??1,...summarizeRenderPlan(item.scene,prepare,
      {...options,_profileNested:true,_nativePageDisabled:!item.native,maxDepth:(options.maxDepth??32)-(item.native?1:0),transparent:true})});
  }
  return summary;
}

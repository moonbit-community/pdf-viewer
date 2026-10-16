// Compiled glyph resources stay in font coordinates. Reproduce the existing
// positioned path arithmetic at the host boundary, including its bounds map.
// Only the browser compiler emits version 2; public model plans remain version 1.
export function expandPdfCanvasProgram(plan) {
  if(plan?.version!==2)return plan;
  if(!Array.isArray(plan.glyph_resources)||plan.glyph_resources.length>16384)throw new Error('Invalid PDF glyph resource table');
  const resources=new Map();
  for(const resource of plan.glyph_resources){
    if(!Number.isInteger(resource.id)||resources.has(resource.id)||!Array.isArray(resource.commands)||resource.commands.length>32768||(resource.kind!==undefined&&resource.kind!=='outline'))throw new Error('Invalid PDF glyph resource');
    resources.set(resource.id,resource);
  }
  const items=plan.items.map(item=>{
    if(!item.glyph)return item;
    const resource=resources.get(item.glyph.resource),m=item.glyph.matrix;
    if(item.kind!=='text'||!resource||!Array.isArray(m)||m.length!==6||!m.every(v=>Number.isFinite(v)&&Math.abs(v)<=1e12))throw new Error('Invalid PDF glyph invocation');
    if(resource.kind==='outline'){
      // Ordinary CFF/Type1 paths use the font transform directly. Type3's
      // elementary scene applies an additional bounds map below.
      const parts=[],commands=resource.commands;
      for(let i=0;i<commands.length;){
        const op=commands[i++],count=op===0||op===1?2:op===2?6:op===3?0:-1;
        if(count<0||i+count>commands.length)throw new Error('Invalid PDF glyph path');
        parts.push(['M','L','C','Z'][op]);
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
  const {glyph_resources,...expanded}=plan;
  return {...expanded,version:1,items};
}

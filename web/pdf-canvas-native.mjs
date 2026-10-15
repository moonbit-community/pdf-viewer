// Plain source-over pages can use Canvas directly. PDF groups, masks and
// component-space compositing still need the retained transparency renderer.
const opaqueColour=colour=>/^#[\da-f]{3}(?:[\da-f]{3})?$/i.test(colour);
export const independentPattern=resource=>{
  const tile=resource?.tile_plan||resource?.pattern_plan;
  if(!tile||tile.page.blend_space!=='DeviceRGB'||tile.blend_profile_id||tile.page.blend_profile_id||tile.blend_calibration||tile.page.blend_calibration)return false;
  if(resource.pattern_plan){
    if(tile.items.length!==1)return false;
    const item=tile.items[0],p=item.paint,groups=item.groups||p.group_path||[];
    // A single opaque normal shading has shape == alpha, including the
    // elementary nonisolated knockout group emitted for shading patterns.
    return item.kind==='shading'&&!p.shading?.pattern_plan&&!item.mask&&!p.soft_mask&&p.fill_alpha===1&&!p.alpha_is_shape&&!p.fill_overprint&&['normal','compatible'].includes(p.blend_mode)&&groups.every(g=>g.alpha===1&&!g.alpha_is_shape&&!g.soft_mask&&!g.icc_profile_id&&!g.calibration&&(!g.color_space||g.color_space==='DeviceRGB')&&['normal','compatible'].includes(g.blend_mode));
  }
  return tile.items.every(item=>{
    const p=item.paint;
    return ['path','image'].includes(item.kind)&&!(item.groups||p.group_path||[]).length&&!item.mask&&!p.soft_mask&&!item.pattern&&!p.pattern&&!item.stroke_pattern&&!p.stroke_pattern&&!p.shading_pattern&&!p.fill_overprint&&!p.stroke_overprint&&!p.alpha_is_shape&&['normal','compatible'].includes(p.blend_mode);
  });
};
export function nativeType3Paths(item,page){
  const scene=item.type3_plan;
  if(!scene||scene.version!==1||scene.diagnostics?.length||scene.annotation_svg||scene.annotation_fragments?.length)return null;
  if(['origin_x','origin_y','width','height'].some(key=>scene.page[key]!==page[key]))return null;
  if(scene.blend_profile_id||scene.page.blend_profile_id||scene.blend_calibration||scene.page.blend_calibration)return null;
  if(!scene.items.length)return [{...item,kind:'path',paint:{...item.paint,svg_path:'',filled:false,stroked:false}}];
  const paths=[];
  for(const child of scene.items){
    const p=child.paint;
    if(child.kind!=='path'||(child.groups||p.group_path||[]).length||child.mask||p.soft_mask||child.pattern||p.pattern||child.stroke_pattern||p.stroke_pattern||p.shading_pattern||!['normal','compatible'].includes(p.blend_mode)||p.fill_alpha!==1||!opaqueColour(p.fill_color)||!p.filled||p.stroked||p.fill_overprint||p.stroke_overprint||p.alpha_is_shape)return null;
    paths.push({...child,paint:{...p,index:item.paint.index},groups:item.groups||item.paint.group_path||[]});
  }
  return paths;
}
export function singleType3Path(item,page){
  const paths=nativeType3Paths(item,page);
  return paths?.length===1?paths[0]:null;
}

// A single image in a source-over text scope is an ordinary page image. Its
// decoded opacity can differ from shape, so overlapping knockout glyphs must
// keep their retained scene and text-object boundary.
const nativeType3Image=(item,page)=>{
  const scene=item.type3_plan;
  if(!scene||scene.version!==1||scene.diagnostics?.length||scene.annotation_svg||scene.annotation_fragments?.length||scene.items.length!==1)return null;
  if(['origin_x','origin_y','width','height'].some(key=>scene.page[key]!==page[key]))return null;
  if([scene.blend_space,scene.page.blend_space].some(space=>space&&space!=='DeviceRGB')||scene.blend_profile_id||scene.page.blend_profile_id||scene.blend_calibration||scene.page.blend_calibration)return null;
  const child=scene.items[0],p=child.paint;
  if(child.kind!=='image'||(child.groups||p.group_path||[]).length||child.mask||p.soft_mask||child.pattern||p.pattern||child.stroke_pattern||p.stroke_pattern||p.shading_pattern||!['normal','compatible'].includes(p.blend_mode)||p.fill_alpha!==1||p.fill_overprint||p.stroke_overprint||p.alpha_is_shape)return null;
  return {...child,paint:{...p,index:item.paint.index},groups:item.groups||item.paint.group_path||[]};
};

// In a knockout group, source-over is equivalent when each elementary
// object's shape equals its alpha. Restrict this proof to opaque vector paints.
const opaqueNativePaint=item=>item.kind==='path'&&!item.paint.pattern&&!item.paint.stroke_pattern&&!item.paint.shading_pattern&&
 (!item.paint.filled||(item.paint.fill_alpha===1&&opaqueColour(item.paint.fill_color)))&&
 (!item.paint.stroked||(item.paint.stroke_alpha===1&&opaqueColour(item.paint.stroke_color)));

export function prepareNativeCanvasItems(plan,options={}){
  if(options.nativeCanvas===false||options._nativePageDisabled||(options.maxDepth??32)<=1||options.returnPixels!==false||options.proof||options.backdrop||options.returnInks||options.returnGroupComponents||options.outputGroupComponents||options._maskBackdrop||options.fullSurfaceReplay||options.fullSceneReplay)return null;
  const space=plan.page.blend_space||'DeviceRGB';
  if(space!=='DeviceRGB'||plan.blend_profile_id||plan.page.blend_profile_id||plan.blend_calibration||plan.page.blend_calibration)return null;
  const items=[];
  let textObjects=null;
  const sourceOverTextScope=paint=>{
    if(!paint.text_object_id||paint.text_knockout===false)return true;
    if(!textObjects){
      textObjects=new Map();
      for(const item of plan.items)if(item.kind==='text'&&item.paint.text_object_id){const id=item.paint.text_object_id;textObjects.set(id,(textObjects.get(id)||0)+1);}
    }
    return textObjects.get(paint.text_object_id)===1;
  };
  for(let i=0;i<plan.items.length;i++){
    const raw=plan.items[i],groups=raw.groups||raw.paint.group_path||[],group=groups[0];
    if(group){
      // Independent unit-opacity groups can stay on the page. Other isolated
      // source-over groups render against transparency before placement.
      if(!['normal','compatible'].includes(group.blend_mode)||group.alpha_is_shape)return null;
      let end=i+1;
      while(end<plan.items.length&&(plan.items[end].groups||plan.items[end].paint.group_path||[])[0]?.id===group.id)end++;
      const scene={...plan,items:plan.items.slice(i,end),annotation_svg:null,annotation_fragments:[]};
      const children={...scene,items:scene.items.map(item=>{
        const groups=(item.groups||item.paint.group_path||[]).slice(1);
        return {...item,groups,paint:{...item.paint,group_path:groups}};
      })};
      const independent=!group.soft_mask&&!group.icc_profile_id&&!group.calibration&&(!group.color_space||group.color_space==='DeviceRGB');
      const nativeChildren=independent?prepareNativeCanvasItems(children,{...options,maxDepth:(options.maxDepth??32)-1,transparent:true}):null;
      // Normal unit-opacity groups preserve source-over composition. Flatten
      // them instead of allocating, reading and uploading a group surface.
      if(group.alpha===1&&nativeChildren&&(!group.knockout||nativeChildren.every(opaqueNativePaint))){
        for(const child of nativeChildren)items.push(group.bounds?{
          ...child,nativeClipBounds:[group.bounds,...(child.nativeClipBounds||[])],
        }:child);i=end-1;continue;
      }
      if(!group.isolated)return null;
      const direct=!group.knockout&&nativeChildren!==null;
      items.push({kind:'retained',scene:direct?children:scene,native:direct,alpha:direct?group.alpha:1,bounds:direct?group.bounds:null});
      i=end-1;continue;
    }
    const p=raw.paint;
    if(raw.mask||p.soft_mask||p.fill_overprint||p.stroke_overprint||p.alpha_is_shape||!['normal','compatible'].includes(p.blend_mode))return null;
    const patterns=[raw.pattern||p.pattern,raw.stroke_pattern||p.stroke_pattern,p.shading_pattern].filter(Boolean);
    if(patterns.length){
      // Simple tiling cells and opaque normal shading scenes are independent
      // of the page backdrop. Rasterize only the pattern; keep siblings native.
      if(raw.kind!=='path'||!patterns.every(independentPattern))return null;
      const fillPattern=raw.pattern||p.pattern;
      if(p.filled&&!p.stroked&&!p.fill_transform&&!p.shading_pattern&&fillPattern?.tile_plan){
        items.push({...raw,paint:{...p,pattern:fillPattern}});continue;
      }
      items.push({kind:'retained',native:false,scene:{...plan,items:[raw],annotation_svg:null,annotation_fragments:[]}});
      continue;
    }
    let item=raw;
    if(raw.kind==='text'){
      // With opaque elementary glyphs, shape equals alpha, so text knockout
      // reduces to source-over. Translucent glyphs retain the PDF group path.
      if(raw.type3_plan){
        // Opaque source-over glyph parts have shape == alpha. Outside knockout
        // groups they can stay vector paths, including multi-path charprocs.
        const paths=nativeType3Paths(raw,plan.page);
        if(!paths){
          const image=options.nativeImageGlyphs!==false&&sourceOverTextScope(p)?nativeType3Image(raw,plan.page):null;
          if(!image)return null;
          items.push(image);continue;
        }
        for(const path of paths)items.push(path);continue;
      }
      else{
        const mode=p.rendering_mode,filled=[0,2,4,6].includes(mode),stroked=[1,2,5,6].includes(mode),pen=p.stroke;
        if((filled&&(p.fill_alpha!==1||!opaqueColour(p.fill_color)))||(stroked&&((pen?.stroke_alpha??p.stroke_alpha)!==1||!opaqueColour(p.stroke_color))))return null;
        if(p.fill_path!=null)item={...raw,kind:'path',paint:{...p,svg_path:p.fill_path,filled,stroked,stroke_alpha:pen?.stroke_alpha??p.stroke_alpha,line_cap:pen?.line_cap,line_join:pen?.line_join}};
        else if(pen?.svg_path!=null)item={...raw,kind:'path',paint:{...p,svg_path:pen.svg_path,fill_transform:pen.transform,filled,stroked,stroke_alpha:pen.stroke_alpha,line_cap:pen.line_cap,line_join:pen.line_join}};
        else if(!filled||stroked)return null;
      }
    }else if(!['path','image'].includes(raw.kind))return null;
    if(item.kind==='path'&&item.paint.filled&&item.paint.stroked&&(item.paint.fill_alpha!==1||item.paint.stroke_alpha!==1||!opaqueColour(item.paint.fill_color)||!opaqueColour(item.paint.stroke_color)))return null;
    items.push(item);
  }
  return items;
}

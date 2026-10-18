// The reader packet separates numeric geometry from JSON metadata. Revive all
// semantic work before resolving the request; painting never owns selection.
export function decodePdfPageData(packet){
  if(typeof packet==='string')return JSON.parse(packet); // XFA and older hosts.
  if(packet?.version!==1||typeof packet.json!=='string'||!Array.isArray(packet.buffers)||packet.buffers.length!==1||!Array.isArray(packet.ranges))throw Error('Invalid PDF page packet');
  const numbers=marker=>{
    const id=marker?.__pdf_numbers;
    if(!marker||Object.keys(marker).length!==1||!Number.isInteger(id)||id<0||id>=packet.ranges.length)throw Error('Invalid PDF numeric resource');
    const buffer=packet.buffers[0],range=packet.ranges[id];
    if(!(buffer instanceof ArrayBuffer)||buffer.byteLength%8||!Array.isArray(range)||range.length!==2||!range.every(Number.isSafeInteger)||range[0]<0||range[1]<0||range[0]+range[1]>buffer.byteLength/8)throw Error('Invalid PDF numeric buffer');
    return new Float64Array(buffer,range[0]*8,range[1]);
  };
  const result=JSON.parse(packet.json);
  if(!result.ok)return result;
  if(!result.canvas||!Array.isArray(result.canvas.items))throw Error('Invalid PDF page program');
  for(const item of result.canvas.items)if(item.kind==='text_run'&&!Array.isArray(item.draws))item.draws=Array.from(numbers(item.draws));
  const layer=result.layer;
  if(layer?.version===2){
    const data=numbers(layer.draws),{text,separators,styles}=layer;
    if(!Array.isArray(text)||!Array.isArray(separators)||!Array.isArray(styles)||data.length!==text.length*16||separators.length!==text.length||!data.every(Number.isFinite))throw Error('Invalid PDF text layer packet');
    for(const style of styles)if(!style||typeof style.font_family!=='string'||typeof style.font_weight!=='string'||typeof style.font_style!=='string'||typeof style.vertical!=='boolean'||Object.keys(style).length!==4)throw Error('Invalid PDF text style');
    const items=[];
    for(let p=0,g=0;p<data.length;p+=16,g++){
      const index=data[p],styleID=data[p+1],style=styles[styleID];
      if(!Number.isSafeInteger(index)||index<0||!Number.isInteger(styleID)||styleID<0||!style||typeof text[g]!=='string'||typeof separators[g]!=='string')throw Error('Invalid PDF text layer operand');
      const point=n=>({x:data[p+n],y:data[p+n+1]});
      items.push({item_index:index,text:text[g],separator:separators[g],quad:{p0:point(2),p1:point(4),p2:point(6),p3:point(8)},
        matrix:Array.from(data.subarray(p+10,p+16)),...style});
    }
    result.layer={page:layer.page,viewport:layer.viewport,items};
  }
  return result;
}

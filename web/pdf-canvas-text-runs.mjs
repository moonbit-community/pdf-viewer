// Version 3 separates a text operation's state from its numeric glyph operands.
// Expand at the existing renderer boundary; public version-1 plans stay intact.
export function expandPdfTextRuns(plan){
  if(plan.version!==3)return plan.items;
  if(!Array.isArray(plan.text_states)||plan.text_states.length>16384||!Array.isArray(plan.items))throw new Error('Invalid PDF text state table');
  for(const state of plan.text_states)if(state?.kind!=='text'||!state.paint||typeof state.paint!=='object'||Array.isArray(state.paint)||state.glyph)throw new Error('Invalid PDF text state');
  const items=[];
  for(const item of plan.items){
    if(item.kind!=='text_run'){items.push(item);continue;}
    const state=plan.text_states[item.state],data=item.draws,text=item.text;
    if(!Number.isInteger(item.state)||item.state<0||!state||!Array.isArray(data)||!Array.isArray(text)||text.length>4096||data.length!==text.length*29||!data.every(Number.isFinite)||!text.every(t=>typeof t==='string'))throw new Error('Invalid PDF text run');
    for(let p=0,g=0;p<data.length;p+=29,g++){
      if(!Number.isSafeInteger(data[p])||data[p]<0||!Number.isSafeInteger(data[p+1])||!Number.isSafeInteger(data[p+22]))throw new Error('Invalid PDF text operand');
      const point=n=>({x:data[p+n],y:data[p+n+1]});
      items.push({...state,paint:{...state.paint,index:data[p],charcode:data[p+1],text:text[g],advance_x:data[p+2],advance_y:data[p+3],
        bounds:{min_x:data[p+4],min_y:data[p+5],max_x:data[p+6],max_y:data[p+7]},
        quad:{p0:point(8),p1:point(10),p2:point(12),p3:point(14)},glyph_transform:data.slice(p+16,p+22)},
        glyph:{resource:data[p+22],matrix:data.slice(p+23,p+29)}});
    }
  }
  return items;
}

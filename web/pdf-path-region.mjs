import {pdfPixelRegion} from './pdf-pixel-region.mjs';

// Collector paths use absolute coordinates. Lines and Bezier curves lie in
// their control-point hull, including implicit close segments. Unknown host
// SVG syntax keeps the caller's existing bounds instead of approximating it.
function pathBounds(path){
  const token=/[MLQCZ]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?/g;
  if(path.replace(token,'').replace(/[\s,]/g,''))return null;
  const tokens=path.match(token)||[];
  if(tokens.length>1000000||tokens[0]!=='M')return null;
  let left=Infinity,top=Infinity,right=-Infinity,bottom=-Infinity;
  for(let i=0;i<tokens.length;){
    const command=tokens[i++],count=command==='C'?6:command==='Q'?4:command==='M'||command==='L'?2:command==='Z'?0:-1;
    if(count<0||i+count>tokens.length)return null;
    for(let j=0;j<count;j+=2){
      const x=Number(tokens[i++]),y=Number(tokens[i++]);
      if(!Number.isFinite(x)||!Number.isFinite(y))return null;
      left=Math.min(left,x);top=Math.min(top,y);right=Math.max(right,x);bottom=Math.max(bottom,y);
    }
  }
  if(!Number.isFinite(left))return null;
  return {left,top,right,bottom};
}

export function pdfPathPixelRegion(path,matrix,width,height,cache=null){
  if(typeof path!=='string')return null;
  let bounds;
  if(cache?.entries.has(path))bounds=cache.entries.get(path);
  else{
    bounds=pathBounds(path);
    const bytes=128+path.length*2;
    if(cache&&cache.entries.size<4096&&bytes<=cache.limit-cache.bytes){cache.entries.set(path,bounds);cache.bytes+=bytes;}
  }
  if(!bounds)return null;
  let left=Infinity,top=Infinity,right=-Infinity,bottom=-Infinity;
  for(const x of [bounds.left,bounds.right])for(const y of [bounds.top,bounds.bottom]){
    const dx=matrix[0]*x+matrix[2]*y+matrix[4],dy=matrix[1]*x+matrix[3]*y+matrix[5];
    if(!Number.isFinite(dx)||!Number.isFinite(dy))return null;
    left=Math.min(left,dx);top=Math.min(top,dy);right=Math.max(right,dx);bottom=Math.max(bottom,dy);
  }
  // Keep the complete antialias fringe. Placement and curve evaluation still
  // happen on the original Canvas and at the original global device centers.
  const x=Math.floor(left)-3,y=Math.floor(top)-3;
  return pdfPixelRegion(width,height,{x,y,width:Math.ceil(right)+3-x,height:Math.ceil(bottom)+3-y});
}

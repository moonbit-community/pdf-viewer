export function pdfPixelRegion(width,height,region=null){
 if(!region)return {x:0,y:0,width,height};
 if(![region.x,region.y,region.width,region.height].every(Number.isFinite))throw new RangeError('Invalid PDF pixel region');
 const x=Math.max(0,Math.min(width,Math.floor(region.x))),y=Math.max(0,Math.min(height,Math.floor(region.y)));
 return {x,y,width:Math.max(0,Math.min(width,Math.ceil(region.x+region.width))-x),height:Math.max(0,Math.min(height,Math.ceil(region.y+region.height))-y)};
}
export function pdfUnionPixelRegions(a,b){
 if(!a?.width||!a?.height)return b;if(!b?.width||!b?.height)return a;
 const x=Math.min(a.x,b.x),y=Math.min(a.y,b.y);
 return {x,y,width:Math.max(a.x+a.width,b.x+b.width)-x,height:Math.max(a.y+a.height,b.y+b.height)-y};
}

// Recycled group pixels previously held a nonisolated backdrop. Keep the
// extracted source identically zero outside its marked device rectangle.
export function clearOutsideRegion(values,stride,width,height,r){
 if(!r.width||!r.height){values.fill(0);return;}
 values.fill(0,0,r.y*width*stride);values.fill(0,(r.y+r.height)*width*stride);
 for(let y=r.y;y<r.y+r.height;y++){values.fill(0,y*width*stride,(y*width+r.x)*stride);values.fill(0,(y*width+r.x+r.width)*stride,(y+1)*width*stride);}
}

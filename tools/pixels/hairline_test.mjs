import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {pdfDashedHairlinePath} from '../../web/pdf-hairline.mjs';
const require=createRequire(process.env.PDF_CANVAS_PACKAGE || import.meta.url),{createCanvas,Path2D,DOMMatrix}=require('@napi-rs/canvas');
const matrix=new DOMMatrix([2,.25,.5,1,10,20]);
function pixels(path){const c=createCanvas(240,180),x=c.getContext('2d');x.strokeStyle='#000';x.lineWidth=1;x.stroke(path);return x.getImageData(0,0,240,180).data;}
for(const svg of ['M 10 10 L 80 10 L 80 35','M 10 10 C 25 60 60 -20 80 35']){
 for(const phase of [0,3,19,-3]){
  const reference=new Path2D(svg).dash(8,5,phase).transform(matrix),actual=pdfDashedHairlinePath(svg,[8,5],phase,matrix,Path2D),a=pixels(actual),b=pixels(reference);
  let maximum=0,changed=0;for(let i=3;i<a.length;i+=4){const error=Math.abs(a[i]-b[i]);maximum=Math.max(maximum,error);if(error>8)changed++;}
  console.log(JSON.stringify({svg,phase,changedAbove8:changed,maximum}));
  if(!svg.includes('C'))assert.equal(changed,0,'linear dash geometry must exactly match native Skia');
 }
}
assert.throws(()=>pdfDashedHairlinePath('M0 0L1 1',[0,0],0,matrix,Path2D),/zero/);
// Validate curve dash arc lengths independently by dense numerical integration.
// Skia's dash effect uses a coarser arc-length estimate, so its edge pixels are
// reported above rather than pretending that matching them proves geometry.
class RecordedPath {
 constructor(){this.runs=[];}
 moveTo(x,y){this.runs.push({start:[x,y],segments:[]});}
 lineTo(x,y){this.runs.at(-1).segments.push([[x,y]]);}
 bezierCurveTo(a,b,c,d,e,f){this.runs.at(-1).segments.push([[a,b],[c,d],[e,f]]);}
}
for(const phase of [0,3,19,-3]){
 const path=pdfDashedHairlinePath('M 10 10 C 25 60 60 -20 80 35',[8,5],phase,{a:1,b:0,c:0,d:1,e:0,f:0},RecordedPath);
 for(let r=0;r<path.runs.length-1;r++){
  let length=0,start=path.runs[r].start;
  for(const segment of path.runs[r].segments){
   let previous=start;
   for(let step=1;step<=4096;step++){
    const t=step/4096,u=1-t,at=segment.length===1?start.map((v,c)=>v*u+segment[0][c]*t):start.map((v,c)=>v*u*u*u+3*segment[0][c]*u*u*t+3*segment[1][c]*u*t*t+segment[2][c]*t*t*t);
    length+=Math.hypot(at[0]-previous[0],at[1]-previous[1]);previous=at;
   }
   start=segment.at(-1);
  }
  const offset=((phase%13)+13)%13,expected=r===0&&offset<8?8-offset:8;
  assert.ok(Math.abs(length-expected)<0.001,`curve dash length ${length}, expected ${expected}`);
 }
}
const dotted=pdfDashedHairlinePath('M0 0L20 0',[0,5],0,{a:1,b:0,c:0,d:1,e:0,f:0},RecordedPath);
assert.equal(dotted.runs.length,4);assert.deepEqual(dotted.runs.map(r=>r.start),[[0,0],[5,0],[10,0],[15,0]]);
const diagonal=pdfDashedHairlinePath('M0 0L20 20',[0,5],0,{a:2,b:.25,c:.5,d:1,e:0,f:0},RecordedPath);
const first=diagonal.runs[0],end=first.segments[0][0];
assert.ok(Math.abs(end[1]/end[0]-.5)<1e-9,'zero-length dash retains its transformed underlying tangent');
assert.ok(Math.hypot(...end)<.001,'orientation carrier stays below one antialiasing byte');
console.log('15 paint-space hairline adapter tests passed');

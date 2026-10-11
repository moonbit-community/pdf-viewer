import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {PdfCompositor,PDF_BLEND_MODES} from '../../web/pdf-compositor.mjs';
import {PdfInkCompositor} from '../../web/pdf-ink-compositor.mjs';
const {createCanvas}=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url)('@napi-rs/canvas');
const width=16,height=12,count=width*height;
let cases=0;
for(const ink of [false,true])for(const mode of PDF_BLEND_MODES)for(const knockout of [false,true]){
 const make=()=>ink?new PdfInkCompositor(width,height,createCanvas):new PdfCompositor(width,height,createCanvas);
 const full=make(),bounded=make(),channels=ink?4:3,stride=channels+1;
 const makeSource=(r,step)=>{const pixels=new Float32Array(count*stride),shape=new Float32Array(count),mask=new Float32Array(count).fill(.73);for(let y=r.y;y<r.y+r.height;y++)for(let x=r.x,p=y*width+x;x<r.x+r.width;x++,p++){const a=(p+step)%7===0?0:.2+(p%5)*.13;shape[p]=1;for(let c=0;c<channels;c++)pixels[p*stride+c]=((p*7+c*19+step*31)%101)/100*a;pixels[p*stride+channels]=a;}return {pixels,shape,mask};};
 const background=makeSource({x:0,y:0,width,height},3);
 for(const e of [full,bounded]){e.beginGroup({isolated:true});e.paint(background.pixels,background.shape);e.beginGroup({isolated:false,knockout},e.frames.at(-1).pixels);}
 for(const [step,r] of [{x:2,y:3,width:6,height:4},{x:8,y:5,width:4,height:5},{x:1,y:1,width:3,height:2}].entries()){
  const source=makeSource(r,step),state={blend_mode:mode,alpha:.61,mask:source.mask,alpha_is_shape:step===2};
  full.paint(source.pixels,source.shape,state);bounded.paint(source.pixels,source.shape,{...state,dirty:r});
 }
 for(const e of [full,bounded]){const child=e.endGroup();e.paint(child.pixels,child.shape,{alpha:.82,dirty:e===bounded?child.dirty:null});}
 assert.deepEqual(bounded.endGroup().pixels,full.endGroup().pixels,`${ink?'CMYK':'RGB'} ${mode} knockout=${knockout}`);cases++;
}
console.log(`${cases} dirty-region group/blend results are bit-identical to full-surface replay`);

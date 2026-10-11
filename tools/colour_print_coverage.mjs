#!/usr/bin/env node
// Local geometry attribution for a supplied pixel list; this does not replay
// colour or alter the original plan. Images are their geometric quadrilateral,
// not decoded sample/alpha verification. Paths use the original affine pen.
import {readFileSync,writeFileSync} from 'node:fs';
import {createRequire} from 'node:module';
const require=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url);
const {createCanvas,Path2D}=require('@napi-rs/canvas');
if(process.argv.length!==5)throw Error('usage: colour_print_coverage.mjs plan.json points.json result.json');
const plan=JSON.parse(readFileSync(process.argv[2],'utf8')),pixels=JSON.parse(readFileSync(process.argv[3],'utf8'));
const width=Math.ceil(plan.page.width),height=Math.ceil(plan.page.height),canvas=createCanvas(width,height),ctx=canvas.getContext('2d');
for(let i=0;i<plan.items.length;i++){
 const item=plan.items[i],p=item.paint,b=p.bounds;if(!b)continue;
 if(item.kind==='path'&&!p.filled&&!p.stroked)continue;
 let path=p.fill_path||p.svg_path;
 if(item.kind==='image'){const q=p.quad;path=`M ${q.p0.x} ${height-q.p0.y} L ${q.p1.x} ${height-q.p1.y} L ${q.p2.x} ${height-q.p2.y} L ${q.p3.x} ${height-q.p3.y} Z`;}
 if(!path)continue;
 // Bounds select candidates only; actual Canvas path coverage decides a hit.
 const pts=pixels.filter(q=>q.x+4>=b.min_x&&q.x-4<=b.max_x&&q.y+4>=height-b.max_y&&q.y-4<=height-b.min_y);if(!pts.length)continue;
 ctx.clearRect(0,0,width,height);ctx.save();ctx.fillStyle=ctx.strokeStyle='white';
 for(const clip of p.clips||[])ctx.clip(new Path2D(clip.svg_path),clip.even_odd?'evenodd':'nonzero');
 const stroke=item.kind==='path'&&!p.filled&&p.stroked;
 if(stroke){const s=p.stroke;if(s){ctx.setTransform(...s.transform);ctx.lineWidth=s.line_width;ctx.setLineDash(s.dash_array||[]);ctx.lineDashOffset=s.dash_phase||0;ctx.miterLimit=s.miter_limit||10;path=s.svg_path;}else ctx.lineWidth=p.line_width;ctx.lineCap=['butt','round','square'][p.line_cap||0];ctx.lineJoin=['miter','round','bevel'][p.line_join||0];ctx.stroke(new Path2D(path));}
 else ctx.fill(new Path2D(path),p.fill_even_odd?'evenodd':'nonzero');
 ctx.restore();
 const x0=Math.min(...pts.map(q=>q.x)),y0=Math.min(...pts.map(q=>q.y)),w=1+Math.max(...pts.map(q=>q.x))-x0,h=1+Math.max(...pts.map(q=>q.y))-y0;
 const rgba=ctx.getImageData(x0,y0,w,h).data;
 for(const q of pts){const alpha=rgba[((q.y-y0)*w+q.x-x0)*4+3];if(alpha)q.last={index:i,kind:item.kind,alpha,operation:stroke?'stroke':'fill',source:item.kind==='image'?p.resource?.ink_samples?.source_colour:stroke?p.stroke_source:p.fill_source,text:p.text,resource:p.resource?.name,overprint:stroke?p.stroke_overprint:p.fill_overprint,opm:p.overprint_mode};}
}
canvas.width=1;writeFileSync(process.argv[4],JSON.stringify(pixels)+'\n');

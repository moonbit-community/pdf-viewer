// Characterize independent Canvas path coverage without changing geometry,
// opacity, compositing equations, or production acceptance thresholds.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {mkdirSync,writeFileSync,readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {renderPdfCanvas} from '../../web/pdf-canvas.mjs';
const {createCanvas,Path2D,loadImage}=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url)('@napi-rs/canvas');
const dir=resolve('_build/coverage-seams');mkdirSync(dir,{recursive:true});
const paths=['M4 4H30.221V36H4Z','M30.221 4H56V36H30.221Z'],colour='#9ea0a1';
const page={number:1,origin_x:0,origin_y:0,width:60,height:40,blend_space:'DeviceRGB'};
let plan={version:1,page,viewport:{width:60,height:40,matrix:[1,0,0,-1,0,40]},items:paths.map(svg_path=>({kind:'path',paint:{svg_path,filled:true,stroked:false,fill_color:colour,fill_alpha:1,blend_mode:'normal'}}))};
const content=`${158/255} ${160/255} ${161/255} rg 4 4 26.221 32 re f 30.221 4 25.779 32 re f`;
const objects=['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R] /Count 1 >>','<< /Type /Page /Parent 2 0 R /MediaBox [0 0 60 40] /Resources << >> /Contents 4 0 R >>',`<< /Length ${content.length} >>\nstream\n${content}\nendstream`];
let pdf='%PDF-1.7\n',offsets=[0];for(const [i,object] of objects.entries()){offsets.push(pdf.length);pdf+=`${i+1} 0 obj\n${object}\nendobj\n`;}const xref=pdf.length;pdf+=`xref\n0 5\n0000000000 65535 f \n${offsets.slice(1).map(n=>String(n).padStart(10,'0')+' 00000 n \n').join('')}trailer << /Size 5 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
writeFileSync(`${dir}/adjacent-fills.pdf`,pdf);
if(process.argv[2]){const bridge=await import(pathToFileURL(resolve(process.argv[2])));const result=JSON.parse(bridge.render_plan(Buffer.from(pdf),1,1,0));assert.ok(result.ok,result.error);plan=result.canvas;}
const actual=createCanvas(60,40),rendered=await renderPdfCanvas(actual,plan,{createCanvas,Path2D,loadImage});
const native=createCanvas(60,40),context=native.getContext('2d');context.fillStyle='#fff';context.fillRect(0,0,60,40);context.fillStyle=colour;for(const path of paths)context.fill(new Path2D(path));
const union=createCanvas(60,40),ux=union.getContext('2d');ux.fillStyle='#fff';ux.fillRect(0,0,60,40);ux.fillStyle=colour;ux.fill(new Path2D(paths.join(' ')));
const coverage=paths.map(path=>{const c=createCanvas(60,40),x=c.getContext('2d');x.fill(new Path2D(path));return x.getImageData(30,20,1,1).data[3]/255;});
execFileSync('gs',['-q','-dSAFER','-dBATCH','-dNOPAUSE','-sDEVICE=png16m','-dGraphicsAlphaBits=4','-r72',`-sOutputFile=${dir}/ghostscript.png`,`${dir}/adjacent-fills.pdf`]);
const reference=createCanvas(60,40);reference.getContext('2d').drawImage(await loadImage(`${dir}/ghostscript.png`),0,0);
const pixel=c=>[...c.getContext('2d').getImageData(30,20,1,1).data];
const raw=context.getImageData(0,0,60,40).data;let maximum=0;for(let i=0;i<raw.length;i++)maximum=Math.max(maximum,Math.abs(raw[i]-rendered.data[i]));assert.ok(maximum<=1,'backend must reproduce host separate-fill coverage');
const report={sha256:createHash('sha256').update(pdf).digest('hex'),ghostscript:execFileSync('gs',['--version'],{encoding:'utf8'}).trim(),point:[30,20],coverage,combinedAlpha:coverage[1]+coverage[0]*(1-coverage[1]),canvas:pixel(actual),directHost:pixel(native),oneCompoundPath:pixel(union),ghostscriptPixel:pixel(reference),maximumBackendVersusHost:maximum};
for(const [name,canvas] of [['canvas',actual],['host',native],['compound-control',union]])writeFileSync(`${dir}/${name}.png`,canvas.toBuffer('image/png'));
writeFileSync(`${dir}/report.json`,JSON.stringify(report,null,2));console.log(JSON.stringify(report));

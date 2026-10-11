#!/usr/bin/env node
// Local-only real ICC printing-page acceptance. PDFs and raster evidence are
// not redistributed. Poppler's installed LCMS backend is the colour oracle;
// PDF.js Node defaults disable its synchronous ICC worker backend.
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,basename} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {renderPdfCanvas} from '../web/pdf-canvas.mjs';
import {createShadingPainter} from '../web/pdf-shading.mjs';
import {createPatternPainter} from '../web/pdf-patterns.mjs';
import {installPdfIccEngine} from '../web/pdf-icc.mjs';
import {installJbig2Decoder} from '../codecs/jbig2/decoder.mjs';
const require=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url);
const {createCanvas,Path2D,loadImage}=require('@napi-rs/canvas');
if(process.argv.length<4)throw Error('usage: node tools/colour_canvas_compare.mjs bridge.mjs input.pdf [...]');
const bridge=await import(pathToFileURL(resolve(process.argv[2])));
const destination=resolve(process.env.PDF_PIXEL_OUTPUT||'_build/colour-canvas');mkdirSync(destination,{recursive:true});
const engine=await installPdfIccEngine();
await installJbig2Decoder({wasmBytes:readFileSync(new URL('../vendor/jbig2/jbig2.wasm',import.meta.url))});
const report=[];
try {
 for(const filename of process.argv.slice(3)){
  const bytes=readFileSync(filename),name=basename(filename,'.pdf'),prefix=resolve(destination,name),before={...engine.statistics};
  const result={file:basename(filename),sha256:createHash('sha256').update(bytes).digest('hex'),page:1,scale:1,oracle:'installed Poppler/LCMS',engine:engine.name};
  const start=performance.now(),rss=process.memoryUsage().rss;
  try {
   const parsed=process.env.PDF_CANVAS_PLAN?{ok:true,canvas:JSON.parse(readFileSync(process.env.PDF_CANVAS_PLAN,'utf8'))}:JSON.parse(bridge.render_plan(new Uint8Array(bytes),1,1,0));if(!parsed.ok)throw Error(parsed.error);
   const plan=parsed.canvas;writeFileSync(prefix+'.plan.json',JSON.stringify(plan));
   result.profileCatalog=(plan.icc_profiles||[]).map(p=>({id:p.id,components:p.components,bytes:Buffer.from(p.data_base64,'base64').length}));
   result.pageBlendSpace=plan.blend_space;result.pageBlendProfile=plan.blend_profile_id;
   result.groupProfiles=[...new Set(plan.items.flatMap(item=>(item.groups||[]).map(group=>group.icc_profile_id).filter(Boolean)))];
   result.itemKinds=Object.fromEntries([...new Set(plan.items.map(i=>i.kind))].map(kind=>[kind,plan.items.filter(i=>i.kind===kind).length]));
   const options={createCanvas,Path2D,loadImage,convertProcess:values=>bridge.process_cmyk_to_rgb(...values)};
   if(process.env.PDF_CANVAS_UNSUPPORTED==='warn'){options.unsupported='warn';result.warningOnlyDiagnosticRun=true;}
   if(process.env.PDF_FULL_SURFACE==='1'){options.fullSurfaceReplay=true;result.fullSurfaceReplay=true;}
   options.paintShading=createShadingPainter(options);options.paintPattern=createPatternPainter(options);
   const target=createCanvas(1,1),rendered=await renderPdfCanvas(target,plan,options);
   writeFileSync(prefix+'.canvas.png',target.toBuffer('image/png'));
   result.width=target.width;result.height=target.height;result.diagnostics=rendered.diagnostics;
   const proof=[];
   if(process.env.PDF_PROOF==='1'){
    proof.push('-overprint');const profile=plan.icc_profiles?.find(p=>p.id===plan.blend_profile_id);
    if(profile){const file=prefix+'.output-profile.icc';writeFileSync(file,Buffer.from(profile.data_base64,'base64'));proof.push(({1:'-defaultgrayprofile',3:'-defaultrgbprofile',4:'-defaultcmykprofile'})[profile.components],file);}
    result.oracle='installed Poppler/LCMS with overprint and actual page output profile';result.oracleSettings=proof;
   }
   const poppler=spawnSync('pdftoppm',['-f','1','-singlefile','-r','72','-png',...proof,resolve(filename),prefix+'.poppler'],{encoding:'utf8',maxBuffer:1024*1024});
   if(poppler.status!==0)throw Error(`Poppler failed: ${poppler.stderr}`);
   result.oracleWarnings=poppler.stderr.trim();
   const image=await loadImage(prefix+'.poppler.png'),reference=createCanvas(image.width,image.height),ctx=reference.getContext('2d');ctx.drawImage(image,0,0);
   if(reference.width!==target.width||reference.height!==target.height){result.dimensionMismatch={actual:[target.width,target.height],reference:[reference.width,reference.height]};}
   else {
    const ref=ctx.getImageData(0,0,target.width,target.height).data,actual=target.getContext('2d').getImageData(0,0,target.width,target.height).data;
    let above8=0,maximum=0,absolute=0;for(let i=0;i<ref.length;i+=4){let error=0;for(let c=0;c<3;c++){const difference=Math.abs(ref[i+c]-actual[i+c]);error=Math.max(error,difference);absolute+=difference;}if(error>8)above8++;maximum=Math.max(maximum,error);}
    result.comparison={pixels:target.width*target.height,above8,maximum,meanAbsoluteError:absolute/(target.width*target.height*3)};
   }
  }catch(error){result.error=String(error.stack||error);}
  result.milliseconds=performance.now()-start;result.rssDelta=process.memoryUsage().rss-rss;
  result.iccCounters=Object.fromEntries(Object.entries(engine.statistics).map(([key,value])=>[key,value-(before[key]||0)]));
  report.push(result);console.log(JSON.stringify(result));writeFileSync(destination+'/report.json',JSON.stringify(report,null,2));
 }
}finally{engine.dispose();}

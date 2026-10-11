// A real unembedded-font PDF, the same-font embedded A1 geometry oracle,
// and the optional native-host outline capability. No browser claim.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {pathToFileURL} from 'node:url';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {createNativeTextOutlineResolver} from '../../web/pdf-native-text.mjs';
const require=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url);
const {createCanvas,Path2D,loadImage,GlobalFonts,convertSVGTextToPath}=require('@napi-rs/canvas');
const {Resvg}=require('@resvg/resvg-js');
const pdfjs=await import(pathToFileURL(require.resolve('pdfjs-dist/legacy/build/pdf.mjs')));
const rendererUrl=process.env.PDF_CANVAS_RENDERER?pathToFileURL(resolve(process.env.PDF_CANVAS_RENDERER)):new URL('../../web/pdf-canvas.mjs',import.meta.url);
const {renderPdfCanvas}=await import(rendererUrl);
const [bridgePath,directory='_build/text-host-pen']=process.argv.slice(2);
assert(bridgePath,'Pass fresh browser bridge.mjs and generated fixture directory');
mkdirSync(directory,{recursive:true});
const bridge=await import(pathToFileURL(resolve(bridgePath)));
const font=readFileSync(require.resolve('pdfjs-dist/standard_fonts/LiberationSans-Regular.ttf'));
assert(GlobalFonts.register(font,'Liberation Sans'));
const nativeResolver=createNativeTextOutlineResolver({convertSVGTextToPath,Path2D});
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const pixels=canvas=>canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data;
const compare=(a,b)=>{assert.equal(a.length,b.length);let sum=0,max=0,changed=0;for(let i=0;i<a.length;i+=4){let pixel=0;for(let c=0;c<3;c++){const d=Math.abs(a[i+c]-b[i+c]);sum+=d;max=Math.max(max,d);pixel=Math.max(pixel,d);}if(pixel>8)changed++;}return{meanAbsoluteError:sum/(a.length/4*3),maximum:max,changedAbove8:changed};};
function directPathPdf(svgPath,pen,page){
 const tokens=svgPath.match(/[A-Za-z]|[-+]?(?:\d*\.)?\d+(?:[eE][-+]?\d+)?/g)||[];
 const ops=[];
 for(let i=0;i<tokens.length;){const command=tokens[i++];if(command==='Z'){ops.push('h');continue;}assert(command==='M'||command==='L','Control fixture needs only line contours');const x=Number(tokens[i++]),y=-Number(tokens[i++]);ops.push(`${x} ${y} ${command==='M'?'m':'l'}`);}
 const m=pen.transform;
 const content=`q ${m[0]} ${-m[1]} ${-m[2]} ${m[3]} ${m[4]+page.origin_x} ${page.origin_y+page.height-m[5]} cm ${pen.line_width} w ${pen.line_cap} J ${pen.line_join} j ${pen.miter_limit} M ${ops.join(' ')} S Q`;
 const objects=['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Count 1 /Kids [3 0 R] >>',`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${page.width} ${page.height}] /Resources << >> /Contents 4 0 R >>`,`<< /Length ${content.length} >>\nstream\n${content}\nendstream`];
 let result='%PDF-1.7\n';const offsets=[];objects.forEach((o,i)=>{offsets.push(result.length);result+=`${i+1} 0 obj\n${o}\nendobj\n`;});const xref=result.length;result+=`xref\n0 5\n0000000000 65535 f \n`+offsets.map(n=>`${String(n).padStart(10,'0')} 00000 n \n`).join('')+`trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;return result;
}
async function quarterTurnFile(filename,width,height,rotation){
 const image=await loadImage(filename),canvas=createCanvas(width,height),ctx=canvas.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,width,height);if(rotation===90)ctx.translate(width,0);if(rotation===180)ctx.translate(width,height);if(rotation===270)ctx.translate(0,height);ctx.rotate(rotation*Math.PI/180);ctx.drawImage(image,0,0);return canvas;
}
const report={bridgeSha256:sha(readFileSync(bridgePath)),nativeCanvas:require('@napi-rs/canvas/package.json').version,resvg:require('@resvg/resvg-js/package.json').version,pdfSha256:sha(readFileSync(`${directory}/text-host-pen.pdf`)),fontSha256:sha(font),pdfjs:pdfjs.version,cases:[]};
for(const scale of [1,2])for(const rotation of [0,90,180,270]){
 const plans=[];
 for(const name of ['text-host-pen.pdf','text-host-pen-embedded-control.pdf']){
  const opened=JSON.parse(bridge.open_pdf(new Uint8Array(readFileSync(`${directory}/${name}`))));assert(opened.ok);
  if(name==='text-host-pen.pdf')assert(JSON.parse(bridge.set_font_fallbacks(JSON.stringify([{pdf_name:'/F1',family:'Liberation Sans'}]))).ok);
  const parsed=JSON.parse(bridge.render_page(1,scale,rotation));assert(parsed.ok);plans.push(parsed);bridge.close_pdf();
 }
 const original=plans[0],control=plans[1],item=original.canvas.items.find(i=>i.kind==='text');
 if(scale===1&&rotation===0)writeFileSync(`${directory}/public.canvas.json`,JSON.stringify(original.canvas));
 assert.equal(item.paint.stroke.svg_path,undefined);assert.equal(item.paint.stroke.unresolved,'affine-text-pen-requires-glyph-outline');
 let strictRejected=false;try{await renderPdfCanvas(createCanvas(1,1),original.canvas,{createCanvas,Path2D,loadImage});}catch(e){strictRejected=String(e).includes('PDF_TEXT_STROKE_GEOMETRY');}assert(strictRejected);
 const target=createCanvas(1,1),approx=createCanvas(1,1),expected=createCanvas(1,1);
 const base={createCanvas,Path2D,loadImage,convertProcess:v=>bridge.process_cmyk_to_rgb(...v)};
 const exact=await renderPdfCanvas(target,original.canvas,{...base,resolveTextOutline:nativeResolver});assert.deepEqual(exact.diagnostics,[]);
 const unresolved=await renderPdfCanvas(approx,original.canvas,{...base,unsupported:'warn'});
 const known=await renderPdfCanvas(expected,control.canvas,base);
 const outlined=nativeResolver(item.text_svg,{paint:item.paint,page:original.canvas.page});assert(outlined);
 const directFilename=`${directory}/text-host-pen-path-control.pdf`;
 if(scale===1&&rotation===0)writeFileSync(directFilename,directPathPdf(outlined.stroke_path,item.paint.stroke,original.canvas.page));
 const directPrefix=`${directory}/path-poppler-${scale}`,gsPrefix=`${directory}/path-ghostscript-${scale}.png`;
 if(rotation===0){
  execFileSync('pdftoppm',['-r',String(scale*72),'-singlefile','-png',directFilename,directPrefix]);
  execFileSync('gs',['-q','-dSAFER','-dBATCH','-dNOPAUSE','-sDEVICE=png16m','-dTextAlphaBits=4','-dGraphicsAlphaBits=4',`-r${72*scale}`,`-sOutputFile=${gsPrefix}`,directFilename]);
 }
 const directPoppler=await quarterTurnFile(directPrefix+'.png',exact.width,exact.height,rotation),directGs=await quarterTurnFile(gsPrefix,exact.width,exact.height,rotation);
 const filename=`${directory}/text-host-pen.pdf`;
 const task=pdfjs.getDocument({data:new Uint8Array(readFileSync(filename)),standardFontDataUrl:resolve(require.resolve('pdfjs-dist/package.json'),'../standard_fonts/')+'/',useSystemFonts:false,isEvalSupported:false});
 const doc=await task.promise,page=await doc.getPage(1),vp=page.getViewport({scale,rotation});
 const reference=createCanvas(Math.ceil(vp.width),Math.ceil(vp.height));await page.render({canvasContext:reference.getContext('2d'),viewport:vp}).promise;await task.destroy();
 const prefix=`${directory}/poppler-${scale}`;if(rotation===0)execFileSync('pdftoppm',['-r',String(scale*72),'-singlefile','-png',filename,prefix]);
 const popImage=await loadImage(prefix+'.png'),poppler=createCanvas(exact.width,exact.height),pc=poppler.getContext('2d');pc.fillStyle='#fff';pc.fillRect(0,0,exact.width,exact.height);if(rotation===90)pc.translate(exact.width,0);if(rotation===180)pc.translate(exact.width,exact.height);if(rotation===270)pc.translate(0,exact.height);pc.rotate(rotation*Math.PI/180);pc.drawImage(popImage,0,0);
 const svg=new Resvg(original.svg,{background:'#fff',font:{fontBuffers:[font],loadSystemFonts:false}}).render();
 const result={scale,rotation,strictRejected,hostVsDirectPathPoppler:compare(exact.data,pixels(directPoppler)),hostVsDirectPathGhostscript:compare(exact.data,pixels(directGs)),hostVsSameFontEmbedded:compare(exact.data,known.data),approxVsSameFontEmbedded:compare(unresolved.data,known.data),hostVsPdfjs:compare(exact.data,pixels(reference)),hostVsPoppler:compare(exact.data,pixels(poppler)),legacySvgVsSameFontEmbedded:compare(svg.pixels,known.data)};
 assert.equal(result.hostVsSameFontEmbedded.maximum,0,'Host conversion must match the existing same-font A1 geometry exactly');
 assert(result.approxVsSameFontEmbedded.meanAbsoluteError>1,'The authored PDF must expose the independent-pen approximation');
 report.cases.push(result);console.log(JSON.stringify(result));
 for(const [name,canvas]of[['host',target],['approx',approx],['embedded',expected],['pdfjs',reference],['poppler',poppler],['path-poppler',directPoppler],['path-ghostscript',directGs]])writeFileSync(`${directory}/${scale}-${rotation}-${name}.png`,canvas.toBuffer('image/png'));
 writeFileSync(`${directory}/${scale}-${rotation}-legacy.svg`,original.svg);
}
// A separate public CLI process has no test font registration. Exercise both
// the existing default A1 family list and an explicit installed family.
assert(JSON.parse(bridge.open_pdf(new Uint8Array(readFileSync(`${directory}/text-host-pen.pdf`)))).ok);
const defaultPlan=JSON.parse(bridge.render_page(1,1,0));assert(defaultPlan.ok);bridge.close_pdf();
writeFileSync(`${directory}/default.canvas.json`,JSON.stringify(defaultPlan.canvas));
report.publicCli={};
for(const name of ['default','public']){
 const stdout=execFileSync(process.execPath,[fileURLToPath(new URL('../render_canvas.mjs',import.meta.url)),`${directory}/${name}.canvas.json`,`${directory}/${name}.png`],{env:{...process.env,PDF_VIEWER_BRIDGE:resolve(bridgePath)},encoding:'utf8'});
 const result=JSON.parse(stdout);assert.deepEqual(result.diagnostics,[]);
 const image=await loadImage(`${directory}/${name}.png`),canvas=createCanvas(image.width,image.height);canvas.getContext('2d').drawImage(image,0,0);
 assert(pixels(canvas).some((v,i)=>i%4!==3&&v<240),'The default host route must not silently return blank output');
 const control=await quarterTurnFile(`${directory}/1-0-host.png`,image.width,image.height,0);
 report.publicCli[name]={...result,vsRegisteredControl:compare(pixels(canvas),pixels(control)),fontRegistrationInCli:false};
}
assert(JSON.parse(bridge.open_pdf(new Uint8Array(readFileSync(`${directory}/text-host-space.pdf`)))).ok);
const space=JSON.parse(bridge.render_page(1,1,0));assert(space.ok);bridge.close_pdf();
const spaceBefore=JSON.stringify(space.canvas.items);
assert.equal(space.canvas.items.find(i=>i.kind==='text').paint.text,' ');
const blank=await renderPdfCanvas(createCanvas(1,1),space.canvas,{createCanvas,Path2D,loadImage,resolveTextOutline:nativeResolver});
assert.deepEqual(blank.diagnostics,[]);assert.equal(JSON.stringify(space.canvas.items),spaceBefore,'No-paint whitespace must retain its source item');
assert(blank.data.every(v=>v===255),'The stroked space has no painted contour');
report.whitespace={diagnostics:blank.diagnostics,sourceItemPreserved:true,blank:true};
writeFileSync(`${directory}/report.json`,JSON.stringify(report,null,2));

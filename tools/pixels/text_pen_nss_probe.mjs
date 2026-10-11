// Capability probe for a separate pen-local SVG image, using an actual A1
// host-font text fragment. The independent CTM is applied once by Canvas.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {createNativeTextOutlineResolver} from '../../web/pdf-native-text.mjs';
const require=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url);
const {createCanvas,Path2D,loadImage,convertSVGTextToPath,GlobalFonts}=require('@napi-rs/canvas');
const {Resvg}=require('@resvg/resvg-js');
const [planName,destination='_build/text-host-pen/nss']=process.argv.slice(2);assert(planName);
mkdirSync(destination,{recursive:true});
const font=readFileSync(require.resolve('pdfjs-dist/standard_fonts/LiberationSans-Regular.ttf'));GlobalFonts.register(font,'Liberation Sans');
const plan=JSON.parse(readFileSync(planName)),item=plan.items.find(i=>i.kind==='text'),pen=item.paint.stroke,m=pen.transform;
const source=item.text_svg;
const resolved=createNativeTextOutlineResolver({convertSVGTextToPath,Path2D})(source,{paint:item.paint});assert(resolved);
const inverse=(()=>{const d=m[0]*m[3]-m[1]*m[2];return[m[3]/d,-m[1]/d,-m[2]/d,m[0]/d,(m[2]*m[5]-m[3]*m[4])/d,(m[1]*m[4]-m[0]*m[5])/d];})();
const body=source.replace(/^[\s\S]*?<svg[^>]*>/,'').replace(/<\/svg>\s*$/,'').replace(/\bstroke-width="[^"]*"/,`stroke-width="${pen.line_width}" vector-effect="non-scaling-stroke"`);
const svg=body=>`<svg xmlns="http://www.w3.org/2000/svg" width="240" height="160" viewBox="-20 -120 240 160">${body}</svg>`;
const exported=convertSVGTextToPath(source).toString();
const outlineBody=[...exported.matchAll(/<path\b([^>]*)>/g)].map(([,attributes])=>{const d=/\bd="([^"]*)"/.exec(attributes)?.[1],transform=/\btransform="([^"]*)"/.exec(attributes)?.[1];assert(d);return `<path d="${d}" ${transform?`transform="${transform}"`:''} fill="none" stroke="black" stroke-width="${pen.line_width}" vector-effect="non-scaling-stroke"/>`;}).join('');
const local=content=>svg(`<g transform="matrix(${inverse.join(' ')})">${content}</g>`);
const candidates={nss:local(body),textNoNss:local(body.replace(' vector-effect="non-scaling-stroke"','')),outlineNss:local(outlineBody),path:svg(`<path d="${resolved.stroke_path}" fill="none" stroke="black" stroke-width="${pen.line_width}" stroke-miterlimit="${pen.miter_limit}"/>`)};
for(const[name,value]of Object.entries(candidates))writeFileSync(`${destination}/${name}.svg`,value);
const compare=(a,b)=>{let sum=0,max=0,count=0;for(let i=0;i<a.length;i+=4){let e=0;for(let c=0;c<3;c++){const d=Math.abs(a[i+c]-b[i+c]);sum+=d;e=Math.max(e,d);max=Math.max(max,d);}if(e>8)count++;}return{meanAbsoluteError:sum/(a.length/4*3),maximum:max,changedAbove8:count};};
const data=c=>c.getContext('2d').getImageData(0,0,c.width,c.height).data;
async function transformed(bytes){const image=await loadImage(bytes),canvas=createCanvas(plan.page.width,plan.page.height),ctx=canvas.getContext('2d');ctx.fillStyle='#fff';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.setTransform(...m);ctx.drawImage(image,-20,-120,240,160);return canvas;}
const report={};
for(const host of ['nativeSvg','resvg']){const results={};for(const[name,value]of Object.entries(candidates)){results[name]=await transformed(host==='nativeSvg'?Buffer.from(value):new Resvg(value,{font:{fontBuffers:[font],loadSystemFonts:false}}).render().asPng());writeFileSync(`${destination}/${host}-${name}.png`,results[name].toBuffer('image/png'));}report[host]={textNssVsPath:compare(data(results.nss),data(results.path)),textNssVsNoNss:compare(data(results.nss),data(results.textNoNss)),outlineNssVsPath:compare(data(results.outlineNss),data(results.path))};}
const python=String.raw`
import ctypes as c,sys
r=c.CDLL('librsvg-2.so.2');a=c.CDLL('libcairo.so.2')
r.rsvg_handle_new_from_data.argtypes=[c.c_void_p,c.c_size_t,c.POINTER(c.c_void_p)];r.rsvg_handle_new_from_data.restype=c.c_void_p
r.rsvg_handle_render_cairo.argtypes=[c.c_void_p,c.c_void_p];r.rsvg_handle_render_cairo.restype=c.c_int
a.cairo_image_surface_create.argtypes=[c.c_int,c.c_int,c.c_int];a.cairo_image_surface_create.restype=c.c_void_p
a.cairo_create.argtypes=[c.c_void_p];a.cairo_create.restype=c.c_void_p
a.cairo_surface_write_to_png.argtypes=[c.c_void_p,c.c_char_p]
for name in ['nss','textNoNss','outlineNss','path']:
 data=open(sys.argv[1]+'/'+name+'.svg','rb').read();buf=c.create_string_buffer(data);error=c.c_void_p();h=r.rsvg_handle_new_from_data(buf,len(data),c.byref(error));assert h and not error.value
 surface=a.cairo_image_surface_create(0,240,160);ctx=a.cairo_create(surface);assert r.rsvg_handle_render_cairo(h,ctx);assert a.cairo_surface_write_to_png(surface,(sys.argv[1]+'/librsvg-'+name+'.png').encode())==0
`;
try{execFileSync('python3',['-c',python,destination]);const a=await transformed(readFileSync(`${destination}/librsvg-nss.png`)),b=await transformed(readFileSync(`${destination}/librsvg-path.png`));const noNss=await transformed(readFileSync(`${destination}/librsvg-textNoNss.png`)),outlineNss=await transformed(readFileSync(`${destination}/librsvg-outlineNss.png`));report.librsvg={textNssVsPath:compare(data(a),data(b)),textNssVsNoNss:compare(data(a),data(noNss)),outlineNssVsPath:compare(data(outlineNss),data(b))};writeFileSync(`${destination}/librsvg-nss-page.png`,a.toBuffer('image/png'));writeFileSync(`${destination}/librsvg-path-page.png`,b.toBuffer('image/png'));}catch(error){report.librsvg={unavailable:String(error)};}
writeFileSync(`${destination}/report.json`,JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));

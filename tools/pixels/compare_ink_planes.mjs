/** Independent process-plane oracle: compare against Ghostscript tiffsep before
 * display ICC conversion. Requires gs, Python3/Pillow/numpy, and the normal
 * Node Canvas test package. Usage: node compare_ink_planes.mjs bridge pdf pages */
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,basename} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {renderPdfCanvas} from '../../web/pdf-canvas.mjs';
const [bridgeFile,filename,countText]=process.argv.slice(2),count=Number(countText);
if(!bridgeFile||!filename||!Number.isInteger(count)||count<1)throw new Error('Usage: compare_ink_planes.mjs bridge.mjs fixture.pdf page-count');
const require=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url),{createCanvas,Path2D,loadImage}=require('@napi-rs/canvas');
const bridge=await import(pathToFileURL(resolve(bridgeFile))),bytes=readFileSync(filename);
const directory=resolve(process.env.PDF_PIXEL_OUTPUT||`_build/ink-planes-${basename(filename,'.pdf')}`);mkdirSync(directory,{recursive:true});
const ghostscript=execFileSync('gs',['--version'],{encoding:'utf8'}).trim();
execFileSync('gs',['-q','-dSAFER','-dBATCH','-dNOPAUSE','-sDEVICE=tiffsep','-r72',`-sOutputFile=${directory}/reference-%d.tif`,resolve(filename)]);
for(let page=1;page<=count;page++){
 const parsed=JSON.parse(bridge.render_plan(bytes,page,1,0));if(!parsed.ok)throw new Error(parsed.error);
 const canvas=createCanvas(1,1),result=await renderPdfCanvas(canvas,parsed.canvas,{createCanvas,Path2D,loadImage,convertProcess:v=>bridge.process_cmyk_to_rgb(...v),returnInks:true});
 if(!result.inkProof)throw new Error('Plane oracle requires an explicit DeviceCMYK page group');
 const proof=result.inkProof;
 for(let c=0;c<4;c++){
  const values=new Uint8Array(result.width*result.height);
  for(let p=0;p<values.length;p++)values[p]=Math.round(proof.premultiplied[p*proof.stride+c]*255);
  writeFileSync(`${directory}/actual-${page}-${c}.raw`,values);
 }
 writeFileSync(`${directory}/actual-${page}.png`,canvas.toBuffer('image/png'));
}
const cases=JSON.parse(execFileSync('python3',['-c',String.raw`
from PIL import Image
import numpy as np,json,sys
root,count=sys.argv[1],int(sys.argv[2]);report=[]
for page in range(1,count+1):
 channels=[]
 for c,name in enumerate(['Cyan','Magenta','Yellow','Black']):
  ref=255-np.array(Image.open(f'{root}/reference-{page}({name}).tif')).astype(int)
  actual=np.fromfile(f'{root}/actual-{page}-{c}.raw',dtype=np.uint8).reshape(ref.shape).astype(int)
  diff=abs(ref-actual)
  channels.append(dict(name=name,maximum=int(diff.max()),meanAbsoluteError=float(diff.mean()),changedAbove2=int((diff>2).sum())))
 report.append(dict(page=page,channels=channels))
print(json.dumps(report))
`,directory,String(count)],{encoding:'utf8'}));
const report={file:basename(filename),sha256:createHash('sha256').update(bytes).digest('hex'),ghostscript,format:'premultiplied CMYK over zero-ink paper, 8-bit comparison',cases};
writeFileSync(`${directory}/report.json`,JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));

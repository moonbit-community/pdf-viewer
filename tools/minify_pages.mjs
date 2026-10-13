// Reuse the locked build tool for the published modules and Worker. Keep the
// development output readable for profiling; optimize only the published site.
import {readFile,writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';

const root=fileURLToPath(new URL('../',import.meta.url));
const require=createRequire(resolve(root,'tools/web-assets/package.json'));
const esbuild=require('esbuild-wasm');
if(esbuild.version!=='0.25.12')throw Error('Pages build requires locked esbuild-wasm 0.25.12');
try {
  for(const module of ['pdf','viewer']){
    const path=resolve(root,`_build/pages/_generated/${module}.js`);
    const source=await readFile(path,'utf8');
    const result=await esbuild.transform(source,{
      loader:'js',format:'esm',target:'es2022',minify:true,legalComments:'inline',
    });
    await writeFile(path,result.code);
    console.log(`Published ${module}.js: ${Buffer.byteLength(source)} → ${Buffer.byteLength(result.code)} bytes.`);
  }
  const worker=resolve(root,'_build/pages/pdf-worker.js');
  // A single entry avoids a network waterfall before any PDF can open. XFA
  // remains an external lazy import; Node-only codec paths never run here.
  const result=await esbuild.build({
    entryPoints:[worker],bundle:true,write:false,outfile:worker,
    platform:'browser',format:'esm',target:'es2022',minify:true,
    legalComments:'inline',metafile:true,
    external:['./pdf-xfa.mjs','node:*','fs','path','module'],
  });
  const entry=Object.values(result.metafile.outputs)[0];
  if(entry.imports.some(dependency=>dependency.kind!=='dynamic-import'))
    throw Error('Published Worker must start without secondary module imports');
  await writeFile(worker,result.outputFiles[0].contents);
  console.log(`Published Worker: ${entry.bytes} bytes in one module.`);
} finally {esbuild.stop();}

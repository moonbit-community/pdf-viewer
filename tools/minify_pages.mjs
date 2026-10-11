// Reuse the locked build tool for MoonBit's generated ES modules. Keep the
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
} finally {esbuild.stop();}

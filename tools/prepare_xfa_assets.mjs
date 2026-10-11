import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {resolve} from 'node:path';
const root=fileURLToPath(new URL('../',import.meta.url));
const require=createRequire(resolve(root,'tools/web-assets/package.json'));
const esbuild=require('esbuild-wasm');
if(esbuild.version!=='0.25.12')throw Error('XFA build requires locked esbuild-wasm 0.25.12');
const manifest=JSON.parse(await readFile(resolve(root,'vendor/xfa/UPSTREAM.json'),'utf8'));
for(const {path,sha256} of manifest.files){
 const bytes=await readFile(resolve(root,'vendor/xfa',path));
 if(createHash('sha256').update(bytes).digest('hex')!==sha256)throw Error(`XFA upstream integrity mismatch: ${path}`);
}
const result=await esbuild.build({
 absWorkingDir:root,entryPoints:['tools/xfa_entry.mjs'],bundle:true,format:'esm',platform:'browser',
 target:'es2022',write:false,metafile:true,legalComments:'inline',
 inject:['tools/xfa_map_compat.mjs'],define:{PDFJSDev:'undefined','Uint8Array.fromBase64':'decodeXfaBase64'},
});
const inputs=Object.keys(result.metafile.inputs);
if(inputs.some(path=>/\/(?:parser|evaluator|document|worker|canvas)\.js$/.test(path)&&!path.includes('/xfa/')))throw Error('XFA bundle unexpectedly included a PDF reader or renderer');
const destination=resolve(root,'web/vendor/xfa');await mkdir(destination,{recursive:true});
await writeFile(resolve(destination,'xfa.mjs'),result.outputFiles[0].contents);
await writeFile(resolve(destination,'LICENSE'),await readFile(resolve(root,'vendor/xfa/LICENSE')));
await writeFile(resolve(destination,'xfa.css'),await readFile(resolve(root,'vendor/xfa/web/xfa_layer_builder.css')));
await writeFile(resolve(destination,'UPSTREAM.json'),JSON.stringify({...manifest,bundle_bytes:result.outputFiles[0].contents.length,bundled_modules:inputs},null,2)+'\n');
esbuild.stop();console.log(`Prepared isolated XFA layout/DOM bundle (${result.outputFiles[0].contents.length} bytes).`);

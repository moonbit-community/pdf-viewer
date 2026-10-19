// Restore source names for a published bundle without executing a different
// build. Both minification stages must reproduce the supplied site's bytes.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {resolve,dirname} from 'node:path';
import {compactPdfData} from '../compact_pdf_data.mjs';
const [site,mapFilename]=process.argv.slice(2);
assert(site&&mapFilename,'Usage: node tools/pixels/map_published_worker.mjs <packaged site> <output.js.map>');
const require=createRequire(resolve('tools/web-assets/package.json')),esbuild=require('esbuild-wasm');
assert.equal(esbuild.version,'0.25.12');
const sha=data=>createHash('sha256').update(data).digest('hex');
try{
 const readable=await readFile('web/_generated/pdf.js','utf8'),compacted=compactPdfData(readable).source;
 const first=await esbuild.transform(compacted,{loader:'js',format:'esm',target:'es2022',minify:true,legalComments:'inline',sourcemap:'external',sourcefile:'moonbit-release.js'});
 assert.equal(first.code,await readFile(resolve(site,'_generated/pdf.js'),'utf8'),'Readable bridge must reproduce the supplied published bridge');
 const result=await esbuild.build({entryPoints:[resolve('web/pdf-worker.js')],bundle:true,write:false,outfile:resolve(dirname(mapFilename),'pdf-worker.js'),platform:'browser',format:'esm',target:'es2022',minify:true,legalComments:'inline',sourcemap:'external',external:['./pdf-xfa.mjs','node:*','fs','path','module'],plugins:[{name:'map-existing-release',setup(build){build.onLoad({filter:/\/web\/_generated\/pdf\.js$/},()=>({contents:first.code+'\n//# sourceMappingURL=data:application/json;base64,'+Buffer.from(first.map).toString('base64'),loader:'js',resolveDir:resolve('web/_generated')}));}}]});
 const code=result.outputFiles.find(f=>f.path.endsWith('.js')),map=result.outputFiles.find(f=>f.path.endsWith('.map'));
 assert.equal(code.text,await readFile(resolve(site,'pdf-worker.js'),'utf8'),'Map must describe the byte-identical published Worker');
 await mkdir(dirname(resolve(mapFilename)),{recursive:true});await writeFile(mapFilename,map.contents);
 const manifest={workerSha256:sha(code.contents),mapSha256:sha(map.contents),readableSha256:sha(readable),publishedBridgeSha256:sha(first.code),esbuild:esbuild.version};
 await writeFile(mapFilename+'.verified.json',JSON.stringify(manifest,null,2)+'\n');
 console.log(JSON.stringify(manifest));
}finally{esbuild.stop();}

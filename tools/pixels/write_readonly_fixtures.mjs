import {writeFileSync,mkdirSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {rangeFixture,xfaFixture,annotationFixture} from './readonly_fixtures.mjs';
const destination=process.argv[2]||'web/_test';mkdirSync(destination,{recursive:true});
const manifest=[];
for(const [name,bytes]of [['range-large.pdf',rangeFixture()],['xfa-binding.pdf',xfaFixture()],['xfa-static.pdf',xfaFixture(false)],['annotations-readonly.pdf',annotationFixture()]]){
  writeFileSync(`${destination}/${name}`,bytes);manifest.push({name,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex'),source:'Authored in tools/pixels/readonly_fixtures.mjs',license:'Apache-2.0'});
}
writeFileSync(`${destination}/manifest.json`,JSON.stringify(manifest,null,2)+'\n');

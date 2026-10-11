import {readFileSync, mkdirSync, copyFileSync, writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import assert from 'node:assert/strict';

const manifest=JSON.parse(readFileSync('tools/ci/corpus.json','utf8'));
assert.equal(execFileSync('git',['-C','reference/pdf.js','rev-parse','HEAD'],{encoding:'utf8'}).trim(),manifest.reference_revision);
const destination='_build/ci-corpus';
mkdirSync(destination,{recursive:true});
for(const item of manifest.cases){
  assert.match(item.file,/^[\w.-]+\.pdf$/);
  const source=`reference/pdf.js/test/pdfs/${item.file}`;
  assert.equal(createHash('sha256').update(readFileSync(source)).digest('hex'),item.sha256,item.file);
  copyFileSync(source,`${destination}/${item.file}`);
}
copyFileSync('reference/pdf.js/LICENSE',`${destination}/PDFJS-LICENSE`);
writeFileSync(`${destination}/manifest.json`,JSON.stringify(manifest,null,2)+'\n');
console.log(`Verified ${manifest.cases.length} corpus inputs at ${manifest.reference_revision}`);

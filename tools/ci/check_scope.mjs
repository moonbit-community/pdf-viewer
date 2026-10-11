import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const read=path=>JSON.parse(readFileSync(path,'utf8'));
const todo=readFileSync('docs/TODO.md','utf8');
const items=[...todo.matchAll(/^- \[([x ])\] ([A-Z]-\d\d) \/ (P[012])[：:]/gm)];
assert.equal(items.length,50,'Update the documented inventory when adding/removing capabilities');
assert.equal(new Set(items.map(item=>item[2])).size,50,'Duplicate TODO IDs');
assert.equal(items.filter(item=>item[1]==='x').length,50,'Readonly gap table and checklist disagree');
assert.match(todo,/50\/50/);
assert.match(todo,/编辑、保存和签名/);
const gapTable=todo.split('## 能力差距表')[1]?.split('## ')[0] || todo;
const gaps=[...gapTable.matchAll(/^\|[^\n]*\| (\d+) \| (?:—|[^|]+) \|$/gm)];
assert.equal(gaps.length,14,'Capability table must cover 14 domains');
assert.equal(gaps.reduce((sum,row)=>sum+Number(row[1]),0),0,'Remaining domain counts disagree with the checklist');
const revision=read('tools/ci/toolchain.json').pdfjs_reference;
assert.equal(read('tools/ci/corpus.json').reference_revision,revision);
assert.equal(read('tools/ci/visual_cases.json').reference_revision,revision);
for(const directory of ['assets/annotations','vendor/xfa']){
  const upstream=read(`${directory}/UPSTREAM.json`);assert.equal(upstream.commit,revision);
  assert.equal(upstream.license,'Apache-2.0');assert.ok(readFileSync(`${directory}/LICENSE`).length>10000);
  for(const file of upstream.files)assert.equal(createHash('sha256').update(readFileSync(`${directory}/${file.path}`)).digest('hex'),file.sha256,`${directory}/${file.path}`);
}
const provenance=read('tools/ci/provenance.json');
for(const item of provenance.authored_pdfs){
  assert.equal(createHash('sha256').update(readFileSync(`web/_test/${item.name}`)).digest('hex'),item.sha256,item.name);
}
const jpeg=readFileSync('image_jpeg_wbtest.mbt','utf8').split('test "single-component JPEG sampling factors preserve raster block order"')[1].match(/@base64\.decode\(\s*"([^"]+)"/)[1];
assert.equal(createHash('sha256').update(Buffer.from(jpeg,'base64')).digest('hex'),provenance.gray_jpeg.sha256);
console.log('50 readonly IDs, fixed reference versions, authored fixtures and vendored licenses/checksums verified.');

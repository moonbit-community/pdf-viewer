import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import * as bridge from '../../web/_generated/pdf.js';
import {createXfaDocument} from '../../web/pdf-xfa.mjs';
import {xfaFixture} from './readonly_fixtures.mjs';
const parse=value=>{const result=JSON.parse(value);assert.equal(result.ok,true,result.error);return result;};
const globalMap=globalThis.Map;
parse(bridge.open_pdf(xfaFixture()));const data=parse(bridge.xfa_data());assert.equal(data.needs_rendering,true);assert.equal(data.packets.length,1);
const doc=await createXfaDocument(data,bridge);assert.equal(doc.count,2);assert.deepEqual(doc.layouts[0],{page:1,width:200,height:300,rotation:0});
const first=parse(doc.render(1,1,0));assert.ok(JSON.stringify(first.xfa.html).includes('Bound value'));assert.ok(JSON.stringify(first.xfa.html).includes('Readonly XFA heading'));
assert.equal(parse(doc.render(1,2,90)).layer.viewport.width,600);
assert.ok(parse(doc.select(1,-1,-1,-1,-1)).selection.text.includes('Readonly XFA heading'));
assert.equal(parse(doc.search('readonly',false,true,false)).results.length,1);
assert.equal(parse(doc.search('read',false,true,false)).results.length,0);
parse(bridge.open_pdf(xfaFixture(false)));assert.equal(parse(bridge.xfa_data()).needs_rendering,false);
for(const [name,count]of [['xfa_issue14315.pdf',1],['xfa_filled_imm1344e.pdf',7]]){
  parse(bridge.open_pdf(readFileSync(new URL(`../../reference/pdf.js/test/pdfs/${name}`,import.meta.url))));
  const data=parse(bridge.xfa_data());assert.ok(data.packets.length>1);const xfa=await createXfaDocument(data,bridge);assert.equal(xfa.count,count);
  if(count===7)assert.ok(parse(xfa.search('Canada',false,false,false)).results.length>20);
}
assert.equal(globalThis.Map,globalMap,'XFA compatibility must remain scoped to the bundle');
console.log('XFA: authored binding/pagination/text/rotation, static fallback, and two real documents passed.');

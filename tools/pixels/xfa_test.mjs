import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import * as bridge from '../../web/_generated/pdf.js';
import {createXfaDocument} from '../../web/pdf-xfa.mjs';
import {xfaFixture,xfaAccessFixture} from './readonly_fixtures.mjs';
import {SimpleXMLParser} from '../../web/vendor/xfa/xfa.mjs';
const parse=value=>{const result=JSON.parse(value);assert.equal(result.ok,true,result.error);return result;};
function packetValue(packets,name){
 const find=node=>node.nodeName.split(':').at(-1)===name?node:(node.childNodes||[]).map(find).find(Boolean);
 for(const packet of packets){
  const root=new SimpleXMLParser({}).parseFromString(Buffer.from(packet.data_base64,'base64').toString())?.documentElement;
  const node=root&&find(root);if(node)return node.textContent;
 }
}
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
parse(bridge.open_pdf(xfaFixture()));
const editable=await createXfaDocument(parse(bridge.xfa_data()),bridge);
const before=parse(editable.render(1,1,0));
const [fieldId]=Object.keys(before.xfa.values);
assert(fieldId,'The authored bound field must have a stable data ID');
parse(editable.apply([{kind:'xfa',data_id:fieldId,value:'Edited & Unicode 你好'}]));
assert.equal(parse(editable.render(1,1,0)).xfa.values[fieldId].value,'Edited & Unicode 你好');
parse(editable.apply([]));
assert.equal(parse(editable.render(1,1,0)).xfa.values[fieldId].value,'Bound value','Undo must restore the original dataset after serializer mutation');
parse(editable.apply([{kind:'xfa',data_id:fieldId,value:'Edited & Unicode 你好'}]));
const saved=Buffer.from(parse(bridge.save_pdf()).data,'base64');
assert.deepEqual(saved.subarray(0,xfaFixture().length),xfaFixture());
parse(bridge.open_pdf(saved));
const reopened=await createXfaDocument(parse(bridge.xfa_data()),bridge);
assert(JSON.stringify(parse(reopened.render(1,1,0)).xfa.html).includes('Edited & Unicode 你好'));
console.log('XFA: authored binding/pagination/text/rotation, static fallback, and two real documents passed.');
console.log('XFA editing: bound values, Unicode/XML escaping, undo, incremental save and fresh reopen passed.');
parse(bridge.open_pdf(xfaAccessFixture({multi:'A\nB'})));
const access=await createXfaDocument(parse(bridge.xfa_data()),bridge);
const inputs=[];
const collect=node=>{if(['input','select'].includes(node.name))inputs.push(node);node.children?.forEach(collect);};
for(let number=1;number<=access.count;number++)collect(parse(access.render(number,1,0)).xfa.html);
const unbound=inputs.find(node=>node.attributes.value==='Initial unbound');
assert(unbound);assert.equal(unbound.attributes['data-xfa-id'],undefined);
assert.throws(()=>access.apply([{kind:'xfa',data_id:unbound.attributes.dataId,value:'Lost edit'}]),/Invalid XFA field/);
const values=parse(access.render(1,1,0)).xfa.values;
const locked=inputs.filter(node=>node.attributes.multiple||['locked','protected'].includes(node.attributes['aria-label']));
assert.equal(locked.length,3);
for(const node of locked){
 const id=node.attributes['data-xfa-id'];assert(id);assert.equal(values[id].editable,false);
 assert.throws(()=>access.apply([{kind:'xfa',data_id:id,value:'Forbidden edit'}]),/Invalid XFA field/);
}
const radio=inputs.find(node=>node.attributes.type==='radio'&&node.attributes.xfaOn==='A');
assert(radio);assert.equal(values[radio.attributes['data-xfa-id']].value,'B');
parse(access.apply([{kind:'xfa',data_id:radio.attributes['data-xfa-id'],value:'A'}]));
const radioSaved=Buffer.from(parse(bridge.save_pdf()).data,'base64');
parse(bridge.open_pdf(radioSaved));
const radioReopened=await createXfaDocument(parse(bridge.xfa_data()),bridge);
inputs.length=0;
for(let number=1;number<=radioReopened.count;number++)collect(parse(radioReopened.render(number,1,0)).xfa.html);
const selected=inputs.find(node=>node.attributes.type==='radio'&&node.attributes.xfaOn==='A');
assert.equal(parse(radioReopened.render(1,1,0)).xfa.values[selected.attributes['data-xfa-id']].value,'A');
const packets=parse(bridge.xfa_data()).packets;
assert.equal(packetValue(packets,'multi'),'A\nB','Unrelated edits preserve raw unsupported multi-values');
assert.equal(packetValue(packets,'legacy'),'Existing legacy value','Unrelated edits preserve choices absent from their options');
parse(radioReopened.apply([]));
const undoPackets=parse(bridge.xfa_data()).packets;
assert.equal(packetValue(undoPackets,'multi'),'A\nB');assert.equal(packetValue(undoPackets,'choice'),'A');
console.log('XFA access: unbound, template-locked and unsupported multiselect edits reject; bound radio saves and reopens.');

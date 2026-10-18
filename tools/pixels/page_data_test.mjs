import assert from 'node:assert/strict';
import {decodePdfPageData} from '../../web/pdf-page-data.mjs';
const buffer=new Float64Array([5,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14]).buffer;
const style={font_family:'serif',font_weight:'normal',font_style:'italic',vertical:false};
const metadata={ok:true,canvas:{version:1,items:[]},layer:{version:2,page:1,viewport:{matrix:[1,0,0,1,0,0]},
 draws:{__pdf_numbers:0},text:['fi😀'],separators:['\n'],styles:[style]}};
const packet=value=>({version:1,json:JSON.stringify(value),buffers:[buffer],ranges:[[0,16]]});
const decoded=decodePdfPageData(packet(metadata));
assert.deepEqual(decoded.layer.items,[{item_index:5,text:'fi😀',separator:'\n',quad:{p0:{x:1,y:2},p1:{x:3,y:4},p2:{x:5,y:6},p3:{x:7,y:8}},matrix:[9,10,11,12,13,14],...style}]);
assert.deepEqual(decodePdfPageData(JSON.stringify(decoded)),decoded,'Legacy/XFA string recovery');
assert.deepEqual(decodePdfPageData(packet({ok:false,code:'page-missing'})),{ok:false,code:'page-missing'});
const alter=edit=>{const value=structuredClone(metadata);edit(value);return packet(value);};
for(const bad of [
 null,{}, {...packet(metadata),ranges:null},...[[0,17],[-1,1],[0,-1],[.5,1]].map(range=>({...packet(metadata),ranges:[range]})), {...packet(metadata),version:2},{...packet(metadata),buffers:null},
 {...packet(metadata),buffers:[new ArrayBuffer(7)]},
 alter(v=>v.layer.draws={__pdf_numbers:-1}),alter(v=>v.layer.draws={__pdf_numbers:1}),
 alter(v=>v.layer.draws={__pdf_numbers:0,extra:true}),alter(v=>v.layer.text=[]),
 alter(v=>v.layer.separators=[]),alter(v=>v.layer.text=[42]),alter(v=>v.layer.styles=[]),
 alter(v=>v.layer.styles[0].vertical=0),alter(v=>v.layer.styles[0].item_index=2),alter(v=>v.canvas=null),
 ...[NaN,Infinity,-1,.5].map(n=>{const b=buffer.slice(0);new Float64Array(b)[0]=n;return {...packet(metadata),buffers:[b]};}),
])assert.throws(()=>decodePdfPageData(bad));
console.log('PASS page packet exact double geometry, Unicode/separators, legacy/XFA recovery and malformed buffers/styles/operands');

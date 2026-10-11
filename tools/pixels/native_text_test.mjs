import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {createNativeTextOutlineResolver} from '../../web/pdf-native-text.mjs';
const require=createRequire(process.env.PDF_CANVAS_PACKAGE||import.meta.url);
const {Path2D}=require('@napi-rs/canvas');
const source='<svg><text>A</text></svg>';
const paint={stroke:{transform:[2,.2,.5,3,4,5]}};
const output='<svg><path transform="matrix(4 1 .5 5 10 20)" d="M0 0L10 0L0 10Z"/><path d="M4 4L5 4L5 5Z"/></svg>';
const resolver=value=>createNativeTextOutlineResolver({Path2D,convertSVGTextToPath:()=>value});
test('native host outline rebases every path into the independent pen',()=>{
 const paths=resolver(output)(source,{paint});assert.ok(paths);
 const page=new Path2D(paths.fill_path),local=new Path2D(paths.stroke_path),mapped=new Path2D();
 mapped.addPath(local,{a:2,b:.2,c:.5,d:3,e:4,f:5});
 const a=page.computeTightBounds(),b=mapped.computeTightBounds();
 a.forEach((value,i)=>assert.ok(Math.abs(value-b[i])<.00001));
});
test('missing host capability is explicit',()=>assert.throws(()=>createNativeTextOutlineResolver({Path2D}),/require/));
test('singular pen and absent pen preserve the unresolved boundary',()=>{
 assert.equal(resolver(output)(source,{paint:{}}),null);
 assert.equal(resolver(output)(source,{paint:{stroke:{transform:[0,0,0,0,0,0]}}}),null);
});
test('unsupported native SVG structures are rejected atomically',()=>{
 for(const svg of ['<svg><g><path d="M0 0L1 1"/></g></svg>','<svg><image/></svg>','<svg><svg><path d="M0 0L1 1"/></svg></svg>','<svg viewBox="1 2 30 40"><path d="M0 0L1 1"/></svg>','<svg><path clip-path="url(#a)" d="M0 0L1 1"/></svg>','<svg><path transform="scale(2)" d="M0 0L1 1"/></svg>'])assert.equal(resolver(svg)(source,{paint}),null);
});
test('conversion failure and missing glyphs do not clear diagnostics',()=>{
 assert.equal(resolver('<svg/>')(source,{paint}),null);
 const fail=createNativeTextOutlineResolver({Path2D,convertSVGTextToPath:()=>{throw Error('missing font');}});
 assert.equal(fail(source,{paint}),null);
});
test('native outline input and output budgets are bounded',()=>{
 const bounded=createNativeTextOutlineResolver({Path2D,convertSVGTextToPath:()=>output,maxSvgBytes:5});
 assert.equal(bounded(source,{paint}),null);
 assert.equal(resolver('<svg>'+'<path d="M0 0L1 1"/>'.repeat(65)+'</svg>')(source,{paint}),null);
});
test('empty converted paths are unresolved rather than successful blank glyphs',()=>{
 for(const svg of ['<svg><path d=""/></svg>','<svg><path d="   "/></svg>'])assert.equal(resolver(svg)(source,{paint}),null);
});
test('repeated pattern cells share bounded native conversion results',()=>{
 let calls=0;
 const cached=createNativeTextOutlineResolver({Path2D,convertSVGTextToPath:()=>{calls++;return output;},maxCacheEntries:2});
 const first=cached(source,{paint});first.fill_path='changed by consumer';
 for(let i=0;i<4096;i++)assert.notEqual(cached(source,{paint}).fill_path,first.fill_path);
 assert.equal(calls,1);
 cached(source.replace('A','B'),{paint});cached(source.replace('A','C'),{paint});cached(source,{paint});
 assert.equal(calls,4);
 cached(source,{paint:{stroke:{transform:[1,0,0,1,0,0]}}});assert.equal(calls,5);
});
test('cache byte budget and negative results are bounded',()=>{
 let calls=0;
 const negative=createNativeTextOutlineResolver({Path2D,convertSVGTextToPath:()=>{calls++;return '<svg/>';}});
 negative(source,{paint});negative(source,{paint});assert.equal(calls,1);
 const uncached=createNativeTextOutlineResolver({Path2D,convertSVGTextToPath:()=>{calls++;return output;},maxCacheBytes:0});
 uncached(source,{paint});uncached(source,{paint});assert.equal(calls,3);
 assert.throws(()=>createNativeTextOutlineResolver({Path2D,convertSVGTextToPath:()=>output,maxCacheEntries:-1}),/budgets/);
});

test('genuine A1 whitespace accepts a successful empty host outline',()=>{
 for(const output of ['<svg/>','<svg><path d=""/></svg>']){
   const source='<svg><text> </text></svg>';
   assert.deepEqual(resolver(output)(source,{paint}),{fill_path:'',stroke_path:''});
 }
});

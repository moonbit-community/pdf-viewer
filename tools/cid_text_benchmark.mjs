// Authored CID scaling diagnostic, not corpus latency. Exercise a large
// ToUnicode table with repeated text operations and a real embedded font.
import assert from 'node:assert/strict';
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {resolve,dirname} from 'node:path';
import {makePdf,stream} from './pixels/readonly_fixtures.mjs';

assert(process.env.PDF_BENCH_BASELINE_ROOT,'Set PDF_BENCH_BASELINE_ROOT to an independent packaged site');
const output=resolve(process.argv[2]||'_build/cid-text-benchmark/report.json');
const rows=Number(process.env.PDF_TEXT_ROWS||128),mappings=Number(process.env.PDF_CID_MAPPINGS||32768);
assert(Number.isInteger(rows)&&rows>=1&&rows<=128);
assert(Number.isInteger(mappings)&&mappings>=64&&mappings<=65536);
const hex=n=>n.toString(16).padStart(4,'0'),first=mappings-64;
const line=Array.from({length:64},(_,i)=>hex(first+i)).join('');
const content='BT /F1 8 Tf 10 TL 20 1500 Td\n'+Array.from({length:rows},(_,i)=>(i?'T* ':'')+'<'+line+'> Tj').join('\n')+'\nET';
const entries=Array.from({length:mappings},(_,i)=>'<'+hex(i)+'> <'+hex(i%64+32)+'>');
const sections=[];
for(let i=0;i<entries.length;i+=100){const batch=entries.slice(i,i+100);sections.push(batch.length+' beginbfchar\n'+batch.join('\n')+'\nendbfchar');}
const cmap='begincmap\n/CMapType 2 def\n1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n'+sections.join('\n')+'\nendcmap';
const gidMap=Buffer.alloc(mappings*2);
for(let i=0;i<mappings;i++)gidMap.writeUInt16BE(i%64+3,i*2);
const font=await readFile('reference/pdf.js/external/standard_fonts/LiberationSans-Regular.ttf');
const bytes=makePdf([
 '<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
 '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 1600] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',stream('',content),
 '<< /Type /Font /Subtype /Type0 /BaseFont /CIDScaling /Encoding /Identity-H /DescendantFonts [6 0 R] /ToUnicode 10 0 R >>',
 '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /CIDScaling /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /DW 500 /CIDToGIDMap 9 0 R /FontDescriptor 7 0 R >>',
 '<< /Type /FontDescriptor /FontName /CIDScaling /Flags 32 /FontBBox [0 -600 2100 2200] /Ascent 1900 /Descent -500 /ItalicAngle 0 /StemV 80 /FontFile2 8 0 R >>',
 stream('',font),stream('',gidMap),stream('',cmap),
]);
await mkdir(dirname(output),{recursive:true});const fixture=output+'.pdf';await writeFile(fixture,bytes);
console.log(`Authored CID diagnostic: ${rows*64} glyphs, ${mappings} two-byte ToUnicode mappings, 64 distinct requested codes; not corpus latency.`);
execFileSync(process.execPath,['tools/document_benchmark.mjs',fixture,output],{stdio:'inherit',env:process.env});

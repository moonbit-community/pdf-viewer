// Authored Standard 14 scaling diagnostic; use document_benchmark.mjs for
// actual corpus PDFs. Keep the same complete preparation/pixel checks here.
import assert from 'node:assert/strict';
import {writeFile,mkdir} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {resolve,dirname} from 'node:path';
import {makePdf,stream} from './pixels/readonly_fixtures.mjs';

assert(process.env.PDF_BENCH_BASELINE_ROOT,'Set PDF_BENCH_BASELINE_ROOT to an independent packaged site');
const output=resolve(process.argv[2]||'_build/text-benchmark/report.json');
const rows=Number(process.env.PDF_TEXT_ROWS||128);
assert(Number.isInteger(rows)&&rows>=1&&rows<=128,'PDF_TEXT_ROWS must be in 1..128');
const line='The quick brown fox jumps over the lazy dog. ABCDEF0123456789 abcde'.padEnd(64,' ').slice(0,64);
const content='BT /F1 8 Tf 10 TL 20 1500 Td\n'+Array.from({length:rows},(_,i)=>(i?'T* ':'')+'('+line+') Tj').join('\n')+'\nET';
const cmap='begincmap\n/CMapType 2 def\n1 begincodespacerange\n<00> <FF>\nendcodespacerange\n256 beginbfchar\n'+Array.from({length:256},(_,i)=>'<'+i.toString(16).padStart(2,'0')+'> <'+i.toString(16).padStart(4,'0')+'>').join('\n')+'\nendbfchar\nendcmap';
const bytes=makePdf([
  '<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
  '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 1600] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',stream('',content),
  '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding /ToUnicode 6 0 R >>',stream('',cmap),
]);
await mkdir(dirname(output),{recursive:true});const fixture=output+'.pdf';await writeFile(fixture,bytes);
console.log(`Authored font diagnostic: ${rows*64} glyphs, 256 valid one-byte ToUnicode mappings; not corpus latency.`);
execFileSync(process.execPath,['tools/document_benchmark.mjs',fixture,output],{stdio:'inherit',env:process.env});

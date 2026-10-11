import assert from 'node:assert/strict';
import {readFileSync, readdirSync, statSync} from 'node:fs';
import {basename, join} from 'node:path';

function latest(prefix){
  const candidates=readdirSync('_build').filter(name=>name.startsWith(prefix)).map(name=>join('_build',name));
  assert.ok(candidates.length,`Missing ${prefix} report`);
  return candidates.sort((a,b)=>statSync(b).mtimeMs-statSync(a).mtimeMs)[0];
}
const read=path=>JSON.parse(readFileSync(path,'utf8'));

export function checkCorpus(report,manifest){
  assert.equal(report.files,manifest.cases.length);
  const cases=new Map(manifest.cases.map(item=>[item.file,item]));
  const seen=new Set();
  for(const result of report.results){
    const name=basename(result.file),expected=cases.get(name);
    assert.ok(expected,`Unexpected corpus input: ${name}`);
    assert.ok(!seen.has(name),`Duplicate corpus input: ${name}`);seen.add(name);
    assert.equal(result.passed,expected.expected_passed,`${name}: reader result changed`);
    if(expected.expected_passed)assert.ok(result.pages>0,`${name}: empty page tree`);
  }
  assert.equal(seen.size,cases.size);
}

export function checkVisual(report,baseline){
  assert.equal(report.reference_revision,baseline.reference_revision);
  assert.equal(report.backend,baseline.backend);
  assert.equal(report.scale,baseline.scale);
  assert.equal(report.failed,0);
  assert.equal(report.runtime_exceptions.length,0);
  assert.equal(report.total,baseline.cases.length);
  const cases=new Map(baseline.cases.map(item=>[`${item.file}:${item.page}:${item.rotation}`,item]));
  const seen=new Set();
  for(const result of report.results){
    const key=`${result.file}:${result.page}:${result.rotation}`,expected=cases.get(key);
    assert.ok(expected,`Unexpected visual case: ${key}`);
    assert.ok(!seen.has(key),`Duplicate visual case: ${key}`);seen.add(key);
    assert.equal(result.file_sha256,expected.sha256,`${key}: fixture changed`);
    assert.equal(result.geometry.equal_within_1e_6,true,`${key}: viewport regression`);
    if(expected.text_equal)assert.equal(result.text.without_whitespace_equal,true,`${key}: text regression`);
    assert.ok(result.pixels.changed_above_tolerance<=expected.max_changed_pixels,`${key}: changed pixels ${result.pixels.changed_above_tolerance} > ${expected.max_changed_pixels}`);
    assert.ok(result.pixels.missing_ink<=expected.max_missing_ink,`${key}: missing ink increased`);
    assert.ok(result.pixels.viewer_ink>=expected.min_viewer_ink,`${key}: viewer lost ink`);
  }
  assert.equal(seen.size,cases.size);
}

if(process.argv[1]?.endsWith('/check_reports.mjs')){
  const corpus=latest('reader-corpus-'),visual=latest('visual-test-'),browser=latest('browser-test-');
  checkCorpus(read(`${corpus}/report.json`),read('tools/ci/corpus.json'));
  const visualReport=read(`${visual}/report.json`),host=visualReport.reference_runtime.userAgent;
  assert.match(host,/Linux|Macintosh/,'No measured visual baseline for this platform');
  checkVisual(visualReport,read(/Linux/.test(host)?'tools/ci/visual_baseline_linux.json':'tools/ci/visual_baseline.json'));
  const dom=read(`${browser}/report.json`);
  assert.equal(dom.status,'passed');assert.ok(dom.passed>=110,'Browser checks were dropped');
  for(const name of [
    'Rabbita updates sidebars and controls while preserving Canvas and native selection',
    'compiled MoonBit thumbnails discard cancelled draws, warnings and late failures',
    'compiled MoonBit printing discards a draw completed after document close',
    'rapid page button clicks retain each navigation before the next view update',
    'Rabbita captures a dropped file before the native drag data is released',
    'Rabbita publishes real host-override warnings for page thumbnail and print',
  ])assert.ok(dom.checks.includes(name),`Missing frontend regression: ${name}`);
  assert.equal(dom.host_runtime.printed_pages,200);
  assert.equal(dom.remaining_readonly.xfa_printed_pages,2);
  assert.equal(dom.remaining_readonly.real_xfa_pages,7);
  assert.ok(dom.remaining_readonly.range_first_page.first_page_bytes<dom.remaining_readonly.range_first_page.total_bytes/10);
  console.log(`Accepted corpus, browser and visual reports: ${corpus}, ${browser}, ${visual}. Visual differences remain recorded.`);
}

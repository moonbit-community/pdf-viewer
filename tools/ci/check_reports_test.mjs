import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {checkVisual,checkCorpus} from './check_reports.mjs';
const baseline=JSON.parse(readFileSync('tools/ci/visual_baseline.json','utf8'));
const results=baseline.cases.map(item=>({file:item.file,page:item.page,rotation:item.rotation,file_sha256:item.sha256,geometry:{equal_within_1e_6:true},text:{without_whitespace_equal:item.text_equal},pixels:{changed_above_tolerance:item.measured_changed_pixels,missing_ink:item.measured_missing_ink,viewer_ink:item.measured_viewer_ink}}));
const good={reference_revision:baseline.reference_revision,backend:baseline.backend,scale:baseline.scale,failed:0,runtime_exceptions:[],total:results.length,results};
checkVisual(good,baseline);
for(const mutate of [p=>p.results.pop(),p=>p.results[0].geometry.equal_within_1e_6=false,p=>p.results[0].pixels.changed_above_tolerance=Infinity,p=>p.results[0].pixels.viewer_ink=0,p=>p.runtime_exceptions.push('error'),p=>p.results[0].file_sha256='changed',p=>p.results[1]=p.results[0]]){
  const report=structuredClone(good);mutate(report);assert.throws(()=>checkVisual(report,baseline));
}
const manifest={cases:[{file:'one.pdf',expected_passed:true}]},corpus={files:1,results:[{file:'dir/one.pdf',passed:true,pages:1}]};
checkCorpus(corpus,manifest);assert.throws(()=>checkCorpus({...corpus,results:[]},manifest));
assert.throws(()=>checkCorpus({...corpus,results:[{file:'one.pdf',passed:false}]},manifest));
console.log('Report gates reject dropped measurements, blank renders, viewport/text failures, source changes and corpus failures.');

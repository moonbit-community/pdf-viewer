import assert from 'node:assert/strict';
import {createPdfIccEngine,pdfCalibrationToPcs,pdfCalibrationFromPcs} from '../web/pdf-icc.mjs';
const rgb={components:3,gamma:[2.2,1.8,2.4],pcs_matrix:[.4360747,.2225045,.0139322,.3850649,.7168786,.0971045,.1430804,.0606169,.7141733],pcs_offset:[0,0,0]};
const gray={components:1,gamma:[2.2],pcs_matrix:[.9642,1,.8249],pcs_offset:[0,0,0]};
const engine=await createPdfIccEngine(),scope=engine.createProfileScope([]);
for(const values of [[.1,.2,.3],[.8,.5,.2],[0,1,.5]]){
 const xyz=pdfCalibrationToPcs(values,rgb),roundtrip=pdfCalibrationFromPcs(xyz,rgb);
 for(let i=0;i<3;i++)assert.ok(Math.abs(values[i]-roundtrip[i])<1e-7);
 const encoded=scope.sourceToGroup({space:'DeviceRGB',components:values},{calibration:rgb,components:3});assert.ok(encoded);
 const displayed=scope.groupToRgb(encoded,{calibration:rgb,components:3});
 // This well-formed authored matrix covers the sRGB primaries. Conversion into
 // its nonlinear group domain and back must preserve the original colour.
 for(let i=0;i<3;i++)assert.ok(Math.abs(displayed[i]-values[i])<.003,`${values}: ${displayed}`);
 const calibrated=scope.sourceToGroup({space:'CalRGB',components:values,calibration:rgb},{calibration:rgb,components:3});
 for(let i=0;i<3;i++)assert.ok(Math.abs(calibrated[i]-values[i])<1e-7);
}
const g=scope.sourceToGroup({space:'DeviceRGB',components:[.5,.5,.5]},{calibration:gray,components:1});assert.ok(g&&g[0]>.49&&g[0]<.51);
const neutral=scope.groupToRgb(g,{calibration:gray,components:1});for(const value of neutral)assert.ok(Math.abs(value-.5)<.001);
const zero={...rgb,gamma:[0,1,1]},singular={...rgb,pcs_matrix:Array(9).fill(1)};
assert.equal(scope.sourceToGroup({space:'DeviceRGB',components:[.2,.4,.6]},{calibration:zero,components:3}),null);
assert.equal(scope.sourceToGroup({space:'DeviceRGB',components:[.2,.4,.6]},{calibration:singular,components:3}),null);
assert.equal(scope.sourceToGroup({space:'DeviceRGB',components:[.2,.4,.6]},{calibration:rgb,components:1}),null);
scope.dispose();engine.dispose();console.log('Calibrated group forward, inverse, CMM XYZ and malformed-target tests: passed');

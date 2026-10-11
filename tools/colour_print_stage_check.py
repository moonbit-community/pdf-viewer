#!/usr/bin/env python3
"""Independent actual Altona solid-paint colour-stage check.
Usage: PDF canvas-plan.json actual.png exact-output-profile.tif report.json
The TIFF must use the embedded output profile, RI=1, BPC=0, DeviceGrayToK=true.
All private input artifacts stay local; the report stores hashes and samples.
"""
import base64
import ctypes as C
import hashlib
import json
from pathlib import Path
import sys
import numpy as np
from PIL import Image
from pypdf import PdfReader

pdf_path, plan_path, actual_path, tiff_path, report_path = map(Path, sys.argv[1:])
plan = json.loads(plan_path.read_text())
profiles = {p['id']:base64.b64decode(p['data_base64']) for p in plan['icc_profiles']}
output_bytes = profiles[plan['blend_profile_id']]
actual = Image.open(actual_path).convert('RGB')
reference = Image.open(tiff_path)
assert reference.mode == 'CMYK'
lib = C.CDLL('liblcms2.so.2')
def bind(name, result, args):
    f=getattr(lib,name); f.restype,f.argtypes=result,args; return f
open_profile=bind('cmsOpenProfileFromMem',C.c_void_p,[C.c_void_p,C.c_uint32])
srgb_profile=bind('cmsCreate_sRGBProfile',C.c_void_p,[])
xyz_profile=bind('cmsCreateXYZProfile',C.c_void_p,[])
class xyY(C.Structure):
    _fields_=[('x',C.c_double),('y',C.c_double),('Y',C.c_double)]
lab_profile=bind('cmsCreateLab4Profile',C.c_void_p,[C.POINTER(xyY)])
create=bind('cmsCreateTransform',C.c_void_p,[C.c_void_p,C.c_uint32,C.c_void_p,C.c_uint32,C.c_uint32,C.c_uint32])
convert=bind('cmsDoTransform',None,[C.c_void_p,C.c_void_p,C.c_void_p,C.c_uint32])
close=bind('cmsCloseProfile',C.c_bool,[C.c_void_p])
delete=bind('cmsDeleteTransform',None,[C.c_void_p])
version=bind('cmsGetEncodedCMMversion',C.c_uint32,[])
def fmt(kind,n):return (1<<22)|(kind<<16)|(n<<3)
def transform(src,srcfmt,dst,dstfmt,values,n):
    handle=create(src,srcfmt,dst,dstfmt,1,0);assert handle
    data=np.asarray(values,dtype=np.float64);out=np.zeros(n,dtype=np.float64)
    try:convert(handle,data.ctypes.data,out.ctypes.data,1)
    finally:delete(handle)
    return out

def opened(data):
    buffer=C.create_string_buffer(data);handle=open_profile(buffer,len(data));assert handle
    return handle

def pcs(matrix,gamma,white,values):
    xyz=np.asarray(matrix).reshape(3,3).T@(np.asarray(values)**np.asarray(gamma))
    b=np.array([[.8951,.2664,-.1614],[-.7502,1.7135,.0367],[.0389,-.0685,1.0296]])
    return np.linalg.inv(b)@((b@xyz)*(b@np.array([.9642,1,.8249]))/(b@np.asarray(white)))

reader=PdfReader(pdf_path)
calibration=reader.pages[0]['/Resources']['/ColorSpace']['/Cs22'][1]
report={'pdf_sha256':hashlib.sha256(pdf_path.read_bytes()).hexdigest(),
        'plan_sha256':hashlib.sha256(plan_path.read_bytes()).hexdigest(),
        'output_profile_sha256':hashlib.sha256(output_bytes).hexdigest(),
        'system_lcms_version':version(),'source_intent':1,'output_intent':1,'flags':0,
        'black_point_compensation':False,'paper_simulation':False,'patches':[]}
output,display=opened(output_bytes),srgb_profile()
try:
    for label,point,space in [('ICC Gray',(55,993),'ICCBased'),('ICC RGB',(55,1037),'ICCBased'),
                              ('Lab',(55,1080),'Lab'),('ICC CMYK',(55,1120),'ICCBased'),
                              ('CalRGB',(182,1037),'CalRGB')]:
        x,y=point;pdf_y=plan['page']['height']-y
        candidates=[q for q in plan['items'] if q['kind']=='path' and
                    q['paint']['fill_source']['space']==space and
                    q['paint']['bounds']['min_x']<=x<=q['paint']['bounds']['max_x'] and
                    q['paint']['bounds']['min_y']<=pdf_y<=q['paint']['bounds']['max_y']]
        assert candidates, label
        source=candidates[-1]['paint']['fill_source'];values=source['components']
        item={'name':label,'point':point,'source':source,'paint_index':candidates[-1]['paint']['index']}
        if space=='ICCBased':
            data=profiles[source['icc_profile_id']];n=len(values);kind={1:3,3:4,4:6}[n]
            src=opened(data);values=np.asarray(values)*(100 if n==4 else 1)
            item['source_profile_sha256']=hashlib.sha256(data).hexdigest()
        elif space=='Lab':
            white=xyY(*source['whitepoint_xyy']);src=lab_profile(C.byref(white));kind,n=10,3
        else:
            assert list(calibration.get('/BlackPoint',[0,0,0]))==[0,0,0]
            values=pcs(calibration['/Matrix'],calibration['/Gamma'],calibration['/WhitePoint'],values)
            item['original_calibration']={str(k):list(v) for k,v in calibration.items()}
            item['analytical_pcs']=values.tolist();src=xyz_profile();kind,n=9,3
        try:
            ink=transform(src,fmt(kind,n),output,fmt(6,4),values,4)
            rgb=transform(output,fmt(6,4),display,fmt(4,3),ink,3)
        finally:close(src)
        expected=np.floor(np.clip(rgb,0,1)*255+.5).astype(int)
        visible=np.asarray(actual.getpixel(point))
        gs=np.asarray(reference.getpixel(point))
        item.update({'independent_cmyk':(ink/100).tolist(),'ghostscript_cmyk8':gs.tolist(),
                     'cmyk8_max_error':float(np.max(np.abs(ink*2.55-gs))),
                     'independent_rgb8':expected.tolist(),'actual_rgb8':visible.tolist(),
                     'visible_max_error':int(np.max(np.abs(expected-visible)))})
        report['patches'].append(item)
    report['process_overprint_probes']=[]
    for point in [(57,620),(57,705),(57,748),(57,150),(57,320),(57,447)]:
        x,y=point;pdf_y=plan['page']['height']-y
        paints=[q['paint'] for q in plan['items'] if q['kind']=='path' and
                q['paint']['bounds']['min_x']<=x<=q['paint']['bounds']['max_x'] and
                q['paint']['bounds']['min_y']<=pdf_y<=q['paint']['bounds']['max_y']]
        assert len(paints)==2 and paints[0]['fill_source']['space']=='DeviceCMYK'
        backdrop=paints[0]['fill_source']['components'];foreground=paints[1]['fill_source']
        assert paints[1]['fill_alpha']==1 and not paints[1]['clips']
        values=foreground['components']
        if foreground['space']=='DeviceGray':ink=[0,0,0,1-values[0]]
        else:
            assert foreground['space']=='DeviceCMYK'
            ink=[backdrop[c] if paints[1]['fill_overprint'] and paints[1]['overprint_mode']==1 and values[c]==0 else values[c] for c in range(4)]
        rgb=transform(output,fmt(6,4),display,fmt(4,3),np.asarray(ink)*100,3)
        expected=np.floor(np.clip(rgb,0,1)*255+.5).astype(int);visible=np.asarray(actual.getpixel(point))
        report['process_overprint_probes'].append({'point':point,'paint_indices':[p['index'] for p in paints],
           'backdrop':backdrop,'foreground':foreground,'overprint':paints[1]['fill_overprint'],
           'overprint_mode':paints[1]['overprint_mode'],'expected_ink':ink,'independent_rgb8':expected.tolist(),
           'actual_rgb8':visible.tolist(),'visible_max_error':int(np.max(np.abs(expected-visible)))})
finally:close(output);close(display)
report['all_visible_within_one_byte']=all(p['visible_max_error']<=1 for p in report['patches']+report['process_overprint_probes'])
report_path.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'system_lcms_version':report['system_lcms_version'],'all_visible_within_one_byte':report['all_visible_within_one_byte'],
                  'patches':[{k:p[k] for k in ['name','visible_max_error','cmyk8_max_error']} for p in report['patches']]},indent=2))

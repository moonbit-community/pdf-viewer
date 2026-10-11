#!/usr/bin/env python3
"""Isolate original Altona logo RI policy using original profile/components.
Usage: original.pdf actual.png reference.png output-directory
Two local authored controls retain the source profile and /Perceptual. GS
RI=0/1 changes only output rendering intent. Original PDF remains unchanged.
"""
import ctypes as C,hashlib,json,os,subprocess,sys
from pathlib import Path
import numpy as np
from PIL import Image
from pypdf import PdfReader,PdfWriter
from pypdf.generic import NameObject,ArrayObject,DictionaryObject,DecodedStreamObject,NumberObject
if len(sys.argv)!=5:raise SystemExit(__doc__)
pdf,actual,reference,out=map(Path,sys.argv[1:]);out.mkdir(parents=True,exist_ok=True)
r=PdfReader(pdf);source=r.pages[0]['/Resources']['/ColorSpace']['/Cs9'][1].get_object().get_data();destination=r.trailer['/Root']['/OutputIntents'][0].get_object()['/DestOutputProfile'].get_object().get_data();(out/'output.icc').write_bytes(destination)
lib=C.CDLL('liblcms2.so.2')
def bind(name,result,args):
 f=getattr(lib,name);f.restype,f.argtypes=result,args;return f
op=bind('cmsOpenProfileFromMem',C.c_void_p,[C.c_void_p,C.c_uint32]);srgb=bind('cmsCreate_sRGBProfile',C.c_void_p,[]);create=bind('cmsCreateTransform',C.c_void_p,[C.c_void_p,C.c_uint32,C.c_void_p,C.c_uint32,C.c_uint32,C.c_uint32]);do=bind('cmsDoTransform',None,[C.c_void_p,C.c_void_p,C.c_void_p,C.c_uint32]);close=bind('cmsCloseProfile',C.c_bool,[C.c_void_p]);delete=bind('cmsDeleteTransform',None,[C.c_void_p]);fmt=lambda n:(1<<22)|((6 if n==4 else 4)<<16)|(n<<3)
def convert(src,dst,values,intent,n):
 t=create(src,fmt(4),dst,fmt(n),intent,0);assert t;v=np.asarray(values,np.float64);o=np.zeros(n,np.float64)
 try:do(t,v.ctypes.data,o.ctypes.data,1)
 finally:delete(t)
 return o
s,d=op(C.create_string_buffer(source),len(source)),op(C.create_string_buffer(destination),len(destination));rgb=srgb()
a,b=np.asarray(Image.open(actual).convert('RGB')),np.asarray(Image.open(reference).convert('RGB'))
report={'original_pdf_sha256':hashlib.sha256(pdf.read_bytes()).hexdigest(),'source_profile_sha256':hashlib.sha256(source).hexdigest(),'output_profile_sha256':hashlib.sha256(destination).hexdigest(),'source_intent':'/Perceptual','display_intent':1,'flags':0,'black_point_compensation':False,'paper_simulation':False,'ghostscript_version':subprocess.check_output(['gs','--version'],text=True).strip(),'patches':[]}
try:
 for name,paint,values,actual_rgb,ref_rgb in [('red',189,[0,.949,.949,0],[231,75,56],[231,72,41]),('turquoise',222,[.8,0,.361,0],[0,162,170],[39,167,172])]:
  expected=convert(d,rgb,convert(s,d,np.asarray(values)*100,0,4),1,3);expected=np.floor(np.clip(expected,0,1)*255+.5).astype(int)
  y,x=np.where((a==actual_rgb).all(2)&(b==ref_rgb).all(2));assert len(x)
  writer=PdfWriter();page=writer.add_blank_page(width=20,height=20);profile=DecodedStreamObject();profile.set_data(source);profile[NameObject('/N')]=NumberObject(4);pr=writer._add_object(profile);page[NameObject('/Resources')]=DictionaryObject({NameObject('/ColorSpace'):DictionaryObject({NameObject('/C'):ArrayObject([NameObject('/ICCBased'),pr])})});content=DecodedStreamObject();content.set_data(('/Perceptual ri /C cs '+' '.join(map(str,values))+' scn 0 0 20 20 re f').encode());page[NameObject('/Contents')]=writer._add_object(content);control=out/(name+'.pdf');writer.write(control)
  patch={'name':name,'original_paint':paint,'source_components':values,'point':[int(x[0]),int(y[0])],'actual_rgb8':actual_rgb,'original_reference_rgb8':ref_rgb,'independent_perceptual_rgb8':expected.tolist(),'actual_max_error':int(np.max(np.abs(expected-actual_rgb))),'control_pdf_sha256':hashlib.sha256(control.read_bytes()).hexdigest(),'ghostscript':[]}
  assert patch['actual_max_error']==0
  for intent in [0,1]:
   tiff=out/f'{name}-ri{intent}.tif';image=out/f'{name}-ri{intent}.png';args=['gs','-q','-dSAFER','-dBATCH','-dNOPAUSE','-sDEVICE=tiff32nc','-r72','-dTextAlphaBits=4','-dGraphicsAlphaBits=4','-dBlackPtComp=0',f'-dRenderIntent={intent}','-dOverrideRI=false','-dKPreserve=0','-dDeviceGrayToK=true','-dOverprint=/enable',f'-sDefaultCMYKProfile={out}/output.icc',f'-sOutputICCProfile={out}/output.icc',f'-sOutputFile={tiff}',str(control)];subprocess.run(args,check=True,env={**os.environ,'XDG_CACHE_HOME':'/tmp/pdf-colour-font-cache'})
   subprocess.run([sys.executable,str(Path(__file__).with_name('colour_cmyk_raster_check.py')),str(out/'output.icc'),str(tiff),str(image)],check=True,capture_output=True)
   colour=list(Image.open(image).getpixel((10,10)));patch['ghostscript'].append({'forced_output_intent':intent,'cmyk8':list(Image.open(tiff).getpixel((10,10))),'rgb8':colour,'arguments':args[1:-1]})
   assert max(abs(v-e) for v,e in zip(colour,actual_rgb if intent==0 else ref_rgb))<=(1 if intent==0 else 0)
  report['patches'].append(patch)
finally:close(s);close(d);close(rgb)
(out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))

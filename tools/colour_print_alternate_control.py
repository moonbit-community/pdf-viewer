#!/usr/bin/env python3
"""Make a labelled local colourant-availability control, never a replacement oracle.
Only process-named Separation/DeviceN entries become unavailable names. Streams
(including functions, image samples, page content and ICC profiles) stay exact.
"""
import hashlib
import json
from pathlib import Path
import sys
from pypdf import PdfReader, PdfWriter
from pypdf.generic import NameObject, StreamObject
source, destination, report_path = map(Path,sys.argv[1:])
reader=PdfReader(source);writer=PdfWriter();writer.clone_document_from_reader(reader)
seen=set();changes=[]
def walk(obj,path):
    if hasattr(obj,'idnum'):
        key=(obj.idnum,obj.generation)
        if key in seen:return
        seen.add(key);obj=obj.get_object()
    if isinstance(obj,list):
        if len(obj)>1 and obj[0]=='/Separation':
            entries=[(obj,1,path+'/1')]
        elif len(obj)>1 and obj[0]=='/DeviceN':
            entries=[(obj[1],i,path+'/1/'+str(i)) for i in range(len(obj[1]))]
        else:entries=[]
        for array,i,entry_path in entries:
            value=array[i]
            if value in ['/Cyan','/Magenta','/Yellow','/Black']:
                replacement='/DisplayAlternate'+str(value)[1:]
                changes.append({'path':entry_path,'before':str(value),'after':replacement})
                array[i]=NameObject(replacement)
        for i,value in enumerate(obj):walk(value,path+'/'+str(i))
    elif isinstance(obj,dict):
        for key,value in obj.items():walk(value,path+str(key))
walk(writer._root_object,'/Root')
with destination.open('wb') as output:writer.write(output)
# Verify semantic graph equality apart from the declared name substitutions.
control=PdfReader(destination);seen=set();observed=[];streams=[]
def compare(a,b,path):
    if hasattr(a,'idnum') or hasattr(b,'idnum'):
        key=(str(a),str(b))
        if key in seen:return
        seen.add(key);a=a.get_object();b=b.get_object()
    if isinstance(a,StreamObject):
        assert isinstance(b,StreamObject) and a._data==b._data,path
        streams.append({'path':path,'encoded_sha256':hashlib.sha256(a._data).hexdigest()})
    if isinstance(a,dict):
        assert isinstance(b,dict) and set(a)==set(b),path
        for key in a:compare(a.raw_get(key),b.raw_get(key),path+str(key))
    elif isinstance(a,list):
        assert isinstance(b,list) and len(a)==len(b),path
        for i,(x,y) in enumerate(zip(a,b)):compare(x,y,path+'/'+str(i))
    elif a!=b:
        assert str(a) in ['/Cyan','/Magenta','/Yellow','/Black'] and str(b)=='/DisplayAlternate'+str(a)[1:],(path,a,b)
        observed.append({'path':path,'before':str(a),'after':str(b)})
compare(reader.trailer.raw_get('/Root'),control.trailer.raw_get('/Root'),'/Root')
assert sorted(changes,key=str)==sorted(observed,key=str)
report={'label':'derived colourant-availability control, not original-page acceptance',
        'original_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'control_sha256':hashlib.sha256(destination.read_bytes()).hexdigest(),
        'changes':changes,'unchanged_streams':streams,'other_semantic_changes':0}
report_path.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({k:v for k,v in report.items() if k!='unchanged_streams'},indent=2))

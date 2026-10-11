#!/usr/bin/env python3
"""Disjoint localization of the ORIGINAL Altona AA4 flat-reference residuals.
Usage: plan.json actual.png reference.png name-control.png report.json [coverage.json]
First run exports report.pending-pixels.json. Pass that list to
colour_print_coverage.mjs, then rerun with its result. No PDF is redistributed.
Categories distinguish causal controlled changes from geometric localization.
"""
import hashlib,json,math,sys
from collections import defaultdict
from pathlib import Path
import numpy as np
from PIL import Image
if len(sys.argv) not in [6,7]:raise SystemExit(__doc__)
plan_file,actual_file,reference_file,control_file,report_file=map(Path,sys.argv[1:6])
plan=json.loads(plan_file.read_text())
a,b,c=[np.asarray(Image.open(f).convert('RGB')).astype(np.int16) for f in [actual_file,reference_file,control_file]]
assert a.shape==b.shape==c.shape
h,w,_=a.shape;yy,xx=np.indices((h,w));flat=np.ones((h,w),bool);flat[[0,-1],:]=False;flat[:,[0,-1]]=False
for dy in [-1,0,1]:
 for dx in [-1,0,1]:flat&=np.max(np.abs(b-np.roll(b,(dy,dx),(0,1))),axis=2)<=1
original=flat&(np.max(np.abs(a-b),axis=2)>8);remaining=original.copy()
report={'plan_sha256':hashlib.sha256(plan_file.read_bytes()).hexdigest(),'dimensions':[w,h],'original_bad_pixels':int(original.sum()),'flat_reference_pixels':int(flat.sum()),'mask_sha256':hashlib.sha256(original.tobytes()).hexdigest(),'categories':[]}
def bbox(mask):
 y,x=np.where(mask);return [int(x.min()),int(y.min()),int(x.max()+1),int(y.max()+1)] if len(x) else None
def take(name,mask,evidence,**extra):
 selected=remaining&mask;remaining[selected]=False
 report['categories'].append({'name':name,'pixels':int(selected.sum()),'box':bbox(selected),'evidence':evidence,**extra});return selected
policy=take('named_process_availability',np.max(np.abs(a-c),axis=2)<=8,'Verified name-only derived control resolves these exact original-mask pixels; original acceptance counts are retained.')
seams=np.zeros_like(remaining);pairs=[]
for i,item in enumerate(plan['items'][:-1]):
 other=plan['items'][i+1]
 if item['kind']!='path' or other['kind']!='path':continue
 p,q=item['paint'],other['paint'];s,t=p.get('fill_source',{}),q.get('fill_source',{})
 if s.get('space')!='DeviceCMYK' or s.get('components')!=[0,0,0,.498] or t.get('space')!='DeviceGray' or t.get('components')!=[.502]:continue
 u,v=p['bounds'],q['bounds']
 if abs(u['max_x']-v['min_x'])>1e-5 or u['min_y']!=v['min_y'] or u['max_y']!=v['max_y']:continue
 assert p['filled'] and q['filled'] and p['fill_alpha']==q['fill_alpha']==1 and not p['clips'] and not q['clips']
 x,y0,y1=math.floor(u['max_x']),math.ceil(h-u['max_y']),math.floor(h-u['min_y']);seams[y0:y1,x]=True
 count=int(remaining[y0:y1,x].sum())
 if count:pairs.append({'paints':[i,i+1],'edge_x':u['max_x'],'box':[x,y0,x+1,y1],'pixels':count})
take('shared_opaque_shape_edges',seams,'Original adjacent CMYK K/Gray geometry; independent host reproduction confirms separate-coverage AA seam, not CMM or blend arithmetic.',paint_pairs=pairs)
red=(a==[231,75,56]).all(2)&(b==[231,72,41]).all(2)
turquoise=(a==[0,162,170]).all(2)&(b==[39,167,172]).all(2)
take('forced_reference_intent',red|turquoise,'Original Perceptual ICC logo samples: forced GS RI1 matches reference; RI0 matches actual within1 byte with same profiles/BPC/paper policy.',paint_indices=[189,222,223,224,225])
for name,box,ids in [('cid0_reference_glyph_selection',[347,11,591,26],[6296,6335]),('cid2_reference_glyph_selection',[347,42,601,59],[6475,6518])]:
 x0,y0,x1,y1=box;take(name,(xx>=x0)&(xx<x1)&(yy>=y0)&(yy<y1),'GS reference selects visibly different CID glyphs; actual and independent Poppler retain the intended outlines. This is a glyph-selection/coverage comparison, not a solid colour error.',paint_index_range=ids)
points=[{'x':int(x),'y':int(y),'actual':a[y,x].tolist(),'reference':b[y,x].tolist(),'alternate':c[y,x].tolist()} for y,x in zip(*np.where(remaining))]
report_file.with_suffix('.pending-pixels.json').write_text(json.dumps(points)+'\n')
if len(sys.argv)>6:
 coverage=json.loads(Path(sys.argv[6]).read_text());by_point={(q['x'],q['y']):q for q in coverage}
 groups=defaultdict(list)
 for q in points:
  hit=by_point.get((q['x'],q['y']),{}).get('last');assert hit,q
  name='font_reference_bitmap_sampling' if hit['index']==6520 else 'partial_'+hit['kind']+'_coverage'
  if name!='font_reference_bitmap_sampling':assert 0<hit['alpha']<255,(name,q,hit)
  groups[name].append({**q,'last':hit})
 for name,values in groups.items():
  mask=np.zeros_like(remaining);paints=defaultdict(list)
  for q in values:mask[q['y'],q['x']]=True;paints[q['last']['index']].append(q)
  detail=[]
  for index,qs in sorted(paints.items()):
   hit=qs[0]['last'];detail.append({'paint':index,'kind':hit['kind'],'operation':hit['operation'],'resource':hit.get('resource'),'source_space':hit.get('source',{}).get('space'),'pixels':len(qs),'box':[min(q['x'] for q in qs),min(q['y'] for q in qs),max(q['x'] for q in qs)+1,max(q['y'] for q in qs)+1],'coverage_range':[min(q['last']['alpha'] for q in qs),max(q['last']['alpha'] for q in qs)],'example':{k:qs[0][k] for k in ['x','y','actual','reference']}})
  take(name,mask,'Geometrically localized by independently rasterizing original source outlines/affine strokes/image quads. Partial host coverage is established; this is not a complete per-pixel numerical proof. Bitmap interiors require their separate sampling audit.',paint_clusters=detail)
report['font_reference_bitmap_evidence']='docs/validation/print-bitmap-sampling.md: all16 raw samples, independent two-stage sampling and LCMS match exactly; GS uses the original unrounded point-sampling policy.'
report['unlocalized_pixels']=int(remaining.sum())
report['disjoint_sum']=sum(q['pixels'] for q in report['categories'])
assert report['disjoint_sum']+report['unlocalized_pixels']==int(original.sum())
report_file.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({q['name']:q['pixels'] for q in report['categories']}))

#!/usr/bin/env python3
"""Original deterministic PDFs for Pattern-painted stencil image regression."""
from pathlib import Path
import json
import sys

objects=[]
def obj(value):
    objects.append(value.encode('ascii') if isinstance(value,str) else value)
    return len(objects)
def stream(dictionary,content):
    content=content.encode('ascii') if isinstance(content,str) else content
    return obj(f'<< {dictionary} /Length {len(content)} >>\nstream\n'.encode()+content+b'\nendstream')

catalog,pages=obj(''),obj('')
base='/Type /Pattern /PatternType 1 /TilingType 1 /BBox [0 0 10 10] /XStep 10 /YStep 10 /Resources << >>'
body='1 0 0 rg 0 0 5 10 re f 0 0 1 rg 5 0 5 10 re f'
coloured=stream(base+' /PaintType 1',body)
green=stream(base+' /PaintType 2','0 0 5 10 re f')
translated=stream(base+' /PaintType 1 /Matrix [1 0 0 1 2 0]',body)
shading=obj('<< /Type /Pattern /PatternType 2 /Shading << /ShadingType 2 /ColorSpace /DeviceRGB /Coords [0 0 20 0] /Extend [true true] /Function << /FunctionType 2 /Domain [0 1] /C0 [1 0 0] /C1 [0 0 1] /N 1 >> >> >>')
full=stream('/Type /XObject /Subtype /Image /Width 1 /Height 1 /ImageMask true /BitsPerComponent 1 /Filter /ASCIIHexDecode','00>')
full_two=stream('/Type /XObject /Subtype /Image /Width 2 /Height 1 /ImageMask true /BitsPerComponent 1 /Filter /ASCIIHexDecode','00>')
half=stream('/Type /XObject /Subtype /Image /Width 2 /Height 1 /ImageMask true /BitsPerComponent 1 /Filter /ASCIIHexDecode','40>')
reverse=stream('/Type /XObject /Subtype /Image /Width 2 /Height 1 /ImageMask true /BitsPerComponent 1 /Decode [1 0] /Filter /ASCIIHexDecode','40>')
colour_image=stream('/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode','00FF00>')
paint='q 20 0 0 20 0 0 cm /Im Do Q'
cases=[
    ('coloured-full',coloured,full,'/Pattern cs /P scn '+paint),
    ('coloured-half',coloured,half,'/Pattern cs /P scn '+paint),
    ('reversed-half',coloured,reverse,'/Pattern cs /P scn '+paint),
    ('inline-coloured',coloured,full,'/Pattern cs /P scn q 20 0 0 20 0 0 cm BI /W 1 /H 1 /IM true /BPC 1 /F /AHx ID 00> EI Q'),
    ('uncoloured-green',green,full,'/PCS cs 0 1 0 /P scn '+paint),
    ('shading-gradient',shading,full,'/Pattern cs /P scn '+paint),
    ('translated-cell',translated,full,'/Pattern cs /P scn '+paint),
    ('constant-alpha',coloured,full,'/Half gs /Pattern cs /P scn '+paint),
    ('clipped',coloured,full,'0 0 8 20 re W n /Pattern cs /P scn '+paint),
    ('ordinary-colour-image',coloured,colour_image,'/Pattern cs /P scn '+paint),
    ('selected-after-cm-stencil',coloured,full,'q 20 0 0 20 0 0 cm /Pattern cs /P scn /Im Do Q'),
    ('uncoloured-green-path',green,full,'/PCS cs 0 1 0 /P scn 0 0 20 20 re f'),
    ('selected-after-cm-path',coloured,full,'q 20 0 0 20 0 0 cm /Pattern cs /P scn 0 0 1 1 re f Q'),
]
# Equivalent fully opaque two-pixel masks bypass PDF.js's one-pixel solid-fill
# optimization, allowing its general Pattern mask path to serve as an oracle.
for name,pattern,im,content in list(cases):
    if im == full and not name.endswith('-path'):
        cases.append((name+'-two-pixel-control',pattern,full_two,content.replace('BI /W 1 /H 1','BI /W 2 /H 1')))
kids=[]
for name,pattern,im,content in cases:
    contents=stream('',content)
    resources=f'<< /Pattern << /P {pattern} 0 R >> /XObject << /Im {im} 0 R >> /ColorSpace << /PCS [/Pattern /DeviceRGB] >> /ExtGState << /Half << /ca .5 >> >> >>'
    kids.append(obj(f'<< /Type /Page /Parent {pages} 0 R /MediaBox [0 0 20 20] /Resources {resources} /Contents {contents} 0 R >>'))
objects[catalog-1]=f'<< /Type /Catalog /Pages {pages} 0 R >>'.encode()
objects[pages-1]=f'<< /Type /Pages /Count {len(kids)} /Kids [{" ".join(f"{k} 0 R" for k in kids)}] >>'.encode()
result=bytearray(b'%PDF-1.7\n');offsets=[]
for index,value in enumerate(objects,1):
    offsets.append(len(result));result.extend(f'{index} 0 obj\n'.encode()+value+b'\nendobj\n')
xref=len(result);result.extend(f'xref\n0 {len(objects)+1}\n0000000000 65535 f \n'.encode())
for offset in offsets:result.extend(f'{offset:010d} 00000 n \n'.encode())
result.extend(f'trailer\n<< /Size {len(objects)+1} /Root {catalog} 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode())
output=Path(sys.argv[1] if len(sys.argv)>1 else '_build/image-pattern.pdf');output.parent.mkdir(parents=True,exist_ok=True);output.write_bytes(result)
output.with_suffix('.cases.json').write_text(json.dumps([name for name,*_ in cases],indent=2)+'\n')
print(output)

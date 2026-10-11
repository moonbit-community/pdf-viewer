"""Deterministic authored PDF fixtures for pattern geometry and cell replay."""
from pathlib import Path
import sys

objects = []
def obj(value):
    objects.append(value.encode('ascii') if isinstance(value, str) else value)
    return len(objects)
def stream(dictionary, content):
    content = content.encode('ascii') if isinstance(content, str) else content
    return obj(f'<< {dictionary} /Length {len(content)} >>\nstream\n'.encode() + content + b'\nendstream')

catalog = obj('')
pages = obj('')
image = stream('/Type /XObject /Subtype /Image /Width 2 /Height 2 /BitsPerComponent 8 /ColorSpace /DeviceRGB /Filter /ASCIIHexDecode', 'FF000000FF000000FFFFFFFF>')
charproc = stream('', '600 0 0 0 600 700 d1 50 0 150 700 re 200 550 350 150 re f')
font = obj(f'<< /Type /Font /Subtype /Type3 /FontBBox [0 0 600 700] /FontMatrix [.001 0 0 .001 0 0] /CharProcs << /A {charproc} 0 R >> /Encoding << /Type /Encoding /Differences [65 /A] >> /FirstChar 65 /LastChar 65 /Widths [600] /Resources << >> >>')
form = stream('/Type /XObject /Subtype /Form /BBox [0 0 12 12] /Group << /S /Transparency /I true >> /Resources << /ExtGState << /Half << /ca .5 >> >> >>', '/Half gs 1 0 0 rg 0 0 10 10 re f 0 0 1 rg 4 4 8 8 re f')
base = '/Type /Pattern /PatternType 1 /TilingType 1'
colored = stream(base+' /PaintType 1 /BBox [0 0 10 10] /XStep 10 /YStep 10 /Matrix [1 .25 .5 1 3 7] /Resources << >>', '0 .3 .7 rg 0 0 5 10 re f 1 .8 0 rg 5 0 5 10 re f')
uncolored = stream(base+' /PaintType 2 /BBox [0 0 8 8] /XStep 8 /YStep 8 /Resources << >>', '1 w 1 1 6 6 re S')
rich = stream(base+f' /PaintType 1 /BBox [2 3 32 33] /XStep 30 /YStep 30 /Resources << /Font << /F {font} 0 R >> /XObject << /Im {image} 0 R /Fm {form} 0 R >> >>', '0 .5 0 rg BT /F 12 Tf 3 17 Td (A) Tj ET q 8 0 0 8 18 20 cm /Im Do Q q 1 0 0 1 6 4 cm /Fm Do Q')
negative = stream(base+' /PaintType 1 /BBox [2 3 12 13] /XStep -15 /YStep -15 /Resources << >>', '.8 0 .2 rg 2 3 5 10 re f')
overlap = stream(base+' /PaintType 1 /BBox [-2 -3 12 13] /XStep 10 /YStep 10 /Resources << /ExtGState << /Half << /ca .5 >> >> >>', '/Half gs .1 .5 .8 rg -2 -3 14 16 re f')
blend = stream(base+' /PaintType 1 /BBox [0 0 20 20] /XStep 20 /YStep 20 /Resources << /ExtGState << /M << /BM /Multiply /ca .5 >> >> >>', '/M gs 1 .4 .2 rg 2 2 16 16 re f')
knockout = stream('/Type /XObject /Subtype /Form /BBox [0 0 200 180] /Group << /S /Transparency /I true /K true >> '+f'/Resources << /Pattern << /P4 {negative} 0 R >> >>', '0 .3 .8 rg 10 10 180 160 re f /Pattern cs /P4 scn 10 10 180 160 re f')
resources=f'<< /Pattern << /P1 {colored} 0 R /P2 {uncolored} 0 R /P3 {rich} 0 R /P4 {negative} 0 R /P5 {overlap} 0 R /P6 {blend} 0 R >> /XObject << /KO {knockout} 0 R >> /ColorSpace << /PCS [/Pattern /DeviceCMYK] >> >>'
cases=[
 ('base-matrix', 'q 1.4 .2 .3 .8 15 20 cm /Pattern cs /P1 scn 0 0 100 130 re f Q'),
 ('uncolored-fill-stroke', '/PCS cs 1 0 0 0 /P2 scn 10 10 80 140 re f /PCS CS 0 1 0 0 /P2 SCN 12 w 110 20 m 170 20 l 170 150 l S'),
 ('rich-cell', '/Pattern cs /P3 scn 10 10 180 160 re f'),
 ('negative-steps', '/Pattern cs /P4 scn 10 10 180 160 re f'),
 ('overlap', '/Pattern cs /P5 scn 10 10 180 160 re f'),
 ('backdrop-multiply', '.2 .7 .8 rg 0 0 100 180 re f .8 .2 .5 rg 100 0 100 180 re f /Pattern cs /P6 scn 10 10 180 160 re f'),
 ('knockout-cell-shape', '/KO Do'),
]
kids=[]
for name, content in cases:
    contents=stream('',content)
    kids.append(obj(f'<< /Type /Page /Parent {pages} 0 R /MediaBox [0 0 200 180] /Resources {resources} /Contents {contents} 0 R >>'))
objects[catalog-1]=f'<< /Type /Catalog /Pages {pages} 0 R >>'.encode()
objects[pages-1]=f'<< /Type /Pages /Count {len(kids)} /Kids [{" ".join(f"{k} 0 R" for k in kids)}] >>'.encode()
output=bytearray(b'%PDF-1.7\n'); offsets=[]
for i, value in enumerate(objects,1):
    offsets.append(len(output));output.extend(f'{i} 0 obj\n'.encode()+value+b'\nendobj\n')
xref=len(output);output.extend(f'xref\n0 {len(objects)+1}\n0000000000 65535 f \n'.encode())
for offset in offsets:output.extend(f'{offset:010d} 00000 n \n'.encode())
output.extend(f'trailer\n<< /Size {len(objects)+1} /Root {catalog} 0 R >>\nstartxref\n{xref}\n%%EOF\n'.encode())
destination=Path(sys.argv[1] if len(sys.argv)>1 else '_build/pattern-fixtures.pdf');destination.parent.mkdir(parents=True,exist_ok=True);destination.write_bytes(output)
print(destination)

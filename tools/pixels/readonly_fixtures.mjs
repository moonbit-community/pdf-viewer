// Authored PDF fixtures. Buffers/strings are byte based so binary streams and
// xref offsets remain exact; format parsing is never done in this helper.
export function makePdf(objects, trailer=''){
  const parts=[Buffer.from('%PDF-1.7\n')],offsets=[0];let length=parts[0].length;
  for(let index=0;index<objects.length;index++){
    offsets.push(length);const part=Buffer.concat([Buffer.from(`${index+1} 0 obj\n`),Buffer.from(objects[index]),Buffer.from('\nendobj\n')]);parts.push(part);length+=part.length;
  }
  parts.push(Buffer.from(`xref\n0 ${objects.length+1}\n0000000000 65535 f \n`+offsets.slice(1).map(offset=>`${String(offset).padStart(10,'0')} 00000 n \n`).join('')+`trailer << /Size ${objects.length+1} /Root 1 0 R ${trailer} >>\nstartxref\n${length}\n%%EOF\n`));
  return Buffer.concat(parts);
}
export function stream(dictionary,body){body=Buffer.from(body);return Buffer.concat([Buffer.from(`<< ${dictionary} /Length ${body.length} >>\nstream\n`),body,Buffer.from('\nendstream')]);}
export function rangeFixture(){
  return makePdf(rangeObjects());
}
function rangeObjects(){
  return [
    '<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 /MediaBox [0 0 200 800] >>',
    '<< /Type /Page /Parent 2 0 R /Resources << /Font << /F 6 0 R >> >> /Contents 5 0 R >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Rotate 90 /Resources << /XObject << /Unused 8 0 R >> >> /Contents 7 0 R >>',
    stream('','BT /F 12 Tf 10 760 Td (Range first page) Tj ET'),
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',stream('','0 0 1 rg 10 10 50 50 re f'),
    stream('/Type /XObject /Subtype /Form /BBox [0 0 200 300] /Resources << >>',Buffer.alloc(8*1024*1024,32)),
  ];
}
export function taggedRangeFixture(){
  const objects=rangeObjects();
  objects[0]='<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 9 0 R /MarkInfo << /Marked true >> >>';
  objects[2]=objects[2].replace('/Type /Page ','/Type /Page /StructParents 0 ');
  objects[4]=stream('','/P << /MCID 0 >> BDC BT /F 12 Tf 10 760 Td (Range first page) Tj ET EMC');
  objects[6]=stream('','0 0 1 rg 10 10 50 50 re f /Unused Do');
  objects[7]=stream('/Type /XObject /Subtype /Form /BBox [0 0 200 300] /Resources << >> /StructParents 1',
    Buffer.concat([Buffer.from('/P << /MCID 0 >> BDC EMC\n'),Buffer.alloc(8*1024*1024,32)]));
  objects.push('<< /Type /StructTreeRoot /K [10 0 R 12 0 R] /ParentTree 11 0 R >>',
    '<< /Type /StructElem /S /P /P 9 0 R /Pg 3 0 R /K 0 >>','<< /Nums [0 [10 0 R] 1 [12 0 R]] >>',
    '<< /Type /StructElem /S /P /P 9 0 R /Pg 4 0 R /K << /Type /MCR /Pg 4 0 R /Stm 8 0 R /MCID 0 >> >>');
  return makePdf(objects);
}
export function annotationFixture(){
  return makePdf([
    '<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [8 0 R 9 0 R 10 0 R 11 0 R] /DA (/Helv 12 Tf 0 g) /DR << /Font << /Helv 6 0 R >> >> >> >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] /Annots [5 0 R 7 0 R 8 0 R 9 0 R 10 0 R 11 0 R 12 0 R] >>',
    'null','<< /Subtype /Text /Rect [10 260 30 280] /Name /Comment /Contents (Readonly note) /F 28 >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    '<< /Subtype /Line /Rect [10 220 170 250] /L [20 230 160 240] /LE [/OpenArrow /Diamond] /C [1 0 0] /IC [0 1 0] /BS << /W 2 /S /D /D [2 3] >> /F 4 >>',
    '<< /Subtype /Widget /FT /Tx /T (name) /V (Readonly field) /Rect [10 175 185 205] /Q 2 /MK << /BG [0.9 0.95 1] /BC [0 0 1] >> /BS << /W 1 /S /I >> /F 4 >>',
    '<< /Subtype /Widget /FT /Tx /T (password) /V (hidden-secret) /Ff 8192 /Rect [10 135 185 165] /F 4 >>',
    '<< /Subtype /Widget /FT /Tx /T (comb) /V (ABCD) /Ff 16777216 /MaxLen 4 /Rect [10 100 185 125] /F 4 >>',
    '<< /Subtype /Widget /FT /Ch /T (list) /Opt [[(a) (Alpha)] [(b) (Beta)] [(c) (Gamma)]] /I [1 2] /V [(b) (c)] /Ff 2097152 /Rect [10 30 185 90] /F 4 >>',
    '<< /Subtype /Squiggly /Rect [10 12 180 24] /QuadPoints [10 24 180 24 10 12 180 12] /C [1 0 0] /F 4 >>',
  ]);
}
export function xfaFixture(dynamic=true){
  const xml=`<xdp:xdp xmlns:xdp="http://ns.adobe.com/xdp/">
<template xmlns="http://www.xfa.org/schema/xfa-template/3.3/"><subform name="form" layout="tb">
<pageSet><pageArea><medium short="200pt" long="300pt"/><contentArea x="10pt" y="10pt" w="180pt" h="280pt"/></pageArea></pageSet>
<draw w="170pt" h="20pt"><value><text>Readonly XFA heading</text></value><font typeface="Helvetica" size="12pt"/></draw>
<field name="customer" w="170pt" h="24pt"><ui><textEdit/></ui><font typeface="Helvetica" size="12pt"/><bind ref="$record.customer"/></field>
<draw w="170pt" h="240pt"><value><text>First page content</text></value></draw>
<draw w="170pt" h="30pt"><value><text>Second page content</text></value></draw>
</subform></template><xfa:datasets xmlns:xfa="http://www.xfa.org/schema/xfa-data/1.0/"><xfa:data><form><customer>Bound value</customer></form></xfa:data></xfa:datasets></xdp:xdp>`;
  return makePdf(['<< /Type /Catalog /Pages 2 0 R /AcroForm 4 0 R '+(dynamic?'/NeedsRendering true':'')+' >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>','<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] >>',
    '<< /XFA 5 0 R >>',stream('',xml)]);
}

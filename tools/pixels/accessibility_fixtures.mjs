import {makePdf,stream} from './readonly_fixtures.mjs';
export function namespaceFixture(){
 return makePdf([
  '<< /Type /Catalog /Version /2.0 /Pages 2 0 R /StructTreeRoot 6 0 R /Lang (en-US) >>',
  '<< /Type /Pages /Count 1 /Kids [3 0 R] >>',
  '<< /Type /Page /Parent 2 0 R /StructParents 0 /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
  stream('','/Span << /MCID 0 >> BDC BT /F1 12 Tf 20 150 Td (Heading) Tj ET EMC /Span << /MCID 1 >> BDC BT /F1 12 Tf 20 100 Td (Formula) Tj ET EMC /Span << /MCID 2 >> BDC BT /F1 12 Tf 20 60 Td (x) Tj ET EMC /Span << /MCID 3 >> BDC BT /F1 12 Tf 35 65 Td (2) Tj ET EMC'),
  '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  '<< /Type /StructTreeRoot /K [7 0 R 8 0 R 9 0 R] /ParentTree 15 0 R >>',
  '<< /Type /StructElem /S /Custom /NS 10 0 R /P 6 0 R /Pg 3 0 R /K 0 >>',
  '<< /Type /StructElem /S /Formula /Alt (x squared) /P 6 0 R /Pg 3 0 R /K 1 >>',
  '<< /Type /StructElem /S /math /NS 12 0 R /P 6 0 R /Pg 3 0 R /K 16 0 R >>',
  '<< /Type /Namespace /NS (urn:example:tags) /RoleMapNS << /Custom [/H2 11 0 R] >> >>',
  '<< /Type /Namespace /NS (http://iso.org/pdf2/ssn) >>',
  '<< /Type /Namespace /NS (http://www.w3.org/1998/Math/MathML) >>',
  '<< /Type /StructElem /S /mi /NS 12 0 R /P 16 0 R /Pg 3 0 R /K 2 >>',
  '<< /Type /StructElem /S /mn /NS 12 0 R /P 16 0 R /Pg 3 0 R /K 3 >>',
  '<< /Nums [0 [7 0 R 8 0 R 13 0 R 14 0 R]] >>',
  '<< /Type /StructElem /S /msup /NS 12 0 R /P 9 0 R /Pg 3 0 R /K [13 0 R 14 0 R] >>',
 ]);
}

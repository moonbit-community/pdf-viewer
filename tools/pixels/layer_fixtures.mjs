import {makePdf,stream} from './readonly_fixtures.mjs';

export function layerFixture({large=false}={}){
  const height=large?800:300;
  const content=`/OC /A BDC BT /F 12 Tf 10 ${height-30} Td (Alpha) Tj ET 0 0 1 rg 10 10 30 20 re f EMC
/OC /B BDC BT /F 12 Tf 10 ${height-50} Td (Beta) Tj ET 1 0 0 rg 50 10 30 20 re f EMC
/OC /Screen BDC BT /F 12 Tf 10 ${height-70} Td (Screen) Tj ET 1 0 1 rg 90 10 30 20 re f EMC
/OC /Paper BDC BT /F 12 Tf 10 ${height-90} Td (Paper) Tj ET 0 1 0 rg 130 10 30 20 re f EMC
/OC /Member BDC BT /F 12 Tf 10 ${height-110} Td (Member) Tj ET EMC /Form Do`;
  return makePdf([
    '<< /Type /Catalog /Pages 2 0 R /OCProperties << /OCGs [6 0 R 7 0 R 8 0 R 9 0 R 10 0 R] /D << /Name (Default) /BaseState /ON /OFF [7 0 R] /RBGroups [[6 0 R 7 0 R]] /Locked [10 0 R] /Order [[<FEFF56FE5C42> 6 0 R [(Nested) 7 0 R]] 8 0 R 9 0 R] >> /Configs [<< /Name (Alternative) /BaseState /OFF /ON [7 0 R 10 0 R] /RBGroups [[6 0 R 7 0 R]] /Locked [10 0 R] >> << /Name (Locked radio) /ON [6 0 R] /OFF [7 0 R] /RBGroups [[6 0 R 7 0 R]] /Locked [6 0 R] >>] >> /AcroForm << /Fields [12 0 R] /DA (/F 12 Tf 0 g) /DR << /Font << /F 5 0 R >> >> >> >>',
    '<< /Type /Pages /Count 2 /Kids [3 0 R 15 0 R] >>',
    `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 ${height}] /Contents 4 0 R /Resources << /Font << /F 5 0 R >> /Properties << /A 6 0 R /B 7 0 R /Screen 8 0 R /Paper 9 0 R /Member 14 0 R >> /XObject << /Form 13 0 R >> >> /Annots [11 0 R 12 0 R] >>`,
    stream('',content),
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    '<< /Type /OCG /Name <FEFF4E2D6587> >>','<< /Type /OCG /Name (Beta) >>',
    '<< /Type /OCG /Name (Screen) /Usage << /View << /ViewState /ON >> /Print << /PrintState /OFF >> >> >>',
    '<< /Type /OCG /Name (Paper) /Usage << /View << /ViewState /OFF >> /Print << /PrintState /ON >> >> >>',
    '<< /Type /OCG /Name (Locked) >>',
    '<< /Subtype /Text /Rect [10 50 30 70] /Contents (Layer note) /F 4 /OC 7 0 R >>',
    '<< /Subtype /Widget /FT /Tx /T (layer-field) /V (Before) /Rect [40 50 170 70] /DA (/F 12 Tf 0 g) /F 4 /OC 7 0 R >>',
    stream('/Type /XObject /Subtype /Form /BBox [0 0 200 300] /OC 7 0 R /Resources << /Font << /F 5 0 R >> >>','BT /F 12 Tf 10 80 Td (Form) Tj ET'),
    '<< /Type /OCMD /OCGs [6 0 R 7 0 R] /VE [/And 6 0 R [/Not 7 0 R]] >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] /Contents 16 0 R /Resources << /Font << /F 5 0 R >> /Properties << /B 7 0 R >> /XObject << /Unused 17 0 R >> >> >>',
    stream('','/OC /B BDC BT /F 12 Tf 10 250 Td (Second Beta) Tj ET EMC'),
    stream('/Type /XObject /Subtype /Form /BBox [0 0 200 300] /Resources << >>',large?Buffer.alloc(8*1024*1024,32):''),
  ]);
}

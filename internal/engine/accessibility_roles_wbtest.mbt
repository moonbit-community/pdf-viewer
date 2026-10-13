///|
test "accessibility resolves namespace-scoped roles and retains MathML token associations" {
  let source = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 6 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /StructParents 0 /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream(
      "", "/Span << /MCID 0 >> BDC BT /F1 12 Tf 20 150 Td (Heading) Tj ET EMC /Span << /MCID 1 >> BDC BT /F1 12 Tf 20 100 Td (Formula) Tj ET EMC /Span << /MCID 2 >> BDC BT /F1 12 Tf 20 60 Td (x) Tj ET EMC /Span << /MCID 3 >> BDC BT /F1 12 Tf 35 65 Td (2) Tj ET EMC",
    ),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    "<< /Type /StructTreeRoot /K [7 0 R 8 0 R 9 0 R] /ParentTree 15 0 R >>",
    "<< /Type /StructElem /S /Custom /NS 10 0 R /P 6 0 R /Pg 3 0 R /K 0 >>",
    "<< /Type /StructElem /S /Formula /Alt (x squared) /P 6 0 R /Pg 3 0 R /K 1 >>",
    "<< /Type /StructElem /S /math /NS 12 0 R /P 6 0 R /Pg 3 0 R /K [13 0 R 14 0 R] >>",
    "<< /Type /Namespace /NS (urn:example:tags) /RoleMapNS << /Custom [/H2 11 0 R] >> >>",
    "<< /Type /Namespace /NS (http://iso.org/pdf2/ssn) >>",
    "<< /Type /Namespace /NS (http://www.w3.org/1998/Math/MathML) >>",
    "<< /Type /StructElem /S /mi /NS 12 0 R /P 9 0 R /Pg 3 0 R /K 2 >>",
    "<< /Type /StructElem /S /mn /NS 12 0 R /P 9 0 R /Pg 3 0 R /K 3 >>",
    "<< /Nums [0 [7 0 R 8 0 R 13 0 R 14 0 R]] >>",
  ])
  let data = source.accessibility_page_json(1).unwrap()
  guard data
    is {
      "nodes": Array([{ "children": Array([heading, formula, math]), .. }]),
      ..
    } else {
    fail(@debug.to_string(data))
  }
  assert_true(
    heading
    is {
      "tag": String("H2"),
      "namespace": String("http://iso.org/pdf2/ssn"),
      ..
    },
  )
  assert_true(
    formula is { "tag": String("Formula"), "alt": String("x squared"), .. },
  )
  assert_true(
    math
    is {
      "tag": String("math"),
      "namespace": String("http://www.w3.org/1998/Math/MathML"),
      "children": Array([_, _]),
      ..
    },
  )
  assert_true(data is { "unmapped_items": Number(0), .. })
}

///|
test "accessibility namespace RoleMap cycles remain bounded" {
  let source = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>", "<< /Type /Namespace /NS (urn:cycle) /RoleMapNS << /A /B /B /A >> >>",
  ])
  let dictionary = @syntax.pdf_dictionary([
    (pdf_name_key("/S"), @syntax.PdfNameObject(pdf_name_key("/A"))),
    (pdf_name_key("/NS"), @syntax.PdfIndirect(4)),
  ])
  assert_eq(
    pdf_accessibility_role(source.document, dictionary, @syntax.PdfNull),
    ("A", Some("urn:cycle")),
  )
}

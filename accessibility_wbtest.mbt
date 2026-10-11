///|
fn accessibility_test_groups(json : Json) -> Array[Json] {
  match json {
    { "nodes": Array(nodes), .. } | { "children": Array(nodes), .. } => {
      let output = []
      for node in nodes {
        output.append(accessibility_test_groups(node))
      }
      output
    }
    { "groups": Array(groups), .. } => groups
    _ => []
  }
}

///|
test "accessibility maps named properties roles language and artifacts to original glyphs" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /Lang (fr) /StructTreeRoot 6 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> /Properties << /Heading << /MCID 0 >> >> >> >>",
    annotation_test_stream(
      "", "BT /F1 10 Tf 20 150 Td /P << /MCID 1 >> BDC (B) Tj EMC 0 -20 Td /H1 /Heading BDC (H) Tj EMC 0 -20 Td /Artifact BMC (Artifact) Tj EMC 0 -20 Td (Tail) Tj ET",
    ),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    "<< /Type /StructTreeRoot /K [7 0 R 8 0 R 9 0 R] /RoleMap << /MyHeading /H2 >> >>",
    "<< /Type /StructElem /S /MyHeading /Pg 3 0 R /Lang (de) /K 0 >>",
    "<< /Type /StructElem /S /P /Pg 3 0 R /ActualText (Replacement) /K 1 >>",
    "<< /Type /StructElem /S /Figure /Pg 3 0 R /Alt (<img> literal) >>",
  ])
  let before = document.page(1).unwrap().text_content()
  let data = document.accessibility_page_json(1).unwrap()
  let cached = document.page(1).unwrap()
  assert_eq(
    document.accessibility_page_json(1, page_model=Some(cached)),
    Some(data),
  )
  assert_eq(document.accessibility_page_json(0, page_model=Some(cached)), None)
  assert_eq(document.accessibility_page_json(2, page_model=Some(cached)), None)
  assert_true(
    data
    is {
      "lang": "fr",
      "tagged": true,
      "mapped_items": 2,
      "excluded_items": 8,
      "unmapped_items": 4,
      "truncated": false,
      "nodes": [
        {
          "children": [
            { "tag": "H2", "lang": "de", .. },
            { "tag": "P", "actual_text": "Replacement", .. },
            { "tag": "Figure", "alt": "<img> literal", .. },
          ],
          ..
        },
        { "tag": "P", "inferred": true, .. },
      ],
      ..
    },
  )
  assert_true(
    accessibility_test_groups(data)
    is [
      { "text": "H", "items": [1], .. },
      { "text": "B", "items": [0], .. },
      { "text": "Tail", "items": [10, 11, 12, 13], .. },
    ],
  )
  assert_eq(document.page(1).unwrap().text_content(), before)
  assert_eq(document.accessibility_page_json(0), None)
  assert_eq(document.accessibility_page_json(2), None)
}

///|
test "accessibility uses ParentTree for page-local MCIDs without Pg" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 8 0 R >>",
    "<< /Type /Pages /Count 2 /Kids [3 0 R 4 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /StructParents 0 /Contents 5 0 R /Resources << /Font << /F1 7 0 R >> >> >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /StructParents 1 /Contents 6 0 R /Resources << /Font << /F1 7 0 R >> >> >>",
    annotation_test_stream(
      "", "/P << /MCID 0 >> BDC BT /F1 10 Tf 20 100 Td (One) Tj ET EMC",
    ),
    annotation_test_stream(
      "", "/P << /MCID 0 >> BDC BT /F1 10 Tf 20 100 Td (Two) Tj ET EMC",
    ),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    "<< /Type /StructTreeRoot /K [9 0 R 10 0 R] /ParentTree 11 0 R >>",
    "<< /Type /StructElem /S /H1 /K 0 >>",
    "<< /Type /StructElem /S /P /K 0 >>",
    "<< /Kids [12 0 R] >>",
    "<< /Nums [0 [9 0 R] 1 [10 0 R]] >>",
  ])
  let first = document.accessibility_page_json(1).unwrap()
  let second = document.accessibility_page_json(2).unwrap()
  assert_true(
    first
    is {
      "mapped_items": 3,
      "nodes": [{ "children": [{ "tag": "H1", .. }], .. }],
      ..
    },
  )
  assert_true(
    second
    is {
      "mapped_items": 3,
      "nodes": [{ "children": [{ "tag": "P", .. }], .. }],
      ..
    },
  )
  assert_true(accessibility_test_groups(first) is [{ "text": "One", .. }])
  assert_true(accessibility_test_groups(second) is [{ "text": "Two", .. }])
}

///|
test "accessibility keeps inherited markers stream MCIDs and repeated Forms distinct" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 8 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> /XObject << /Shared 6 0 R /Own 7 0 R >> >> >>",
    annotation_test_stream(
      "", "/P << /MCID 3 >> BDC /Shared Do /Shared Do EMC /Own Do /Own Do",
    ),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    annotation_test_stream(
      "/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Resources << /Font << /F1 5 0 R >> >>",
      "BT /F1 10 Tf 10 50 Td (S) Tj ET",
    ),
    annotation_test_stream(
      "/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Resources << /Font << /F1 5 0 R >> >>",
      "/P << /MCID 3 >> BDC BT /F1 10 Tf 10 50 Td (T) Tj ET EMC",
    ),
    "<< /Type /StructTreeRoot /K [9 0 R 10 0 R] >>",
    "<< /Type /StructElem /S /P /Pg 3 0 R /K 3 >>",
    "<< /Type /StructElem /S /P /Pg 3 0 R /K << /Type /MCR /Stm 7 0 R /MCID 3 >> >>",
  ])
  let data = document.accessibility_page_json(1).unwrap()
  let groups = accessibility_test_groups(data)
  assert_true(data is { "mapped_items": 4, "unmapped_items": 0, .. })
  assert_eq(groups.length(), 4)
  assert_true(
    groups
    is [
      {
        "text": "S",
        "items": [0],
        "form_path": [{ "operator_index": 1, .. }],
        ..
      },
      {
        "text": "S",
        "items": [1],
        "form_path": [{ "operator_index": 2, .. }],
        ..
      },
      {
        "text": "T",
        "items": [2],
        "form_path": [{ "operator_index": 4, .. }],
        ..
      },
      {
        "text": "T",
        "items": [3],
        "form_path": [{ "operator_index": 5, .. }],
        ..
      },
    ],
  )
}

///|
test "accessibility retains annotation OBJR original indices and table attributes" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 4 0 R >>", "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> /Annots [5 0 R 6 0 R] >>",
    "<< /Type /StructTreeRoot /K [7 0 R 8 0 R] >>", "<< /Subtype /Popup /Rect [10 10 20 20] >>",
    "<< /Subtype /Link /Rect [10 10 20 20] /A << /S /URI /URI (https://example.com/) >> >>",
    "<< /Type /StructElem /S /Link /Pg 3 0 R /K << /Type /OBJR /Obj 6 0 R >> >>",
    "<< /Type /StructElem /S /TH /Pg 3 0 R /Alt (Heading) /A [<< /O /Layout >> << /O /Table /ColSpan 2 /RowSpan 3 /Scope /Row >>] >>",
  ])
  assert_true(
    document.accessibility_page_json(1).unwrap()
    is {
      "nodes": [
        {
          "children": [
            {
              "tag": "Link",
              "children": [{ "type": "annotation", "index": 1, .. }],
              ..
            },
            { "tag": "TH", "col_span": 2, "row_span": 3, "scope": "Row", .. },
          ],
          ..
        },
      ],
      ..
    },
  )
}

///|
test "accessibility bounds cyclic structure and role maps while retaining unclaimed text" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 6 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream("", "BT /F1 10 Tf 20 100 Td (Safe) Tj ET"),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    "<< /Type /StructTreeRoot /K 7 0 R /RoleMap << /A /B /B /A >> >>",
    "<< /Type /StructElem /S /A /Pg 3 0 R /K [7 0 R 6 0 R] >>",
  ])
  let data = document.accessibility_page_json(1).unwrap()
  assert_true(data is { "mapped_items": 0, "unmapped_items": 4, .. })
  assert_true(accessibility_test_groups(data) is [{ "text": "Safe", .. }])
  let untagged = provenance_test_document(
    "BT /F1 10 Tf 20 100 Td (Readable) Tj ET",
  )
  assert_true(
    untagged.accessibility_page_json(1).unwrap()
    is { "tagged": false, "nodes": [{ "tag": "P", "inferred": true, .. }], .. },
  )
}

///|
test "accessibility does not expose hidden optional content in a tagged paragraph" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 7 0 R /OCProperties << /OCGs [6 0 R] /D << /OFF [6 0 R] >> >> >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> /Properties << /Layer 6 0 R >> >> >>",
    annotation_test_stream(
      "", "/P << /MCID 0 >> BDC BT /F1 10 Tf 20 100 Td /OC /Layer BDC (Hidden) Tj EMC (Visible) Tj ET EMC",
    ),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    "<< /Type /OCG /Name (Hidden layer) >>",
    "<< /Type /StructTreeRoot /K 8 0 R >>",
    "<< /Type /StructElem /S /P /Pg 3 0 R /K 0 >>",
  ])
  let data = document.accessibility_page_json(1).unwrap()
  assert_true(data is { "mapped_items": 7, "unmapped_items": 0, .. })
  assert_true(accessibility_test_groups(data) is [{ "text": "Visible", .. }])
}

///|
test "accessibility reports bounded deep trees and retains BDC ActualText" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 6 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream(
      "", "/P << /MCID 0 /ActualText (Logical text) >> BDC BT /F1 10 Tf 20 100 Td (Painted) Tj ET EMC",
    ),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    "<< /Type /StructTreeRoot /K 7 0 R >>",
    "<< /Type /StructElem /S /P /Pg 3 0 R /K 0 >>",
  ])
  assert_true(
    accessibility_test_groups(document.accessibility_page_json(1).unwrap())
    is [{ "text": "Logical text", "items": [0, 1, 2, 3, 4, 5, 6], .. }],
  )
  let objects = [
    "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 6 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream("", "BT /F1 10 Tf 20 100 Td (Safe) Tj ET"),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    "<< /Type /StructTreeRoot /K 7 0 R >>",
  ]
  for index in 7..<87 {
    objects.push(
      "<< /Type /StructElem /S /Div /Pg 3 0 R /K \{index + 1} 0 R >>",
    )
  }
  objects.push(
    "<< /Type /StructElem /S /P /Pg 3 0 R /ActualText (Beyond limit) >>",
  )
  let data = annotation_test_document(objects)
    .accessibility_page_json(1)
    .unwrap()
  assert_true(data is { "truncated": true, "unmapped_items": 4, .. })
  assert_true(accessibility_test_groups(data) is [{ "text": "Safe", .. }])
}

///|
test "accessibility replaces an inline ActualText span once without dropping surrounding glyphs" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 6 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream(
      "", "/P << /MCID 0 >> BDC BT /F1 10 Tf 20 100 Td (Before ) Tj /Span << /ActualText (Replacement) >> BDC (XX) Tj (YY) Tj EMC ( after) Tj ET EMC",
    ),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    "<< /Type /StructTreeRoot /K 7 0 R >>",
    "<< /Type /StructElem /S /P /Pg 3 0 R /K 0 >>",
  ])
  let data = document.accessibility_page_json(1).unwrap()
  assert_true(data is { "mapped_items": 17, "unmapped_items": 0, .. })
  assert_true(
    accessibility_test_groups(data)
    is [
      { "text": "Before ", "items": [0, 1, 2, 3, 4, 5, 6], .. },
      { "text": "Replacement", "items": [7, 8, 9, 10], "separator": "", .. },
      {
        "text": " after",
        "items": [11, 12, 13, 14, 15, 16],
        "separator": "",
        ..
      },
    ],
  )
  assert_eq(document.page(1).unwrap().text_content().text, "Before XXYY after")
}

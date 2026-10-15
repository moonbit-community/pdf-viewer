///|
test "accessibility retains descendant page overrides and page-local alternate text" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 8 0 R >>",
    "<< /Type /Pages /Count 2 /Kids [3 0 R 6 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream(
      "", "/Span << /MCID 0 >> BDC BT /F1 12 Tf 20 150 Td (First) Tj ET EMC",
    ),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 7 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream("", ""),
    "<< /Type /StructTreeRoot /K 9 0 R >>",
    "<< /Type /StructElem /S /Sect /Pg 6 0 R /P 8 0 R /K [10 0 R 11 0 R] >>",
    "<< /Type /StructElem /S /H1 /Pg 3 0 R /P 9 0 R /K 0 >>",
    "<< /Type /StructElem /S /Figure /Pg 6 0 R /P 9 0 R /Alt (Second figure) >>",
  ])
  let first = document.accessibility_page_json(1).unwrap()
  guard first is { "nodes": Array([{ "children": Array([section]), .. }]), .. } else {
    fail(@debug.to_string(first))
  }
  assert_true(
    section
    is {
      "tag": String("Sect"),
      "children": Array([{ "tag": String("H1"), .. }]),
      ..
    },
  )
  assert_true(first is { "unmapped_items": Number(0, ..), .. })
  let second = document.accessibility_page_json(2).unwrap()
  guard second is { "nodes": Array([{ "children": Array([section]), .. }]), .. } else {
    fail(@debug.to_string(second))
  }
  assert_true(
    section
    is {
      "tag": String("Sect"),
      "children": Array(
        [
          {
            "tag": String("Figure"),
            "alt": String("Second figure"),
            "children": Array([]),
            ..
          },
        ]
      ),
      ..
    },
  )
}

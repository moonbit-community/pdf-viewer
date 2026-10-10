///|
test "run paragraph sources retain UTF16 ligatures surrogate pairs and inferred gaps" {
  let document = unicode_search_test_document(
    ["😀", "ﬁ", "Next", "Last"],
    positions=[(20.0, 100.0), (26.0, 100.0), (20.0, 86.0), (20.0, 50.0)],
    widths=[600, 600, 2400, 2400],
  )
  let page = document.page(1).unwrap()
  let structure = page.text_structure()
  assert_eq(structure.text, page.text_content().text)
  assert_eq(structure.text, "😀ﬁ\nNext\nLast")
  assert_eq(
    [
      for paragraph in structure.paragraphs => (paragraph.start, paragraph.end)
    ],
    [(0, 8), (9, 13)],
  )
  assert_eq(
    [
      for run in structure.paragraphs[0].runs => (run.start, run.end)
    ],
    [(0, 3), (4, 8)],
  )
  let sources : Array[PdfTextSourceRange] = []
  for paragraph in structure.paragraphs {
    for run in paragraph.runs {
      sources.append(run.sources)
    }
  }
  assert_eq(sources, page.text_sources())
  assert_eq(document.search("fi")[0].index, 2)
  assert_eq(page.select_text(0, 0, 0, 1), None)
  assert_eq(page.select_text(0, 0, 2, 4).unwrap().text, "😀ﬁ\nNext")
}

///|
test "runs split font and direction boundaries while sharing source order" {
  let document = provenance_test_document(
    "BT /F1 10 Tf 20 100 Td (A) Tj /F2 10 Tf (B) Tj ET",
    resources="<< /Font << /F1 5 0 R /F2 6 0 R >> >>",
    extra_objects=["<< /Subtype /Type1 /BaseFont /Courier >>"],
  )
  let page = document.page(1).unwrap()
  let structure = page.text_structure()
  assert_eq(structure.paragraphs.length(), 1)
  assert_eq([ for run in structure.paragraphs[0].runs => run.font ], [
    "/F1", "/F2",
  ])
  assert_eq(
    structure.paragraphs[0].bounds,
    pdf_bounds_union(
      page.text_content().items[0].bounds,
      page.text_content().items[1].bounds,
    ),
  )
}

///|
test "textless structure returns an empty paragraph list" {
  let page = provenance_test_document("0 0 10 10 re f").page(1).unwrap()
  assert_eq(page.text_structure(), { text: "", paragraphs: [], })
}

///|
fn unicode_search_test_document(
  mappings : Array[String],
  positions? : Array[(Double, Double)] = [],
  widths? : Array[Int] = [],
) -> PdfViewerDocument raise {
  let cmap = StringBuilder()
  let codes = StringBuilder()
  let positioned = StringBuilder()
  let hex = "0123456789ABCDEF"
  cmap.write_string(mappings.length().to_string() + " beginbfchar\n")
  for index, text in mappings {
    let code = 65 + index
    let name = hex.get_char(code / 16).unwrap().to_string() +
      hex.get_char(code % 16).unwrap().to_string()
    codes.write_string(name)
    match positions.get(index) {
      Some((x, y)) =>
        positioned.write_string(
          "1 0 0 1 " +
          x.to_string() +
          " " +
          y.to_string() +
          " Tm <" +
          name +
          "> Tj ",
        )
      None => ()
    }
    cmap.write_string("<" + name + "> <")
    for unit in text.code_units() {
      let value = unit.to_int()
      for shift in [12, 8, 4, 0] {
        cmap.write_char(hex.get_char((value >> shift) & 15).unwrap())
      }
    }
    cmap.write_string(">\n")
  }
  cmap.write_string("endbfchar")
  annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream(
      "",
      "BT /F1 10 Tf " +
      (if positions.is_empty() {
        "20 100 Td <" + codes.to_string() + "> Tj"
      } else {
        positioned.to_string()
      }) +
      " ET",
    ),
    "<< /Type /Font /Subtype /TrueType /BaseFont /UnicodeProbe /FirstChar 65 /LastChar " +
    (64 + mappings.length()).to_string() +
    " /Widths [" +
    [
      for index, _ in mappings => widths.get(index).unwrap_or(600).to_string()
    ].join(" ") +
    "] /FontDescriptor << /FontBBox [0 -200 1000 800] /Ascent 800 /Descent -200 >> /ToUnicode 6 0 R >>",
    annotation_test_stream("", cmap.to_string()),
  ])
}

///|
test "Unicode search joins decomposed accents to their original glyph range" {
  let viewer = unicode_search_test_document([
    "😀", "c", "a", "f", "e", "\u0301",
  ])
  let page = viewer.page(1).unwrap()
  let matches = viewer.search("CAFÉ")
  assert_eq(matches.length(), 1)
  assert_eq(
    (matches[0].index, matches[0].length, matches[0].text),
    (2, 5, "cafe\u0301"),
  )
  assert_eq(
    matches[0].item_indices,
    [
      for item in page.text_content().items[1:] => item.index
    ],
  )
  let items = page.text_content().items
  assert_eq(
    page.select_text(items[1].index, 0, items[5].index, 1).unwrap().text,
    matches[0].text,
  )
}

///|
test "Unicode search covers compatibility ligatures Hangul and non Latin accents" {
  for
    (source, query) in [
      ("oﬃce", "office"),
      ("ＡＢ", "ab"),
      ("가", "\u1100\u1161"),
      ("ὒ", "υ"),
    ] {
    let viewer = unicode_search_test_document(["😀", source])
    let result = viewer.search(query)
    assert_eq(result.length(), 1)
    assert_eq(
      (result[0].index, result[0].length, result[0].text),
      (2, source.length(), source),
    )
    assert_eq(result[0].item_indices, [
      viewer.page(1).unwrap().text_content().items[1].index,
    ])
  }
}

///|
test "diacritic sensitive search preserves canonical equivalence and rejects bare bases" {
  let viewer = unicode_search_test_document(["é", " ", "e", "\u0301"])
  let sensitive = pdf_search_options(diacritic_sensitive=true)
  assert_eq(viewer.search("é", options=sensitive).length(), 2)
  assert_eq(viewer.search("e\u0301", options=sensitive).length(), 2)
  assert_true(viewer.search("e", options=sensitive).is_empty())
  assert_eq(viewer.search("e").length(), 2)
}

///|
test "canonical mark ordering preserves source intervals after reordering" {
  let source = "a\u0315\u0300"
  let viewer = unicode_search_test_document(["😀", source])
  let result = viewer.search(
    "à\u0315",
    options=pdf_search_options(diacritic_sensitive=true),
  )
  assert_eq(result.length(), 1)
  assert_eq((result[0].index, result[0].length, result[0].text), (2, 3, source))
  let normalized = pdf_search_normalized(
    source,
    pdf_search_options(diacritic_sensitive=true),
  )
  assert_eq(normalized.text, "a\u0300\u0315")
  assert_eq(normalized.source_starts, [0, 2, 1])
  assert_eq(normalized.source_ends, [1, 3, 2])
}

///|
test "Unicode word boundaries distinguish letters from punctuation and emoji" {
  let options = pdf_search_options(whole_word=true)
  let viewer = unicode_search_test_document([
    "😀", "café", "—", "cafe", "😀",
  ])
  assert_eq(viewer.search("cafe", options~).length(), 2)
  let joined = unicode_search_test_document(["x", "café", "y"])
  assert_true(joined.search("cafe", options~).is_empty())
  assert_true(
    unicode_search_test_document(["café", "_"])
    .search("cafe", options~)
    .is_empty(),
  )
}

///|
test "case sensitive compatibility search keeps case while case folding expands sharp s" {
  let viewer = unicode_search_test_document(["Æ", " ", "Straße"])
  assert_true(
    viewer
    .search("ae", options=pdf_search_options(case_sensitive=true))
    .is_empty(),
  )
  assert_eq(
    viewer
    .search("AE", options=pdf_search_options(case_sensitive=true))
    .length(),
    1,
  )
  assert_eq(
    viewer
    .search("STRASSE", options=pdf_search_options(diacritic_sensitive=true))
    .length(),
    1,
  )
}

///|
test "compatibility capitals fold after decomposition without losing supplementary offsets" {
  let viewer = unicode_search_test_document(["😀", "𝔄", "ℐ"])
  let hit = viewer.search("ai")[0]
  assert_eq(
    (hit.index, hit.length, hit.text, hit.item_indices),
    (2, 3, "𝔄ℐ", [1, 2]),
  )
  assert_eq(
    viewer
    .search("AI", options=pdf_search_options(case_sensitive=true))
    .length(),
    1,
  )
  assert_true(
    viewer
    .search("ai", options=pdf_search_options(case_sensitive=true))
    .is_empty(),
  )
}

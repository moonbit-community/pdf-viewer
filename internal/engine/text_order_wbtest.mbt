///|
test "text APIs build reading order from line geometry" {
  let page = annotation_test_page(
    [],
    contents="BT /F1 10 Tf 20 60 Td (Second) Tj 0 40 Td (First) Tj ET",
    resources="<< /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >>",
  )
  let content = page.text_content()
  assert_eq(content.text, "First\nSecond")
  assert_eq([ for item in content.items => item.text ], [
    "F", "i", "r", "s", "t", "S", "e", "c", "o", "n", "d",
  ])
  assert_eq([ for item in page.text_layer().items => item.separator ], [
    "", "", "", "", "", "\n", "", "", "", "", "",
  ])
}

///|
test "text APIs synthesize a word separator from a geometric gap" {
  let page = annotation_test_page(
    [],
    contents="BT /F1 10 Tf 20 100 Td (A) Tj 20 0 Td (B) Tj ET",
    resources="<< /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >>",
  )
  assert_eq(page.text_content().text, "A B")
  assert_eq([ for item in page.text_layer().items => item.separator ], ["", " "])
}

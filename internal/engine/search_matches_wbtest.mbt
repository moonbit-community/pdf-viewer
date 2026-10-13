///|
test "shared search ranges retain original UTF16 positions after Unicode expansion and mark removal" {
  let text = "😀á ﬃ İ Straße"
  let options = pdf_search_options()
  assert_eq(options.find_matches(text, "a"), [(2, 4), (12, 13)])
  assert_eq(options.find_matches(text, "ffi"), [(5, 6)])
  assert_eq(options.find_matches(text, "i"), [(5, 6), (7, 8)])
  assert_eq(pdf_search_options(whole_word=true).find_matches(text, "strasse"), [
    (9, 15),
  ])
  assert_eq(
    pdf_search_options(diacritic_sensitive=true).find_matches(text, "a"),
    [(12, 13)],
  )
  assert_eq(options.find_matches(text, ""), [])
  assert_eq(options.find_matches(text, "missing"), [])
  assert_eq(options.find_matches("ΣΟΣ σος", "σοσ"), [(0, 3), (4, 7)])
  assert_eq(options.find_matches("ΣΟΣ σος", "σος"), [(0, 3), (4, 7)])
}

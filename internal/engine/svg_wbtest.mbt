///|
test "XML serialization escapes every repeated metacharacter once" {
  assert_eq(
    pdf_escape_xml("&&<<>>\"\"''"),
    "&amp;&amp;&lt;&lt;&gt;&gt;&quot;&quot;&apos;&apos;",
  )
  assert_eq(pdf_escape_xml("&lt;<"), "&amp;lt;&lt;")
}

///|
test "public SVG outline labels preserve repeated XML metacharacters" {
  let page = annotation_test_page(
    [],
    contents="BT /F1 12 Tf 20 80 Td (<<>>&&\"\"'') Tj ET",
    resources="<< /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >> >> >>",
  )
  assert_eq(page.text, "<<>>&&\"\"''")
  let svg = page.render_svg()
  assert_true(
    svg.contains(
      "<title>&lt;&lt;&gt;&gt;&amp;&amp;&quot;&quot;&apos;&apos;</title>",
    ),
  )
}

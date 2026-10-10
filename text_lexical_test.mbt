///|
test "public lexical origins do not claim file glyph offsets for encrypted streams" {
  for
    bytes in [
      pdf_viewer_encrypted_fixture(),
      pdf_viewer_encrypted_40bit_fixture(),
      pdf_viewer_encrypted_aesv2_fixture(),
    ] {
    let document = @pdf-viewer.open_document_with_passwords(
      bytes,
      user_password=Some(@utf8.encode("user-password")),
    )
    let sources = document.text_lexical_sources(1).unwrap()
    assert_eq(
      [
        for source in sources => source.string_source.unwrap().bytes
      ],
      [
        for byte in b"Encrypted\xA0preview" => Bytes::from_array([byte])
      ],
    )
    for source in sources {
      assert_eq(source.failure, None)
      assert_true(!source.spans.is_empty())
      for span in source.spans {
        assert_eq(span.file_span, None)
      }
    }
  }
}

///|
test "public lexical origins share selection source and optional content state" {
  let (bytes, layer) = pdf_viewer_optional_content_fixture()
  let hidden = @pdf-viewer.open_document(bytes)
  assert_eq(hidden.text_lexical_sources(1), Some([]))
  let document = hidden.with_optional_content_state(
    @pdf-viewer.pdf_optional_content_state(on=[layer]),
  )
  let page = document.page(1).unwrap()
  let sources = document.text_lexical_sources(1).unwrap()
  assert_eq(
    [
      for source in sources => source.logical_source.unwrap()
    ],
    page.text_sources(),
  )
  assert_true(sources.all(source => source.failure is None))
  assert_true(ToJson::to_json(sources[0]) is Json::Object(_))
}

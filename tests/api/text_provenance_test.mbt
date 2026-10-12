///|
test "public provenance joins copy search and selection without changing rendering" {
  let viewer = pdf_viewer_fixture()
  let page = viewer.page(1).unwrap()
  let before = viewer.render_svg(1).unwrap()
  let provenance = viewer.text_provenance(1).unwrap()
  assert_eq([ for item in provenance => item.source ], page.text_sources())
  let hits = viewer.search("Hello")
  assert_eq(hits.length(), 1)
  let joined : Array[Bytes] = []
  for index in hits[0].item_indices {
    let found = provenance
      .search_by(item => item.source.item_index == index)
      .unwrap()
    let item = provenance[found]
    let origin = item.string_source.unwrap()
    assert_true(origin.charcode_valid)
    assert_eq(origin.byte_end - origin.byte_start, 1)
    joined.push(origin.bytes)
    assert_true(item.font_object_number is Some(_))
    assert_eq(item.gid, None)
  }
  assert_eq(joined, [b"H", b"e", b"l", b"l", b"o"])
  assert_eq(viewer.render_svg(1).unwrap(), before)
  assert_true(ToJson::to_json(provenance[0]) is Json::Object(_))
}

///|
test "public provenance reports decrypted operand bytes for encrypted documents" {
  for
    bytes in [
      pdf_viewer_encrypted_fixture(),
      pdf_viewer_encrypted_40bit_fixture(),
      pdf_viewer_encrypted_aesv2_fixture(),
    ] {
    let viewer = @pdf-viewer.open_document_with_passwords(
      bytes,
      user_password=Some(@utf8.encode("user-password")),
    )
    let page = viewer.page(1).unwrap()
    let provenance = viewer.text_provenance(1).unwrap()
    assert_eq([ for item in provenance => item.source ], page.text_sources())
    assert_eq(
      [
        for item in provenance => item.string_source.unwrap().bytes
      ],
      // pdflite typesets the space with the WinAnsi nonbreaking-space code.
      [
        for byte in b"Encrypted\xA0preview" => Bytes::from_array([byte])
      ],
    )
  }
}

///|
test "public provenance respects changed optional content visibility" {
  let (bytes, layer) = pdf_viewer_optional_content_fixture()
  let viewer = @pdf-viewer.open_document(bytes)
  assert_eq(viewer.text_provenance(1), Some([]))
  let visible = viewer.with_optional_content_state(
    @pdf-viewer.pdf_optional_content_state(on=[layer]),
  )
  let provenance = visible.text_provenance(1).unwrap()
  assert_eq(
    [
      for item in provenance => item.source
    ],
    visible.page(1).unwrap().text_sources(),
  )
  assert_true(!provenance.is_empty())
  assert_true(provenance.all(item => item.string_source is Some(_)))
}

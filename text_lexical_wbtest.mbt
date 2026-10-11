///|
fn lexical_test_spellings(
  document : PdfViewerDocument,
  sources : ArrayView[PdfTextLexicalSource],
) -> Array[Bytes] raise {
  [
    for source in sources => {
      assert_eq(source.failure, None)
      let bytes : Array[Byte] = []
      for span in source.spans {
        let stream = document.document
          .pdf_decode_stream(@syntax.PdfIndirect(span.object_number.unwrap()))
          .stream_bytes()
        for
          byte in stream[span.decoded_stream_span.start:span.decoded_stream_span.end] {
          bytes.push(byte)
        }
      }
      Bytes::from_array(bytes)
    }
  ]
}

///|
test "lexical glyph sources retain escaped spellings and correct TJ quote operands" {
  let document = provenance_test_document(
    "BT /F1 10 Tf 12 TL 20 100 Td (A\\101\\nB\\\r\nC) Tj [(D) -100 () <45>] TJ (F) ' 0 1 (G) \" ET",
  )
  let sources = document.text_lexical_sources(1).unwrap()
  assert_eq(lexical_test_spellings(document, sources[:]), [
    b"A", b"\\101", b"\\n", b"B", b"C", b"D", b"45", b"F", b"G",
  ])
  assert_eq(
    [
      for source in sources => source.string_source.unwrap().operand_index
    ],
    [0, 0, 0, 0, 0, 0, 3, 0, 2],
  )
  for source in sources {
    assert_eq(source.logical_source.unwrap().item_index, source.item_index)
    for span in source.spans {
      assert_eq(span.object_number, Some(4))
      assert_true(span.file_span is Some(_))
      assert_true(span.encoded_stream_span is Some(_))
      guard document.document.direct(@syntax.PdfIndirect(4))
        is @syntax.PdfStreamObject({ data: @syntax.StreamToGet(input), .. }) else {
        fail("expected lazy source stream")
      }
      let file = span.file_span.unwrap()
      let decoded = document.document
        .pdf_decode_stream(@syntax.PdfIndirect(4))
        .stream_bytes()
      assert_eq(
        input.input.view()[file.start:file.end],
        decoded[span.decoded_stream_span.start:span.decoded_stream_span.end],
      )
    }
  }
}

///|
test "lexical hex spans preserve whitespace odd nibble and multi byte codes" {
  let document = cid_layout_test_document(
    "BT /F1 10 Tf 20 100 Td <41 81 01 C0 01 02 F0 01 02 03> Tj ET",
    cmap=cmap_text_test_mixed_cmap(),
    tounicode=cmap_text_test_tounicode(),
  )
  let sources = document.text_lexical_sources(1).unwrap()
  assert_eq(lexical_test_spellings(document, sources[:]), [
    b"41", b"8101", b"C00102", b"F0010203",
  ])
  assert_eq([ for source in sources => source.spans.length() ], [1, 2, 3, 4])
  let odd = provenance_test_document("BT /F1 10 Tf 20 100 Td <414> Tj ET")
  let sources = odd.text_lexical_sources(1).unwrap()
  assert_eq(lexical_test_spellings(odd, sources[:]), [b"41", b"4"])
  assert_eq(sources[1].string_source.unwrap().bytes, b"\x40")
}

///|
test "lexical source maps shared Forms without losing invocation identity" {
  let document = provenance_test_document(
    "BT /F1 10 Tf 20 100 Td ET /Fm Do /Fm Do",
    resources="<< /Font << /F1 5 0 R >> /XObject << /Fm 6 0 R >> >>",
    extra_objects=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 200 200] /Resources << >>", "BT (A\\102) Tj ET",
      ),
    ],
  )
  let sources = document.text_lexical_sources(1).unwrap()
  assert_eq(lexical_test_spellings(document, sources[:]), [
    b"A", b"\\102", b"A", b"\\102",
  ])
  assert_eq(sources[0].spans, sources[2].spans)
  assert_true(
    sources[0].string_source.unwrap().form_path !=
    sources[2].string_source.unwrap().form_path,
  )
  assert_eq(sources[0].spans[0].object_number, Some(6))
}

///|
test "lexical scopes associate operators split between concatenated streams" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents [4 0 R 6 0 R] /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream("", "BT /F1 10 Tf 20 100 Td <41>"),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    annotation_test_stream("", "Tj <42> Tj ET"),
  ])
  let sources = document.text_lexical_sources(1).unwrap()
  assert_eq(lexical_test_spellings(document, sources[:]), [b"41", b"42"])
  assert_eq([ for source in sources => source.spans[0].stream_index ], [0, 1])
  assert_eq([ for source in sources => source.spans[0].object_number ], [
    Some(4),
    Some(6),
  ])
}

///|
test "lexical source retains empty copied glyphs without inventing logical positions" {
  let document = unicode_search_test_document(["", "😀fi"])
  let sources = document.text_lexical_sources(1).unwrap()
  assert_eq(sources.length(), 2)
  assert_eq(sources[0].logical_source, None)
  assert_eq(sources[0].string_source.unwrap().bytes, b"A")
  assert_eq(lexical_test_spellings(document, sources[:]), [b"41", b"42"])
  assert_eq(sources[1].logical_source.unwrap().end, 4)
}

///|
test "lexical source passes inline images through the existing parser" {
  let document = provenance_test_document(
    "q BI /W 1 /H 1 /BPC 8 /CS /G ID x EI Q BT /F1 10 Tf 20 100 Td (A) Tj ET",
  )
  let sources = document.text_lexical_sources(1).unwrap()
  assert_eq(lexical_test_spellings(document, sources[:]), [b"A"])
  assert_eq(sources[0].string_source.unwrap().operator_index, 6)
}

///|
test "lexical inline image candidates cannot mistake image bytes for EI" {
  let document = provenance_test_document(
    "q BI /W 6 /H 1 /BPC 8 /CS /G ID x EI y EI Q BT /F1 10 Tf 20 100 Td (A) Tj ET",
  )
  assert_eq(
    lexical_test_spellings(
      document,
      document.text_lexical_sources(1).unwrap()[:],
    ),
    [b"A"],
  )
}

///|
test "compressed lexical source has decoded spelling and whole encoded stream but no fake file glyph offset" {
  let original = provenance_test_document(
    "BT /F1 10 Tf 20 100 Td (A\\102) Tj ET",
  )
  let decoded = original.document
    .pdf_decode_stream(@syntax.PdfIndirect(4))
    .stream_bytes()
  original.document.add_object_given_number(
    4,
    font_stream_test_stream(@flate.pdf_flate_encode(decoded)),
  )
  let document = open_document(@pdflite.pdf_write_document(original.document))
  let sources = document.text_lexical_sources(1).unwrap()
  assert_eq(lexical_test_spellings(document, sources[:]), [b"A", b"\\102"])
  for source in sources {
    for span in source.spans {
      assert_eq(span.file_span, None)
      assert_true(span.encoded_stream_span is Some(_))
    }
  }
}

///|
test "in memory replacement streams cannot masquerade as original file locations" {
  let document = provenance_test_document("BT /F1 10 Tf 20 100 Td (A) Tj ET")
  let decoded = document.document
    .pdf_decode_stream(@syntax.PdfIndirect(4))
    .stream_bytes()
  guard document.document.direct(@syntax.PdfIndirect(4))
    is @syntax.PdfStreamObject(stream) else {
    fail("missing stream")
  }
  let cursor = @core.byte_cursor_of_bytes(decoded)
  let replacement = @syntax.pdf_stream(
    stream.dictionary,
    @syntax.StreamToGet(@syntax.stream_to_get(cursor, 0, decoded.length())),
  )
  document.document.add_object_given_number(4, replacement)
  let sources = document.text_lexical_sources(1).unwrap()
  assert_eq(lexical_test_spellings(document, sources[:]), [b"A"])
  assert_eq(sources[0].spans[0].file_span, None)
  assert_eq(sources[0].spans[0].encoded_stream_span, None)
}

///|
test "lexical source bounds and invalid pages are explicit" {
  let document = provenance_test_document("BT /F1 10 Tf 20 100 Td (A) Tj ET")
  assert_eq(document.text_lexical_sources(0), None)
  assert_eq(document.text_lexical_sources(2), None)
  let stream = document.document.direct(@syntax.PdfIndirect(4))
  let data = stream.stream_bytes()
  let ops = @pdflite.pdf_parse_content_ops_from_bytes(data)
  assert_true(
    pdf_text_locate_strings(
      document.document,
      document.pages[0].resources,
      data[:],
      [],
    )
    is None,
  )
  assert_true(
    pdf_text_locate_strings(
      document.document,
      document.pages[0].resources,
      data[:],
      ops[:],
    )
    is Some(_),
  )
}

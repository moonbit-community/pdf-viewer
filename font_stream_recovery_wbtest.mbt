///|
fn font_stream_test_bad_checksum(encoded : Bytes) -> Bytes {
  let bytes = [ for byte in encoded => byte ]
  bytes[bytes.length() - 1] = (bytes[bytes.length() - 1].to_int() ^ 1).to_byte()
  Bytes::from_array(bytes)
}

///|
fn font_stream_test_stream(encoded : Bytes) -> @syntax.PdfObject {
  let dictionary = @syntax.PdfDictionary([
    (pdf_name_key("/Length"), @syntax.PdfInteger(encoded.length())),
    (
      pdf_name_key("/Filter"),
      @syntax.PdfNameObject(pdf_name_key("/FlateDecode")),
    ),
  ])
  @syntax.pdf_stream(dictionary, @syntax.StreamGot(encoded))
}

///|
fn font_stream_test_replace(
  document : PdfViewerDocument,
  number : Int,
  decoded : Bytes,
) -> @syntax.PdfObject raise {
  let original = document.document.lookup_object_or_null(number)
  guard original is @syntax.PdfStreamObject(stream) else {
    fail("stream missing")
  }
  let encoded = font_stream_test_bad_checksum(@flate.pdf_flate_encode(decoded))
  let dictionary = stream.dictionary
    .add_dict_entry(
      pdf_name_key("/Filter"),
      @syntax.PdfNameObject(pdf_name_key("/FlateDecode")),
    )
    .add_dict_entry(
      pdf_name_key("/Length"),
      @syntax.PdfInteger(encoded.length()),
    )
  let damaged = @syntax.pdf_stream(dictionary, @syntax.StreamGot(encoded))
  document.document.add_object_given_number(number, damaged)
  damaged
}

///|
test "font Flate recovery accepts only a complete checksum mismatch" {
  let text = b"1 beginbfchar <41> <005A> endbfchar"
  let encoded = @flate.pdf_flate_encode(text)
  let damaged = font_stream_test_bad_checksum(encoded)
  assert_true(
    try @flate.pdf_flate_decode(damaged) catch {
      @core.InvalidFlateData => true
      _ => false
    } noraise {
      _ => false
    },
  )
  assert_eq(pdf_recover_font_flate(damaged), Some(text))
  assert_eq(pdf_recover_font_flate(encoded), None)
  for length in 0..<damaged.length() {
    assert_eq(pdf_recover_font_flate(damaged[:length].to_owned()), None)
  }
}

///|
test "font Flate recovery rejects invalid headers dictionaries and DEFLATE blocks" {
  let damaged = font_stream_test_bad_checksum(
    @flate.pdf_flate_encode(b"font program"),
  )
  let bad_header = [ for byte in damaged => byte ]
  bad_header[0] = b'\x00'
  assert_eq(pdf_recover_font_flate(Bytes::from_array(bad_header)), None)
  let bad_check = [ for byte in damaged => byte ]
  bad_check[1] = (bad_check[1].to_int() ^ 1).to_byte()
  assert_eq(pdf_recover_font_flate(Bytes::from_array(bad_check)), None)
  assert_eq(pdf_recover_font_flate(b"\x78\xBB\x00\x00\x00\x00\x00"), None)
  assert_eq(pdf_recover_font_flate(b"\x78\x9C\x07\x00\x00\x00\x00"), None)
}

///|
test "font Flate recovery enforces exact output limits including the final step" {
  for size in [0, 1, 32767, 32768, 32769, 65536, 65537] {
    let text = Bytes::from_array(Array::make(size, b'x'))
    let damaged = font_stream_test_bad_checksum(@flate.pdf_flate_encode(text))
    assert_eq(pdf_recover_font_flate(damaged, max_output=size), Some(text))
    if size > 0 {
      assert_eq(pdf_recover_font_flate(damaged, max_output=size - 1), None)
    }
  }
  assert_eq(
    pdf_recover_font_flate(b"\x78\x9C\x03\x00\x00\x00\x00\x00", max_output=-1),
    None,
  )
}

///|
test "font Flate recovery drains input beyond the decoder window and ignores trailing bytes" {
  let text = Bytes::from_array([ for i in 0..<100003 => (i % 251).to_byte() ])
  let encoded = font_stream_test_bad_checksum(
    @flate.pdf_flate_encode_with_level(text, 0),
  )
  assert_true(encoded.length() > @font_zlib.DECODER_INPUT_LIMIT)
  let with_suffix = [ for byte in encoded => byte ]
  for byte in b"\nendstream" {
    with_suffix.push(byte)
  }
  assert_eq(pdf_recover_font_flate(Bytes::from_array(with_suffix)), Some(text))
}

///|
test "font stream recovery preserves source objects and refreshes only decoded metadata" {
  let viewer = truetype_test_document(truetype_test_fixture())
  let encoded = font_stream_test_bad_checksum(
    @flate.pdf_flate_encode(b"mapping"),
  )
  let original = font_stream_test_stream(encoded)
    .add_dict_entry(pdf_name_key("/UseCMap"), @syntax.PdfIndirect(8))
    .add_dict_entry(pdf_name_key("/Length1"), @syntax.PdfInteger(7))
  let (decoded, recovered) = pdf_decode_font_stream_result(
    viewer.document,
    original,
  )
  assert_true(recovered)
  assert_eq(decoded.stream_bytes(), b"mapping")
  assert_eq(decoded.lookup_immediate(pdf_name_key("/Filter")), None)
  assert_eq(
    decoded.lookup_immediate(pdf_name_key("/Length")),
    Some(@syntax.PdfInteger(7)),
  )
  assert_eq(
    decoded.lookup_immediate(pdf_name_key("/Length1")),
    Some(@syntax.PdfInteger(7)),
  )
  assert_eq(
    decoded.lookup_immediate(pdf_name_key("/UseCMap")),
    Some(@syntax.PdfIndirect(8)),
  )
  assert_eq(original.stream_bytes(), encoded)
  assert_true(original.lookup_immediate(pdf_name_key("/Filter")) is Some(_))
  assert_eq(
    pdf_decode_font_stream_result(viewer.document, original),
    (decoded, true),
  )
}

///|
test "font stream recovery accepts single indirect filters and no-op predictors" {
  let viewer = truetype_test_document(truetype_test_fixture())
  let document = viewer.document
  let damaged = font_stream_test_stream(
    font_stream_test_bad_checksum(@flate.pdf_flate_encode(b"cmap")),
  )
  document.add_object_given_number(
    20,
    @syntax.PdfNameObject(pdf_name_key("/Fl")),
  )
  document.add_object_given_number(
    21,
    @syntax.PdfDictionary([
      (pdf_name_key("/Predictor"), @syntax.PdfIndirect(22)),
    ]),
  )
  document.add_object_given_number(22, @syntax.PdfInteger(1))
  document.add_object_given_number(
    23,
    @syntax.PdfInteger(damaged.stream_bytes().length()),
  )
  let stream = damaged
    .remove_dict_entry(pdf_name_key("/Filter"))
    .add_dict_entry(
      pdf_name_key("/F"),
      @syntax.PdfArray([@syntax.PdfIndirect(20)]),
    )
    .add_dict_entry(
      pdf_name_key("/DP"),
      @syntax.PdfArray([@syntax.PdfIndirect(21)]),
    )
    .add_dict_entry(pdf_name_key("/Length"), @syntax.PdfIndirect(23))
  let recovered = pdf_decode_font_stream_with_recovery(document, stream)
  assert_eq(recovered.stream_bytes(), b"cmap")
  assert_eq(recovered.lookup_immediate(pdf_name_key("/F")), None)
  assert_eq(recovered.lookup_immediate(pdf_name_key("/DP")), None)
}

///|
test "font stream recovery never bypasses filters predictors or missing lengths on cache hits" {
  let viewer = truetype_test_document(truetype_test_fixture())
  let document = viewer.document
  let damaged = font_stream_test_stream(
    font_stream_test_bad_checksum(@flate.pdf_flate_encode(b"glyphs")),
  )
  assert_eq(
    pdf_decode_font_stream_with_recovery(document, damaged).stream_bytes(),
    b"glyphs",
  )
  let predictor = @syntax.PdfDictionary([
    (pdf_name_key("/Predictor"), @syntax.PdfInteger(12)),
  ])
  for
    object in [
      damaged.add_dict_entry(
        pdf_name_key("/Filter"),
        @syntax.PdfArray([
          @syntax.PdfNameObject(pdf_name_key("/FlateDecode")),
          @syntax.PdfNameObject(pdf_name_key("/ASCIIHexDecode")),
        ]),
      ),
      damaged.add_dict_entry(pdf_name_key("/DecodeParms"), predictor),
      damaged.remove_dict_entry(pdf_name_key("/Length")),
      damaged.add_dict_entry(pdf_name_key("/Filter"), @syntax.PdfInteger(3)),
    ] {
    assert_eq(pdf_font_stream_recovery_input(document, object), None)
    assert_true(
      try pdf_decode_font_stream_with_recovery(document, object) catch {
        _ => true
      } noraise {
        _ => false
      },
    )
  }
  assert_eq(
    pdf_font_stream_recovery_input(
      document,
      font_stream_test_stream(Bytes::from_array(Array::make(0x400001, b'x'))),
    ),
    None,
  )
}

///|
test "font stream recovery cache evicts old content and caps retained output" {
  pdf_font_stream_recovery_cache.clear()
  for index in 0..<10 {
    let text = @utf8.encode("font-\{index}")
    let damaged = font_stream_test_bad_checksum(@flate.pdf_flate_encode(text))
    assert_eq(pdf_font_stream_recovery_cached(damaged), Some(text))
  }
  assert_eq(pdf_font_stream_recovery_cache.length(), 8)
  let first = font_stream_test_bad_checksum(@flate.pdf_flate_encode(b"font-0"))
  assert_true(
    !pdf_font_stream_recovery_cache.any(entry => entry.encoded == first),
  )
  pdf_font_stream_recovery_cache.clear()
  for index in 0..<3 {
    let text = Bytes::from_array(Array::make(0x600000, (65 + index).to_byte()))
    assert_eq(
      pdf_font_stream_recovery_cached(
        font_stream_test_bad_checksum(@flate.pdf_flate_encode(text)),
      ),
      Some(text),
    )
  }
  assert_eq(pdf_font_stream_recovery_cache.length(), 2)
  pdf_font_stream_recovery_cache.clear()
  for index in 0..<3 {
    let invalid = Array::make(0x300000, b'x')
    invalid[0] = index.to_byte()
    assert_eq(pdf_font_stream_recovery_cached(Bytes::from_array(invalid)), None)
  }
  assert_eq(pdf_font_stream_recovery_cache.length(), 2)
  pdf_font_stream_recovery_cache.clear()
}

///|
test "damaged TrueType and ToUnicode checksums recover painting clipping copying and embedding" {
  let bytes = truetype_test_fixture()
  let document = truetype_test_document(
    bytes,
    encoding="/Encoding << /BaseEncoding /WinAnsiEncoding /Differences [65 /customGlyph] >>",
  )
  let original_font = font_stream_test_replace(document, 7, bytes)
  let original_unicode = font_stream_test_replace(
    document, 8, b"1 beginbfchar <41> <005A> endbfchar",
  )
  let page = document.page(1).unwrap()
  assert_eq(page.text_content().text, "Z")
  let glyph = page.text_content().items[0]
  assert_eq((glyph.charcode, glyph.advance_x), (65, 6.0))
  assert_true(glyph.type3_outline.unwrap().contains("L 22 100"))
  assert_true(
    text_clip_test_paths(page)[0].clip_path.unwrap().contains("L 22 100"),
  )
  assert_eq(
    page.fonts[0].data_uri,
    Some("data:font/ttf;base64," + @base64.encode(bytes)),
  )
  assert_eq((page.text_sources()[0].start, page.text_sources()[0].end), (0, 1))
  assert_eq(document.search("Z")[0].item_indices, [0])
  let diagnostics = document.text_diagnostics(1).unwrap()
  assert_eq([ for diagnostic in diagnostics => diagnostic.kind ], [
    FontStreamChecksumRecovered,
    FontStreamChecksumRecovered,
  ])
  assert_eq(
    [
      for diagnostic in diagnostics => {
        (diagnostic.resource, diagnostic.object_number)
      }
    ],
    [("/F1/ToUnicode", Some(8)), ("/F1/FontDescriptor/FontFile2", Some(7))],
  )
  assert_eq(document.document.lookup_object_or_null(7), original_font)
  assert_eq(document.document.lookup_object_or_null(8), original_unicode)
  assert_true(
    document.document.read_font(@syntax.PdfIndirect(5))
    is @pdflite.PdfFontSimple(
      { fontdescriptor: Some({ tounicode: None, .. }), .. }
    ),
  )
  assert_true(
    try document.document.pdf_decode_stream(original_font) catch {
      @core.InvalidFlateData => true
      _ => false
    } noraise {
      _ => false
    },
  )
}

///|
test "valid TrueType Flate streams keep encoding glyphs separate from ToUnicode" {
  let bytes = truetype_test_fixture()
  let document = truetype_test_document(bytes)
  document.document.add_object_given_number(
    7,
    font_stream_test_stream(@flate.pdf_flate_encode(bytes)),
  )
  document.document.add_object_given_number(
    8,
    font_stream_test_stream(
      @flate.pdf_flate_encode(b"1 beginbfchar <41> <005A> endbfchar"),
    ),
  )
  let page = document.page(1).unwrap()
  assert_eq(page.text_content().text, "Z")
  assert_true(
    page.text_content().items[0].type3_outline.unwrap().contains("L 21 100"),
  )
  assert_true(
    !pdf_decode_font_stream_result(document.document, @syntax.PdfIndirect(7)).1,
  )
  assert_eq(document.text_diagnostics(1).unwrap(), [])
  assert_eq(document.page(1).unwrap().text_content().text, "Z")
}

///|
test "truncated font streams keep extracted text and metrics with visible fallback diagnostics" {
  let bytes = truetype_test_fixture()
  let document = truetype_test_document(bytes)
  let damaged = font_stream_test_bad_checksum(@flate.pdf_flate_encode(bytes))
  document.document.add_object_given_number(
    7,
    font_stream_test_stream(damaged[:damaged.length() - 1].to_owned()),
  )
  let page = document.page(1).unwrap()
  assert_eq(page.text_content().text, "Z")
  assert_eq(page.text_content().items[0].advance_x, 6.0)
  assert_eq(page.text_content().items[0].type3_outline, None)
  assert_eq(page.fonts[0].data_uri, None)
  let diagnostics = document.text_diagnostics(1).unwrap()
  assert_eq([ for diagnostic in diagnostics => diagnostic.kind ], [
    MissingClipOutline,
    HostFontFallback,
  ])
}

///|
test "checksum recovery composes CID CMap and ToUnicode parents with local mappings first" {
  let encoding = "1 begincodespacerange <00> <FF> endcodespacerange 2 begincidchar <41> 1 <42> 2 endcidchar"
  let unicode = "2 beginbfchar <41> <0058> <42> <0059> endbfchar"
  let document = cid_layout_test_document(
    "BT /F1 10 Tf 4 Tr 20 50 Td <4142> Tj ET 0 0 200 200 re f",
    cmap="1 begincidchar <41> 2 endcidchar",
    tounicode="1 beginbfchar <41> <005A> endbfchar",
    cmap_parent=encoding,
    tounicode_parent=unicode,
  )
  font_stream_test_replace(document, 8, b"1 begincidchar <41> 2 endcidchar")
  |> ignore
  font_stream_test_replace(document, 10, b"1 beginbfchar <41> <005A> endbfchar")
  |> ignore
  font_stream_test_replace(document, 11, @utf8.encode(encoding)) |> ignore
  font_stream_test_replace(document, 12, @utf8.encode(unicode)) |> ignore
  let page = document.page(1).unwrap()
  assert_eq(page.text_content().text, "ZY")
  assert_eq([ for item in page.text_content().items => item.advance_x ], [
    3.0, 3.0,
  ])
  assert_true(
    page.text_content().items.all(item => item.type3_outline is Some(_)),
  )
  assert_true(text_clip_test_paths(page)[0].clip_path.unwrap().contains("L"))
  let recovery = pdf_viewer_cmap_recovery_of_object(
    document.document,
    @syntax.PdfIndirect(8),
    Map([]),
  ).unwrap()
  assert_true(!recovery.diagnostics.source_unavailable)
  let diagnostics = document.text_diagnostics(1).unwrap()
  assert_eq(diagnostics.length(), 8)
  assert_eq(
    [
      for diagnostic in diagnostics[:4] => {
        (diagnostic.resource, diagnostic.object_number)
      }
    ],
    [
      ("/F1/Encoding", Some(8)),
      ("/F1/Encoding/UseCMap", Some(11)),
      ("/F1/ToUnicode", Some(10)),
      ("/F1/ToUnicode/UseCMap", Some(12)),
    ],
  )
  assert_true(
    diagnostics.all(diagnostic => diagnostic.kind == FontStreamChecksumRecovered),
  )
  assert_eq([ for diagnostic in diagnostics => diagnostic.source.charcode ], [
    65, 65, 65, 65, 66, 66, 66, 66,
  ])
}

///|
test "damaged Type1 checksum recovers encrypted outlines and clipping" {
  let document = type1_test_clip_document(
    "BT /F1 10 Tf 4 Tr 40 60 Td (A) Tj ET 0 0 200 200 re f",
  )
  font_stream_test_replace(document, 7, type1_test_encrypted_font()) |> ignore
  let page = document.page(1).unwrap()
  assert_true(page.text_content().items[0].type3_outline.unwrap().contains("L"))
  assert_true(text_clip_test_paths(page)[0].clip_path.unwrap().contains("L"))
}

///|
test "damaged CFF checksum recovers FontFile3 outlines and clipping" {
  let code = cff_test_program([
    cff_test_op([0, 0], 21),
    cff_test_op([500, 0, 0, 700, -500, 0], 5),
    b"\x0E",
  ])
  let bytes = cff_test_raw_font([b"\x0E", code], [0, cff_test_sid("A")])
  let document = type1_test_clip_document(
    "BT /F1 10 Tf 4 Tr 40 60 Td (A) Tj ET 0 0 200 200 re f",
  )
  let descriptor = document.document
    .lookup_object_or_null(6)
    .remove_dict_entry(pdf_name_key("/FontFile"))
    .add_dict_entry(pdf_name_key("/FontFile3"), @syntax.PdfIndirect(7))
  document.document.add_object_given_number(6, descriptor)
  let stream = font_stream_test_replace(document, 7, bytes).add_dict_entry(
    pdf_name_key("/Subtype"),
    @syntax.PdfNameObject(pdf_name_key("/Type1C")),
  )
  document.document.add_object_given_number(7, stream)
  let page = document.page(1).unwrap()
  assert_true(
    page.text_content().items[0].type3_outline.unwrap().contains("L 45 133"),
  )
  assert_true(
    text_clip_test_paths(page)[0].clip_path.unwrap().contains("L 45 133"),
  )
  assert_eq(page.fonts[0].format, "cff")
  let diagnostics = document.text_diagnostics(1).unwrap()
  assert_eq(
    [
      for diagnostic in diagnostics => {
        (diagnostic.kind, diagnostic.object_number)
      }
    ],
    [(FontStreamChecksumRecovered, Some(7))],
  )
}

///|
test "damaged CIDToGIDMap checksum recovers mapped TrueType glyphs without changing widths" {
  let bytes = truetype_test_fixture()
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream(
      "", "BT /F1 10 Tf 4 Tr 20 100 Td <0041> Tj ET 0 0 200 200 re f",
    ),
    "<< /Type /Font /Subtype /Type0 /BaseFont /ViewerGidTest /Encoding /Identity-H /DescendantFonts [6 0 R] /ToUnicode 10 0 R >>",
    "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /ViewerGidTest /DW 600 /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor 7 0 R /CIDToGIDMap 9 0 R >>",
    "<< /Type /FontDescriptor /FontName /ViewerGidTest /Flags 32 /FontBBox [0 0 300 400] /Ascent 800 /Descent -200 /ItalicAngle 0 /StemV 80 /FontFile2 8 0 R >>",
    annotation_test_stream(
      "/Filter /ASCIIHexDecode",
      type1_test_bytes_hex(bytes),
    ),
    annotation_test_stream("", ""),
    annotation_test_stream("", "1 beginbfchar <0041> <005A> endbfchar"),
  ])
  let map = Array::make(132, b'\x00')
  map[131] = b'\x02'
  let original_map = font_stream_test_replace(
    document,
    9,
    Bytes::from_array(map),
  )
  font_stream_test_replace(document, 8, bytes) |> ignore
  let page = document.page(1).unwrap()
  assert_eq(page.text_content().text, "Z")
  let glyph = page.text_content().items[0]
  assert_eq((glyph.charcode, glyph.advance_x), (65, 6.0))
  assert_true(glyph.type3_outline.unwrap().contains("L 22 100"))
  assert_true(
    text_clip_test_paths(page)[0].clip_path.unwrap().contains("L 22 100"),
  )
  assert_eq(document.document.lookup_object_or_null(9), original_map)
  let diagnostics = document.text_diagnostics(1).unwrap()
  assert_eq(
    [
      for diagnostic in diagnostics => {
        (diagnostic.resource, diagnostic.object_number)
      }
    ],
    [
      ("/F1/DescendantFonts[0]/CIDToGIDMap", Some(9)),
      ("/F1/DescendantFonts[0]/FontDescriptor/FontFile2", Some(8)),
    ],
  )
}

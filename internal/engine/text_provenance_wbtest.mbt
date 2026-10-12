///|
fn provenance_test_document(
  contents : String,
  font? : String = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
  resources? : String = "<< /Font << /F1 5 0 R >> >>",
  extra_objects? : Array[String] = [],
) -> PdfViewerDocument raise {
  annotation_test_document(
    [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources " +
      resources +
      " >>",
      annotation_test_stream("", contents),
      font,
      ..extra_objects,
    ],
  )
}

///|
fn provenance_test_paint_order(
  document : PdfViewerDocument,
) -> Array[PdfTextProvenance] raise {
  let values = document.text_provenance(1).unwrap()
  values.sort_by((a, b) => a.source.item_index.compare(b.source.item_index))
  values
}

///|
test "provenance retains decoded escape bytes and all text operator operand indices" {
  let document = provenance_test_document(
    "0 0 1 1 re f BT /F1 10 Tf 12 TL 20 100 Td (A\\101\\nB) Tj [(C) -100 () (D)] TJ (E) ' 0 1 (F) \" ET",
  )
  let provenance = provenance_test_paint_order(document)
  assert_eq([ for item in provenance => item.source.item_index ], [
    1, 2, 3, 4, 5, 6, 7, 8,
  ])
  assert_eq([ for item in provenance => item.source.charcode ], [
    65, 65, 10, 66, 67, 68, 69, 70,
  ])
  assert_eq(
    [
      for item in provenance => {
        let origin = item.string_source.unwrap()
        (
          origin.operator_index,
          origin.operand_index,
          origin.byte_start,
          origin.byte_end,
        )
      }
    ],
    [
      (6, 0, 0, 1),
      (6, 0, 1, 2),
      (6, 0, 2, 3),
      (6, 0, 3, 4),
      (7, 0, 0, 1),
      (7, 3, 0, 1),
      (8, 0, 0, 1),
      (9, 2, 0, 1),
    ],
  )
  for item in provenance {
    let origin = item.string_source.unwrap()
    assert_eq(origin.content_streams, [Some(4)])
    assert_eq(origin.form_path, [])
    assert_eq(origin.bytes[0].to_int(), item.source.charcode)
    assert_true(origin.charcode_valid)
    assert_eq(item.font_object_number, Some(5))
    assert_eq(item.font_program_object_number, None)
    assert_eq((item.cid, item.gid, item.glyph_name), (None, None, None))
  }
}

///|
test "provenance preserves non UTF8 bytes rather than reencoding extracted text" {
  let document = provenance_test_document("BT /F1 10 Tf 20 100 Td <80FF> Tj ET")
  let items = provenance_test_paint_order(document)
  assert_eq([ for item in items => item.string_source.unwrap().bytes ], [
    b"\x80", b"\xFF",
  ])
  assert_eq([ for item in items => item.source.charcode ], [128, 255])
}

///|
test "provenance spans use the same one to four byte CMap decoder as layout" {
  let document = cid_layout_test_document(
    "BT /F1 10 Tf 20 100 Td <418101C00102F0010203> Tj ET",
    cmap=cmap_text_test_mixed_cmap(),
    tounicode=cmap_text_test_tounicode(),
  )
  let items = provenance_test_paint_order(document)
  assert_eq([ for item in items => item.cid ], [
    Some(1),
    Some(2),
    Some(1),
    Some(2),
  ])
  assert_eq([ for item in items => item.gid ], [None, None, None, None])
  assert_eq([ for item in items => item.glyph_name ], [
    Some("cid1"),
    Some("cid2"),
    Some("cid1"),
    Some("cid2"),
  ])
  assert_eq(items[3].source.charcode.reinterpret_as_uint(), 0xF0010203U)
  assert_eq(
    [
      for item in items => {
        let origin = item.string_source.unwrap()
        (origin.byte_start, origin.byte_end, origin.bytes)
      }
    ],
    [
      (0, 1, b"A"),
      (1, 3, b"\x81\x01"),
      (3, 6, b"\xC0\x01\x02"),
      (6, 10, b"\xF0\x01\x02\x03"),
    ],
  )
  assert_eq(document.search("fi")[0].item_indices, [items[2].source.item_index])
  assert_eq(items[2].source.end - items[2].source.start, 2)
}

///|
test "provenance retains invalid and truncated CMap bytes without inventing CID GID" {
  let document = cid_layout_test_document(
    "BT /F1 10 Tf 20 100 Td <4181> Tj ET",
    cmap=cmap_text_test_mixed_cmap(),
    tounicode=cmap_text_test_tounicode(),
  )
  let items = provenance_test_paint_order(document)
  assert_eq(items.length(), 2)
  let invalid = items[1]
  let origin = invalid.string_source.unwrap()
  assert_eq((origin.byte_start, origin.byte_end, origin.bytes), (1, 2, b"\x81"))
  assert_true(!origin.charcode_valid)
  assert_eq(invalid.source.charcode, 0)
  assert_eq((invalid.cid, invalid.gid, invalid.glyph_name), (None, None, None))
  let font = document.document
    .lookup_object_or_null(5)
    .add_dict_entry(
      pdf_name_key("/Encoding"),
      @syntax.PdfNameObject(pdf_name_key("/Identity-H")),
    )
  document.document.add_object_given_number(5, font)
  document.document.add_object_given_number(
    4,
    @pdflite.pdf_content_stream_of_ops([
      @content.Op_BT,
      @content.Op_Tf(pdf_name_key("/F1"), 10.0),
      @content.Op_Tj(b"\x00\x41\x00"),
      @content.Op_ET,
    ]),
  )
  let items = provenance_test_paint_order(document)
  assert_eq(items[0].cid, Some(65))
  assert_eq(items[0].string_source.unwrap().bytes, b"\x00\x41")
  assert_eq(items[1].string_source.unwrap().bytes, b"\x00")
  assert_eq(items[1].string_source.unwrap().byte_start, 2)
  assert_true(!items[1].string_source.unwrap().charcode_valid)
  assert_eq(items[1].cid, None)
}

///|
test "provenance keeps TrueType GID independent of ToUnicode and Encoding differences" {
  let plain = truetype_test_document(truetype_test_fixture())
  let item = plain.text_provenance(1).unwrap()[0]
  assert_eq(plain.page(1).unwrap().text_content().text, "Z")
  assert_eq((item.source.charcode, item.cid, item.gid), (65, None, Some(1)))
  assert_eq(
    (item.font_object_number, item.font_program_object_number),
    (Some(5), Some(7)),
  )
  let different = truetype_test_document(
    truetype_test_fixture(),
    encoding="/Encoding << /BaseEncoding /WinAnsiEncoding /Differences [65 /Z] >>",
    unicode="0041",
  )
  assert_eq(different.page(1).unwrap().text_content().text, "A")
  assert_eq(different.text_provenance(1).unwrap()[0].gid, Some(2))
}

///|
test "provenance reuses predefined UTF8 UTF16 and UTF32 CMap code boundaries" {
  for
    (encoding, bytes, chunks, codes) in [
      (
        "UniJIS-UTF8-H",
        b"A\xE3\x81\x82",
        [b"A", b"\xE3\x81\x82"],
        [65, 0xE38182],
      ),
      (
        "UniJIS-UTF16-H",
        b"\x00A\x30\x42",
        [b"\x00A", b"\x30\x42"],
        [65, 0x3042],
      ),
      (
        "UniJIS-UTF32-H",
        b"\x00\x00\x00A\x00\x00\x30\x42",
        [b"\x00\x00\x00A", b"\x00\x00\x30\x42"],
        [65, 0x3042],
      ),
    ] {
    let document = builtin_cmap_test_document("", encoding)
    document.document.add_object_given_number(
      4,
      @pdflite.pdf_content_stream_of_ops([
        @content.Op_BT,
        @content.Op_Tf(pdf_name_key("/F1"), 10.0),
        @content.Op_Tj(bytes),
        @content.Op_ET,
      ]),
    )
    let items = provenance_test_paint_order(document)
    assert_eq([ for item in items => item.source.charcode ], codes)
    assert_eq([ for item in items => item.cid ], [Some(34), Some(843)])
    assert_eq(
      [
        for item in items => item.string_source.unwrap().bytes
      ],
      chunks,
    )
    let mut offset = 0
    for (item, chunk) in items.zip(chunks) {
      let origin = item.string_source.unwrap()
      assert_eq(
        (origin.byte_start, origin.byte_end),
        (offset, offset + chunk.length()),
      )
      assert_true(origin.charcode_valid)
      offset += chunk.length()
    }
    assert_eq(offset, bytes.length())
  }
}

///|
test "provenance omits empty copies but keeps following multi scalar glyph byte positions" {
  let document = unicode_search_test_document(["", "a\u0301😀fi", "End"], widths=[
    0, 600, 3000,
  ])
  let items = document.text_provenance(1).unwrap()
  let page = document.page(1).unwrap()
  assert_eq([ for item in items => item.source ], page.text_sources())
  assert_eq(items.length(), 2)
  assert_true(items.all(item => item.source.charcode != 65))
  let collected = pdf_collected_entries_of_page(
    document.document,
    document.pages[0],
    collect_text_sources=true,
  )
  assert_eq(collected[0].text_source.unwrap().string_source.bytes, b"A")
  let multi = items[items.search_by(item => item.source.charcode == 66).unwrap()]
  assert_eq(multi.source.end - multi.source.start, 6)
  assert_eq(multi.string_source.unwrap().bytes, b"B")
  assert_eq(multi.string_source.unwrap().byte_start, 1)
  let hit = document.search("á")[0]
  assert_eq(hit.item_indices, [multi.source.item_index])
  assert_eq((hit.index, hit.length), (multi.source.start, 2))
}

///|
test "provenance uses recovered TrueType programs and CIDToGIDMap without mutating source objects" {
  let bytes = truetype_test_fixture()
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream("", "BT /F1 10 Tf 20 100 Td <0041> Tj ET"),
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
  let original_font = font_stream_test_replace(document, 8, bytes)
  let item = document.text_provenance(1).unwrap()[0]
  assert_eq((item.source.charcode, item.cid, item.gid), (65, Some(65), Some(2)))
  assert_eq(item.font_program_object_number, Some(8))
  assert_eq(item.string_source.unwrap().bytes, b"\x00A")
  assert_eq(document.document.lookup_object_or_null(9), original_map)
  assert_eq(document.document.lookup_object_or_null(8), original_font)
}

///|
test "provenance uses Type1 names and CFF charset GIDs from existing program readers" {
  let type1 = type1_test_clip_document("BT /F1 10 Tf 20 100 Td (A) Tj ET")
  let item = type1.text_provenance(1).unwrap()[0]
  assert_eq((item.gid, item.glyph_name), (None, Some("A")))
  let code = cff_test_program([
    cff_test_op([0, 0], 21),
    cff_test_op([500, 0, 0, 700, -500, 0], 5),
    b"\x0E",
  ])
  let bytes = cff_test_raw_font([b"\x0E", code], [0, cff_test_sid("A")])
  let descriptor = type1.document
    .lookup_object_or_null(6)
    .remove_dict_entry(pdf_name_key("/FontFile"))
    .add_dict_entry(pdf_name_key("/FontFile3"), @syntax.PdfIndirect(7))
  type1.document.add_object_given_number(6, descriptor)
  let stream = font_stream_test_replace(type1, 7, bytes).add_dict_entry(
    pdf_name_key("/Subtype"),
    @syntax.PdfNameObject(pdf_name_key("/Type1C")),
  )
  type1.document.add_object_given_number(7, stream)
  let item = type1.text_provenance(1).unwrap()[0]
  assert_eq((item.gid, item.glyph_name), (Some(1), Some("A")))
  assert_eq(item.font_program_object_number, Some(7))
}

///|
test "provenance identifies Type3 charprocs without fabricating numeric glyph IDs" {
  let document = provenance_test_document(
    "BT /F1 10 Tf 20 100 Td (A) Tj ET",
    font="<< /Type /Font /Subtype /Type3 /Name /F1 /FontBBox [0 0 500 700] /FontMatrix [0.001 0 0 0.001 0 0] /CharProcs << /A 6 0 R >> /Encoding << /Differences [65 /A] >> /FirstChar 65 /LastChar 65 /Widths [500] /Resources << >> >>",
    extra_objects=[annotation_test_stream("", "500 0 d0 0 0 500 700 re f")],
  )
  let item = document.text_provenance(1).unwrap()[0]
  assert_eq((item.gid, item.glyph_name), (None, Some("A")))
  assert_eq(item.font_object_number, Some(5))
  assert_eq(item.font_program_object_number, None)
}

///|
test "provenance leaves non UTF8 Type3 glyph names absent instead of inventing a name" {
  let document = provenance_test_document(
    "BT /F1 10 Tf 20 100 Td (A) Tj ET",
    font="<< /Type /Font /Subtype /Type3 /Name /F1 /FontBBox [0 0 500 700] /FontMatrix [0.001 0 0 0.001 0 0] /CharProcs << /#FF 6 0 R >> /Encoding << /Differences [65 /#FF] >> /FirstChar 65 /LastChar 65 /Widths [500] /Resources << >> >>",
    extra_objects=[annotation_test_stream("", "500 0 d0 0 0 500 700 re f")],
  )
  let item = document.text_provenance(1).unwrap()[0]
  assert_eq((item.source.charcode, item.gid, item.glyph_name), (65, None, None))
  assert_eq(item.string_source.unwrap().bytes, b"A")
}

///|
test "provenance distinguishes repeated nested Forms and inherited shadowed font resources" {
  let document = provenance_test_document(
    "BT /F1 10 Tf 20 100 Td ET /Outer Do /Outer Do",
    resources="<< /Font << /F1 5 0 R >> /XObject << /Outer 6 0 R >> >>",
    extra_objects=[
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 200 200] /Resources << /Font << /F1 7 0 R >> /XObject << /Inner 8 0 R >> >>",
        "BT (A) Tj /F1 10 Tf (B) Tj ET /Inner Do",
      ),
      "<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>",
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 200 200] /Resources << >>", "BT (C) Tj ET",
      ),
    ],
  )
  let items = provenance_test_paint_order(document)
  assert_eq([ for item in items => item.font_object_number ], [
    Some(5),
    Some(7),
    Some(7),
    Some(5),
    Some(7),
    Some(7),
  ])
  assert_eq(
    [
      for item in items => item.string_source.unwrap().content_streams
    ],
    [[Some(6)], [Some(6)], [Some(8)], [Some(6)], [Some(6)], [Some(8)]],
  )
  let first = items[0].string_source.unwrap().form_path
  let repeated = items[3].string_source.unwrap().form_path
  assert_eq(first, [
    { name: "/Outer", object_number: Some(6), operator_index: 4, },
  ])
  assert_eq(repeated[0].operator_index, 5)
  assert_eq(items[2].string_source.unwrap().form_path, [
    first[0],
    { name: "/Inner", object_number: Some(8), operator_index: 5, },
  ])
  assert_eq(
    [
      for item in items => item.string_source.unwrap().operator_index
    ],
    [1, 3, 1, 1, 3, 1],
  )
}

///|
test "provenance follows q Q font restoration ExtGState and missing Tf fallback" {
  let document = provenance_test_document(
    "BT /F1 10 Tf 20 100 Td (A) Tj q /F2 10 Tf (B) Tj Q (C) Tj /Missing 10 Tf (D) Tj q /GS gs (E) Tj Q (F) Tj ET",
    resources="<< /Font << /F1 5 0 R /F2 6 0 R >> /ExtGState << /GS << /Font [6 0 R 10] >> >> >>",
    extra_objects=["<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>"],
  )
  let items = provenance_test_paint_order(document)
  assert_eq([ for item in items => item.font_object_number ], [
    Some(5),
    Some(6),
    Some(5),
    Some(5),
    Some(6),
    Some(5),
  ])
  assert_eq(items[3].source.font, "/Missing")
  assert_eq(items[4].source.font, "__EXTGSTATE__6")
}

///|
test "provenance mirrors the interpreter implicit Form q and outer frames during unmatched Q recovery" {
  let document = provenance_test_document(
    "BT /F1 10 Tf 20 100 Td ET q /F2 10 Tf /Outer Do Q BT (D) Tj ET",
    resources="<< /Font << /F1 5 0 R /F2 6 0 R >> /XObject << /Outer 7 0 R >> >>",
    extra_objects=[
      "<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>",
      annotation_test_stream(
        "/Type /XObject /Subtype /Form /BBox [0 0 200 200] /Resources << /Font << /F1 8 0 R >> >>",
        "BT /F1 10 Tf (A) Tj Q (B) Tj Q (C) Tj ET",
      ),
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>",
    ],
  )
  let items = provenance_test_paint_order(document)
  assert_eq([ for item in items => item.font_object_number ], [
    Some(8),
    Some(6),
    Some(5),
    Some(5),
  ])
  assert_eq([ for item in items => item.string_source.unwrap().bytes ], [
    b"A", b"B", b"C", b"D",
  ])
}

///|
test "provenance keeps original concatenated stream scope and decoded string offsets" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents [4 0 R 6 0 R] /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream("", "BT /F1 10 Tf 20 100 Td <41>"),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    annotation_test_stream("", "Tj <42> Tj ET"),
  ])
  let items = provenance_test_paint_order(document)
  assert_eq(
    [
      for item in items => item.string_source.unwrap().operator_index
    ],
    [3, 4],
  )
  for item in items {
    let origin = item.string_source.unwrap()
    assert_eq(origin.content_streams, [Some(4), Some(6)])
    assert_eq((origin.byte_start, origin.byte_end), (0, 1))
  }
  let stream = @pdflite.pdf_content_stream_of_ops([
    @content.Op_BT,
    @content.Op_Tf(pdf_name_key("/F1"), 10.0),
    @content.Op_Tj(b"Z"),
    @content.Op_ET,
  ])
  document.pages[0] = { ..document.pages[0], content: [stream], }
  let origin = document.text_provenance(1).unwrap()[0].string_source.unwrap()
  assert_eq(origin.content_streams, [None])
  assert_eq(origin.bytes, b"Z")
}

///|
test "provenance logical ranges join bidi ligature search and surrogate selection to original bytes" {
  let document = unicode_search_test_document(["גד", "😀", "ﬁ", "אב"], positions=[
    (12.0, 100.0),
    (24.0, 100.0),
    (18.0, 100.0),
    (30.0, 100.0),
  ])
  let page = document.page(1).unwrap()
  let items = document.text_provenance(1).unwrap()
  assert_eq([ for item in items => item.source ], page.text_sources())
  assert_eq([ for item in items => item.string_source.unwrap().bytes ], [
    b"D", b"B", b"C", b"A",
  ])
  assert_eq(
    [
      for item in items => item.string_source.unwrap().operator_index
    ],
    [9, 5, 7, 3],
  )
  let hit = document.search("fi")[0]
  assert_eq(
    (hit.index, hit.length, hit.item_indices),
    (items[2].source.start, 1, [items[2].source.item_index]),
  )
  assert_eq(items[1].source.end - items[1].source.start, 2)
  assert_eq(
    page
    .select_text(items[1].source.item_index, 0, items[1].source.item_index, 2)
    .unwrap().text,
    "😀",
  )
}

///|
test "provenance is opt in and empty or invalid pages return explicit results" {
  let document = provenance_test_document("BT /F1 10 Tf 20 100 Td (A) Tj ET")
  let ordinary = pdf_collected_entries_of_page(
    document.document,
    document.pages[0],
  )
  assert_true(ordinary.all(entry => entry.text_source is None))
  assert_eq(document.text_provenance(0), None)
  assert_eq(document.text_provenance(2), None)
  let blank = provenance_test_document("0 0 10 10 re f")
  assert_eq(blank.text_provenance(1), Some([]))
}

///|
fn truetype_cmap_test_format4(code : Int, gid : Int) -> Bytes {
  let bytes = Array::make(32, b'\x00')
  @font.write_be16(bytes, 0, 4)
  @font.write_be16(bytes, 2, bytes.length())
  @font.write_be16(bytes, 6, 4)
  @font.write_be16(bytes, 8, 4)
  @font.write_be16(bytes, 10, 1)
  @font.write_be16(bytes, 14, code)
  @font.write_be16(bytes, 16, 65535)
  @font.write_be16(bytes, 20, code)
  @font.write_be16(bytes, 22, 65535)
  @font.write_be16(bytes, 24, gid - code)
  @font.write_be16(bytes, 26, 1)
  Bytes::from_array(bytes)
}

///|
fn truetype_cmap_test_format12(groups : Array[(Int, Int, Int)]) -> Bytes {
  let bytes = Array::make(16 + groups.length() * 12, b'\x00')
  @font.write_be16(bytes, 0, 12)
  @font.write_be32(bytes, 4, bytes.length())
  @font.write_be32(bytes, 12, groups.length())
  for index, (start, end, gid) in groups {
    @font.write_be32(bytes, 16 + index * 12, start)
    @font.write_be32(bytes, 20 + index * 12, end)
    @font.write_be32(bytes, 24 + index * 12, gid)
  }
  Bytes::from_array(bytes)
}

///|
fn truetype_cmap_test_table(records : Array[(Int, Int, Bytes)]) -> Bytes {
  let bytes = Array::make(4 + records.length() * 8, b'\x00')
  @font.write_be16(bytes, 2, records.length())
  for index, (platform, encoding, subtable) in records {
    @font.write_be16(bytes, 4 + index * 8, platform)
    @font.write_be16(bytes, 6 + index * 8, encoding)
    @font.write_be32(bytes, 8 + index * 8, bytes.length())
    for byte in subtable {
      bytes.push(byte)
    }
  }
  Bytes::from_array(bytes)
}

///|
/// Replace only cmap in the authored six-glyph fixture via the library writer.
fn truetype_cmap_test_font(records : Array[(Int, Int, Bytes)]) -> Bytes raise {
  let original = truetype_test_fixture()
  let tables = [
    for table in @pdflite.pdf_truetype_tables(original[:]) if table.tag !=
    "cmap" => {
      (table.tag, original[table.offset:table.offset + table.length].to_owned())
    }
  ]
  tables.push(("cmap", truetype_cmap_test_table(records)))
  @font.rebuild_sfnt(0x00010000, tables)
}

///|
test "TrueType format 12 selects supplementary glyphs independently of ToUnicode" {
  let bytes = truetype_cmap_test_font([
    (3, 1, truetype_cmap_test_format4(65, 1)),
    (3, 10, truetype_cmap_test_format12([(65, 65, 1), (0x1F600, 0x1F601, 2)])),
  ])
  let cmap = pdf_viewer_ttf_cmap(bytes[:], false, true).unwrap()
  assert_eq(cmap.platform, 3)
  assert_eq(cmap.encoding, 10)
  assert_eq(pdf_viewer_ttf_cmap_gid(bytes[:], cmap, 0x1F600), 2)
  assert_eq(pdf_viewer_ttf_cmap_gid(bytes[:], cmap, 0x1F601), 3)
  assert_eq(pdf_viewer_ttf_cmap_gid(bytes[:], cmap, 0x1F602), 0)
  let page = truetype_test_document(
      bytes,
      encoding="/Encoding << /BaseEncoding /WinAnsiEncoding /Differences [65 /u1F600] >>",
      unicode="0041",
    )
    .page(1)
    .unwrap()
  assert_eq(page.text_content().text, "A")
  assert_true(
    page.text_content().items[0].type3_outline.unwrap().contains("L 22 100"),
  )
  assert_true(
    text_clip_test_paths(page)[0].clip_path.unwrap().contains("L 22 100"),
  )
  for encoding in [4, 6] {
    let unicode_only = truetype_cmap_test_font([
      (
        0,
        encoding,
        truetype_cmap_test_format12([(65, 65, 1), (0x1F600, 0x1F600, 2)]),
      ),
    ])
    for (supplementary, code, expected) in [(false, 65, 1), (true, 0x1F600, 2)] {
      let cmap = pdf_viewer_ttf_cmap(unicode_only[:], false, supplementary).unwrap()
      assert_eq(pdf_viewer_ttf_cmap_gid(unicode_only[:], cmap, code), expected)
    }
  }
}

///|
test "TrueType platform preference is independent of cmap directory order" {
  for
    records in [
      [
        (3, 1, truetype_cmap_test_format4(65, 1)),
        (0, 3, truetype_cmap_test_format4(65, 2)),
        (1, 0, truetype_cmap_test_format4(65, 3)),
      ],
      [
        (1, 0, truetype_cmap_test_format4(65, 3)),
        (0, 3, truetype_cmap_test_format4(65, 2)),
        (3, 1, truetype_cmap_test_format4(65, 1)),
      ],
    ] {
    let bytes = truetype_cmap_test_font(records)
    let cmap = pdf_viewer_ttf_cmap(bytes[:], false, false).unwrap()
    assert_eq((cmap.platform, cmap.encoding), (3, 1))
    assert_eq(pdf_viewer_ttf_cmap_gid(bytes[:], cmap, 65), 1)
  }
  let bytes = truetype_cmap_test_font([
    (3, 1, truetype_cmap_test_format4(65, 1)),
    (3, 1, truetype_cmap_test_format4(65, 2)),
  ])
  assert_eq(
    pdf_viewer_ttf_cmap_gid(
      bytes[:],
      pdf_viewer_ttf_cmap(bytes[:], false, false).unwrap(),
      65,
    ),
    1,
  )
}

///|
test "TrueType symbol cmap takes precedence over conflicting Unicode and Mac tables" {
  let bytes = truetype_cmap_test_font([
    (3, 1, truetype_cmap_test_format4(65, 2)),
    (1, 0, truetype_cmap_test_format4(65, 3)),
    (3, 0, truetype_cmap_test_format4(0xF041, 1)),
  ])
  let page = truetype_test_document(bytes, encoding="", flags=4)
    .page(1)
    .unwrap()
  assert_eq(page.text_content().text, "Z")
  assert_true(
    page.text_content().items[0].type3_outline.unwrap().contains("L 21 100"),
  )
  let unicode = pdf_viewer_ttf_cmap(bytes[:], false, false).unwrap()
  assert_eq(pdf_viewer_ttf_cmap_gid(bytes[:], unicode, 65), 2)
}

///|
test "TrueType MacRoman cmap converts a PDF glyph name to its Mac byte" {
  let subtable = Array::make(262, b'\x00')
  @font.write_be16(subtable, 2, subtable.length())
  subtable[6 + 0x96] = b'\x02' // MacRoman ntilde.
  subtable[6 + 0xF1] = b'\x01' // Not the Unicode index for this table.
  let bytes = truetype_cmap_test_font([(1, 0, Bytes::from_array(subtable))])
  let page = truetype_test_document(
      bytes,
      encoding="/Encoding << /BaseEncoding /WinAnsiEncoding /Differences [65 /ntilde] >>",
    )
    .page(1)
    .unwrap()
  assert_eq(page.text_content().text, "Z")
  assert_true(
    page.text_content().items[0].type3_outline.unwrap().contains("L 22 100"),
  )
}

///|
test "TrueType trimmed cmap maps its interval and preserves missing glyphs" {
  let subtable = Array::make(16, b'\x00')
  @font.write_be16(subtable, 0, 6)
  @font.write_be16(subtable, 2, subtable.length())
  @font.write_be16(subtable, 6, 65)
  @font.write_be16(subtable, 8, 3)
  @font.write_be16(subtable, 10, 1)
  @font.write_be16(subtable, 14, 2)
  let bytes = truetype_cmap_test_font([(3, 1, Bytes::from_array(subtable))])
  let cmap = pdf_viewer_ttf_cmap(bytes[:], false, false).unwrap()
  for (code, expected) in [(64, 0), (65, 1), (66, 0), (67, 2), (68, 0)] {
    assert_eq(pdf_viewer_ttf_cmap_gid(bytes[:], cmap, code), expected)
  }
  @font.write_be16(subtable, 8, 4)
  assert_true(
    !pdf_viewer_ttf_cmap_subtable_valid(Bytes::from_array(subtable)[:]),
  )
}

///|
test "TrueType format 4 preserves notdef holes and validates maxp glyph IDs" {
  let subtable = truetype_cmap_test_format4(65, 1).to_array()
  subtable.push(b'\x00')
  subtable.push(b'\x00')
  @font.write_be16(subtable, 2, subtable.length())
  @font.write_be16(subtable, 28, 4)
  let bytes = truetype_cmap_test_font([(3, 1, Bytes::from_array(subtable))])
  let cmap = pdf_viewer_ttf_cmap(bytes[:], false, false).unwrap()
  assert_eq(pdf_viewer_ttf_cmap_gid(bytes[:], cmap, 65), 0)
  assert_eq(pdf_viewer_ttf_cmap_gid(bytes[:], cmap, 66), 0)
  @font.write_be16(subtable, 32, 6)
  @font.write_be16(subtable, 24, 0)
  let invalid_gid = truetype_cmap_test_font([
    (3, 1, Bytes::from_array(subtable)),
  ])
  assert_eq(
    pdf_viewer_ttf_cmap_gid(
      invalid_gid[:],
      pdf_viewer_ttf_cmap(invalid_gid[:], false, false).unwrap(),
      65,
    ),
    0,
  )
  let signed = truetype_cmap_test_table([
    (3, 1, truetype_cmap_test_format4(65, 65534)),
  ])
  assert_eq(
    pdf_viewer_ttf_cmap_gid(
      b"",
      pdf_viewer_ttf_read_cmap(signed[:], false, false).unwrap(),
      65,
    ),
    65534,
  )
}

///|
test "TrueType cmap truncation cannot cross a declared subtable boundary" {
  for
    subtable in [
      truetype_cmap_test_format4(65, 1),
      truetype_cmap_test_format12([(65, 65, 1), (0x1F600, 0x1F600, 2)]),
    ] {
    let encoding = if subtable[1] == b'\x0C' { 10 } else { 1 }
    let table = truetype_cmap_test_table([(3, encoding, subtable)])
    for length in 0..<table.length() {
      assert_true(
        pdf_viewer_ttf_read_cmap(table[:length], false, false) is None,
      )
    }
    assert_true(pdf_viewer_ttf_read_cmap(table[:], false, false) is Some(_))
  }
  let bad_range = truetype_cmap_test_format4(65, 1).to_array()
  @font.write_be16(bad_range, 28, 4) // Points beyond its own subtable.
  let bytes = truetype_cmap_test_font([
    (3, 1, Bytes::from_array(bad_range)),
    (0, 3, truetype_cmap_test_format4(65, 2)),
  ])
  let cmap = pdf_viewer_ttf_cmap(bytes[:], false, false).unwrap()
  assert_eq(cmap.platform, 0)
  assert_eq(pdf_viewer_ttf_cmap_gid(bytes[:], cmap, 65), 2)
}

///|
test "TrueType format 12 rejects wrapped ranges and excessive expansions" {
  for
    groups in [
      [(100, 99, 1)],
      [(0, 0xFFFFFFFF, 1)],
      [(0x110000, 0x110000, 1)],
      [(65, 66, 65535)],
      [(65, 66, 1), (66, 67, 3)],
      [(0, 65535, 0), (65536, 131071, 0), (131072, 131072, 0)],
    ] {
    assert_true(
      !pdf_viewer_ttf_cmap_subtable_valid(
        truetype_cmap_test_format12(groups)[:],
      ),
    )
  }
  let too_many = truetype_cmap_test_format12([(65, 65, 1)]).to_array()
  @font.write_be32(too_many, 12, 0xFFFFFFFF)
  assert_true(
    !pdf_viewer_ttf_cmap_subtable_valid(Bytes::from_array(too_many)[:]),
  )
}

///|
test "TrueType cmap cache separates font bytes and stays bounded" {
  pdf_viewer_ttf_cmap_cache.clear()
  for index in 0..<12 {
    let subtable = truetype_cmap_test_format4(65, index % 2 + 1).to_array()
    @font.write_be16(subtable, 4, index)
    let bytes = truetype_cmap_test_font([(3, 1, Bytes::from_array(subtable))])
    for _ in 0..<2 {
      let cmap = pdf_viewer_ttf_cmap(bytes[:], false, false).unwrap()
      assert_eq(pdf_viewer_ttf_cmap_gid(bytes[:], cmap, 65), index % 2 + 1)
    }
    assert_true(pdf_viewer_ttf_cmap_cache.length() <= 8)
  }
  assert_eq(pdf_viewer_ttf_cmap_cache.length(), 8)
  pdf_viewer_ttf_cmap_cache.clear()
  for index in 0..<3 {
    let subtable = truetype_cmap_test_format12([
      (0, 49999, 1),
      (65536, 115535, 1),
    ]).to_array()
    @font.write_be32(subtable, 8, index)
    let bytes = truetype_cmap_test_font([(3, 10, Bytes::from_array(subtable))])
    assert_eq(
      pdf_viewer_ttf_cmap(bytes[:], false, true).unwrap().glyphs.length(),
      100000,
    )
  }
  assert_eq(pdf_viewer_ttf_cmap_cache.length(), 2)
  pdf_viewer_ttf_cmap_cache.clear()
}

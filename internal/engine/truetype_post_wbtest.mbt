///|
fn truetype_post_test_table(
  indices : Array[Int],
  extra : Array[String],
) -> Bytes {
  let table = Array::make(34 + indices.length() * 2, b'\x00')
  @font.write_be32(table, 0, 0x00020000)
  @font.write_be16(table, 32, indices.length())
  for index, name in indices {
    @font.write_be16(table, 34 + index * 2, name)
  }
  for name in extra {
    let bytes = @utf8.encode(name)
    table.push(bytes.length().to_byte())
    for byte in bytes {
      table.push(byte)
    }
  }
  Bytes::from_array(table)
}

///|
fn truetype_post_test_replace(
  font : Bytes,
  tag : String,
  replacement : Bytes?,
) -> Bytes {
  let tables = [
    for table in @pdflite.pdf_truetype_tables(font[:]) if table.tag != tag => {
      (table.tag, font[table.offset:table.offset + table.length].to_owned())
    }
  ]
  match replacement {
    Some(bytes) => tables.push((tag, bytes))
    None => ()
  }
  @font.rebuild_sfnt(0x00010000, tables)
}

///|
fn truetype_post_test_simple(
  document : PdfViewerDocument,
) -> @pdflite.PdfSimpleFont raise {
  match pdf_read_font_for_viewer(document.document, @syntax.PdfIndirect(5)) {
    @pdflite.PdfFontSimple(simple) => simple
    _ => fail("simple font missing")
  }
}

///|
test "TrueType custom post name selects painting and clipping independently of copied text" {
  let bytes = truetype_post_test_replace(
    truetype_test_fixture(),
    "post",
    Some(truetype_post_test_table([0, 0, 258, 0, 0, 0], ["customGlyph"])),
  )
  let document = truetype_test_document(
    bytes,
    encoding="/Encoding << /BaseEncoding /WinAnsiEncoding /Differences [65 /customGlyph] >>",
  )
  assert_eq(
    pdf_viewer_ttf_simple_gid(truetype_post_test_simple(document), bytes, 65),
    2,
  )
  let page = document.page(1).unwrap()
  assert_eq(page.text_content().text, "Z")
  assert_true(
    page.text_content().items[0].type3_outline.unwrap().contains("L 22 100"),
  )
  assert_true(
    text_clip_test_paths(page)[0].clip_path.unwrap().contains("L 22 100"),
  )
}

///|
test "TrueType valid Windows cmap wins over a conflicting post name" {
  let bytes = truetype_post_test_replace(
    truetype_test_fixture(),
    "post",
    Some(truetype_post_test_table([0, 0, 36, 0, 0, 0], [])),
  )
  let document = truetype_test_document(bytes)
  assert_eq(
    pdf_viewer_ttf_simple_gid(truetype_post_test_simple(document), bytes, 65),
    1,
  )
  assert_eq(document.page(1).unwrap().text_content().text, "Z")
}

///|
test "TrueType Unicode-platform cmap prefers explicit post names" {
  let bytes = truetype_post_test_replace(
    truetype_cmap_test_font([(0, 3, truetype_cmap_test_format4(65, 1))]),
    "post",
    Some(truetype_post_test_table([0, 0, 61, 0, 0, 0], [])),
  )
  let document = truetype_test_document(
    bytes,
    encoding="/Encoding << /BaseEncoding /WinAnsiEncoding /Differences [65 /Z] >>",
    unicode="0041",
  )
  let page = document.page(1).unwrap()
  assert_eq(page.text_content().text, "A")
  assert_true(
    page.text_content().items[0].type3_outline.unwrap().contains("L 22 100"),
  )
  assert_true(
    text_clip_test_paths(page)[0].clip_path.unwrap().contains("L 22 100"),
  )
  let implicit = truetype_test_document(bytes, encoding="", flags=4)
  assert_eq(
    pdf_viewer_ttf_simple_gid(truetype_post_test_simple(implicit), bytes, 65),
    1,
  )
  let supplementary = truetype_cmap_test_font([
    (0, 4, truetype_cmap_test_format12([(65, 65, 1), (0x1F600, 0x1F600, 2)])),
  ])
  let document = truetype_test_document(
    supplementary,
    encoding="/Encoding << /BaseEncoding /WinAnsiEncoding /Differences [65 /u1F600] >>",
  )
  assert_eq(
    pdf_viewer_ttf_simple_gid(
      truetype_post_test_simple(document),
      supplementary,
      65,
    ),
    2,
  )
}

///|
test "TrueType post names recover a cmap hole and a font without cmap" {
  let post = truetype_post_test_table([0, 0, 36, 0, 0, 0], [])
  let missing = truetype_post_test_replace(
    truetype_test_fixture(),
    "cmap",
    None,
  )
  let hole = truetype_cmap_test_font([(3, 1, truetype_cmap_test_format4(66, 1))])
  for original in [missing, hole] {
    let bytes = truetype_post_test_replace(original, "post", Some(post))
    let document = truetype_test_document(bytes)
    assert_eq(
      pdf_viewer_ttf_simple_gid(truetype_post_test_simple(document), bytes, 65),
      2,
    )
    assert_true(
      document.page(1).unwrap().text_content().items[0].type3_outline
      .unwrap()
      .contains("L 22 100"),
    )
  }
}

///|
test "TrueType symbolic cmap keeps its mapping and uses post only for a hole" {
  for (code, expected) in [(0xF041, 1), (0xF042, 2)] {
    let bytes = truetype_post_test_replace(
      truetype_cmap_test_font([(3, 0, truetype_cmap_test_format4(code, 1))]),
      "post",
      Some(truetype_post_test_table([0, 0, 36, 0, 0, 0], [])),
    )
    let document = truetype_test_document(bytes, flags=4)
    assert_eq(
      pdf_viewer_ttf_simple_gid(truetype_post_test_simple(document), bytes, 65),
      expected,
    )
  }
}

///|
test "TrueType post version 1 reuses standard names and version 3 has no names" {
  let header = Array::make(32, b'\x00')
  @font.write_be32(header, 0, 0x00010000)
  let names = pdf_viewer_ttf_read_post(Bytes::from_array(header)[:], 258).unwrap()
  assert_eq(names.get("A"), Some(36))
  assert_eq(names.get("z"), Some(93))
  assert_eq(names.get("dcroat"), Some(257))
  let bytes = truetype_post_test_replace(
    truetype_test_fixture(),
    "post",
    Some(Bytes::from_array(header)),
  )
  let document = truetype_test_document(
    bytes,
    encoding="/Encoding << /BaseEncoding /WinAnsiEncoding /Differences [65 /exclam] >>",
  )
  assert_eq(
    pdf_viewer_ttf_simple_gid(truetype_post_test_simple(document), bytes, 65),
    4,
  )
  @font.write_be32(header, 0, 0x00030000)
  assert_true(
    pdf_viewer_ttf_read_post(Bytes::from_array(header)[:], 258) is None,
  )
}

///|
test "TrueType unknown glyph name may use ToUnicode only without usable post names" {
  let unknown = "/Encoding << /BaseEncoding /WinAnsiEncoding /Differences [65 /customGlyph] >>"
  let absent = truetype_test_fixture()
  let no_names = Array::make(32, b'\x00')
  @font.write_be32(no_names, 0, 0x00030000)
  let version3 = truetype_post_test_replace(
    absent,
    "post",
    Some(Bytes::from_array(no_names)),
  )
  for bytes in [absent, version3] {
    let document = truetype_test_document(bytes, encoding=unknown)
    assert_eq(
      pdf_viewer_ttf_simple_gid(truetype_post_test_simple(document), bytes, 65),
      2,
    )
    let simple = truetype_post_test_simple(document)
    let without_unicode = { ..simple, fontdescriptor: None, }
    assert_eq(pdf_viewer_ttf_simple_gid(without_unicode, bytes, 65), 0)
  }
  let bytes = truetype_post_test_replace(
    absent,
    "post",
    Some(truetype_post_test_table([0, 36, 61, 0, 0, 0], [])),
  )
  let document = truetype_test_document(bytes, encoding=unknown)
  assert_eq(
    pdf_viewer_ttf_simple_gid(truetype_post_test_simple(document), bytes, 65),
    0,
  )
  assert_eq(document.page(1).unwrap().text_content().text, "Z")
  let known = truetype_test_document(bytes)
  assert_eq(
    pdf_viewer_ttf_simple_gid(truetype_post_test_simple(known), bytes, 65),
    1,
  )
  let supplementary = truetype_cmap_test_font([
    (3, 10, truetype_cmap_test_format12([(65, 65, 1), (0x1F600, 0x1F600, 2)])),
  ])
  let document = truetype_test_document(
    supplementary,
    encoding=unknown,
    unicode="D83DDE00",
  )
  assert_eq(
    pdf_viewer_ttf_simple_gid(
      truetype_post_test_simple(document),
      supplementary,
      65,
    ),
    2,
  )
  assert_true(pdf_viewer_ttf_tounicode_first(b"\xD8\x3D") is None)
}

///|
test "TrueType post rejects truncated names mismatched counts and out-of-range indices" {
  let post = truetype_post_test_table([0, 258, 259, 260, 0, 0], [
    "A", "uni0041", "customGlyph",
  ])
  for end in 0..<post.length() {
    assert_true(pdf_viewer_ttf_read_post(post[:end], 6) is None)
  }
  assert_eq(
    pdf_viewer_ttf_read_post(post[:], 6).unwrap().get("customGlyph"),
    Some(3),
  )
  assert_true(pdf_viewer_ttf_read_post(post[:], 5) is None)
  assert_true(pdf_viewer_ttf_read_post(post[:], 0) is None)
  for (offset, value) in [(32, 65535), (36, 65535)] {
    let damaged = [ for byte in post => byte ]
    @font.write_be16(damaged, offset, value)
    assert_true(
      pdf_viewer_ttf_read_post(Bytes::from_array(damaged)[:], 6) is None,
    )
  }
  let damaged = [ for byte in post => byte ]
  damaged[46] = b'\xFF'
  assert_true(
    pdf_viewer_ttf_read_post(Bytes::from_array(damaged)[:], 6) is None,
  )
}

///|
test "TrueType post fallback skips notdef duplicates empty glyphs and invalid table bounds" {
  let bytes = truetype_post_test_replace(
    truetype_test_fixture(),
    "post",
    Some(truetype_post_test_table([36, 0, 36, 0, 0, 0], [])),
  )
  let names = pdf_viewer_ttf_post(bytes[:]).unwrap()
  assert_eq(pdf_viewer_ttf_post_gid(bytes[:], names, pdf_name_key("/A")), 0)
  assert_eq(
    pdf_viewer_ttf_post_gid(bytes[:], names, pdf_name_key("/.notdef")),
    0,
  )
  let named = truetype_post_test_replace(
    truetype_test_fixture(),
    "post",
    Some(truetype_post_test_table([0, 0, 36, 0, 0, 0], [])),
  )
  let names = pdf_viewer_ttf_post(named[:]).unwrap()
  assert_eq(pdf_viewer_ttf_post_gid(named[:], names, pdf_name_key("/A")), 2)
  for (tag, table) in [("loca", b"\x00\x00"), ("glyf", b""), ("head", b"\x00")] {
    let damaged = truetype_post_test_replace(named, tag, Some(table))
    assert_eq(pdf_viewer_ttf_post_gid(damaged[:], names, pdf_name_key("/A")), 0)
  }
  let offsets = pdf_viewer_ttf_glyph_offsets(named[:]).unwrap()
  let loca = [ for offset in offsets => offset ]
  loca[3] = loca[2]
  let table = Array::make(loca.length() * 4, b'\x00')
  for index, offset in loca {
    @font.write_be32(table, index * 4, offset)
  }
  let empty = truetype_post_test_replace(
    named,
    "loca",
    Some(Bytes::from_array(table)),
  )
  assert_eq(pdf_viewer_ttf_post_gid(empty[:], names, pdf_name_key("/A")), 0)
  let maxp = Array::make(6, b'\x00')
  @font.write_be16(maxp, 4, 5)
  let mismatched = truetype_post_test_replace(
    named,
    "maxp",
    Some(Bytes::from_array(maxp)),
  )
  assert_true(pdf_viewer_ttf_post(mismatched[:]) is None)
}

///|
test "TrueType post cache stays within entry and input limits" {
  pdf_viewer_ttf_post_cache.clear()
  for index in 0..<12 {
    let name = "glyph" + index.to_string()
    let bytes = truetype_post_test_replace(
      truetype_test_fixture(),
      "post",
      Some(truetype_post_test_table([0, 0, 258, 0, 0, 0], [name])),
    )
    assert_eq(pdf_viewer_ttf_post(bytes[:]).unwrap().get(name), Some(2))
  }
  assert_eq(pdf_viewer_ttf_post_cache.length(), 8)
  for index in 0..<3 {
    let table = [
      for byte in truetype_post_test_table([0, 0, 36, 0, 0, 0], []) => byte
    ]
    @font.write_be32(table, 4, index)
    while table.length() < 400000 {
      table.push(b'\x00')
    }
    let bytes = truetype_post_test_replace(
      truetype_test_fixture(),
      "post",
      Some(Bytes::from_array(table)),
    )
    assert_eq(pdf_viewer_ttf_post(bytes[:]).unwrap().get("A"), Some(2))
  }
  assert_true(pdf_viewer_ttf_post_cache.length() <= 8)
  assert_true(
    pdf_viewer_ttf_post_cache
    .iter()
    .fold(init=0, (total, entry) => total + entry.table.length()) <=
    0x100000,
  )
  assert_true(
    pdf_viewer_ttf_post_cache
    .iter()
    .fold(init=0, (total, entry) => {
      total + entry.names.map(names => names.length()).unwrap_or(0)
    }) <=
    131072,
  )
  pdf_viewer_ttf_post_cache.clear()
}

///|
test "TrueType post cache bounds decoded names even when input bytes fit" {
  pdf_viewer_ttf_post_cache.clear()
  let count = 45000
  let indices = [ for index in 0..<count => 258 + index ]
  let names = [
    for index in 0..<count => index.to_string(radix=36).pad_start(3, '0')
  ]
  let maxp = Array::make(6, b'\x00')
  @font.write_be16(maxp, 4, count)
  let fixture = truetype_post_test_replace(
    truetype_test_fixture(),
    "maxp",
    Some(Bytes::from_array(maxp)),
  )
  for index in 0..<3 {
    let table = [ for byte in truetype_post_test_table(indices, names) => byte ]
    @font.write_be32(table, 4, index)
    let bytes = truetype_post_test_replace(
      fixture,
      "post",
      Some(Bytes::from_array(table)),
    )
    assert_eq(pdf_viewer_ttf_post(bytes[:]).unwrap().length(), count)
  }
  assert_eq(pdf_viewer_ttf_post_cache.length(), 2)
  assert_eq(
    pdf_viewer_ttf_post_cache
    .iter()
    .fold(init=0, (total, entry) => {
      total + entry.names.map(names => names.length()).unwrap_or(0)
    }),
    count * 2,
  )
  pdf_viewer_ttf_post_cache.clear()
}

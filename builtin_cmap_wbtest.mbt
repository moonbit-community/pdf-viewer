///|
test "all pinned Adobe binary CMaps decode and retain valid inherited names" {
  let names = pdf_builtin_cmap_names()
  assert_eq(names.length(), 168)
  for name in names {
    guard pdf_builtin_cmap_asset(name) is Some(bytes) else {
      fail("CMap asset missing: " + name)
    }
    let cmap = pdf_parse_binary_cmap(bytes)
    assert_eq(cmap.vertical, name.has_suffix("-V") || name == "V", msg=name)
    for space in cmap.codespaces {
      assert_true(space.length >= 1 && space.length <= 4, msg=name)
      assert_true(
        space.first.reinterpret_as_uint() <= space.last.reinterpret_as_uint(),
        msg=name,
      )
    }
    if cmap.usecmap is Some(base) {
      assert_true(
        names.contains(base) || base == "Identity-H" || base == "Identity-V",
        msg=name + ": " + base,
      )
    }
  }
}

///|
test "Adobe CMap CID mappings match pinned PDF.js unit fixtures" {
  assert_eq(pdf_cmap_name_text(pdf_name_key("/ETenms-B5-H")), "ETenms-B5-H")
  assert_eq(pdf_builtin_cmap_cid("ETenms-B5-H", 0x41), Some(34))
  assert_eq(pdf_builtin_cmap_cid("ETenms-B5-H", 0xA140), Some(99))
  assert_eq(pdf_builtin_cmap_cid("90ms-RKSJ-H", 0x82A0), Some(843))
  assert_eq(pdf_builtin_cmap_cid("UniJIS-UCS2-H", 0x3042), Some(843))
  assert_eq(pdf_builtin_cmap_cid("unknown", 0x41), None)
  assert_eq(pdf_builtin_cmap_cid("Identity-H", 0xFFFF), Some(0xFFFF))
  assert_eq(pdf_builtin_cmap_cid("Identity-H", -1), None)
}

///|
test "binary CMap Unicode signed deltas and ranges decode CID collections" {
  assert_eq(pdf_builtin_cmap_unicode("Adobe-CNS1-UCS2", 99), Some(b"\x30\x00"))
  assert_eq(pdf_builtin_cmap_unicode("Adobe-CNS1-UCS2", 34), Some(b"\x00\x41"))
  assert_eq(
    pdf_builtin_cmap_unicode("Adobe-Japan1-UCS2", 843),
    Some(b"\x30\x42"),
  )
  assert_eq(
    pdf_builtin_cmap_unicode("Adobe-Japan1-UCS2", 526),
    Some(b"\x30\x42"),
  )
}

///|
test "binary CMap rejects truncated fields overlong numbers and unknown record kinds" {
  for
    bytes in [
      b"", b"\x00\x00", b"\x00\x00\x81", b"\x00\xC0\x01", b"\x00\x00\x81\x80\x80\x80\x80\x00",
    ] {
    let rejected = try {
      ignore(pdf_parse_binary_cmap(bytes))
      false
    } catch {
      InvalidBinaryCMap => true
    }
    assert_true(rejected)
  }
}

///|
test "external CMap local mapping precedes inherited built-in CID and codespaces" {
  let document = cid_layout_test_document(
    "BT /F1 10 Tf 20 50 Td <41A140> Tj ET",
    cmap="/ETen-B5-H usecmap 1 begincidchar <41> 2 endcidchar",
  )
  let page = document.page(1).unwrap()
  let text = page.text_content().items
  assert_eq(text.length(), 2)
  assert_eq([ for item in text => item.charcode ], [65, 0xA140])
  assert_eq([ for item in text => item.advance_x ], [3.0, 7.0])
  let font = pdf_collected_entries_of_page(document.document, document.pages[0])[0].state.text_state.current_font
  guard font is @pdflite.PdfFontCIDKeyed(cid) else { fail("CID font missing") }
  assert_eq(pdf_viewer_cid_of_charcode(cid, 65), Some(2))
  assert_eq(pdf_viewer_cid_of_charcode(cid, 0xA140), Some(99))
}

///|
fn builtin_cmap_test_document(
  contents : String,
  encoding : String,
) -> PdfViewerDocument raise {
  let font_hex = type1_test_bytes_hex(glyph_geometry_test_font())
  let gid_hex = type1_test_bytes_hex(Bytes::make(200, b'\x00'))
  annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream("", contents),
    "<< /Type /Font /Subtype /Type0 /BaseFont /BuiltinProbe /Encoding /\{encoding} /DescendantFonts [6 0 R] >>",
    "<< /Type /Font /Subtype /CIDFontType2 /BaseFont /BuiltinProbe /CIDSystemInfo << /Registry (Adobe) /Ordering (CNS1) /Supplement 0 >> /DW 500 /W [34 [500] 99 [700]] /W2 [34 [-800 300 700] 99 [-1100 250 900]] /CIDToGIDMap 9 0 R /FontDescriptor 7 0 R >>",
    "<< /Type /FontDescriptor /FontName /BuiltinProbe /Flags 4 /FontBBox [0 0 1000 1000] /Ascent 1000 /Descent 0 /ItalicAngle 0 /StemV 80 /FontFile2 8 0 R >>",
    annotation_test_stream("/Filter /ASCIIHexDecode", font_hex),
    annotation_test_stream("/Filter /ASCIIHexDecode", gid_hex),
  ])
}

///|
test "named mixed-length CMap joins CID widths Unicode and TrueType outlines" {
  let page = builtin_cmap_test_document(
      "BT /F1 10 Tf 20 50 Td <41A140> Tj ET", "ETenms-B5-H",
    )
    .page(1)
    .unwrap()
  let text = page.text_content().items
  assert_eq([ for item in text => item.text ], ["A", "\u3000"])
  assert_eq([ for item in text => item.advance_x ], [5.0, 7.0])
  for item in text {
    guard item.type3_outline is Some(outline) else {
      fail("TrueType outline missing")
    }
    assert_true(outline.contains("data-pdf-font-outline=\"truetype\""))
  }
  assert_eq(text[1].glyph_transform, Some([10.0, 0.0, 0.0, 10.0, 25.0, 50.0]))
}

///|
test "named vertical CMap uses binary WMode and CID-indexed W2 metrics" {
  let page = builtin_cmap_test_document(
      "BT /F1 10 Tf 20 100 Td <41A140> Tj ET", "ETenms-B5-V",
    )
    .page(1)
    .unwrap()
  let text = page.text_content().items
  assert_true(text.iter().all(item => item.vertical))
  assert_eq(text[0].advance_y, -8.0)
  assert_eq(text[0].glyph_transform, Some([10.0, 0.0, 0.0, 10.0, 17.0, 93.0]))
  assert_eq(text[1].charcode, 0xA140)
  assert_eq(text[1].text, "\u3000")
}

///|
test "external CMap inherits named WMode while local WMode takes priority" {
  for local_mode in ["", "/WMode 0 def "] {
    let document = cid_layout_test_document(
      "BT /F1 10 Tf 20 100 Td <4142> Tj ET",
      cmap=local_mode + "/ETenms-B5-V usecmap",
    )
    let text = document.page(1).unwrap().text_content().items
    assert_eq(text.length(), 2)
    assert_eq(text[0].vertical, local_mode == "")
    assert_eq(text[0].advance_y, if local_mode == "" { -10.0 } else { 0.0 })
    assert_eq(text[0].advance_x, if local_mode == "" { 0.0 } else { 7.0 })
  }
}

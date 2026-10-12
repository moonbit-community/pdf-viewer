///|
/// Authored by tools/font_library_probe.mbtx --synthetic, not an external font.
/// Glyphs 1/2 are rectangles; 3 shears, 4 attaches points, 5 scales its offset.
fn truetype_test_fixture() -> Bytes raise {
  @base64.decode(
    "AAEAAAAHAEAAAgAwaGVhZGA8Qm4AAAB8AAAANm1heHAABwAAAAAAtAAAACBoaGVhAyH/PgAAANQAAAAkaG10eA4Q" +
    "AAAAAAD4AAAAGGNtYXAAhQBlAAABEAAAADRsb2NhAAAByAAAAUQAAAAcZ2x5ZkdCj0YAAAFgAAAAjAABAAAAAAAA" +
    "AAAAAF8PPPUAAAPoAAAAAAAAAAAAAAAAAAAAAAAAAAABLAGQAAAAAAAAAAEAAAAAAAEAAAAGAAAAAAAAAAAAAAAA" +
    "AAAAAAAAAAAAAAAAAAAAAQAAAyD/OAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAYCWAAAAlgAAAJYAAACWAAA" +
    "AlgAAAJYAAAAAAABAAMAAQAAAAwABAAoAAAABgAEAAEAAgBBAFr//wAAAEEAWv///8D/qAABAAAAAAAAAAAAAAAA" +
    "AAAAAAAiAAAARAAAAF4AAAB4AAAAjAABAAAAAABkAMgAAwAAAQEBAQAAAGQAAP+cAAAAAADIAAAAAQAAAAAAyADI" +
    "AAMAAAEBAQEAAADIAAD/OAAAAAAAyAAA//8AAAAAAMgAyACDAAEAAAAAQAAAACAAQAD//wAAAAABLAGQACMAAQAA" +
    "AAAAAQACAAIAAP//AAAAAAAAAAAICwABAGQAyCAA",
  )
}

///|
fn truetype_test_document(
  bytes : Bytes,
  encoding? : String = "/Encoding /WinAnsiEncoding",
  flags? : Int = 32,
  unicode? : String = "005A",
) -> PdfViewerDocument raise {
  let font_hex = StringBuilder()
  for byte in bytes {
    font_hex.write_string(byte.to_int().to_string(radix=16).pad_start(2, '0'))
  }
  font_hex.write_char('>')
  annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    annotation_test_stream(
      "", "BT /F1 10 Tf 4 Tr 20 100 Td <41> Tj ET 0 0 200 200 re f",
    ),
    "<< /Type /Font /Subtype /TrueType /BaseFont /ViewerGidTest /FirstChar 65 /LastChar 65 /Widths [600] " +
    encoding +
    " /FontDescriptor 6 0 R /ToUnicode 8 0 R >>",
    "<< /Type /FontDescriptor /FontName /ViewerGidTest /Flags " +
    flags.to_string() +
    " /FontBBox [0 0 300 400] /Ascent 800 /Descent -200 /ItalicAngle 0 /StemV 80 /FontFile2 7 0 R >>",
    annotation_test_stream("/Filter /ASCIIHexDecode", font_hex.to_string()),
    annotation_test_stream("", "1 beginbfchar <41> <" + unicode + "> endbfchar"),
  ])
}

///|
test "TrueType encoding selects the painted glyph while ToUnicode selects copied text" {
  let fixture = truetype_test_fixture()
  assert_eq(@pdflite.pdf_truetype_cmap_glyph(fixture[:], 65), Some(1))
  let document = truetype_test_document(fixture)
  let font = pdf_read_font_for_viewer(document.document, @syntax.PdfIndirect(5))
  guard font is @pdflite.PdfFontSimple(simple) else {
    fail("simple font missing")
  }
  assert_eq(pdf_viewer_ttf_simple_gid(simple, fixture, 65), 1)
  assert_eq(
    pdf_viewer_ttf_embedded_bytes(document.document, font),
    Some(fixture),
  )
  let page = document.page(1).unwrap()
  let text = page.text_content().items[0]
  assert_eq(text.text, "Z")
  assert_eq(text.charcode, 65)
  assert_eq(text.advance_x, 6.0)
  assert_true(text.type3_outline.unwrap().contains("L 21 100"))
  assert_true(!text.type3_outline.unwrap().contains("L 22 100"))
  assert_true(
    text_clip_test_paths(page)[0].clip_path.unwrap().contains("L 21 100"),
  )
}

///|
test "TrueType Differences override glyph selection independently of copied Unicode" {
  let page = truetype_test_document(
      truetype_test_fixture(),
      encoding="/Encoding << /BaseEncoding /WinAnsiEncoding /Differences [65 /Z] >>",
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
}

///|
test "TrueType symbolic fonts resolve byte codes in the F000 cmap window" {
  let fixture = truetype_test_fixture()
  let cmap = pdf_viewer_ttf_table(fixture[:], "cmap").unwrap()
  let bytes = [ for byte in fixture => byte.to_int() ]
  bytes[cmap.offset + 7] = 0
  bytes[cmap.offset + 26] = 0xF0
  bytes[cmap.offset + 34] = 0xF0
  bytes[cmap.offset + 28] = 0xF0
  bytes[cmap.offset + 36] = 0xF0
  bytes[cmap.offset + 40] = 0x0F
  bytes[cmap.offset + 41] = 0xC0
  bytes[cmap.offset + 42] = 0x0F
  bytes[cmap.offset + 43] = 0xA8
  let page = truetype_test_document(
      @core.pdf_bytes_of_int_array(bytes),
      encoding="",
      flags=4,
    )
    .page(1)
    .unwrap()
  assert_eq(page.text_content().text, "Z")
  assert_true(
    page.text_content().items[0].type3_outline.unwrap().contains("L 21 100"),
  )
}

///|
test "TrueType compound glyphs preserve shear and align child control points" {
  let fixture = truetype_test_fixture()
  let sheared = pdf_viewer_ttf_glyph_contours_of_index(fixture[:], 3).unwrap()
  assert_eq([ for point in sheared[0] => (point.x, point.y) ], [
    (0.0, 0.0),
    (100.0, 0.0),
    (200.0, 200.0),
    (100.0, 200.0),
  ])
  let attached = pdf_viewer_ttf_glyph_contours_of_index(fixture[:], 4).unwrap()
  assert_eq(attached.length(), 2)
  assert_eq([ for point in attached[1] => (point.x, point.y) ], [
    (100.0, 200.0),
    (300.0, 200.0),
    (300.0, 400.0),
    (100.0, 400.0),
  ])
}

///|
test "TrueType scaled component offsets are transformed with their glyph" {
  let fixture = truetype_test_fixture()
  let scaled = pdf_viewer_ttf_glyph_contours_of_index(fixture[:], 5).unwrap()
  assert_eq([ for point in scaled[0] => (point.x, point.y) ], [
    (50.0, 100.0),
    (100.0, 100.0),
    (100.0, 200.0),
    (50.0, 200.0),
  ])
}

///|
test "TrueType truncated compound records cannot read into the next glyph" {
  let fixture = truetype_test_fixture()
  let loca = pdf_viewer_ttf_table(fixture[:], "loca").unwrap()
  let offsets = pdf_viewer_ttf_glyph_offsets(fixture[:]).unwrap()
  let end = offsets[3] + 14
  let bytes = [ for byte in fixture => byte.to_int() ]
  for index, shift in [24, 16, 8, 0] {
    bytes[loca.offset + 16 + index] = (end >> shift) & 255
  }
  assert_true(
    pdf_viewer_ttf_glyph_contours_of_index(
      @core.pdf_bytes_of_int_array(bytes)[:],
      3,
    )
    is None,
  )
}

///|
test "TrueType invalid point attachments and cyclic components fall back safely" {
  let fixture = truetype_test_fixture()
  let glyf = pdf_viewer_ttf_table(fixture[:], "glyf").unwrap()
  let offsets = pdf_viewer_ttf_glyph_offsets(fixture[:]).unwrap()
  let invalid = [ for byte in fixture => byte.to_int() ]
  invalid[glyf.offset + offsets[4] + 23] = 255
  assert_true(
    pdf_viewer_ttf_glyph_contours_of_index(
      @core.pdf_bytes_of_int_array(invalid)[:],
      4,
    )
    is None,
  )
  let cyclic = [ for byte in fixture => byte.to_int() ]
  cyclic[glyf.offset + offsets[3] + 13] = 3
  assert_true(
    pdf_viewer_ttf_glyph_contours_of_index(
      @core.pdf_bytes_of_int_array(cyclic)[:],
      3,
    )
    is None,
  )
  assert_eq(
    pdf_viewer_ttf_component_argument(b"\xFF", 0, false, false),
    Some(255),
  )
}

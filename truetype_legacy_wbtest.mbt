///|
/// Single byte A maps to 1; lead bytes 0x81/0x82 share a low-byte subarray,
/// whose signed delta maps nonzero raw GIDs modulo 65536. Zero stays absent.
fn truetype_legacy_test_cmap2() -> Bytes {
  let data = Array::make(542, b'\x00')
  @font.write_be16(data, 0, 2)
  @font.write_be16(data, 2, data.length())
  for high in [0x81, 0x82] {
    @font.write_be16(data, 6 + high * 2, 8)
  }
  for
    (offset, first, count, delta, range) in [
      (518, 65, 1, 0, 10),
      (526, 65, 3, -1, 4),
    ] {
    @font.write_be16(data, offset, first)
    @font.write_be16(data, offset + 2, count)
    @font.write_be16(data, offset + 4, delta)
    @font.write_be16(data, offset + 6, range)
  }
  for index, gid in [1, 3, 0, 1] {
    @font.write_be16(data, 534 + index * 2, gid)
  }
  Bytes::from_array(data)
}

///|
test "Legacy cmap 2 maps single bytes and aliased lead bytes with signed deltas" {
  let subtable = truetype_legacy_test_cmap2()
  let bytes = truetype_cmap_test_font([(3, 1, subtable)])
  let cmap = pdf_viewer_ttf_cmap(bytes[:], false, false).unwrap()
  for
    (code, gid) in [
      (65, 1),
      (0x8141, 2),
      (0x8241, 2),
      (0x8142, 0),
      (0x8143, 0),
      (0x81, 0),
      (0x8341, 0),
    ] {
    assert_eq(pdf_viewer_ttf_cmap_gid(bytes[:], cmap, code), gid)
  }
  let page = truetype_test_document(bytes).page(1).unwrap()
  assert_eq(page.text_content().text, "Z")
  assert_true(
    page.text_content().items[0].type3_outline.unwrap().contains("L 21 100"),
  )
  assert_true(
    text_clip_test_paths(page)[0].clip_path.unwrap().contains("L 21 100"),
  )
  let changed = subtable.to_array()
  @font.write_be16(changed, 534, 65535)
  @font.write_be16(changed, 522, 2)
  let normalized = pdf_viewer_ttf_cmap2_normalize(Bytes::from_array(changed)[:]).unwrap()
  let decoded = pdf_viewer_ttf_read_cmap(
    truetype_cmap_test_table([(3, 1, normalized)])[:],
    false,
    false,
  ).unwrap()
  assert_eq(decoded.glyphs.get(65), Some(1))
}

///|
test "Legacy cmap 2 rejects relative offsets and retains a later usable subtable" {
  for
    (offset, value) in [
      (6 + 0x81 * 2, 7),
      (524, 0),
      (524, 65534),
      (528, 256),
      (526, 255),
    ] {
    let changed = truetype_legacy_test_cmap2().to_array()
    @font.write_be16(changed, offset, value)
    let damaged = Bytes::from_array(changed)
    assert_eq(pdf_viewer_ttf_cmap2_normalize(damaged[:]), None)
    let font = truetype_cmap_test_font([
      (3, 1, damaged),
      (3, 1, truetype_cmap_test_format4(65, 2)),
    ])
    let cmap = pdf_viewer_ttf_cmap(font[:], false, false).unwrap()
    assert_eq(pdf_viewer_ttf_cmap_gid(font[:], cmap, 65), 2)
  }
  for end in [0, 517, 525, 541] {
    let bytes = truetype_legacy_test_cmap2()
    assert_eq(pdf_viewer_ttf_cmap2_normalize(bytes[:end]), None)
  }
}

///|
test "Legacy post 2.5 reuses library names and treats post 3 as intentionally nameless" {
  let table = Array::make(40, b'\x00')
  @font.write_be32(table, 0, 0x00025000)
  @font.write_be16(table, 32, 6)
  for index, delta in [0, 35, 59, -3, -4, -5] {
    table[34 + index] = (delta & 255).to_byte()
  }
  let bytes = truetype_post_test_replace(truetype_test_fixture(), "cmap", None)
  let bytes = truetype_post_test_replace(
    bytes,
    "post",
    Some(Bytes::from_array(table)),
  )
  let page = truetype_test_document(
      bytes,
      encoding="/Encoding << /Differences [65 /Z] >>",
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
  table[34] = b'\xFF'
  assert_eq(pdf_viewer_ttf_read_post(Bytes::from_array(table)[:], 6), None)
  @font.write_be32(table, 0, 0x00030000)
  assert_eq(pdf_viewer_ttf_read_post(Bytes::from_array(table)[:32], 6), None)
}

///|
test "Damaged sfnt tables preserve copied text and the remaining page" {
  for
    bytes in [
      b"\x00\x01\x00\x00",
      b"\x00\x01\x00\x00\xFF\xFF",
      truetype_test_fixture()[:40].to_owned(),
    ] {
    let document = truetype_test_document(bytes)
    font_scope_test_content(
      document, "BT /F1 10 Tf 20 100 Td <41> Tj ET 0 0 10 10 re f",
    )
    let page = document.page(1).unwrap()
    assert_eq(page.text_content().text, "Z")
    assert_true(pdf_render_page_svg(page, 1.0, 0).contains("<path"))
    assert_true(page.text_content().items[0].type3_outline is None)
  }
}

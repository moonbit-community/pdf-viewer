///|
test "XFA uses pdflite stream decoding and preserves packet order" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /NeedsRendering true /AcroForm << /XFA [(preamble) 4 0 R (template) 5 0 R (datasets) 6 0 R] >> >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] >>",
    annotation_test_stream("", "<xdp:xdp>"),
    annotation_test_stream("", "<template/>"),
    annotation_test_stream("", "<datasets/></xdp:xdp>"),
  ])
  assert_true(document.xfa_needs_rendering())
  let packets = document.xfa_packets()
  assert_eq(packets.map(packet => packet.name), [
    "preamble", "template", "datasets",
  ])
  assert_eq(packets.map(packet => @utf8.decode_lossy(packet.data)), [
    "<xdp:xdp>", "<template/>", "<datasets/></xdp:xdp>",
  ])
}

///|
test "XFA static forms and malformed packet arrays are distinguished" {
  let document = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /AcroForm << /XFA [(template)] >> >>", "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] >>",
  ])
  assert_true(!document.xfa_needs_rendering())
  let rejected = try {
    ignore(document.xfa_packets())
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "XFA glyph widths reuse field font metrics instead of host measurement" {
  let document = field_layout_document(
    "<< /Subtype /Widget /FT /Tx /Rect [0 0 50 20] >>",
  )
  let widths = document.xfa_font_glyphs_json("/Helv", "Wi")
  assert_eq(
    widths,
    Json::array([
      { "unicode": "W", "width": 600 },
      { "unicode": "i", "width": 600 },
    ]),
  )
}

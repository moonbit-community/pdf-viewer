///|
fn recovery_test_fixture() -> (Bytes, Int) {
  let pages = "<< /Type /Pages /Count 1 /Kids [3 0 R] >>"
  let font = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
  let annotation = "<< /Subtype /Square /Rect [10 20 40 50] /C [1 0 0] >>"
  let header = "2 0 5 \{pages.length()} 6 \{pages.length() + font.length()} "
  let members = header + pages + font + annotation
  let content = "BT /F1 12 Tf 10 150 Td (Recovered) Tj ET"
  let objects : Array[(Int, String)] = [
    (1, "<< /Type /Catalog /Pages 2 0 R >>"),
    (
      3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> /Annots [6 0 R] >>",
    ),
    (4, annotation_test_stream("", content)),
    (
      7,
      annotation_test_stream(
        "/Type /ObjStm /N 3 /First \{header.length()}",
        members,
      ),
    ),
  ]
  let output = StringBuilder()
  output.write_string("%PDF-1.7\n")
  let offsets : Map[Int, Int] = Map([])
  for (number, object) in objects {
    offsets[number] = output.to_string().length()
    output.write_string("\{number} 0 obj\n\{object}\nendobj\n")
  }
  let xref = output.to_string().length()
  offsets[8] = xref
  let hex = StringBuilder()
  for number in 0..<10 {
    let (kind, offset, index) = match number {
      0 => (0, 0, 65535)
      2 => (2, 7, 0)
      5 => (2, 7, 1)
      6 => (2, 7, 2)
      // Like the upstream annotation fixtures, an unrelated in-use record
      // points at the PDF header, which is not an indirect object.
      9 => (1, 0, 0)
      _ => (1, offsets[number], 0)
    }
    hex.write_string(kind.to_string(radix=16).pad_start(2, '0'))
    hex.write_string(offset.to_string(radix=16).pad_start(8, '0'))
    hex.write_string(index.to_string(radix=16).pad_start(4, '0'))
  }
  hex.write_string(">")
  output.write_string("8 0 obj\n")
  output.write_string(
    annotation_test_stream(
      "/Type /XRef /W [1 4 2] /Index [0 10] /Size 10 /Root 1 0 R /Filter /ASCIIHexDecode",
      hex.to_string(),
    ),
  )
  output.write_string("\nendobj\nstartxref\n\{xref}\n%%EOF\n")
  (@utf8.encode(output.to_string()), xref)
}

///|
test "compressed reader recovery preserves page, font and annotation objects" {
  let (bytes, _) = recovery_test_fixture()
  let repaired = pdf_recover_compressed_document(
    bytes,
    @pdflite.pdf_document_empty(),
  )
  assert_eq(repaired.endpage(), 1)
  let viewer = open_document(bytes)
  assert_eq(viewer.source_length(), bytes.length())
  assert_eq(viewer.page_count(), 1)
  guard viewer.page(1) is Some(page) else { fail("missing recovered page") }
  assert_eq(page.width, 200.0)
  assert_eq(page.text, "Recovered")
  assert_eq(page.annotations.length(), 1)
  assert_eq(page.annotations[0].color, Some("#FF0000"))
  guard viewer.render_svg(1) is Some(svg) else { fail("missing recovered SVG") }
  assert_true(svg.contains("Recovered"))
  assert_true(svg.contains("data-pdf-annotation-index=\"0\""))
}

///|
test "compressed recovery respects newer classic revisions and deleted objects" {
  let (bytes, previous) = recovery_test_fixture()
  let revision = StringBuilder()
  let page_offset = bytes.length()
  revision.write_string(
    "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> /Annots [6 0 R] >>\nendobj\n",
  )
  let xref = bytes.length() + revision.to_string().length()
  revision.write_string("xref\n3 1\n")
  revision.write_string(
    page_offset.to_string().pad_start(10, '0') + " 00000 n \n",
  )
  revision.write_string("6 1\n0000000000 00001 f \n")
  revision.write_string(
    "trailer\n<< /Size 10 /Root 1 0 R /Prev \{previous} >>\nstartxref\n\{xref}\n%%EOF\n",
  )
  let source = bytes + @utf8.encode(revision.to_string())
  let repaired = pdf_recover_compressed_document(
    source,
    @pdflite.pdf_document_empty(),
  )
  assert_eq(repaired.endpage(), 1)
  let viewer = open_document(source)
  guard viewer.page(1) is Some(page) else { fail("missing revised page") }
  assert_eq(page.width, 300.0)
  assert_eq(page.height, 400.0)
  assert_eq(page.text, "Recovered")
  assert_eq(page.annotations.length(), 0)
}

///|
test "compressed recovery rejects cyclic xref revisions" {
  let (bytes, _) = recovery_test_fixture()
  let offset = bytes.length()
  let revision = "xref\n0 1\n0000000000 65535 f \ntrailer\n<< /Size 10 /Root 1 0 R /Prev \{offset} >>\nstartxref\n\{offset}\n%%EOF\n"
  let original = @pdflite.pdf_document_empty()
  try
    pdf_recover_compressed_document(bytes + @utf8.encode(revision), original)
  catch {
    @core.XRefEntryExpected => ()
    error => fail("unexpected recovery failure: \{@debug.to_string(error)}")
  } noraise {
    _ => fail("cyclic xref must fail")
  }
}

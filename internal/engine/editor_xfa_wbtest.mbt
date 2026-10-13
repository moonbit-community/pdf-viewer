///|
test "XFA editing replaces data packets while preserving template and source bytes" {
  let source = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /NeedsRendering true /AcroForm << /XFA [(template) 4 0 R (datasets) 5 0 R] >> >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>", "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] >>",
    "<< /Length 11 >>\nstream\n<template/>\nendstream", "<< /Length 11 >>\nstream\n<datasets/>\nendstream",
  ])
  let xml = @utf8.encode(
    "<datasets><name>你好 &amp; MoonBit</name></datasets>",
  )
  let edited = source.with_xfa_packets([{ name: "datasets", data: xml, }])
  let saved = edited.save_bytes()
  assert_eq(saved[:source.source_length].to_owned(), source.source_bytes)
  let packets = open_document(saved).xfa_packets()
  assert_eq(packets[0].name, "template")
  assert_eq(packets[0].data, source.xfa_packets()[0].data)
  assert_eq(packets[1].data, xml)
  assert_eq(source.xfa_packets()[1].data, b"<datasets/>")
  assert_true(
    (try? source.with_xfa_packets([{ name: "template", data: xml, }])) is Err(_),
  )
}

///|
test "XFA editing can add a missing datasets packet and respects encrypted permissions" {
  let source = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /NeedsRendering true /AcroForm << /XFA [(template) 4 0 R] >> >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>", "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 300] >>",
    "<< /Length 11 >>\nstream\n<template/>\nendstream",
  ])
  let patches = [{ name: "datasets", data: b"<datasets/>", }]
  assert_eq(source.with_xfa_packets(patches).xfa_packets().length(), 2)
  let bytes = editor_security_encrypt(source, 3, [
    @crypt_core.PdfNoForms,
    @crypt_core.PdfNoAnnot,
  ])
  let reader = open_document_with_passwords(
    bytes,
    user_password=Some(b"reader"),
  )
  assert_true((try? reader.with_xfa_packets(patches)) is Err(_))
  let owner = open_document_with_passwords(bytes, owner_password=Some(b"owner"))
  let edited = owner.with_xfa_packets(patches)
  let saved = edited.save_bytes(
    aes_iv_provider=@pdflite.pdf_deterministic_aes_iv_provider_from_seed(
      b"xfa-test",
    ),
  )
  assert_eq(saved[:bytes.length()].to_owned(), bytes)
  let reopened = open_document_with_passwords(
    saved,
    user_password=Some(b"reader"),
  )
  assert_eq(reopened.xfa_packets()[1].data, b"<datasets/>")
}

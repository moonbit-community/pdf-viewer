///|
fn pdfx_test_document(
  group : String,
  intent_kind : String,
) -> PdfViewerDocument raise {
  let viewer = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /OutputIntents [<< /S /" +
    intent_kind +
    " /DestOutputProfile 5 0 R >>] >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] " +
    group +
    " /Contents 4 0 R /Resources << >> >>",
    annotation_test_stream("", "0 1 1 0 k 0 0 50 50 re f"),
    icc_test_stream(icc_test_cmyk, "/N 4"),
  ])
  viewer
}

///|
fn pdfx_test_mark(viewer : PdfViewerDocument) -> Unit {
  viewer.document.set_trailer_dict(
    @syntax.pdf_dictionary([
      (pdf_name_key("/Root"), @syntax.PdfIndirect(1)),
      (
        pdf_name_key("/Info"),
        @syntax.pdf_dictionary([
          (pdf_name_key("/GTS_PDFXVersion"), @syntax.PdfString(b"PDF/X-3:2002")),
        ]),
      ),
    ]),
  )
}

///|
test "PDFX OutputIntent defines default process blending but ordinary PDF does not" {
  let viewer = pdfx_test_document("", "GTS_PDFX")
  assert_eq(viewer.page(1).unwrap().blend_space, "DeviceRGB")
  pdfx_test_mark(viewer)
  let page = viewer.page(1).unwrap()
  assert_eq(page.blend_space, "DeviceCMYK")
  assert_eq(page.blend_profile_id, Some("icc-0"))
  assert_eq(page.icc_profiles[0].components, 4)
}

///|
test "explicit page blending space has priority over PDFX OutputIntent" {
  let viewer = pdfx_test_document(
    "/Group << /S /Transparency /CS /DeviceRGB >>", "GTS_PDFX",
  )
  pdfx_test_mark(viewer)
  let page = viewer.page(1).unwrap()
  assert_eq(page.blend_space, "DeviceRGB")
  assert_eq(page.blend_profile_id, None)
}

///|
test "PDFX missing matching output profile is an explicit capability diagnostic" {
  let viewer = pdfx_test_document("", "GTS_PDFA1")
  pdfx_test_mark(viewer)
  let page = viewer.page(1).unwrap()
  assert_eq(
    page.graphics_diagnostics()[0].code,
    "PDFX_OUTPUT_INTENT_UNAVAILABLE",
  )
}

///|
test "Type3 bindings preserve Differences overrides and first CharProc matches" {
  let encoding : @pdflite.PdfEncoding = @pdflite.PdfCustomEncoding(
    @pdflite.PdfImplicitInFontFile,
    [
      { code: 65, name: pdf_name_key("/Old"), },
      { code: 65, name: pdf_name_key("/A"), },
      { code: 66, name: pdf_name_key("/Missing"), },
    ],
  )
  let charprocs = [
    (pdf_name_key("/Old"), @syntax.PdfIndirect(10)),
    (pdf_name_key("/A"), @syntax.PdfIndirect(11)),
    (pdf_name_key("/A"), @syntax.PdfIndirect(12)),
  ]
  let context = pdf_resource_build_context()
  for _ in 0..<2 {
    assert_eq(
      pdf_type3_charproc(
        encoding,
        charprocs[:],
        Some(@syntax.PdfIndirect(5)),
        65,
        context,
      ),
      Some(@syntax.PdfIndirect(11)),
    )
    assert_eq(
      pdf_type3_charproc(
        encoding,
        charprocs[:],
        Some(@syntax.PdfIndirect(5)),
        66,
        context,
      ),
      None,
    )
  }
  assert_eq(context.type3_charprocs.length(), 1)
  // The same code and object number in a fresh page/document must resolve
  // from the new font, rather than retaining the preceding document's table.
  assert_eq(
    pdf_type3_charproc(
      encoding,
      [(pdf_name_key("/A"), @syntax.PdfIndirect(20))],
      Some(@syntax.PdfIndirect(5)),
      65,
      pdf_resource_build_context(),
    ),
    Some(@syntax.PdfIndirect(20)),
  )
  // Direct font dictionaries cannot share an indirect-font binding table.
  assert_eq(
    pdf_type3_charproc(
      encoding,
      [(pdf_name_key("/A"), @syntax.PdfIndirect(21))],
      Some(@syntax.pdf_dictionary([])),
      65,
      context,
    ),
    Some(@syntax.PdfIndirect(21)),
  )
}

///|
test "Type3 binding budget preserves lookups after saturation" {
  let context = pdf_resource_build_context()
  let encoding : @pdflite.PdfEncoding = @pdflite.PdfCustomEncoding(
    @pdflite.PdfImplicitInFontFile,
    [{ code: 65, name: pdf_name_key("/A"), }],
  )
  for number in 1..<131 {
    assert_eq(
      pdf_type3_charproc(
        encoding,
        [(pdf_name_key("/A"), @syntax.PdfIndirect(number + 1000))],
        Some(@syntax.PdfIndirect(number)),
        65,
        context,
      ),
      Some(@syntax.PdfIndirect(number + 1000)),
    )
  }
  assert_eq(context.type3_charprocs.length(), 128)
}

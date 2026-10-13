///|
test "editor preserves a selected PDF font instead of rasterizing encodable Unicode text" {
  let cmap = "/CIDInit /ProcSet findresource begin 12 dict begin begincmap /CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def /CMapName /Greek def /CMapType 2 def 1 begincodespacerange <00> <FF> endcodespacerange 1 beginbfchar <57> <03A9> endbfchar endcmap CMapName currentdict /CMap defineresource pop end end"
  let source = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [4 0 R] /DA (/Sym 12 Tf 0 g) /DR << /Font << /Sym 6 0 R >> >> >> >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Annots [4 0 R 5 0 R] >>",
    "<< /Subtype /Widget /Rect [10 20 150 45] /FT /Tx /T (greek) /V (Before) >>",
    "<< /Subtype /FreeText /Rect [10 60 150 85] /DA (/Sym 12 Tf 0 g) /Contents (Before) >>",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Symbol /ToUnicode 7 0 R >>",
    annotation_test_stream("", cmap),
  ])
  let image : Json = { "width": 1, "height": 1, "rgba": "/wAA/w==" }
  let edited = source.with_editor_changes([
    {
      "kind": "field",
      "id": "object:4",
      "page": 1,
      "values": ["Ω"],
      "image": image,
    },
    {
      "kind": "update",
      "id": "object:5",
      "page": 1,
      "contents": "Ω",
      "size": 16,
      "image": image,
    },
  ])
  for raw in pdf_edit_annots(edited.document, edited.pages[0].rest) {
    let ap = edited.document.lookup_direct(pdf_name_key("/AP"), raw).unwrap()
    let normal = edited.document.lookup_direct(pdf_name_key("/N"), ap).unwrap()
    let resources = edited.document
      .lookup_direct(pdf_name_key("/Resources"), normal)
      .unwrap()
    assert_true(
      edited.document.lookup_direct(pdf_name_key("/XObject"), resources) is None,
    )
    let fonts = edited.document
      .lookup_direct(pdf_name_key("/Font"), resources)
      .unwrap()
    let font = edited.document
      .lookup_direct(pdf_name_key("/Sym"), fonts)
      .unwrap()
    assert_eq(
      edited.document.lookup_direct(pdf_name_key("/BaseFont"), font),
      Some(@syntax.PdfNameObject(pdf_name_key("/Symbol"))),
    )
    let ops = @pdflite.pdf_parse_content_ops_from_bytes(normal.stream_bytes())
    assert_true(ops.contains(@content.Op_Tj(b"W")))
  }
  let reopened = open_document(edited.save_bytes())
  assert_eq(reopened.page(1).unwrap().annotations[0].field_value, Some("Ω"))
}

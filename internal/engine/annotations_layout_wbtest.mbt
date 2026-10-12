///|
fn field_layout_document(
  widget : String,
  defaults? : String = "/DA (/Helv 10 Tf 0 g) /DR << /Font << /Helv << /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >> >> >>",
  extra? : Array[String] = [],
) -> PdfViewerDocument raise {
  annotation_test_document(
    [
      "<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [5 0 R] \{defaults} >> >>",
      "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << >> /Annots [5 0 R] >>",
      annotation_test_stream("", ""),
      widget,
      ..extra,
    ],
  )
}

///|
fn field_layout_ops(
  document : PdfViewerDocument,
) -> Array[@content.PdfContentOp] raise {
  let object = @syntax.PdfIndirect(5)
  let rectangle = document.document.read_annotation(object).rectangle
  let appearance = pdf_annotation_generated_appearance(
    document.document,
    object,
    rectangle,
  ).unwrap()
  @pdflite.pdf_parse_content_ops_from_bytes(appearance.stream_bytes())
}

///|
test "field layout inherits AcroForm DA DR font metrics alignment and clipping" {
  let document = field_layout_document(
    "<< /Subtype /Widget /Rect [10 20 90 40] /FT /Tx /V (Wi) /Q 2 >>",
  )
  let page = document.page(1).unwrap()
  let appearance = page.annotations[0].appearance.unwrap()
  assert_true(appearance.svg.contains("standard14:Courier"))
  assert_true(appearance.svg.contains(">Wi</title>"))
  let ops = field_layout_ops(document)
  assert_true(ops.contains(@content.Op_Tf(pdf_name_key("/Helv"), 10.0)))
  assert_true(ops.contains(@content.Op_re(2.0, 2.0, 76.0, 16.0)))
  let matrices = ops.filter_map(op => {
    match op {
      @content.Op_Tm(matrix) => Some(matrix)
      _ => None
    }
  })
  // Courier's W and i are both 600 units: right alignment is 78 - 12.
  assert_eq(matrices[0].e, 66.0)
  assert_true(matrices[0].f > 2.0 && matrices[0].f < 12.0)
}

///|
test "field multiline wraps words honours CRLF and fixed DA size" {
  let document = field_layout_document(
    "<< /Subtype /Widget /Rect [0 0 46 70] /FT /Tx /Ff 4096 /V (one two three\r\nfour) >>",
  )
  let ops = field_layout_ops(document)
  let lines = ops.filter_map(op => {
    match op {
      @content.Op_Tj(bytes) => Some(@utf8.decode_lossy(bytes[:]))
      _ => None
    }
  })
  assert_eq(lines, ["one ", "two ", "three", "four"])
  let matrices = ops.filter_map(op => {
    match op {
      @content.Op_Tm(matrix) => Some(matrix)
      _ => None
    }
  })
  assert_eq(matrices.length(), 4)
  assert_true(matrices[0].f > matrices[1].f && matrices[1].f > matrices[2].f)
  assert_true(document.page(1).unwrap().annotations[0].appearance is Some(_))
}

///|
test "field comb centres glyphs in cells respects Q and MaxLen" {
  let document = field_layout_document(
    "<< /Subtype /Widget /Rect [0 0 80 20] /FT /Tx /Ff 16777216 /MaxLen 4 /Q 2 /V (Wi) >>",
  )
  let matrices = field_layout_ops(document).filter_map(op => {
    match op {
      @content.Op_Tm(matrix) => Some(matrix)
      _ => None
    }
  })
  assert_eq(matrices.map(matrix => matrix.e), [46.5, 65.5])
  let overflow = field_layout_document(
    "<< /Subtype /Widget /Rect [0 0 80 20] /FT /Tx /Ff 16777216 /MaxLen 4 /V (ABCDEF) >>",
  )
  let shown = field_layout_ops(overflow).filter_map(op => {
    match op {
      @content.Op_Tj(bytes) => Some(bytes)
      _ => None
    }
  })
  assert_eq(shown, [b"A", b"B", b"C", b"D"])
}

///|
test "field password masks Unicode characters and zero DA size fits the box" {
  let document = field_layout_document(
    "<< /Subtype /Widget /Rect [0 0 30 20] /FT /Tx /Ff 8192 /V <FEFF006100E94E2D> >>",
    defaults="/DA (/Helv 0 Tf 0 g)",
  )
  let ops = field_layout_ops(document)
  assert_true(ops.contains(@content.Op_Tj(b"***")))
  let sizes = ops.filter_map(op => {
    match op {
      @content.Op_Tf(_, size) => Some(size)
      _ => None
    }
  })
  assert_true(sizes[0] > 0.0 && sizes[0] <= 26.0 / (3.0 * 0.389))
  let svg = document.page(1).unwrap().annotations[0].appearance.unwrap().svg
  assert_true(!svg.contains("é") && !svg.contains("中"))
}

///|
test "FreeText uses its DA inherited resources multiline and contents" {
  let document = field_layout_document(
    "<< /Subtype /FreeText /Rect [0 0 60 50] /DA (/Helv 9 Tf 1 0 0 rg) /Contents (first\nsecond) /Q 1 >>",
  )
  let ops = field_layout_ops(document)
  assert_true(ops.contains(@content.Op_Tf(pdf_name_key("/Helv"), 9.0)))
  assert_true(ops.contains(@content.Op_rg(1.0, 0.0, 0.0)))
  assert_true(ops.contains(@content.Op_Tj(b"first")))
  assert_true(ops.contains(@content.Op_Tj(b"second")))
  assert_true(document.page(1).unwrap().annotations[0].appearance is Some(_))
}

///|
test "choice preserves export display and duplicate export selection indices" {
  let document = field_layout_document(
    "<< /Subtype /Widget /Rect [0 0 80 70] /FT /Ch /Ff 2097152 /Opt [[(a) (Alpha)] [(a) (Again)] [(b) (Beta)]] /V [(a) (b)] /I [1 2] >>",
  )
  let options = document.page(1).unwrap().annotations[0].choice_options
  assert_eq(
    options.map(option => {
      (option.export_value, option.display_value, option.selected)
    }),
    [("a", "Alpha", false), ("a", "Again", true), ("b", "Beta", true)],
  )
  let ops = field_layout_ops(document)
  assert_true(ops.contains(@content.Op_Tj(b"Alpha")))
  assert_true(ops.contains(@content.Op_Tj(b"Again")))
  assert_true(ops.contains(@content.Op_Tj(b"Beta")))
  assert_eq(ops.filter(op => op == @content.Op_rg(0.15, 0.35, 0.7)).length(), 2)
}

///|
test "choice combo displays label and list honours TI without changing values" {
  let combo = field_layout_document(
    "<< /Subtype /Widget /Rect [0 0 90 20] /FT /Ch /Ff 131072 /Opt [[(a) (Alpha)] [(b) (Beta)]] /V (b) >>",
  )
  assert_eq(combo.page(1).unwrap().annotations[0].field_value, Some("b"))
  assert_true(field_layout_ops(combo).contains(@content.Op_Tj(b"Beta")))
  let list = field_layout_document(
    "<< /Subtype /Widget /Rect [0 0 90 40] /FT /Ch /Opt [(Alpha) (Beta) (Gamma)] /TI 1 /V (Gamma) >>",
  )
  let ops = field_layout_ops(list)
  assert_true(!ops.contains(@content.Op_Tj(b"Alpha")))
  assert_true(ops.contains(@content.Op_Tj(b"Beta")))
}

///|
test "missing AP radio identifies Opt by Kids and pushbutton paints MK caption" {
  let radio = annotation_test_page(
    [
      "<< /Subtype /Widget /Rect [0 0 20 20] /Parent 7 0 R >>", "<< /Subtype /Widget /Rect [30 0 50 20] /Parent 7 0 R /AS /Off >>",
    ],
    extra=["<< /FT /Btn /Ff 32768 /V (B) /Opt [(A) (B)] /Kids [5 0 R 6 0 R] >>"],
  )
  assert_eq(
    radio.annotations.map(annotation => {
      (annotation.button_value, annotation.button_checked)
    }),
    [(Some("A"), Some(false)), (Some("B"), Some(true))],
  )
  let push = field_layout_document(
    "<< /Subtype /Widget /Rect [0 0 80 20] /FT /Btn /Ff 65536 /MK << /CA (Proceed) >> >>",
  )
  assert_true(field_layout_ops(push).contains(@content.Op_Tj(b"Proceed")))
  assert_true(push.page(1).unwrap().annotations[0].appearance is Some(_))
}

///|
test "empty normal AP suppresses field-generated appearance" {
  let document = field_layout_document(
    "<< /Subtype /Widget /Rect [0 0 80 20] /FT /Tx /V (Secret) /AP << /N 6 0 R >> >>",
    extra=[annotation_test_stream("/BBox [0 0 80 20]", "")],
  )
  let appearance = document.page(1).unwrap().annotations[0].appearance.unwrap()
  assert_true(!appearance.svg.contains("Secret"))
  assert_true(!appearance.svg.contains("data-pdf-font-outline"))
}

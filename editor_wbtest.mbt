///|
test "editor saves Unicode FreeText highlight and ink with portable AP and preserves source" {
  let source = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << >> >>",
    annotation_test_stream("", ""),
  ])
  let changes : Json = [
    {
      "kind": "add",
      "id": "new:text",
      "page": 1,
      "subtype": "FreeText",
      "bounds": [10, 20, 130, 60],
      "contents": "你好 MoonBit 🌙",
      "size": 14,
      "color": [0, 0, 0],
    },
    {
      "kind": "add",
      "id": "new:highlight",
      "page": 1,
      "subtype": "Highlight",
      "bounds": [10, 80, 90, 100],
      "color": [1, 1, 0],
    },
    {
      "kind": "add",
      "id": "new:ink",
      "page": 1,
      "subtype": "Ink",
      "bounds": [10, 120, 100, 170],
      "paths": [[[15, 125], [30, 160], [80, 140]]],
      "size": 2,
      "color": [0, 0, 1],
    },
  ]
  let edited = source.with_editor_changes(changes)
  assert_eq(source.page(1).unwrap().annotations.length(), 0)
  assert_eq(edited.page(1).unwrap().annotations.length(), 3)
  let reopened = open_document(edited.save_bytes())
  let page = reopened.page(1).unwrap()
  assert_eq(page.annotations[0].contents, Some("你好 MoonBit 🌙"))
  let text = pdf_edit_annots(reopened.document, reopened.pages[0].rest)[0]
  assert_eq(
    reopened.document.lookup_direct(pdf_name_key("/C"), text),
    Some(@syntax.PdfArray([])),
  )
  let ap = reopened.document.lookup_direct(pdf_name_key("/AP"), text).unwrap()
  let normal = reopened.document.lookup_direct(pdf_name_key("/N"), ap).unwrap()
  assert_true(
    !@pdflite.pdf_parse_content_ops_from_bytes(normal.stream_bytes()).contains(
      @content.Op_f,
    ),
  )
  if !page.annotations.all(annotation => annotation.appearance is Some(_)) {
    fail(
      @debug.to_string(
        page.annotations.map(annotation => {
          (annotation.subtype, annotation.appearance is Some(_))
        }),
      ),
    )
  }
  assert_eq(page.annotations[2].ink_paths[0][1], { x: 30.0, y: 160.0, })
  assert_true(reopened.render_svg(1).unwrap().contains("<svg"))
  assert_eq(
    source.with_editor_changes([]).page(1).unwrap().annotations.length(),
    0,
  )
}

///|
test "editor deletes popup children and keeps direct annotation identities after compaction" {
  let source = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> /Annots [4 0 R 5 0 R << /Subtype /Text /Rect [90 90 110 110] /Contents (Direct) >>] >>",
    "<< /Subtype /Text /Rect [10 10 30 30] /Contents (First) /Popup 5 0 R >>", "<< /Subtype /Popup /Rect [20 20 70 70] /Parent 4 0 R >>",
  ])
  let edited = source.with_editor_changes([
    { "kind": "delete", "id": "object:4", "page": 1 },
  ])
  assert_eq(edited.page(1).unwrap().annotations.length(), 1)
  assert_eq(pdf_edit_annots(edited.document, edited.pages[0].rest).length(), 1)
  let manifest = edited.editor_page_json(1).unwrap()
  guard manifest is Array([entry]) else { fail("unexpected editor manifest") }
  assert_eq(pdf_edit_string(entry, "id"), "page:1:index:2")
  let next = edited.with_editor_changes([
    {
      "kind": "update",
      "id": "page:1:index:2",
      "page": 1,
      "contents": "Revised",
    },
  ])
  let reopened = open_document(next.save_bytes())
  assert_eq(reopened.page(1).unwrap().annotations[0].contents, Some("Revised"))
  assert_eq(source.page(1).unwrap().annotations.length(), 2)
}

///|
test "editor preserves multiline highlights ink colours and stroke widths during geometry edits" {
  let source = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> /Annots [4 0 R 5 0 R 6 0 R] >>",
    "<< /Subtype /Highlight /Rect [0 0 100 40] /C [1 0 0] /QuadPoints [0 40 100 40 0 25 100 25 0 15 70 15 0 0 70 0] >>",
    "<< /Subtype /Ink /Rect [0 50 100 100] /C [0 1 0] /BS << /W 3 >> /InkList [[0 50 100 100]] >>",
    "<< /Subtype /FreeText /Rect [0 120 100 160] /Contents (Before) /C [1 1 0] /DA (/Helv 12 Tf 0 g) >>",
  ])
  let edited = source.with_editor_changes([
    {
      "kind": "update",
      "id": "object:4",
      "page": 1,
      "bounds": [20, 10, 120, 50],
    },
    {
      "kind": "update",
      "id": "object:5",
      "page": 1,
      "bounds": [20, 70, 120, 120],
    },
    {
      "kind": "update",
      "id": "object:6",
      "page": 1,
      "contents": "After",
      "color": [0, 0, 1],
    },
  ])
  let reopened = open_document(edited.save_bytes())
  let annotations = reopened.page(1).unwrap().annotations
  assert_eq(annotations[0].quad_points.length(), 2)
  assert_eq(annotations[0].quad_points[1].p0, { x: 20.0, y: 10.0, })
  assert_eq(
    reopened.document.read_annotation(@syntax.PdfIndirect(5)).border.width,
    3.0,
  )
  assert_eq(annotations[1].color, Some("#00FF00"))
  let ink = reopened.document.lookup_object_or_null(5)
  let ap = reopened.document.lookup_direct(pdf_name_key("/AP"), ink).unwrap()
  let normal = reopened.document.lookup_direct(pdf_name_key("/N"), ap).unwrap()
  let ops = @pdflite.pdf_parse_content_ops_from_bytes(normal.stream_bytes())
  assert_true(ops.contains(@content.Op_RG(0.0, 1.0, 0.0)))
  assert_true(ops.contains(@content.Op_w(3.0)))
  assert_eq(
    reopened.document.lookup_direct(pdf_name_key("/C"), @syntax.PdfIndirect(6)),
    Some(
      @syntax.PdfArray([
        @syntax.PdfInteger(1),
        @syntax.PdfInteger(1),
        @syntax.PdfInteger(0),
      ]),
    ),
  )
  assert_eq(
    pdf_edit_text_color(reopened.document, @syntax.PdfIndirect(6)),
    Some("#0000FF"),
  )
}

///|
test "editor respects annotation locks encrypted sources and anonymous direct widget identity" {
  let source = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> /Annots [4 0 R << /Subtype /Widget /Rect [0 20 100 40] /FT /Tx /V (old) >> << /Subtype /Widget /Rect [0 20 100 40] /FT /Tx /V (old) >>] >>",
    "<< /Subtype /Text /Rect [0 50 20 70] /F 128 /Contents (Locked) >>",
  ])
  let bytes = @pdflite.pdf_write_encrypted_40bit_document(
    source.document,
    @utf8.encode("user-password"),
    @utf8.encode("owner-password"),
    [],
    file_id=b"editor-encrypted",
  )
  let encrypted = open_document_with_passwords(
    bytes,
    user_password=Some(@utf8.encode("user-password")),
  )
  assert_true((try? encrypted.with_editor_changes([])) is Err(_))
  assert_true((try? encrypted.save_bytes()) is Err(_))
  assert_true(
    (try? source.with_editor_changes([
      { "kind": "delete", "id": "object:4", "page": 1 },
    ]))
    is Err(_),
  )
  let edited = source.with_editor_changes([
    { "kind": "field", "id": "page:1:index:1", "page": 1, "values": ["new"] },
  ])
  assert_eq(
    edited.page(1).unwrap().annotations.map(annotation => annotation.field_value),
    [None, Some("new"), Some("old")],
  )
}

///|
test "editor fills inherited shared text widgets on two pages and persists explicit AP" {
  let source = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [5 0 R] /DA (/Helv 12 Tf 0 g) >> >>",
    "<< /Type /Pages /Count 2 /Kids [3 0 R 4 0 R] >>", "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> /Annots [6 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> /Annots [7 0 R] >>",
    "<< /FT /Tx /T (person) /V (old) /Kids [6 0 R 7 0 R] >>", "<< /Subtype /Widget /Rect [10 20 130 45] /Parent 5 0 R >>",
    "<< /Subtype /Widget /Rect [20 50 140 75] /Parent 5 0 R >>",
  ])
  let edited = source.with_editor_changes([
    { "kind": "field", "id": "object:6", "page": 1, "values": ["New value"] },
  ]) catch {
    error => fail(@debug.to_string(error))
  }
  let reopened = open_document(edited.save_bytes())
  for number in 1..<=2 {
    let field = reopened.page(number).unwrap().annotations[0]
    assert_eq(field.field_value, Some("New value"))
    assert_true(field.appearance is Some(_))
  }
  assert_eq(source.page(1).unwrap().annotations[0].field_value, Some("old"))
}

///|
test "editor choice stores export values sorted selection indices and readonly constraints" {
  let source = field_layout_document(
    "<< /Subtype /Widget /Rect [0 0 100 60] /FT /Ch /T (choices) /Ff 2097152 /Opt [[(B) (Beta)] [(A) (Alpha)] [(C) (Gamma)]] /V [(B)] /I [0] >>",
  )
  let edited = source.with_editor_changes([
    { "kind": "field", "id": "object:5", "page": 1, "values": ["C", "A"] },
  ])
  let reopened = open_document(edited.save_bytes())
  let widget = reopened.document.lookup_object_or_null(5)
  assert_eq(
    reopened.document.lookup_direct(pdf_name_key("/I"), widget),
    Some(@syntax.PdfArray([@syntax.PdfInteger(1), @syntax.PdfInteger(2)])),
  )
  assert_eq(
    pdf_annotation_choice_options(reopened.document, widget)
    .filter(option => option.selected)
    .map(option => option.export_value),
    ["A", "C"],
  )
  assert_true(
    (try? source.with_editor_changes([
      { "kind": "field", "id": "object:5", "page": 1, "values": ["unknown"] },
    ]))
    is Err(_),
  )
  let fixed_field = field_layout_document(
    "<< /Subtype /Widget /Rect [0 0 100 30] /FT /Tx /Ff 1 /V (fixed) >>",
  )
  assert_true(
    (try? fixed_field.with_editor_changes([
      { "kind": "field", "id": "object:5", "page": 1, "values": ["changed"] },
    ]))
    is Err(_),
  )
  let limited = field_layout_document(
    "<< /Subtype /Widget /Rect [0 0 100 30] /FT /Tx /MaxLen 2 >>",
  )
  assert_true(
    (try? limited.with_editor_changes([
      { "kind": "field", "id": "object:5", "page": 1, "values": ["long"] },
    ]))
    is Err(_),
  )
}

///|
test "editor choice indices disambiguate duplicate exports and reject mismatched values" {
  let source = field_layout_document(
    "<< /Subtype /Widget /Rect [0 0 100 30] /FT /Ch /T (duplicate) /Ff 131072 /Opt [[(D) (First)] [(D) (Second)] [(X) (Other)]] /V (D) /I [0] >>",
  )
  let edited = source.with_editor_changes([
    {
      "kind": "field",
      "id": "object:5",
      "page": 1,
      "values": ["D"],
      "indices": [1],
    },
  ])
  let reopened = open_document(edited.save_bytes())
  let widget = reopened.document.lookup_object_or_null(5)
  assert_eq(
    pdf_annotation_choice_options(reopened.document, widget)
    .filter(option => option.selected)
    .map(option => option.display_value),
    ["Second"],
  )
  assert_true(
    (try? source.with_editor_changes([
      {
        "kind": "field",
        "id": "object:5",
        "page": 1,
        "values": ["X"],
        "indices": [1],
      },
    ]))
    is Err(_),
  )
  assert_true(
    (try? source.with_editor_changes([
      {
        "kind": "field",
        "id": "object:5",
        "page": 1,
        "values": ["D"],
        "indices": [-1],
      },
    ]))
    is Err(_),
  )
}

///|
test "editor radio group updates sibling AS and preserves on Off appearances after save" {
  let source = annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [4 0 R] >> >>", "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> /Annots [5 0 R 6 0 R] >>",
    "<< /FT /Btn /Ff 32768 /T (radio) /V /A /Kids [5 0 R 6 0 R] /Opt [(A) (B)] >>",
    "<< /Subtype /Widget /Rect [10 10 30 30] /Parent 4 0 R /AS /A >>", "<< /Subtype /Widget /Rect [40 10 60 30] /Parent 4 0 R /AS /Off >>",
  ])
  let edited = source.with_editor_changes([
    { "kind": "field", "id": "object:6", "page": 1, "values": ["B"] },
  ]) catch {
    error => fail(@debug.to_string(error))
  }
  let reopened = open_document(edited.save_bytes())
  let fields = reopened.page(1).unwrap().annotations
  assert_eq(fields.map(field => field.button_checked), [Some(false), Some(true)])
  assert_eq(fields.map(field => field.field_value), [Some("B"), Some("B")])
}

///|
test "editor image signature stores RGB soft mask and reopens with the same bounds" {
  let source = field_layout_document(
    "<< /Subtype /Widget /Rect [0 0 100 30] /FT /Tx >>",
  )
  let rgba : Bytes = b"\xff\x00\x00\xff\x00\x00\xff\x80"
  let patch : Json = {
    "kind": "add",
    "id": "new:signature",
    "page": 1,
    "subtype": "Stamp",
    "bounds": [20, 70, 100, 110],
    "image": { "width": 2, "height": 1, "rgba": @base64.encode(rgba) },
    "contents": "Signature",
  }
  let reopened = open_document(source.with_editor_changes([patch]).save_bytes())
  let signature = reopened.page(1).unwrap().annotations[1]
  assert_eq(signature.bounds, {
    min_x: 20.0,
    min_y: 70.0,
    max_x: 100.0,
    max_y: 110.0,
  })
  assert_true(signature.appearance is Some(_))
  let streams = reopened.document.objects.stream_entries()
  assert_true(
    streams.any(entry => {
      reopened.document.lookup_direct(
        pdf_name_key("/ColorSpace"),
        @syntax.PdfStreamObject(entry.2),
      ) ==
      Some(@syntax.PdfNameObject(pdf_name_key("/DeviceGray")))
    }),
  )
}

///|
test "editor rejects invalid patches atomically and scales existing ink when moved" {
  let source = field_layout_document(
    "<< /Subtype /Widget /Rect [0 0 100 30] /FT /Tx /V (original) >>",
  )
  assert_true(
    (try? source.with_editor_changes([
      { "kind": "field", "id": "object:5", "page": 1, "values": ["mutated"] },
      { "kind": "delete", "id": "object:999", "page": 1 },
    ]))
    is Err(_),
  )
  assert_eq(
    source.page(1).unwrap().annotations[0].field_value,
    Some("original"),
  )
  let first = source.with_editor_changes([
    {
      "kind": "add",
      "id": "new:ink",
      "page": 1,
      "subtype": "Ink",
      "bounds": [0, 50, 100, 100],
      "paths": [[[0, 50], [100, 100]]],
      "size": 2,
    },
  ])
  let moved = first.with_editor_changes([
    {
      "kind": "update",
      "id": "new:ink",
      "page": 1,
      "bounds": [20, 70, 220, 170],
      "size": 2,
    },
  ])
  assert_eq(moved.page(1).unwrap().annotations[1].ink_paths[0], [
    { x: 20.0, y: 70.0, },
    { x: 220.0, y: 170.0, },
  ])
  assert_true(
    (try? source.with_editor_changes([
      {
        "kind": "add",
        "id": "new:bad",
        "page": 1,
        "subtype": "Stamp",
        "bounds": [1, 2, 3, 4],
        "image": { "width": 4096, "height": 4096, "rgba": "" },
      },
    ]))
    is Err(_),
  )
}

///|
fn layer_test_document(config? : String = "") -> PdfViewerDocument raise {
  annotation_test_document([
    "<< /Type /Catalog /Pages 2 0 R /OCProperties << /OCGs [6 0 R 7 0 R 8 0 R 9 0 R 10 0 R] /D << /Name (Default) /BaseState /ON /OFF [7 0 R] /RBGroups [[6 0 R 7 0 R]] /Locked [10 0 R] /Order [(ignored) [<FEFF56FE5C42> 6 0 R [(Nested) 7 0 R]] 8 0 R 9 0 R] \{config} >> /Configs [<< /Name (Alternative) /BaseState /OFF /ON [7 0 R 10 0 R] /RBGroups [[6 0 R 7 0 R]] /Locked [10 0 R] >> << /Name (Locked radio) /ON [6 0 R] /OFF [7 0 R] /RBGroups [[6 0 R 7 0 R]] /Locked [6 0 R] >>] >> /AcroForm << /Fields [12 0 R] >> >>",
    "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Font << /F 5 0 R >> /Properties << /A 6 0 R /B 7 0 R /Screen 8 0 R /Paper 9 0 R /Member 14 0 R >> /XObject << /Form 13 0 R >> >> /Annots [11 0 R 12 0 R] >>",
    annotation_test_stream(
      "", "/OC /A BDC BT /F 12 Tf 10 170 Td (Alpha) Tj ET EMC /OC /B BDC BT /F 12 Tf 10 150 Td (Beta) Tj ET 1 0 0 rg 10 10 20 20 re f EMC /OC /Screen BDC BT /F 12 Tf 10 130 Td (Screen) Tj ET EMC /OC /Paper BDC BT /F 12 Tf 10 110 Td (Paper) Tj ET EMC /OC /Member BDC BT /F 12 Tf 10 90 Td (Member) Tj ET EMC /Form Do",
    ),
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    "<< /Type /OCG /Name <FEFF4E2D6587> >>",
    "<< /Type /OCG /Name (Beta) >>",
    "<< /Type /OCG /Name (Screen) /Usage << /View << /ViewState /ON >> /Print << /PrintState /OFF >> >> >>",
    "<< /Type /OCG /Name (Paper) /Usage << /View << /ViewState /OFF >> /Print << /PrintState /ON >> /Export << /ExportState /OFF >> >> >>",
    "<< /Type /OCG /Name (Locked) >>",
    "<< /Subtype /Text /Rect [10 50 30 70] /Contents (Layer note) /F 4 /OC 7 0 R >>",
    "<< /Subtype /Widget /FT /Tx /T (layer-field) /V (Before) /Rect [40 50 170 70] /F 4 /OC 7 0 R >>",
    annotation_test_stream(
      "/Type /XObject /Subtype /Form /BBox [0 0 200 200] /OC 7 0 R /Resources << /Font << /F 5 0 R >> >>",
      "BT /F 12 Tf 10 80 Td (Form) Tj ET",
    ),
    "<< /Type /OCMD /OCGs [6 0 R 7 0 R] /VE [/And 6 0 R [/Not 7 0 R]] >>",
  ])
}

///|
test "layer usage separates display print and export content" {
  let source = layer_test_document()
  let screen = source.page(1).unwrap()
  let paper = source.page(1, optional_content_intent=Print).unwrap()
  assert_true(screen.text.contains("Alpha") && screen.text.contains("Screen"))
  assert_true(!screen.text.contains("Beta") && !screen.text.contains("Paper"))
  assert_true(paper.text.contains("Alpha") && paper.text.contains("Paper"))
  assert_true(!paper.text.contains("Screen"))
  assert_true(
    !source.pages(optional_content_intent=Export)[0].text.contains("Paper"),
  )
  let enabled = source.with_optional_content_visibility(9, true)
  assert_true(enabled.page(1).unwrap().text.contains("Paper"))
  assert_true(
    enabled.page(1, optional_content_intent=Export).unwrap().text.contains(
      "Paper",
    ),
  )
  let disabled = enabled.with_optional_content_visibility(9, false)
  assert_true(
    !disabled.page(1, optional_content_intent=Print).unwrap().text.contains(
      "Paper",
    ),
  )
  assert_true(!source.page(1).unwrap().text.contains("Paper"))
}

///|
test "layer radio buttons update immutable states and OCMD expressions" {
  let source = layer_test_document()
  assert_true(source.page(1).unwrap().text.contains("Member"))
  let beta = source.with_optional_content_visibility(7, true)
  assert_true(beta.page(1).unwrap().text.contains("Beta"))
  assert_true(!beta.page(1).unwrap().text.contains("Alpha"))
  assert_true(!beta.page(1).unwrap().text.contains("Member"))
  assert_true(
    !beta.page(1, optional_content_intent=Print).unwrap().text.contains(
      "Member",
    ),
  )
  let alpha = beta.with_optional_content_visibility(6, true)
  assert_true(alpha.page(1).unwrap().text.contains("Alpha"))
  assert_true(!alpha.page(1).unwrap().text.contains("Beta"))
  assert_true(source.page(1).unwrap().text.contains("Alpha"))
}

///|
test "hidden layers remove form paths annotations and native controls with stable IDs" {
  let source = layer_test_document()
  assert_eq(source.page(1).unwrap().annotations.length(), 0)
  assert_eq(source.annotation_layer_json(1), Some(Json::array([])))
  assert_eq(source.editor_page_json(1), Some(Json::array([])))
  let visible = source.with_optional_content_visibility(7, true)
  let page = visible.page(1).unwrap()
  assert_eq(page.annotations.length(), 2)
  assert_true(page.text.contains("Form"))
  assert_true(page.items.any(item => item is Path(_)))
  assert_true(!source.page(1).unwrap().items.any(item => item is Path(_)))
  guard visible.editor_page_json(1) is Some(Array([note, field])) else {
    fail("Missing layer controls")
  }
  assert_eq(pdf_edit_string(note, "id"), "object:11")
  assert_eq(pdf_edit_string(field, "id"), "object:12")
  assert_eq(pdf_edit_string(field, "field_name"), "layer-field")
}

///|
test "layer configuration resets overrides and validates selection" {
  let source = layer_test_document()
  let beta = source.with_optional_content_visibility(7, true)
  let reset = beta.with_optional_content_config(None)
  assert_true(reset.page(1).unwrap().text.contains("Alpha"))
  assert_true(!reset.page(1).unwrap().text.contains("Beta"))
  let alternative = reset.with_optional_content_config(Some(0))
  assert_true(alternative.page(1).unwrap().text.contains("Beta"))
  assert_true(!alternative.page(1).unwrap().text.contains("Screen"))
  assert_true(
    (Some(source.with_optional_content_config(Some(2))) catch { _ => None })
    is None,
  )
  assert_true(
    (Some(source.with_optional_content_config(Some(-1))) catch { _ => None })
    is None,
  )
}

///|
test "locked layer and locked radio peer reject changes atomically" {
  let source = layer_test_document()
  assert_true(
    (Some(source.with_optional_content_visibility(10, false)) catch {
      _ => None
    })
    is None,
  )
  assert_true(
    (Some(source.with_optional_content_visibility(999, false)) catch {
      _ => None
    })
    is None,
  )
  let locked = source.with_optional_content_config(Some(1))
  let before = locked.optional_content_layers_json()
  assert_true(
    (Some(locked.with_optional_content_visibility(7, true)) catch { _ => None })
    is None,
  )
  assert_eq(locked.optional_content_layers_json(), before)
  assert_true(locked.page(1).unwrap().text.contains("Alpha"))
}

///|
test "layer panel preserves Unicode nested order and appends omitted groups" {
  let source = layer_test_document()
  guard source.optional_content_layers_json() is Some(Object(fields)) else {
    fail("Missing layers")
  }
  guard fields.get("groups") is Some(Array([Object(first), ..])) else {
    fail("Missing groups")
  }
  assert_eq(first.get("name"), Some(Json::string("中文")))
  assert_eq(fields.get("config_index"), Some(Json::null()))
  assert_eq(
    fields.get("order"),
    Some(
      (
        [
          {
            "name": "图层",
            "children": [
              { "id": 6 },
              { "name": "Nested", "children": [{ "id": 7 }] },
            ],
          },
          { "id": 8 },
          { "id": 9 },
          { "name": "", "children": [{ "id": 10 }] },
        ] : Json),
    ),
  )
  guard source
    .with_optional_content_config(Some(0))
    .optional_content_layers_json()
    is Some(Object(alternate)) else {
    fail("Missing alternate configuration")
  }
  assert_eq(alternate.get("config_index"), Some(Json::number(0)))
}

///|
test "layer OFF precedence matches PDF.js and bounds recursive order" {
  let source = layer_test_document()
  let catalog = source.document.lookup_object_or_null(source.document.root())
  let properties = source.document
    .lookup_direct(pdf_name_key("/OCProperties"), catalog)
    .unwrap()
  let config = source.document
    .lookup_direct(pdf_name_key("/D"), properties)
    .unwrap()
    .add_dict_entry(
      pdf_name_key("/ON"),
      @syntax.PdfArray([@syntax.PdfIndirect(6)]),
    )
    .add_dict_entry(
      pdf_name_key("/OFF"),
      @syntax.PdfArray([@syntax.PdfIndirect(6), @syntax.PdfIndirect(7)]),
    )
    .add_dict_entry(
      pdf_name_key("/Order"),
      @syntax.PdfArray([@syntax.PdfIndirect(15)]),
    )
  source.document.add_object_given_number(
    source.document.root(),
    catalog.add_dict_entry(
      pdf_name_key("/OCProperties"),
      properties.add_dict_entry(pdf_name_key("/D"), config),
    ),
  )
  assert_true(!source.page(1).unwrap().text.contains("Alpha"))
  // Unknown/cyclic order links cannot suppress the complete group list.
  source.document.add_object_given_number(
    15,
    @syntax.PdfArray([@syntax.PdfIndirect(15)]),
  )
  guard source.optional_content_layers_json() is Some(Object(fields)) else {
    fail("Missing layers")
  }
  assert_eq(
    fields.get("order"),
    Some(
      (
        [
          {
            "name": "",
            "children": [
              { "id": 6 },
              { "id": 7 },
              { "id": 8 },
              { "id": 9 },
              { "id": 10 },
            ],
          },
        ] : Json),
    ),
  )
}

///|
test "editing snapshots keep layer selection without rewriting original configuration" {
  let source = layer_test_document()
  let selected = source.with_optional_content_visibility(7, true)
  let changed = selected.with_editor_changes([
    {
      "kind": "field",
      "id": "object:12",
      "page": 1,
      "field_name": "layer-field",
      "values": ["After"],
    },
  ])
  assert_eq(changed.optional_content_state(), selected.optional_content_state())
  assert_true(changed.page(1).unwrap().text.contains("Beta"))
  let reopened = open_document(changed.save_bytes())
  assert_true(reopened.page(1).unwrap().text.contains("Alpha"))
  assert_eq(reopened.page(1).unwrap().annotations.length(), 0)
  let restored = reopened.with_optional_content_visibility(7, true)
  guard restored.editor_page_json(1) is Some(Array([_, entry])) else {
    fail("Missing edited field")
  }
  assert_eq(pdf_edit_entry(entry, "values"), (["After"] : Json))
}

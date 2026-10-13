///|
fn pdf_edit_field_owner(
  document : @pdflite.PdfDocument,
  widget : @syntax.PdfObject,
) -> @syntax.PdfObject raise @core.PdfError {
  let mut current = widget
  let seen : Array[@syntax.PdfObject] = []
  for _ in 0..<64 {
    if seen.contains(current) {
      raise @core.SoftError("Cyclic form field parent")
    }
    seen.push(current)
    if document.lookup_direct(pdf_name_key("/Subtype"), current) ==
      Some(@syntax.PdfNameObject(pdf_name_key("/Widget"))) &&
      document.lookup_direct(pdf_name_key("/T"), current) is None &&
      document.direct(current).lookup_immediate(pdf_name_key("/Parent"))
      is Some(parent) {
      current = parent
      continue
    }
    if document.lookup_direct(pdf_name_key("/T"), current) is Some(_) ||
      document.lookup_direct(pdf_name_key("/FT"), current) is Some(_) {
      return current
    }
    match document.direct(current).lookup_immediate(pdf_name_key("/Parent")) {
      Some(parent) => current = parent
      None => return current
    }
  }
  raise @core.SoftError("Form field parent chain is too deep")
}

///|
fn pdf_edit_field(
  document : @pdflite.PdfDocument,
  source : PdfViewerDocument,
  patch : Json,
) -> Unit raise @core.PdfError {
  let page = pdf_edit_int(patch, "page")
  let id = pdf_edit_string(patch, "id")
  let annots = pdf_edit_annots(source.document, source.pages[page - 1].rest)
  let mut widget : @syntax.PdfObject? = None
  for index, raw in annots {
    if pdf_edit_id(source.document, raw, page, index) == id {
      widget = Some(raw)
      break
    }
  }
  guard widget is Some(widget) else {
    raise @core.SoftError("Form widget does not exist")
  }
  if document.lookup_direct(pdf_name_key("/Subtype"), widget) !=
    Some(@syntax.PdfNameObject(pdf_name_key("/Widget"))) {
    raise @core.SoftError("Expected a form widget")
  }
  let flags = pdf_annotation_field_flags(document, widget).unwrap_or(0)
  if (flags & 1) != 0 {
    raise @core.SoftError("This form field is readonly")
  }
  let field_type = pdf_annotation_field_name(document, widget, "/FT").unwrap_or(
    "",
  )
  if (field_type != "Tx" && field_type != "Ch" && field_type != "Btn") ||
    (field_type == "Btn" && (flags & 65536) != 0) {
    raise @core.SoftError("This field type cannot be filled")
  }
  guard pdf_edit_entry(patch, "values") is Array(entries) &&
    entries.length() <= 10000 else {
    raise @core.SoftError("Field values must be an array")
  }
  let values = entries.map(value => {
    guard value is String(value) && value.length() <= 65536 else {
      raise @core.SoftError("Invalid field value")
    }
    value
  })
  if field_type != "Ch" || (flags & 2097152) == 0 {
    if values.length() != 1 {
      raise @core.SoftError("Expected one field value")
    }
  }
  if field_type == "Tx" {
    let max = pdf_annotation_field_lookup(document, widget, "/MaxLen", 0)
      .bind(value => {
        match value {
          @syntax.PdfInteger(n) => Some(n)
          _ => None
        }
      })
      .unwrap_or(0)
    if max > 0 && values[0].iter().count() > max {
      raise @core.SoftError("Text exceeds field MaxLen")
    }
  }
  let owner = pdf_edit_field_owner(document, widget)
  let mut field = document.direct(owner)
  let choices = pdf_annotation_choice_options(document, widget)
  let indices : Array[Int] = []
  if field_type == "Ch" {
    if pdf_edit_entry(patch, "indices") is Array(selected) {
      if selected.length() != values.length() {
        raise @core.SoftError("Choice indices must match values")
      }
      for position, selected in selected {
        let number = pdf_edit_number(selected)
        let index = number.to_int()
        if number != number.trunc() || indices.contains(index) {
          raise @core.SoftError("Invalid choice selection index")
        }
        guard choices.filter(choice => choice.index == index).get(0)
          is Some(choice) &&
          choice.export_value == values[position] else {
          raise @core.SoftError("Choice index does not match export value")
        }
        indices.push(index)
      }
    } else {
      for value in values {
        match choices.filter(choice => choice.export_value == value).get(0) {
          Some(choice) => indices.push(choice.index)
          None =>
            if (flags & 131072) == 0 || (flags & 262144) == 0 {
              raise @core.SoftError("Unknown choice export value")
            }
        }
      }
    }
    indices.sort()
    field = field.add_dict_entry(
      pdf_name_key("/I"),
      @syntax.PdfArray(indices.map(index => @syntax.PdfInteger(index))),
    )
  }
  let value = if field_type == "Btn" {
    let on = pdf_annotation_button_state(document, widget).0.unwrap_or("Yes")
    if values[0] != "Off" && values[0] != on {
      raise @core.SoftError("Unknown button appearance state")
    }
    if (flags & 32768) != 0 && (flags & 16384) != 0 && values[0] == "Off" {
      raise @core.SoftError("This radio group requires a selection")
    }
    @syntax.PdfNameObject(pdf_name_key("/" + values[0]))
  } else if field_type == "Ch" && (flags & 2097152) != 0 {
    @syntax.PdfArray(values.map(value => pdf_edit_pdf_string(value)))
  } else {
    pdf_edit_pdf_string(values[0])
  }
  field = field.add_dict_entry(pdf_name_key("/V"), value)
  if !(owner is @syntax.PdfIndirect(_)) && owner != widget {
    raise @core.SoftError("Direct shared field parents cannot be updated")
  }
  ignore(pdf_edit_replace(document, owner, field))
  // Visit all pages because multiple widgets can belong to the same field.
  for page_index, source_page in source.pages {
    let number = document.page_object_number(page_index + 1).unwrap()
    let raw_page = document.lookup_object_or_null(number)
    let current_annots = pdf_edit_annots(document, raw_page)
    let mut changed = false
    let updated : Array[@syntax.PdfObject] = []
    for index, raw in current_annots {
      if document.lookup_direct(pdf_name_key("/Subtype"), raw) !=
        Some(@syntax.PdfNameObject(pdf_name_key("/Widget"))) {
        updated.push(raw)
        continue
      }
      let same = if owner is @syntax.PdfIndirect(_) {
        pdf_edit_field_owner(document, raw) == owner
      } else {
        page_index + 1 == page && pdf_edit_id(document, raw, page, index) == id
      }
      if !same {
        updated.push(raw)
        continue
      }
      let mut object = if raw == owner { field } else { document.direct(raw) }
      // A widget-local V must not shadow the newly written inherited value.
      if raw != owner {
        object = object.remove_dict_entry(pdf_name_key("/V"))
        object = object.remove_dict_entry(pdf_name_key("/I"))
      }
      if field_type == "Btn" {
        let on = pdf_annotation_button_state(document, object).0.unwrap_or(
          "Yes",
        )
        let checked = values[0] != "Off" && values[0] == on
        object = object.add_dict_entry(
          pdf_name_key("/AS"),
          @syntax.PdfNameObject(
            pdf_name_key(if checked { "/" + on } else { "/Off" }),
          ),
        )
        if document.lookup_direct(pdf_name_key("/AP"), object) is None {
          let rectangle = document.read_annotation(object).rectangle
          let w = rectangle.max_x - rectangle.min_x
          let h = rectangle.max_y - rectangle.min_y
          let off = pdf_edit_form(w, h, @syntax.pdf_dictionary([]), [])
          let on_ap = pdf_edit_form(w, h, @syntax.pdf_dictionary([]), [
            @content.Op_w(1.5),
            @content.Op_m(w * 0.2, h * 0.5),
            @content.Op_l(w * 0.45, h * 0.25),
            @content.Op_l(w * 0.8, h * 0.8),
            @content.Op_S,
          ])
          object = object.add_dict_entry(
            pdf_name_key("/AP"),
            @syntax.pdf_dictionary([
              (
                pdf_name_key("/N"),
                @syntax.pdf_dictionary([
                  (
                    pdf_name_key("/Off"),
                    @syntax.PdfIndirect(pdf_edit_install_ap(document, off)),
                  ),
                  (
                    pdf_name_key("/" + on),
                    @syntax.PdfIndirect(pdf_edit_install_ap(document, on_ap)),
                  ),
                ]),
              ),
            ]),
          )
        }
      } else {
        object = object.remove_dict_entry(pdf_name_key("/AP"))
        let rectangle = document.read_annotation(object).rectangle
        let native = pdf_annotation_generated_appearance(
          document,
          object,
          rectangle,
          require_encoding=pdf_edit_entry(patch, "image") != Json::null(),
        )
        let ap = if native is Some(native) {
          native
        } else if pdf_edit_entry(patch, "image") != Json::null() &&
          field_type == "Tx" {
          pdf_edit_image_appearance(document, pdf_edit_entry(patch, "image"), {
            min_x: rectangle.min_x,
            min_y: rectangle.min_y,
            max_x: rectangle.max_x,
            max_y: rectangle.max_y,
          })
        } else {
          raise @core.SoftError("Unable to generate field appearance")
        }
        object = object.add_dict_entry(
          pdf_name_key("/AP"),
          @syntax.pdf_dictionary([
            (
              pdf_name_key("/N"),
              @syntax.PdfIndirect(pdf_edit_install_ap(document, ap)),
            ),
          ]),
        )
      }
      updated.push(pdf_edit_replace(document, raw, object))
      changed = true
    }
    if changed {
      pdf_edit_replace_number(
        document,
        number,
        raw_page.add_dict_entry(
          pdf_name_key("/Annots"),
          @syntax.PdfArray(updated),
        ),
      )
    }
    ignore(source_page)
  }
}

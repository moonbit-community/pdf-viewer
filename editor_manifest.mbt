///|
/// Editable native control metadata. No PDF actions or scripts are executed.
pub fn PdfViewerDocument::editor_page_json(
  self : PdfViewerDocument,
  number : Int,
) -> Json? {
  guard number >= 1 && number <= self.pages.length() else { return None }
  let document = self.document
  let permissions = self.editor_permissions()
  let output : Array[Json] = []
  for index, raw in pdf_edit_annots(document, self.pages[number - 1].rest) {
    let annotation = document.read_annotation(raw) catch { _ => continue }
    let subtype = pdf_annotation_subtype_name(annotation.subtype)
    if subtype == "link" || subtype == "popup" {
      continue
    }
    let rect = annotation.rectangle
    let flags = pdf_annotation_flags(document, raw)
    if !pdf_annotation_is_visible(flags) {
      continue
    }
    let field_type = pdf_annotation_field_name(document, raw, "/FT").unwrap_or(
      "",
    )
    let field_flags = pdf_annotation_field_flags(document, raw).unwrap_or(0)
    let values = match pdf_annotation_field_lookup(document, raw, "/V", 0) {
      Some(@syntax.PdfArray(values)) =>
        values.filter_map(value => pdf_annotation_field_scalar(document, value))
      Some(value) =>
        [pdf_annotation_field_scalar(document, value).unwrap_or("")]
      None => [pdf_annotation_field_value(document, raw).unwrap_or("")]
    }
    let (on, checked) = pdf_annotation_button_state(document, raw)
    let max_length = match
      pdf_annotation_field_lookup(document, raw, "/MaxLen", 0) {
      Some(@syntax.PdfInteger(n)) => n
      _ => 0
    }
    let editable = if subtype == "widget" {
      (
        field_type == "Tx" ||
        field_type == "Ch" ||
        (field_type == "Btn" && (field_flags & 65536) == 0)
      ) &&
      (field_flags & 1) == 0 &&
      permissions.forms
    } else {
      (flags & 704) == 0 && permissions.annotations
    }
    let color = if subtype == "free-text" {
      pdf_edit_text_color(document, raw)
    } else {
      pdf_annotation_color(document, raw)
    }
    output.push({
      "id": pdf_edit_id(document, raw, number, index),
      "index": index,
      "page": number,
      "subtype": subtype,
      "bounds": [rect.min_x, rect.min_y, rect.max_x, rect.max_y],
      "editable": editable,
      "contents": pdf_annotation_text(annotation.contents).unwrap_or(""),
      "field_type": field_type,
      "field_name": pdf_annotation_field_full_name(document, raw).unwrap_or(""),
      "field_label": pdf_annotation_field_string(document, raw, "/TU").unwrap_or(
        pdf_annotation_field_full_name(document, raw).unwrap_or(""),
      ),
      "field_flags": field_flags,
      "values": values,
      "options": pdf_annotation_choice_options(document, raw),
      "on_value": on.unwrap_or("Yes"),
      "checked": checked.unwrap_or(false),
      "max_length": max_length,
      "color": color,
      "paths": if subtype == "ink" {
        pdf_annotation_ink_paths(document, raw).to_json()
      } else {
        Json::array([])
      },
    })
  }
  Some(Json::array(output))
}

///|
fn pdf_edit_text_color(
  document : @pdflite.PdfDocument,
  raw : @syntax.PdfObject,
) -> String? {
  let da = pdf_annotation_default(document, raw, "/DA")
    .bind(value => pdf_annotation_field_scalar(document, value))
    .unwrap_or("")
  let ops = @pdflite.pdf_parse_content_ops_from_bytes(@utf8.encode(da)) catch {
    _ => []
  }
  let mut color = [0.0]
  for op in ops {
    match op {
      @content.Op_g(g) => color = [g]
      @content.Op_rg(r, g, b) => color = [r, g, b]
      @content.Op_k(c, m, y, k) => color = [c, m, y, k]
      _ => ()
    }
  }
  Some(pdf_colour_hex(@pdflite.PdfContentColourFloats(color)))
}

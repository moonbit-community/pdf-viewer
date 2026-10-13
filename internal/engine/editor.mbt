///|
/// Browser editor patches use stable annotation ids, PDF-space rectangles and
/// UTF-8 JSON strings. Each snapshot is applied to a copy of the original
/// document; a failed patch never changes the original or a previous snapshot.
pub fn PdfViewerDocument::with_editor_changes(
  self : PdfViewerDocument,
  changes : Json,
) -> PdfViewerDocument raise @core.PdfError {
  self.pdf_edit_require_unlocked()
  guard changes is Json::Array(patches) && patches.length() <= 10000 else {
    raise @core.SoftError("Expected at most 10000 editor patches")
  }
  let document = self.document.copy()
  let touched : Map[Int, Array[Json]] = Map([])
  let ids : Map[String, Bool] = Map([])
  let permissions = self.editor_permissions()
  for patch in patches {
    if pdf_edit_string(patch, "kind") == "field" {
      if !permissions.forms {
        raise @core.SoftError("PDF permissions forbid filling form fields")
      }
    } else if !permissions.annotations {
      raise @core.SoftError("PDF permissions forbid editing annotations")
    }
    let page = pdf_edit_int(patch, "page")
    if page < 1 || page > self.pages.length() {
      raise @core.SoftError("Editor page does not exist")
    }
    let id = pdf_edit_string(patch, "id")
    if id == "" || ids.contains(id) {
      raise @core.SoftError("Editor ids must be nonempty and unique")
    }
    ids[id] = true
    match touched.get(page) {
      Some(entries) => entries.push(patch)
      None => touched[page] = [patch]
    }
  }
  // Field changes run before annotation rebuilding so all widgets of an
  // inherited field see the same value and appearance state across pages.
  for patch in patches {
    if pdf_edit_string(patch, "kind") == "field" {
      pdf_edit_field(document, self, patch)
    }
  }
  for page, patches in touched {
    let page_number = document.page_object_number(page).unwrap()
    let raw_page = document.lookup_object_or_null(page_number)
    let annots = pdf_edit_annots(document, raw_page)
    let output : Array[@syntax.PdfObject] = []
    let matched : Map[String, Bool] = Map([])
    let deleted : Array[@syntax.PdfObject] = []
    for index, raw in annots {
      if patches.any(patch => {
          pdf_edit_string(patch, "kind") == "delete" &&
          pdf_edit_string(patch, "id") ==
          pdf_edit_id(document, raw, page, index)
        }) {
        deleted.push(raw)
      }
    }
    for index, raw in annots {
      let id = pdf_edit_id(document, raw, page, index)
      let patch = patches
        .filter(patch => pdf_edit_string(patch, "id") == id)
        .get(0)
      if patch is Some(patch) {
        matched[id] = true
        match pdf_edit_string(patch, "kind") {
          "delete" => {
            pdf_edit_require_annotation(document, raw)
            continue
          }
          "update" => {
            let object = pdf_edit_annotation(
              document,
              document.direct(raw),
              patch,
              false,
            )
            output.push(pdf_edit_replace(document, raw, object))
            continue
          }
          "field" => ()
          _ =>
            raise @core.SoftError(
              "Invalid operation for an existing annotation",
            )
        }
      }
      // Popup objects of deleted parents must not remain in the page array.
      let parent = document
        .direct(raw)
        .lookup_immediate(pdf_name_key("/Parent"))
      if document.lookup_direct(pdf_name_key("/Subtype"), raw) ==
        Some(@syntax.PdfNameObject(pdf_name_key("/Popup"))) &&
        parent is Some(parent) &&
        deleted.contains(parent) {
        continue
      }
      // Indirect object ids survive deletions. Direct dictionaries receive a
      // private PDF extension key so their ids survive array compaction too.
      if raw is @syntax.PdfIndirect(_) ||
        !(document.direct(raw) is @syntax.PdfDictionary(_)) {
        output.push(raw)
      } else {
        output.push(
          pdf_edit_replace(
            document,
            raw,
            document
            .direct(raw)
            .add_dict_entry(
              pdf_name_key("/MoonBitEditorId"),
              pdf_edit_pdf_string(id),
            ),
          ),
        )
      }
    }
    for patch in patches {
      let id = pdf_edit_string(patch, "id")
      if pdf_edit_string(patch, "kind") == "add" {
        if matched.contains(id) || !id.has_prefix("new:") {
          raise @core.SoftError("Invalid new annotation id")
        }
        let object = pdf_edit_annotation(
          document,
          @syntax.pdf_dictionary([]),
          patch,
          true,
        )
        output.push(@syntax.PdfIndirect(document.add_object(object)))
      } else if !matched.contains(id) {
        raise @core.SoftError("Editor annotation does not exist")
      }
    }
    let updated = raw_page.add_dict_entry(
      pdf_name_key("/Annots"),
      @syntax.PdfArray(output),
    )
    pdf_edit_replace_number(document, page_number, updated)
  }
  { ..self, document, pages: document.pages_of_pagetree(), }
}

///|
/// Serialize edited objects with pdflite's writer. Incremental saving retains
/// the original bytes and appends changed objects and a new xref revision.
/// Recovered inputs without a validated original xref use a complete rewrite.
pub fn PdfViewerDocument::save_bytes(
  self : PdfViewerDocument,
  aes_iv_provider? : (Int, Int, Int) -> Bytes raise @core.PdfError,
  incremental? : Bool = true,
) -> Bytes raise @core.PdfError {
  self.pdf_edit_require_unlocked()
  let document = match (self.document.saved_encryption, self.editor_security) {
    (Some(saved), Some(security)) =>
      match saved.values.crypt_type {
        @core.PdfCryptARC4(_, _) =>
          self.document.recrypt_with_password(security.password)
        @core.PdfCryptAESV2 =>
          self.document.recrypt_with_password_aesv2_with_iv_provider(
            security.password,
            pdf_edit_require_iv_provider(aes_iv_provider),
          )
        @core.PdfCryptAESV3(_) =>
          self.document.recrypt_with_password_aesv3_with_iv_provider(
            security.password,
            pdf_edit_require_iv_provider(aes_iv_provider),
          )
      }
    _ => self.document
  }
  if incremental && !self.source_bytes.is_empty() {
    // Recovery can open files without a usable original xref. Such files must
    // be rewritten rather than appending an invalid /Prev chain.
    let previous = @reader.pdf_read_startxref_position(self.source_bytes) catch {
      _ => -1
    }
    if previous > 0 &&
      previous < self.source_bytes.length() &&
      self.document.first_xref() == previous {
      return @pdflite.pdf_write_document_incremental_update(
        self.source_bytes,
        document,
      )
    }
  }
  @pdflite.pdf_write_document(document)
}

///|
fn pdf_edit_entry(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn pdf_edit_string(value : Json, key : String) -> String {
  match pdf_edit_entry(value, key) {
    String(value) => value
    _ => ""
  }
}

///|
fn pdf_edit_number(value : Json) -> Double raise @core.PdfError {
  guard value is Number(number, ..) &&
    !number.is_nan() &&
    !number.is_inf() &&
    number.abs() <= 1.0e9 else {
    raise @core.SoftError("Expected a finite editor number")
  }
  number
}

///|
fn pdf_edit_int(value : Json, key : String) -> Int raise @core.PdfError {
  let number = pdf_edit_number(pdf_edit_entry(value, key))
  if number != number.trunc() {
    raise @core.SoftError("Expected an editor integer")
  }
  number.to_int()
}

///|
fn pdf_edit_pdf_string(
  value : String,
) -> @syntax.PdfObject raise @core.PdfError {
  @syntax.PdfString(@pdflite.pdf_pdfdocstring_of_utf8(@utf8.encode(value)))
}

///|
fn pdf_edit_id(
  document : @pdflite.PdfDocument,
  raw : @syntax.PdfObject,
  page : Int,
  index : Int,
) -> String {
  match document.lookup_direct(pdf_name_key("/MoonBitEditorId"), raw) {
    Some(value) => pdf_annotation_field_scalar(document, value).unwrap_or("")
    None =>
      match raw {
        @syntax.PdfIndirect(number) => "object:\{number}"
        _ => "page:\{page}:index:\{index}"
      }
  }
}

///|
fn pdf_edit_annots(
  document : @pdflite.PdfDocument,
  page : @syntax.PdfObject,
) -> Array[@syntax.PdfObject] {
  match document.lookup_direct(pdf_name_key("/Annots"), page) {
    Some(@syntax.PdfArray(values)) => values
    _ => []
  }
}

///|
fn pdf_edit_replace_number(
  document : @pdflite.PdfDocument,
  number : Int,
  value : @syntax.PdfObject,
) -> Unit {
  let generation = document.objects
    .get_entry(number)
    .map(entry => entry.generation)
    .unwrap_or(0)
  document.add_object_given_number(number, value, generation~)
}

///|
fn pdf_edit_replace(
  document : @pdflite.PdfDocument,
  raw : @syntax.PdfObject,
  value : @syntax.PdfObject,
) -> @syntax.PdfObject {
  match raw {
    @syntax.PdfIndirect(number) => {
      pdf_edit_replace_number(document, number, value)
      raw
    }
    _ => value
  }
}

///|
fn pdf_edit_bounds(value : Json) -> PdfBounds raise @core.PdfError {
  guard value is Array([x0, y0, x1, y1]) else {
    raise @core.SoftError("Expected a PDF rectangle")
  }
  let bounds : PdfBounds = {
    min_x: pdf_edit_number(x0),
    min_y: pdf_edit_number(y0),
    max_x: pdf_edit_number(x1),
    max_y: pdf_edit_number(y1),
  }
  if bounds.max_x <= bounds.min_x || bounds.max_y <= bounds.min_y {
    raise @core.SoftError("Editor rectangle must have positive area")
  }
  bounds
}

///|
fn pdf_edit_rect(bounds : PdfBounds) -> @syntax.PdfObject {
  @syntax.PdfArray([
    @syntax.PdfReal(bounds.min_x),
    @syntax.PdfReal(bounds.min_y),
    @syntax.PdfReal(bounds.max_x),
    @syntax.PdfReal(bounds.max_y),
  ])
}

///|
fn pdf_edit_require_annotation(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> Unit raise @core.PdfError {
  let subtype = document.lookup_direct(pdf_name_key("/Subtype"), object)
  if subtype == Some(@syntax.PdfNameObject(pdf_name_key("/Widget"))) ||
    subtype == Some(@syntax.PdfNameObject(pdf_name_key("/Link"))) ||
    subtype == Some(@syntax.PdfNameObject(pdf_name_key("/Popup"))) ||
    subtype is None {
    raise @core.SoftError("This annotation cannot be edited")
  }
  if (pdf_annotation_flags(document, object) & 704) != 0 {
    raise @core.SoftError("This annotation is locked")
  }
}

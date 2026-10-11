///|
fn pdf_annotation_layer_string(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  key : String,
) -> String? {
  match document.lookup_direct(pdf_name_key(key), object) {
    Some(@syntax.PdfString(bytes)) => pdf_annotation_text(Some(bytes))
    _ => None
  }
}

///|
fn pdf_annotation_layer_optional(value : String?) -> Json {
  match value {
    Some(value) => Json::string(value)
    None => Json::null()
  }
}

///|
/// Resolve names/dictionaries with a limit before passing a destination array
/// to pdflite. A cyclic named target stays unresolved rather than recursing.
fn PdfViewerDocument::pdf_annotation_layer_destination(
  self : PdfViewerDocument,
  object : @syntax.PdfObject,
  remote : Bool,
) -> PdfDestination {
  let document = self.document
  let mut object = object
  let mut name : String? = None
  let mut destination = @destination.DestNull
  for _ in 0..<32 {
    match document.direct(object) {
      @syntax.PdfDictionary(_) as dictionary =>
        match document.lookup_direct(pdf_name_key("/D"), dictionary) {
          Some(value) => object = value
          None => break
        }
      @syntax.PdfNameObject(value) => {
        let query = pdf_destination_name_text(value.bytes()[:])
        if name is None {
          name = Some(query)
        }
        destination = @destination.DestNamed(value)
        if remote {
          break
        }
        let entries : Map[String, @syntax.PdfObject] = Map(
          pdf_named_destination_entries(document) catch {
            _ => []
          },
        )
        guard entries.get(query) is Some(value) else { break }
        object = value
      }
      @syntax.PdfString(value) => {
        let query = pdf_destination_string_text(value[:])
        if name is None {
          name = Some(query)
        }
        destination = @destination.DestString(value)
        if remote {
          break
        }
        let entries : Map[String, @syntax.PdfObject] = Map(
          pdf_named_destination_entries(document) catch {
            _ => []
          },
        )
        guard entries.get(query) is Some(value) else { break }
        object = value
      }
      @syntax.PdfArray(_) as array => {
        destination = document.read_destination(array, shallow=true) catch {
          _ => @destination.DestNull
        }
        break
      }
      _ => break
    }
  }
  // The generic destination model asks pdflite to resolve a named page. Do
  // not send an unresolved/cyclic name back into that recursive resolver.
  let target = match destination {
    @destination.DestNamed(_) | @destination.DestString(_) => {
      let target = pdf_destination_model(
        document,
        self.pages.length(),
        @destination.DestNull,
        name,
      )
      { ..target, kind: "named", }
    }
    _ => pdf_destination_model(document, self.pages.length(), destination, name)
  }
  if remote {
    { ..target, page: None, remote: true, resolved: false, }
  } else {
    target
  }
}

///|
fn PdfViewerDocument::pdf_annotation_layer_link(
  self : PdfViewerDocument,
  object : @syntax.PdfObject,
) -> Json {
  let document = self.document
  if document.lookup_direct(pdf_name_key("/A"), object) is Some(action) {
    match document.lookup_direct(pdf_name_key("/S"), action) {
      Some(@syntax.PdfNameObject(name)) =>
        match pdf_destination_name_text(name.bytes()[:]) {
          "URI" => {
            let uri = pdf_annotation_layer_string(document, action, "/URI")
            return { "kind": "uri", "uri": pdf_annotation_layer_optional(uri) }
          }
          "GoTo" | "GoToR" as kind => {
            let destination = document
              .lookup_direct(pdf_name_key("/D"), action)
              .unwrap_or(@syntax.PdfNull)
            return {
              "kind": "destination",
              "destination": self.pdf_annotation_layer_destination(
                destination,
                kind == "GoToR",
              ),
            }
          }
          "Named" => {
            let action = match
              document.lookup_direct(pdf_name_key("/N"), action) {
              Some(@syntax.PdfNameObject(name)) =>
                Some(pdf_destination_name_text(name.bytes()[:]))
              _ => None
            }
            return {
              "kind": "named-action",
              "action": pdf_annotation_layer_optional(action),
            }
          }
          _ => return { "kind": "unsupported" }
        }
      _ => return { "kind": "unsupported" }
    }
  }
  if document.lookup_direct(pdf_name_key("/Dest"), object) is Some(destination) {
    return {
      "kind": "destination",
      "destination": self.pdf_annotation_layer_destination(destination, false),
    }
  }
  Json::null()
}

///|
/// Lightweight read-only annotation interaction data, without decoding AP
/// streams. Bounds/quads stay in PDF space and indices refer to `/Annots`.
/// Popup children and malformed annotations are omitted. Remote/unknown
/// destinations remain explicit and must not be used for local navigation.
pub fn PdfViewerDocument::annotation_layer_json(
  self : PdfViewerDocument,
  number : Int,
) -> Json? {
  guard number >= 1 && number <= self.pages.length() else { return None }
  let document = self.document
  let annotations = match
    document.lookup_direct(pdf_name_key("/Annots"), self.pages[number - 1].rest) {
    Some(@syntax.PdfArray(values)) => values
    _ => []
  }
  let output : Array[Json] = []
  for index, object in annotations {
    if document.lookup_direct(pdf_name_key("/Subtype"), object) ==
      Some(@syntax.PdfNameObject(pdf_name_key("/Popup"))) {
      continue
    }
    let annotation = document.read_annotation(object) catch { _ => continue }
    let rectangle = annotation.rectangle
    let flags = pdf_annotation_flags(document, object)
    let popup = document
      .lookup_direct(pdf_name_key("/Popup"), object)
      .unwrap_or(object)
    output.push({
      "index": index,
      "subtype": pdf_annotation_subtype_name(annotation.subtype),
      "flags": flags,
      "visible": pdf_annotation_is_visible(flags),
      "print": pdf_annotation_is_printable(flags),
      "bounds": {
        "min_x": rectangle.min_x,
        "min_y": rectangle.min_y,
        "max_x": rectangle.max_x,
        "max_y": rectangle.max_y,
      },
      "quad_points": pdf_annotation_quad_points(document, object),
      "contents": pdf_annotation_layer_optional(
        pdf_annotation_text(annotation.contents),
      ),
      "title": pdf_annotation_layer_optional(
        pdf_annotation_layer_string(document, object, "/T"),
      ),
      "subject": pdf_annotation_layer_optional(
        pdf_annotation_text(annotation.subject),
      ),
      "popup_open": pdf_bool_entry(
        document,
        pdf_name_key("/Open"),
        popup,
        false,
      ),
      "link": self.pdf_annotation_layer_link(object),
    })
  }
  Some(Json::array(output))
}

///|
/// Select annotation appearances by the Print flag, including NoView/Print
/// annotations, while preserving the original model and body paint items.
pub fn PdfPageModel::with_print_annotations(
  self : PdfPageModel,
) -> PdfPageModel {
  {
    ..self,
    annotations: self.annotations.map(annotation => {
      ..annotation,
      visible: annotation.print,
      style: { ..annotation.style, no_zoom: false, no_rotate: false, },
    }),
  }
}

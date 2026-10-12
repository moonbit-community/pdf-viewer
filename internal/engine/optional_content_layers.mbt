///|
fn pdf_optional_content_config(
  content : @ocg.PdfOptionalContent,
  selected : PdfOptionalContentState?,
) -> @ocg.PdfOcgConfig {
  match selected.bind(state => state.config_index) {
    Some(index) if index >= 0 && index < content.configs.length() =>
      content.configs[index]
    _ => content.default_config
  }
}

///|
fn pdf_optional_content_base_groups(
  content : @ocg.PdfOptionalContent,
  selected : PdfOptionalContentState?,
) -> Array[(Int, Bool)] {
  let config = pdf_optional_content_config(content, selected)
  let groups : Array[(Int, Bool)] = []
  for (number, _) in content.ocgs {
    let mut visible = config.base_state != @ocg.OcgOff
    if config.on.contains(number) {
      visible = true
    }
    if config.off.contains(number) {
      visible = false
    }
    match selected {
      Some(state) => {
        if state.off.contains(number) {
          visible = false
        }
        if state.on.contains(number) {
          visible = true
        }
      }
      None => ()
    }
    groups.push((number, visible))
  }
  groups
}

///|
/// Change one layer without mutating the document. User toggles override usage
/// in every intent, preserve /RBGroups, and cannot change /Locked groups.
pub fn PdfViewerDocument::with_optional_content_visibility(
  self : PdfViewerDocument,
  number : Int,
  visible : Bool,
) -> PdfViewerDocument raise @core.PdfError {
  guard self.document.read_optional_content_groups() is Some(content) &&
    content.ocgs.any(entry => entry.0 == number) else {
    raise @core.SoftError("Optional-content group does not exist")
  }
  let selected = self.optional_content_state
  let config = pdf_optional_content_config(content, selected)
  if config.locked.contains(number) {
    raise @core.SoftError("The optional-content group is locked")
  }
  let affected : Map[Int, Bool] = Map([(number, visible)])
  if visible && config.radio_button_groups is Some(radio_groups) {
    let base = pdf_optional_content_base_groups(content, selected)
    for group in radio_groups {
      if !group.contains(number) {
        continue
      }
      for peer in group {
        if peer == number {
          continue
        }
        if config.locked.contains(peer) {
          if pdf_optional_content_group_state(base[:], peer) == Some(true) {
            raise @core.SoftError(
              "A locked group prevents this layer from being enabled",
            )
          }
        } else {
          affected[peer] = false
        }
      }
    }
  }
  let state = selected.unwrap_or(pdf_optional_content_state())
  let on = state.on.filter(number => !affected.contains(number))
  let off = state.off.filter(number => !affected.contains(number))
  for number, visible in affected {
    if visible {
      on.push(number)
    } else {
      off.push(number)
    }
  }
  self.with_optional_content_state(
    pdf_optional_content_state(config_index=state.config_index, on~, off~),
  )
}

///|
/// Select the default configuration (`None`) or an alternate configuration.
/// Selecting a configuration resets user overrides for that configuration.
pub fn PdfViewerDocument::with_optional_content_config(
  self : PdfViewerDocument,
  index : Int?,
) -> PdfViewerDocument raise @core.PdfError {
  guard self.document.read_optional_content_groups() is Some(content) else {
    raise @core.SoftError("Document has no optional-content configurations")
  }
  if index is Some(index) && (index < 0 || index >= content.configs.length()) {
    raise @core.SoftError("Optional-content configuration does not exist")
  }
  self.with_optional_content_state(
    pdf_optional_content_state(config_index=index),
  )
}

///|
// pdflite resolves all PDF objects. This bounded projection preserves nested
// /Order labels beyond the one-level grouping in its typed OCG model.
fn pdf_optional_content_order_json(
  document : @pdflite.PdfDocument,
  raw : @syntax.PdfObject,
  known : Map[Int, Unit],
  seen : Map[Int, Unit],
  depth : Int,
  budget : Ref[Int],
) -> Array[Json] {
  if depth > 10 || budget.val <= 0 {
    return []
  }
  guard document.direct(raw) is @syntax.PdfArray(items) else { return [] }
  let rows : Array[Json] = []
  for raw in items {
    budget.val -= 1
    if budget.val < 0 {
      break
    }
    match raw {
      @syntax.PdfIndirect(number) if known.contains(number) =>
        if !seen.contains(number) {
          seen[number] = ()
          rows.push({ "id": number })
        }
      _ => {
        let nested = document.direct(raw)
        let (name, children) = match nested {
          @syntax.PdfArray([@syntax.PdfString(name), .. rest]) =>
            (
              pdf_destination_string_text(name[:]),
              @syntax.PdfArray(rest.to_owned()),
            )
          @syntax.PdfArray(_) => ("", nested)
          _ => continue
        }
        let children = pdf_optional_content_order_json(
          document,
          children,
          known,
          seen,
          depth + 1,
          budget,
        )
        if !children.is_empty() {
          rows.push({ "name": name, "children": children })
        }
      }
    }
  }
  rows
}

///|
/// Layer-panel data with Unicode names, nested order, active configuration,
/// display/print visibility, and lock/radio metadata. Bytes remain in the PDF.
pub fn PdfViewerDocument::optional_content_layers_json(
  self : PdfViewerDocument,
) -> Json? raise @core.PdfError {
  guard self.document.read_optional_content_groups() is Some(content) else {
    return None
  }
  let config = pdf_optional_content_config(content, self.optional_content_state)
  let display = pdf_optional_content_view(
    self.document,
    self.optional_content_state,
  ).unwrap()
  let print = pdf_optional_content_view(
    self.document,
    self.optional_content_state,
    intent=Print,
  ).unwrap()
  let groups : Array[Json] = []
  let known : Map[Int, Unit] = Map([])
  for (number, group) in content.ocgs {
    known[number] = ()
    groups.push({
      "id": number,
      "name": pdf_destination_string_text(group.name[:]),
      "visible": pdf_optional_content_group_state(display.groups[:], number).unwrap_or(
        true,
      ),
      "print_visible": pdf_optional_content_group_state(print.groups[:], number).unwrap_or(
        true,
      ),
      "locked": config.locked.contains(number),
    })
  }
  let index = match
    self.optional_content_state.bind(state => state.config_index) {
    Some(index) if index >= 0 && index < content.configs.length() => Some(index)
    _ => None
  }
  let configs : Array[Json] = [
    {
      "index": Json::null(),
      "name": content.default_config.name
      .map(bytes => pdf_destination_string_text(bytes[:]))
      .unwrap_or(""),
    },
  ]
  for index, config in content.configs {
    configs.push({
      "index": index,
      "name": config.name
      .map(bytes => pdf_destination_string_text(bytes[:]))
      .unwrap_or(""),
    })
  }
  let catalog = self.document.lookup_object_or_null(self.document.root())
  let properties = pdf_optional_content_raw_entry(
    self.document,
    pdf_name_key("/OCProperties"),
    catalog,
  ).unwrap_or(@syntax.PdfNull)
  let raw_config = match index {
    Some(index) =>
      match
        pdf_optional_content_raw_entry(
          self.document,
          pdf_name_key("/Configs"),
          properties,
        ).map(object => self.document.direct(object)) {
        Some(@syntax.PdfArray(configs)) => configs[index]
        _ => @syntax.PdfNull
      }
    None =>
      pdf_optional_content_raw_entry(
        self.document,
        pdf_name_key("/D"),
        properties,
      ).unwrap_or(@syntax.PdfNull)
  }
  let order = pdf_optional_content_raw_entry(
    self.document,
    pdf_name_key("/Order"),
    raw_config,
  ).unwrap_or(@syntax.PdfNull)
  let seen : Map[Int, Unit] = Map([])
  let rows = pdf_optional_content_order_json(
    self.document,
    order,
    known,
    seen,
    0,
    Ref(10000),
  )
  let unlisted : Array[Json] = []
  for (number, _) in content.ocgs {
    if !seen.contains(number) {
      unlisted.push({ "id": number })
    }
  }
  if !unlisted.is_empty() {
    rows.push({ "name": "", "children": unlisted })
  }
  Some({
    "config_index": match index {
      Some(index) => Json::number(index.to_double())
      None => Json::null()
    },
    "configs": configs,
    "groups": groups,
    "order": rows,
    "radio_groups": config.radio_button_groups.unwrap_or([]),
  })
}

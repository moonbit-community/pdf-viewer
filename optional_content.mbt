///|
/// A viewer-owned optional-content selection.
///
/// `config_index` is zero-based into the alternate `/Configs` array. `None`
/// selects the catalog `/D` configuration. `on` and `off` contain OCG object
/// numbers and override the selected configuration for this view.
pub(all) struct PdfOptionalContentState {
  config_index : Int?
  on : Array[Int]
  off : Array[Int]
} derive(Eq, Debug, ToJson)

///|
/// Build a selectable optional-content state using pdflite's object-number
/// identity. Keeping object numbers in the public state avoids inventing a
/// second layer identifier and lets hosts join this state with
/// `optional_content_json()`.
pub fn pdf_optional_content_state(
  config_index? : Int? = None,
  on? : Array[Int] = [],
  off? : Array[Int] = [],
) -> PdfOptionalContentState {
  {
    config_index,
    on: [
      for number in on => number
    ],
    off: [
      for number in off => number
    ],
  }
}

///|
priv struct PdfOptionalContentView {
  groups : Array[(Int, Bool)]
}

///|
fn pdf_optional_content_raw_entry(
  document : @pdflite.PdfDocument,
  key : @core.PdfName,
  object : @syntax.PdfObject,
) -> @syntax.PdfObject? {
  match document.direct(object).dictionary_view() {
    Some(entries) =>
      for entry in entries {
        if entry.0 == key {
          break Some(entry.1)
        }
      } nobreak {
        None
      }
    None => None
  }
}

///|
fn pdf_optional_content_group_state(
  groups : ArrayView[(Int, Bool)],
  number : Int,
) -> Bool? {
  for entry in groups {
    if entry.0 == number {
      break Some(entry.1)
    }
  } nobreak {
    None
  }
}

///|
fn pdf_optional_content_group_numbers(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
) -> Array[Int] {
  match object {
    @syntax.PdfIndirect(number) => [number]
    _ =>
      match document.direct(object) {
        @syntax.PdfArray(values) => {
          let output : Array[Int] = []
          for value in values {
            match value {
              @syntax.PdfIndirect(number) => output.push(number)
              _ => ()
            }
          }
          output
        }
        _ => []
      }
  }
}

///|
fn pdf_optional_content_visible_expression(
  document : @pdflite.PdfDocument,
  expression : @syntax.PdfObject,
  groups : ArrayView[(Int, Bool)],
) -> Bool {
  match document.direct(expression) {
    @syntax.PdfArray(values) if values.length() > 0 => {
      let operator = match document.direct(values[0]) {
        @syntax.PdfNameObject(name) => Some(name)
        _ => None
      }
      let operands = values[1:]
      match operator {
        Some(name) if name == pdf_name_key("/And") =>
          operands
          .iter()
          .all(value => {
            pdf_optional_content_visible_expression(document, value, groups)
          })
        Some(name) if name == pdf_name_key("/Or") =>
          operands
          .iter()
          .any(value => {
            pdf_optional_content_visible_expression(document, value, groups)
          })
        Some(name) if name == pdf_name_key("/Not") =>
          match operands.get(0) {
            Some(value) =>
              !pdf_optional_content_visible_expression(document, value, groups)
            None => true
          }
        _ => false
      }
    }
    @syntax.PdfDictionary(_) | @syntax.PdfStreamObject(_) =>
      pdf_optional_content_visible_object(document, expression, groups)
    @syntax.PdfIndirect(number) =>
      pdf_optional_content_group_state(groups, number).unwrap_or(true)
    _ => true
  }
}

///|
fn pdf_optional_content_visible_object(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  groups : ArrayView[(Int, Bool)],
) -> Bool {
  let direct = document.direct(object)
  match
    pdf_optional_content_raw_entry(document, pdf_name_key("/Type"), direct) {
    Some(@syntax.PdfNameObject(name)) if name == pdf_name_key("/OCMD") =>
      match
        pdf_optional_content_raw_entry(document, pdf_name_key("/VE"), direct) {
        Some(expression) =>
          pdf_optional_content_visible_expression(document, expression, groups)
        None => {
          let numbers = match
            pdf_optional_content_raw_entry(
              document,
              pdf_name_key("/OCGs"),
              direct,
            ) {
            Some(value) => pdf_optional_content_group_numbers(document, value)
            None => []
          }
          let policy = match
            pdf_optional_content_raw_entry(document, pdf_name_key("/P"), direct) {
            Some(@syntax.PdfNameObject(name)) => name
            _ => pdf_name_key("/AnyOn")
          }
          let states : Array[Bool] = [
            for number in numbers => {
              pdf_optional_content_group_state(groups, number).unwrap_or(true)
            }
          ]
          if policy == pdf_name_key("/AllOn") {
            states.iter().all(value => value)
          } else if policy == pdf_name_key("/AnyOff") {
            states.iter().any(value => !value)
          } else if policy == pdf_name_key("/AllOff") {
            states.iter().all(value => !value)
          } else {
            states.iter().any(value => value)
          }
        }
      }
    _ =>
      match object {
        @syntax.PdfIndirect(number) =>
          pdf_optional_content_group_state(groups, number).unwrap_or(true)
        _ => true
      }
  }
}

///|
fn pdf_optional_content_view(
  document : @pdflite.PdfDocument,
  selected : PdfOptionalContentState?,
) -> PdfOptionalContentView? raise @core.PdfError {
  match document.read_optional_content_groups() {
    None => None
    Some(content) => {
      let selected_config_index = match selected {
        Some(value) => value.config_index
        None => None
      }
      let config = match selected_config_index {
        Some(index) if index >= 0 && index < content.configs.length() =>
          content.configs[index]
        _ => content.default_config
      }
      let groups : Array[(Int, Bool)] = []
      let base_visible = match config.base_state {
        @ocg.OcgOff => false
        _ => true
      }
      for entry in content.ocgs {
        groups.push((entry.0, base_visible))
      }
      for number in config.off {
        for index, entry in groups {
          if entry.0 == number {
            groups[index] = (number, false)
          }
        }
      }
      for number in config.on {
        for index, entry in groups {
          if entry.0 == number {
            groups[index] = (number, true)
          }
        }
      }
      match selected {
        Some(state) => {
          for number in state.off {
            for index, entry in groups {
              if entry.0 == number {
                groups[index] = (number, false)
              }
            }
          }
          for number in state.on {
            for index, entry in groups {
              if entry.0 == number {
                groups[index] = (number, true)
              }
            }
          }
        }
        None => ()
      }
      Some({ groups, })
    }
  }
}

///|
fn pdf_optional_content_visible_marked_content(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  marked_content : ArrayView[@pdflite.PdfContentMarkedContent],
  view : PdfOptionalContentView?,
  inherited_visible : Bool,
) -> Bool {
  if !inherited_visible {
    return false
  }
  match view {
    None => true
    Some(view) =>
      for marked in marked_content {
        if marked.tag == "/OC" || marked.tag == "OC" {
          let property = match marked.properties {
            Some(@syntax.PdfNameObject(name)) =>
              match
                pdf_optional_content_raw_entry(
                  document,
                  name,
                  pdf_optional_content_raw_entry(
                    document,
                    pdf_name_key("/Properties"),
                    resources,
                  ).unwrap_or(@syntax.PdfDictionary([])),
                ) {
                Some(value) => value
                None => @syntax.PdfNull
              }
            Some(value) => value
            None => @syntax.PdfNull
          }
          if !pdf_optional_content_visible_object(
              document,
              property,
              view.groups[:],
            ) {
            return false
          }
        }
      } nobreak {
        true
      }
  }
}

///|
fn pdf_optional_content_visible_form(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : @core.PdfName,
  view : PdfOptionalContentView?,
  inherited_visible : Bool,
) -> Bool {
  if !inherited_visible {
    return false
  }
  match view {
    None => true
    Some(view) =>
      match pdf_form_xobject_of_resources_raw(document, resources, name) {
        Some(xobject) =>
          match
            pdf_optional_content_raw_entry(
              document,
              pdf_name_key("/OC"),
              xobject,
            ) {
            Some(value) =>
              pdf_optional_content_visible_object(
                document,
                value,
                view.groups[:],
              )
            None => true
          }
        None => true
      }
  }
}

///|
fn pdf_form_xobject_of_resources_raw(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  name : @core.PdfName,
) -> @syntax.PdfObject? {
  match
    pdf_optional_content_raw_entry(
      document,
      pdf_name_key("/XObject"),
      resources,
    ) {
    Some(xobjects) => pdf_optional_content_raw_entry(document, name, xobjects)
    None => None
  }
}

///|
priv struct PdfAccessibilityMark {
  mcid : Int?
  stream : Int?
  actual_text : String?
  actual_key : String?
  artifact : Bool
}

///|
priv struct PdfAccessibilityGroup {
  mark : PdfAccessibilityMark
  form_path : Array[PdfTextFormInvocation]
  items : Array[PdfTextItem]
}

///|
fn pdf_accessibility_name(name : @core.PdfName) -> String {
  pdf_destination_name_text(name.bytes()[:])
}

///|
fn pdf_accessibility_path(path : ArrayView[PdfTextFormInvocation]) -> String {
  [ for invocation in path => invocation.operator_index.to_string() ].join("/")
}

///|
fn pdf_accessibility_operator(path : String, index : Int) -> String {
  path + "#" + index.to_string()
}

///|
// Track only scopes needed by collected glyphs. A marker keeps the stream in
// which BDC began, even when its text is emitted by a nested Form invocation.
fn pdf_accessibility_scan(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  ops : ArrayView[@content.PdfContentOp],
  path : String,
  stream : Int?,
  inherited : ArrayView[PdfAccessibilityMark],
  wanted : Map[String, Bool],
  prefixes : Map[String, Bool],
  output : Map[String, PdfAccessibilityMark],
  remaining : Ref[Int],
  depth : Int,
) -> Unit raise @core.PdfError {
  if depth > 32 {
    remaining.val = 0
    return
  }
  if remaining.val <= 0 {
    return
  }
  let stack = [ for mark in inherited => mark ]
  for index, op in ops {
    if remaining.val <= 0 {
      break
    }
    remaining.val -= 1
    match op {
      @content.Op_BMC(tag) =>
        stack.push({
          mcid: None,
          stream,
          actual_text: None,
          actual_key: None,
          artifact: pdf_accessibility_name(tag) == "Artifact",
        })
      @content.Op_BDC(tag, properties) => {
        let properties = match properties {
          @syntax.PdfNameObject(name) =>
            document
            .lookup_direct(pdf_name_key("/Properties"), resources)
            .bind(properties => document.lookup_direct(name, properties))
            .unwrap_or(@syntax.PdfNull)
          _ => properties
        }
        let mcid = match
          document.lookup_direct(pdf_name_key("/MCID"), properties) {
          Some(@syntax.PdfInteger(value)) if value >= 0 => Some(value)
          _ => None
        }
        let actual_text = pdf_annotation_layer_string(
          document, properties, "/ActualText",
        )
        stack.push({
          mcid,
          stream,
          actual_text,
          actual_key: actual_text.map(_ => {
            pdf_accessibility_operator(path, index)
          }),
          artifact: pdf_accessibility_name(tag) == "Artifact",
        })
      }
      @content.Op_EMC => {
        let _ = stack.pop()
      }
      @content.Op_Do(name) => {
        let child_path = if path.is_empty() {
          index.to_string()
        } else {
          path + "/" + index.to_string()
        }
        if prefixes.contains(child_path) {
          match
            (
              document.content_form_xobject_ops(resources, name),
              document.content_form_xobject_resources(resources, name),
            ) {
            (Some(ops), Some(resources_child)) => {
              let object = document
                .lookup_direct(pdf_name_key("/XObject"), resources)
                .bind(objects => objects.lookup_immediate(name))
              pdf_accessibility_scan(
                document,
                resources_child,
                ops[:],
                child_path,
                object.bind(pdf_text_object_number),
                stack[:],
                wanted,
                prefixes,
                output,
                remaining,
                depth + 1,
              )
            }
            _ => ()
          }
        }
      }
      _ => ()
    }
    let key = pdf_accessibility_operator(path, index)
    if wanted.contains(key) {
      let mut mark : PdfAccessibilityMark = {
        mcid: None,
        stream,
        actual_text: None,
        actual_key: None,
        artifact: false,
      }
      for candidate in stack {
        if candidate.mcid is Some(_) {
          mark = candidate
        }
      }
      for candidate in stack {
        if candidate.actual_text is Some(_) {
          mark = {
            ..mark,
            actual_text: candidate.actual_text,
            actual_key: candidate.actual_key,
          }
        }
        if candidate.artifact {
          mark = { ..mark, artifact: true, }
        }
      }
      output[key] = mark
    }
  }
}

///|
fn pdf_accessibility_text(items : ArrayView[PdfTextItem]) -> String {
  let output = StringBuilder()
  for index, item in items {
    if index > 0 {
      output.write_string(pdf_text_separator(items[index - 1], item))
    }
    output.write_string(item.text)
  }
  output.to_string()
}

///|
fn pdf_accessibility_number(value : Int?) -> Json {
  match value {
    Some(value) => Json::number(value.to_double())
    None => Json::null()
  }
}

///|
// ParentTree allows page-local integer /K references without /Pg. Bounds and
// cycles are limited; an absent association never guesses another page.
fn pdf_accessibility_parent_entry(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  key : Int,
  depth : Int,
  budget : Ref[Int],
) -> @syntax.PdfObject? {
  if depth > 32 || budget.val <= 0 {
    return None
  }
  budget.val -= 1
  if document.lookup_direct(pdf_name_key("/Nums"), object)
    is Some(@syntax.PdfArray(values)) {
    for index = 0; index + 1 < values.length(); index = index + 2 {
      if values[index] == @syntax.PdfInteger(key) {
        return Some(document.direct(values[index + 1]))
      }
    }
  }
  if document.lookup_direct(pdf_name_key("/Kids"), object)
    is Some(@syntax.PdfArray(kids)) {
    for child in kids {
      if pdf_accessibility_parent_entry(document, child, key, depth + 1, budget)
        is Some(value) {
        return Some(value)
      }
    }
  }
  None
}

///|
priv struct PdfAccessibilityTree {
  document : @pdflite.PdfDocument
  page_object : Int?
  single_page : Bool
  role_map : @syntax.PdfObject
  parents : Map[Int, Int]
  annotations : Array[@syntax.PdfObject]
  groups : Array[PdfAccessibilityGroup]
  used : Map[Int, Bool]
  actual_used : Map[String, Bool]
  seen : Map[Int, Bool]
  remaining : Ref[Int]
}

///|
fn PdfAccessibilityTree::content(
  self : PdfAccessibilityTree,
  mcid : Int,
  stream : Int?,
  page : Int?,
  owner : Int?,
) -> Array[Json] {
  if mcid < 0 {
    return []
  }
  let belongs = match page {
    Some(_) => page == self.page_object
    None =>
      stream is Some(_) ||
      self.single_page ||
      (self.parents.get(mcid) == owner && owner is Some(_))
  }
  if !belongs {
    return []
  }
  let groups : Array[Json] = []
  let mut previous : PdfTextItem? = None
  for index, group in self.groups {
    if group.mark.mcid != Some(mcid) ||
      group.mark.stream != stream ||
      self.used.contains(index) {
      continue
    }
    self.used[index] = true
    let text = match (group.mark.actual_text, group.mark.actual_key) {
      (Some(text), Some(key)) =>
        if self.actual_used.contains(key) {
          ""
        } else {
          self.actual_used[key] = true
          text
        }
      _ => pdf_accessibility_text(group.items[:])
    }
    let separator = previous
      .map(previous => pdf_text_separator(previous, group.items[0]))
      .unwrap_or("")
    groups.push({
      "items": group.items.map(item => item.index),
      "text": text,
      "separator": separator,
      "form_path": group.form_path,
    })
    previous = group.items.last()
  }
  if groups.is_empty() {
    []
  } else {
    [
      {
        "type": "content",
        "mcid": mcid,
        "stream": pdf_accessibility_number(stream),
        "groups": groups,
      },
    ]
  }
}

///|
fn PdfAccessibilityTree::walk(
  self : PdfAccessibilityTree,
  object : @syntax.PdfObject,
  inherited_page : Int?,
  owner : Int?,
  depth : Int,
) -> Array[Json] {
  if depth > 40 {
    self.remaining.val = 0
    return []
  }
  if self.remaining.val <= 0 {
    return []
  }
  self.remaining.val -= 1
  let object_number = pdf_text_object_number(object)
  match object_number {
    Some(number) => {
      if self.seen.contains(number) {
        return []
      }
      self.seen[number] = true
    }
    None => ()
  }
  match self.document.direct(object) {
    @syntax.PdfInteger(mcid) => self.content(mcid, None, inherited_page, owner)
    @syntax.PdfArray(children) => {
      let output = []
      for child in children {
        output.append(self.walk(child, inherited_page, owner, depth + 1))
      }
      output
    }
    @syntax.PdfDictionary(_) as dictionary => {
      let document = self.document
      let page = match
        dictionary
        .lookup_immediate(pdf_name_key("/Pg"))
        .bind(pdf_text_object_number) {
        Some(_) as page => page
        None => inherited_page
      }
      match document.lookup_direct(pdf_name_key("/Type"), dictionary) {
        Some(@syntax.PdfNameObject(name)) if pdf_accessibility_name(name) ==
          "MCR" => {
          let stream = dictionary
            .lookup_immediate(pdf_name_key("/Stm"))
            .bind(pdf_text_object_number)
          match document.lookup_direct(pdf_name_key("/MCID"), dictionary) {
            Some(@syntax.PdfInteger(mcid)) =>
              self.content(mcid, stream, page, owner)
            _ => []
          }
        }
        Some(@syntax.PdfNameObject(name)) if pdf_accessibility_name(name) ==
          "OBJR" => {
          if page is Some(_) && page != self.page_object {
            return []
          }
          let target = dictionary
            .lookup_immediate(pdf_name_key("/Obj"))
            .bind(pdf_text_object_number)
          if target is None {
            return []
          }
          for index, annotation in self.annotations {
            if pdf_text_object_number(annotation) == target &&
              pdf_annotation_is_visible(
                pdf_annotation_flags(document, annotation),
              ) {
              return [{ "type": "annotation", "index": index }]
            }
          }
          []
        }
        _ => {
          let owner = match object_number {
            Some(_) => object_number
            None => owner
          }
          let children = dictionary
            .lookup_immediate(pdf_name_key("/K"))
            .map(children => self.walk(children, page, owner, depth + 1))
            .unwrap_or([])
          // Descendants can override /Pg, so traverse before dropping a branch.
          // Empty nodes on another page need no role, text or attribute reads.
          if children.is_empty() &&
            !(page == self.page_object || (page is None && self.single_page)) {
            return []
          }
          let alt = pdf_annotation_layer_string(document, dictionary, "/Alt")
          let actual = pdf_annotation_layer_string(
            document, dictionary, "/ActualText",
          )
          if children.is_empty() &&
            !((alt is Some(_) || actual is Some(_)) &&
            (page == self.page_object || (page is None && self.single_page))) {
            return []
          }
          let (tag, role_namespace) = pdf_accessibility_role(
            document,
            dictionary,
            self.role_map,
          )
          let attributes = document
            .lookup_direct(pdf_name_key("/A"), dictionary)
            .unwrap_or(@syntax.PdfNull)
          let attributes = match attributes {
            @syntax.PdfArray(values) => {
              let mut table = @syntax.PdfNull
              for value in values {
                if document.lookup_direct(pdf_name_key("/O"), value) ==
                  Some(@syntax.PdfNameObject(pdf_name_key("/Table"))) {
                  table = value
                  break
                }
              }
              table
            }
            _ => attributes
          }
          let span = key => {
            match document.lookup_direct(pdf_name_key(key), attributes) {
              Some(@syntax.PdfInteger(value)) if value > 0 => value
              _ => 1
            }
          }
          [
            {
              "type": "element",
              "tag": tag,
              "namespace": pdf_annotation_layer_optional(role_namespace),
              "children": children,
              "lang": pdf_annotation_layer_optional(
                pdf_annotation_layer_string(document, dictionary, "/Lang"),
              ),
              "alt": pdf_annotation_layer_optional(alt),
              "actual_text": pdf_annotation_layer_optional(actual),
              "row_span": span("/RowSpan"),
              "col_span": span("/ColSpan"),
              "scope": match
                document.lookup_direct(pdf_name_key("/Scope"), attributes) {
                Some(@syntax.PdfNameObject(name)) =>
                  Json::string(pdf_accessibility_name(name))
                _ => Json::null()
              },
            },
          ]
        }
      }
    }
    _ => []
  }
}

///|
/// Page-local semantic nodes associated with stable body glyph indices. Uses
/// existing reader/interpreter/provenance data; it does not mutate paint or
/// infer PDF tags for untagged content. Unmapped visible text is retained in
/// geometrically ordered paragraphs. Invalid page numbers return None.
/// Pass the page model already decoded for this document view to avoid
/// rebuilding image/font resources while constructing semantic nodes.
pub fn PdfViewerDocument::accessibility_page_json(
  self : PdfViewerDocument,
  number : Int,
  page_model? : PdfPageModel? = None,
) -> Json? raise @core.PdfError {
  pdf_accessibility_page_json(self, number, page_model~)
}

///|
fn pdf_accessibility_page_json(
  view : PdfViewerDocument,
  number : Int,
  page_model? : PdfPageModel? = None,
  text_content? : PdfTextContent? = None,
) -> Json? raise @core.PdfError {
  guard number >= 1 && number <= view.pages.length() else { return None }
  let page = match page_model {
    Some(page) if page.number == number => Some(page)
    _ => view.page(number)
  }
  guard page is Some(page) else { return None }
  let content = text_content.unwrap_or_else(() => page.text_content())
  let document = view.document
  let catalog = document.catalog()
  let root = document.lookup_direct(pdf_name_key("/StructTreeRoot"), catalog)
  let used_items : Map[Int, Bool] = Map([])
  let excluded_items : Map[Int, Bool] = Map([])
  let nodes : Array[Json] = []
  let mut truncated = false
  if root is Some(root) {
    let raw_page = view.pages[number - 1]
    let cached = view.accessibility_sources.val
    view.accessibility_sources.val = None
    let sources = match cached {
      Some((cached_number, sources)) if cached_number == number => sources
      _ =>
        pdf_collected_entries_of_page(
          document,
          raw_page,
          optional_content_view=pdf_optional_content_view(
            document,
            view.optional_content_state,
          ),
          collect_text_sources=true,
          resource_context=pdf_resource_build_context(
            font_fallbacks=view.font_fallbacks[:],
            parsed_fonts=view.parsed_fonts,
          ),
          font_fallbacks=view.font_fallbacks[:],
        ).map(entry => entry.text_source.map(source => source.string_source))
    }
    let wanted : Map[String, Bool] = Map([])
    let prefixes : Map[String, Bool] = Map([])
    for source in sources {
      if source is Some(source) {
        wanted[pdf_accessibility_operator(
          pdf_accessibility_path(source.form_path[:]),
          source.operator_index,
        )] = true
        for length in 1..<=source.form_path.length() {
          prefixes[pdf_accessibility_path(source.form_path[:length])] = true
        }
      }
    }
    let marks : Map[String, PdfAccessibilityMark] = Map([])
    let scan_budget = Ref(100000)
    let ops = document.parse_content_ops_with_resources(
      raw_page.resources,
      raw_page.content,
    )
    pdf_accessibility_scan(
      document,
      raw_page.resources,
      ops[:],
      "",
      None,
      [],
      wanted,
      prefixes,
      marks,
      scan_budget,
      0,
    )
    let groups : Array[PdfAccessibilityGroup] = []
    let mut previous_key : String? = None
    for item in content.items {
      guard sources.get(item.index) is Some(Some(source)) else { continue }
      let path = pdf_accessibility_path(source.form_path[:])
      guard marks.get(pdf_accessibility_operator(path, source.operator_index))
        is Some(mark) else {
        continue
      }
      if mark.artifact {
        excluded_items[item.index] = true
        continue
      }
      guard mark.mcid is Some(mcid) else { continue }
      let key = mark.stream.unwrap_or(-1).to_string() +
        ":" +
        mcid.to_string() +
        ":" +
        path +
        ":" +
        mark.actual_key.unwrap_or("")
      if previous_key == Some(key) && !groups.is_empty() {
        groups[groups.length() - 1].items.push(item)
      } else {
        groups.push({ mark, form_path: source.form_path, items: [item], })
      }
      previous_key = Some(key)
    }
    let parents : Map[Int, Int] = Map([])
    match
      (
        document.lookup_direct(pdf_name_key("/StructParents"), raw_page.rest),
        document.lookup_direct(pdf_name_key("/ParentTree"), root),
      ) {
      (Some(@syntax.PdfInteger(key)), Some(tree)) =>
        if pdf_accessibility_parent_entry(document, tree, key, 0, Ref(2000))
          is Some(@syntax.PdfArray(values)) {
          for mcid, value in values {
            if pdf_text_object_number(value) is Some(owner) {
              parents[mcid] = owner
            }
          }
        }
      _ => ()
    }
    let tree : PdfAccessibilityTree = {
      document,
      page_object: (document.page_reference_numbers() catch { _ => [] }).get(
        number - 1,
      ),
      single_page: view.pages.length() == 1,
      role_map: document
      .lookup_direct(pdf_name_key("/RoleMap"), root)
      .unwrap_or(@syntax.PdfNull),
      parents,
      annotations: match
        document.lookup_direct(pdf_name_key("/Annots"), raw_page.rest) {
        Some(@syntax.PdfArray(values)) => values
        _ => []
      },
      groups,
      used: Map([]),
      actual_used: Map([]),
      seen: Map([]),
      remaining: Ref(6000),
    }
    nodes.append(tree.walk(root, None, None, 0))
    for index, _ in tree.used {
      for item in groups[index].items {
        used_items[item.index] = true
      }
    }
    truncated = scan_budget.val <= 0 || tree.remaining.val <= 0
  }
  let items : Map[Int, PdfTextItem] = Map(
    [
      for item in content.items => (item.index, item)
    ],
  )
  for paragraph in pdf_text_structure_of_content(content).paragraphs {
    let remaining : Array[PdfTextItem] = []
    for run in paragraph.runs {
      for source in run.sources {
        if !used_items.contains(source.item_index) &&
          !excluded_items.contains(source.item_index) {
          if items.get(source.item_index) is Some(item) {
            remaining.push(item)
          }
        }
      }
    }
    if !remaining.is_empty() {
      nodes.push({
        "type": "element",
        "tag": "P",
        "inferred": true,
        "children": [
          {
            "type": "content",
            "groups": [
              {
                "items": remaining.map(item => item.index),
                "text": pdf_accessibility_text(remaining[:]),
                "form_path": [],
              },
            ],
          },
        ],
      })
    }
  }
  Some({
    "page": number,
    "tagged": root is Some(_),
    "nodes": nodes,
    "lang": pdf_annotation_layer_optional(
      pdf_annotation_layer_string(document, catalog, "/Lang"),
    ),
    "mapped_items": used_items.length(),
    "excluded_items": excluded_items.length(),
    "unmapped_items": items.length() -
    used_items.length() -
    excluded_items.length(),
    "truncated": truncated,
  })
}

///|
/// A host-facing PDF destination.
///
/// `page` is a one-based page number in the current document. A destination
/// that points into another document keeps its page number in `remote_page`
/// and sets `remote`; it must not be used for a local jump. The optional view
/// coordinates retain the values from the PDF destination array, including
/// null values represented by `None`.
pub(all) struct PdfDestination {
  kind : String
  name : String?
  page : Int?
  remote_page : Int?
  left : Double?
  bottom : Double?
  right : Double?
  top : Double?
  zoom : Double?
  remote : Bool
  resolved : Bool
} derive(Eq, Debug, ToJson)

///|
/// A named destination advertised by the document catalog.
pub(all) struct PdfNamedDestination {
  name : String
  destination : PdfDestination
} derive(Eq, Debug, ToJson)

///|
fn pdf_destination_name_text(bytes : BytesView) -> String {
  let text = try @utf8.decode(bytes) catch {
    _ => ""
  } noraise {
    value => value
  }
  if text.has_prefix("/") {
    text[1:].to_owned()
  } else {
    text
  }
}

///|
fn pdf_destination_string_text(bytes : BytesView) -> String {
  let utf8 = @pdflite.pdf_utf8_of_pdfdocstring(bytes) catch { _ => return "" }
  @utf8.decode(utf8[:]) catch {
    _ => ""
  }
}

///|
fn pdf_destination_target_info(
  target : @destination.PdfTargetPage,
) -> (Bool, Int?) {
  match target {
    @destination.TargetPageObject(_) => (false, None)
    @destination.TargetOtherDocPageNumber(page) => (true, Some(page))
  }
}

///|
fn pdf_destination_local_page(
  document : @pdflite.PdfDocument,
  destination : @destination.PdfDestination,
  page_count : Int,
) -> Int? {
  let page = document.page_number_of_target(destination) catch { _ => 0 }
  if page >= 1 && page <= page_count {
    Some(page)
  } else {
    None
  }
}

///|
fn pdf_destination_action_is_remote(
  document : @pdflite.PdfDocument,
  action : @syntax.PdfObject,
) -> Bool {
  match document.lookup_direct(pdf_name_key("/S"), action) {
    Some(@syntax.PdfNameObject(name)) => {
      let value = pdf_destination_name_text(name.bytes()[:])
      value == "GoToR" || value == "Launch"
    }
    _ => false
  }
}

///|
fn pdf_destination_model(
  document : @pdflite.PdfDocument,
  page_count : Int,
  destination : @destination.PdfDestination,
  name : String?,
) -> PdfDestination {
  let local_page = pdf_destination_local_page(document, destination, page_count)
  match destination {
    @destination.DestXYZ(target, left, top, zoom) => {
      let (remote, remote_page) = pdf_destination_target_info(target)
      {
        kind: "XYZ",
        name,
        page: if remote {
          None
        } else {
          local_page
        },
        remote_page,
        left,
        bottom: None,
        right: None,
        top,
        zoom,
        remote,
        resolved: local_page is Some(_) && !remote,
      }
    }
    @destination.DestFit(target) => {
      let (remote, remote_page) = pdf_destination_target_info(target)
      {
        kind: "Fit",
        name,
        page: if remote {
          None
        } else {
          local_page
        },
        remote_page,
        left: None,
        bottom: None,
        right: None,
        top: None,
        zoom: None,
        remote,
        resolved: local_page is Some(_) && !remote,
      }
    }
    @destination.DestFitH(target, top) => {
      let (remote, remote_page) = pdf_destination_target_info(target)
      {
        kind: "FitH",
        name,
        page: if remote {
          None
        } else {
          local_page
        },
        remote_page,
        left: None,
        bottom: None,
        right: None,
        top,
        zoom: None,
        remote,
        resolved: local_page is Some(_) && !remote,
      }
    }
    @destination.DestFitV(target, left) => {
      let (remote, remote_page) = pdf_destination_target_info(target)
      {
        kind: "FitV",
        name,
        page: if remote {
          None
        } else {
          local_page
        },
        remote_page,
        left,
        bottom: None,
        right: None,
        top: None,
        zoom: None,
        remote,
        resolved: local_page is Some(_) && !remote,
      }
    }
    @destination.DestFitR(target, left, bottom, right, top) => {
      let (remote, remote_page) = pdf_destination_target_info(target)
      {
        kind: "FitR",
        name,
        page: if remote {
          None
        } else {
          local_page
        },
        remote_page,
        left: Some(left),
        bottom: Some(bottom),
        right: Some(right),
        top: Some(top),
        zoom: None,
        remote,
        resolved: local_page is Some(_) && !remote,
      }
    }
    @destination.DestFitB(target) => {
      let (remote, remote_page) = pdf_destination_target_info(target)
      {
        kind: "FitB",
        name,
        page: if remote {
          None
        } else {
          local_page
        },
        remote_page,
        left: None,
        bottom: None,
        right: None,
        top: None,
        zoom: None,
        remote,
        resolved: local_page is Some(_) && !remote,
      }
    }
    @destination.DestFitBH(target, top) => {
      let (remote, remote_page) = pdf_destination_target_info(target)
      {
        kind: "FitBH",
        name,
        page: if remote {
          None
        } else {
          local_page
        },
        remote_page,
        left: None,
        bottom: None,
        right: None,
        top,
        zoom: None,
        remote,
        resolved: local_page is Some(_) && !remote,
      }
    }
    @destination.DestFitBV(target, left) => {
      let (remote, remote_page) = pdf_destination_target_info(target)
      {
        kind: "FitBV",
        name,
        page: if remote {
          None
        } else {
          local_page
        },
        remote_page,
        left,
        bottom: None,
        right: None,
        top: None,
        zoom: None,
        remote,
        resolved: local_page is Some(_) && !remote,
      }
    }
    @destination.DestNamed(destination_name) => {
      let destination_name = pdf_destination_name_text(
        destination_name.bytes()[:],
      )
      let display_name : String? = match name {
        Some(value) => Some(value)
        None => Some(destination_name)
      }
      {
        kind: "named",
        name: display_name,
        page: None,
        remote_page: None,
        left: None,
        bottom: None,
        right: None,
        top: None,
        zoom: None,
        remote: false,
        resolved: false,
      }
    }
    @destination.DestString(destination_name) => {
      let destination_name = pdf_destination_string_text(destination_name[:])
      let display_name : String? = match name {
        Some(value) => Some(value)
        None => Some(destination_name)
      }
      {
        kind: "named",
        name: display_name,
        page: None,
        remote_page: None,
        left: None,
        bottom: None,
        right: None,
        top: None,
        zoom: None,
        remote: false,
        resolved: false,
      }
    }
    @destination.DestAction(action) => {
      let remote = pdf_destination_action_is_remote(document, action)
      {
        kind: "action",
        name,
        page: if remote {
          None
        } else {
          local_page
        },
        remote_page: None,
        left: None,
        bottom: None,
        right: None,
        top: None,
        zoom: None,
        remote,
        resolved: local_page is Some(_) && !remote,
      }
    }
    @destination.DestNull =>
      {
        kind: "null",
        name,
        page: None,
        remote_page: None,
        left: None,
        bottom: None,
        right: None,
        top: None,
        zoom: None,
        remote: false,
        resolved: false,
      }
  }
}

///|
fn pdf_named_destination_entries(
  document : @pdflite.PdfDocument,
) -> Array[(String, @syntax.PdfObject)] raise @core.PdfError {
  let catalog = document.catalog()
  let output : Array[(String, @syntax.PdfObject)] = []
  let seen : Map[String, Bool] = Map([])
  let push = fn(name : String, destination : @syntax.PdfObject) -> Unit {
    if !seen.contains(name) {
      seen[name] = true
      output.push((name, destination))
    }
  }
  match document.lookup_direct(pdf_name_key("/Dests"), catalog) {
    Some(@syntax.PdfDictionary(entries)) =>
      for (name, destination) in entries {
        push(pdf_destination_name_text(name.bytes()[:]), destination)
      }
    _ => ()
  }
  match document.lookup_direct(pdf_name_key("/Names"), catalog) {
    Some(names) =>
      match document.lookup_direct(pdf_name_key("/Dests"), names) {
        Some(dest_tree) =>
          for (name, destination) in document.read_name_tree(dest_tree) {
            push(pdf_destination_string_text(name[:]), destination)
          }
        None => ()
      }
    None => ()
  }
  output
}

///|
fn pdf_named_destination_model(
  document : @pdflite.PdfDocument,
  page_count : Int,
  name : String,
  raw_destination : @syntax.PdfObject,
) -> PdfNamedDestination {
  let shallow = document.read_destination(raw_destination, shallow=true) catch {
    _ => @destination.DestNull
  }
  let resolved = document.read_destination(raw_destination) catch {
    _ => shallow
  }
  {
    name,
    destination: pdf_destination_model(
      document,
      page_count,
      resolved,
      Some(name),
    ),
  }
}

///|
/// Return all named destinations from both PDF catalog forms: the legacy
/// `/Dests` dictionary and the `/Names` `/Dests` name tree.
pub fn PdfViewerDocument::named_destinations(
  self : PdfViewerDocument,
) -> Array[PdfNamedDestination] raise @core.PdfError {
  [
    for entry in pdf_named_destination_entries(self.document) => {
      pdf_named_destination_model(
        self.document,
        self.pages.length(),
        entry.0,
        entry.1,
      )
    }
  ]
}

///|
/// Return named destinations as a JSON array for a host that does not want to
/// depend on MoonBit constructors.
pub fn PdfViewerDocument::named_destinations_json(
  self : PdfViewerDocument,
) -> Json raise @core.PdfError {
  Json::array(
    [
      for destination in self.named_destinations() => {
        ToJson::to_json(destination)
      }
    ],
  )
}

///|
/// Resolve one local named destination. Names are compared after removing a
/// leading slash, matching PDF name tokens and the host-facing API.
pub fn PdfViewerDocument::named_destination(
  self : PdfViewerDocument,
  name : String,
) -> PdfDestination? raise @core.PdfError {
  let query = if name.has_prefix("/") { name[1:].to_owned() } else { name }
  for destination in self.named_destinations() {
    if destination.name == query {
      return Some(destination.destination)
    }
  }
  None
}

///|
/// Build an explicit fit destination for a local one-based page number.
/// Invalid page numbers return `None` rather than a remote or null target.
pub fn PdfViewerDocument::destination_for_page(
  self : PdfViewerDocument,
  page_number : Int,
) -> PdfDestination? raise @core.PdfError {
  if page_number < 1 || page_number > self.pages.length() {
    None
  } else {
    let destination = self.document.target_of_page_number(page_number)
    Some(
      pdf_destination_model(
        self.document,
        self.pages.length(),
        destination,
        None,
      ),
    )
  }
}

///|
/// Return flattened outline entries with typed destination data. This keeps
/// explicit page destinations and preserved named/action targets usable by a
/// browser or another host without exposing pdflite's object dictionaries.
pub fn PdfViewerDocument::outline_navigation_json(
  self : PdfViewerDocument,
) -> Json raise @core.PdfError {
  let bookmarks : Array[@bookmark.PdfBookmark] = self.document.read_bookmarks(
    preserve_actions=true,
  )
  Json::array(
    [
      for bookmark in bookmarks => {
        let title = pdf_destination_string_text(bookmark.text[:])
        let destination = pdf_destination_model(
          self.document,
          self.pages.length(),
          bookmark.target,
          None,
        )
        Json::object({
          "level": Json::number(bookmark.level.to_double()),
          "title": Json::string(title),
          "open": Json::boolean(bookmark.is_open),
          "destination": ToJson::to_json(destination),
        })
      }
    ],
  )
}

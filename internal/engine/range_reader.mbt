///|
/// A segmented, unencrypted reader. The host supplies byte ranges; syntax,
/// xref and object-stream decoding remain pdflite operations.
pub struct PdfRangeReader {
  priv document : @pdflite.PdfDocument
  priv length : Int
  priv pending : Array[(Int, Int)]
  priv sections : Map[Int, Unit]
  priv entries : Map[Int, (Int, @reader.PdfClassicXRefEntry)]
  priv offset_ends : Map[Int, Int]
  priv trailer : Ref[@syntax.PdfObject]
  priv spans : Map[Int, PdfByteSpan]
  priv loaded : Map[Int, Unit]
  priv page_roots : Array[Array[@syntax.PdfObject]]
  priv streams : Map[Int, (Int, Int)]
  priv protected : Ref[Map[Int, Unit]]
  priv retained : Ref[Int]
  priv tick : Ref[Int]
  priv evictions : Ref[Int]
  priv stream_budget : Int
}

///|
pub fn open_range_reader(
  header : Bytes,
  tail : Bytes,
  length : Int,
  stream_budget? : Int = 67108864,
) -> PdfRangeReader raise @core.PdfError {
  guard length > 0 else { raise @core.SoftError("Invalid PDF length") }
  guard stream_budget > 0 else {
    raise @core.SoftError("Invalid range cache budget")
  }
  let version = @reader.pdf_read_header_from_bytes(header)
  let start = @reader.pdf_read_startxref_position(tail)
  guard start > 0 && start < length else { raise @core.XRefExpected }
  let document = @pdflite.pdf_document_empty()
  document.set_version(version.major, version.minor)
  {
    document,
    length,
    pending: [(start, 1)],
    sections: Map([]),
    entries: Map([]),
    offset_ends: Map([]),
    trailer: Ref(@syntax.PdfNull),
    spans: Map([]),
    loaded: Map([]),
    page_roots: [],
    streams: Map([]),
    protected: Ref(Map([])),
    retained: Ref(0),
    tick: Ref(0),
    evictions: Ref(0),
    stream_budget,
  }
}

///|
pub fn PdfRangeReader::next_section(self : PdfRangeReader) -> Int? {
  self.pending.get(0).map(entry => entry.0)
}

///|
pub fn PdfRangeReader::install_section(
  self : PdfRangeReader,
  offset : Int,
  bytes : Bytes,
) -> Unit raise @core.PdfError {
  guard self.pending.get(0) is Some((wanted, rank)) && wanted == offset else {
    raise @core.XRefExpected
  }
  // Parsing at local offset zero retains absolute object offsets from the xref.
  let section = pdf_recovery_xref_section(bytes, 0, self.document)
  if section.trailer.lookup_immediate(pdf_name_key("/Encrypt")) is Some(value) &&
    value != @syntax.PdfNull {
    raise @core.SoftError(
      "range-encrypted: encrypted documents require complete password authentication",
    )
  }
  if self.sections.length() >= 1024 {
    raise @core.XRefExpected
  }
  if @reader.pdf_trailer_prev_position(section.trailer) is Some(previous) &&
    (previous == offset || self.sections.contains(previous)) {
    raise @core.XRefEntryExpected
  }
  self.sections[offset] = ()
  ignore(self.pending.remove(0))
  for entry in section.entries {
    if entry.offset < 0 || entry.offset >= self.length {
      if entry.in_use && entry.object_stream is None {
        raise @core.XRefEntryExpected
      }
    }
    match self.entries.get(entry.object_number) {
      Some((old_rank, _)) if old_rank <= rank => ()
      _ => self.entries[entry.object_number] = (rank, entry)
    }
  }
  if self.trailer.val is @syntax.PdfNull {
    self.trailer.val = section.trailer
  } else if section.trailer is @syntax.PdfDictionary(values) {
    for (key, value) in values {
      if self.trailer.val.lookup_immediate(key) is None {
        self.trailer.val = self.trailer.val.add_dict_entry(key, value)
      }
    }
  }
  if @reader.pdf_trailer_xref_stream_position(section.trailer) is Some(hybrid) &&
    !self.sections.contains(hybrid) &&
    !self.pending.any(item => item.0 == hybrid) {
    self.pending.push((hybrid, rank - 1))
  }
  if @reader.pdf_trailer_prev_position(section.trailer) is Some(previous) &&
    !self.sections.contains(previous) &&
    !self.pending.any(item => item.0 == previous) {
    self.pending.push((previous, rank / 2 * 2 + 3))
  }
  if self.pending.is_empty() {
    let physical : Array[(Int, Int)] = []
    for (_, (_, entry)) in self.entries {
      if entry.in_use && entry.object_stream is None {
        physical.push((entry.offset, entry.object_number))
      }
    }
    physical.sort()
    let mut next = self.length
    let mut last = self.length
    for step in 0..<physical.length() {
      let (start, number) = physical[physical.length() - 1 - step]
      if start < last {
        next = last
      }
      self.offset_ends[number] = next
      last = start
    }
    self.document.set_trailer_dict(self.trailer.val)
    guard self.trailer.val.lookup_immediate(pdf_name_key("/Root"))
      is Some(@syntax.PdfIndirect(root)) else {
      raise @core.RootExpected
    }
    self.document.set_root(root)
  }
}

///|
/// Describe a physical object range. Object-stream members request their
/// container once and are installed together using the active xref entries.
pub fn PdfRangeReader::object_request(
  self : PdfRangeReader,
  number : Int,
) -> (Int, Int, Int)? {
  let mut number = number
  let visited : Map[Int, Unit] = Map([])
  for ;; {
    if visited.contains(number) || visited.length() >= 64 {
      return None
    }
    visited[number] = ()
    guard self.entries.get(number) is Some((_, entry)) && entry.in_use else {
      return None
    }
    match entry.object_stream {
      Some(stream) => number = stream.object_stream_number
      None => break
    }
  }
  guard self.entries.get(number) is Some((_, entry)) else { return None }
  let end = self.offset_ends.get(number).unwrap_or(self.length)
  Some((entry.object_number, entry.offset, end))
}

///|
pub fn PdfRangeReader::install_object(
  self : PdfRangeReader,
  number : Int,
  bytes : Bytes,
) -> Unit raise @core.PdfError {
  guard self.entries.get(number) is Some((_, entry)) &&
    entry.in_use &&
    entry.object_stream is None else {
    raise @core.XRefEntryExpected
  }
  let stream_start : Ref[Int?] = Ref(None)
  let parsed = pdf_recovery_object(
    bytes,
    0,
    self.document,
    stream_start=Some(stream_start),
    require_end=true,
  )
  if parsed.number != number || parsed.generation != entry.generation {
    raise @core.XRefEntryExpected
  }
  // Validate every compressed member before publishing any parsed state.
  let members : Array[(Int, @syntax.PdfObject)] = []
  if parsed.object.lookup_immediate(pdf_name_key("/Type")) ==
    Some(@syntax.PdfNameObject(pdf_name_key("/ObjStm"))) ||
    (
      parsed.object is @syntax.PdfStreamObject(stream) &&
      stream.dictionary.lookup_immediate(pdf_name_key("/Type")) ==
      Some(@syntax.PdfNameObject(pdf_name_key("/ObjStm")))
    ) {
    let decoded = self.document.pdf_decode_stream(parsed.object)
    guard decoded is @syntax.PdfStreamObject(stream) else {
      raise @core.ParseStreamExpected
    }
    guard stream.dictionary.lookup_immediate(pdf_name_key("/N"))
      is Some(@syntax.PdfInteger(count)) &&
      stream.dictionary.lookup_immediate(pdf_name_key("/First"))
      is Some(@syntax.PdfInteger(first)) else {
      raise @core.XRefEntryExpected
    }
    let data = @syntax.pdf_stream_data_bytes(stream.data)
    let pairs = @reader.pdf_object_stream_number_offsets(data, first, count)
    let ends = @reader.pdf_object_stream_end_offsets(
      pairs,
      data.length(),
      first,
    )
    for (_, (_, member)) in self.entries {
      guard member.in_use &&
        member.object_stream is Some(reference) &&
        reference.object_stream_number == number else {
        continue
      }
      guard pairs.get(reference.index) is Some((member_number, start)) &&
        member_number == member.object_number else {
        raise @core.XRefEntryExpected
      }
      let end = ends[reference.index]
      if start < 0 || end < start || first + end > data.length() {
        raise @core.XRefEntryExpected
      }
      let object = @syntax.pdf_parse_object_from_view(
        data[first + start:first + end],
      )
      members.push((member_number, object))
    }
  }
  if parsed.object is @syntax.PdfStreamObject(stream) {
    let size = @syntax.pdf_stream_data_bytes(stream.data).length()
    if size > self.stream_budget {
      raise @core.SoftError("Range stream exceeds retained-object budget")
    }
    let old_size = self.streams.get(number).map(value => value.0).unwrap_or(0)
    while self.retained.val - old_size + size > self.stream_budget ||
          (!self.streams.contains(number) && self.streams.length() >= 4096) {
      let mut victim : (Int, Int)? = None
      for (candidate, (_, tick)) in self.streams {
        if candidate == number || self.protected.val.contains(candidate) {
          continue
        }
        if victim.map(value => value.1 > tick).unwrap_or(true) {
          victim = Some((candidate, tick))
        }
      }
      guard victim is Some((candidate, _)) else {
        raise @core.SoftError("Page resources exceed the range object budget")
      }
      let (old_size, _) = self.streams[candidate]
      self.retained.val -= old_size
      self.streams.remove(candidate)
      self.loaded.remove(candidate)
      self.document.remove_object(candidate)
      self.evictions.val += 1
    }
    if self.streams.get(number) is Some((old_size, _)) {
      self.retained.val -= old_size
    }
    self.tick.val += 1
    self.streams[number] = (size, self.tick.val)
    self.retained.val += size
  }
  self.document.add_object_given_number(
    number,
    parsed.object,
    generation=parsed.generation,
  )
  self.loaded[number] = ()
  if stream_start.val is Some(start) &&
    parsed.object is @syntax.PdfStreamObject(stream) {
    let length = @syntax.pdf_stream_data_bytes(stream.data).length()
    self.spans[number] = {
      start: entry.offset + start,
      end: entry.offset + start + length,
    }
  }

  for (member_number, object) in members {
    self.document.add_object_given_number(member_number, object)
    self.loaded[member_number] = ()
  }
}

///|
/// Missing references reachable from the page tree, one page, structure, or metadata.
/// Following parents of fields is required; page parents and page backlinks
/// are excluded so one page cannot pull in other pages' images or content.
pub fn PdfRangeReader::missing(
  self : PdfRangeReader,
  mode : String,
  page : Int,
) -> Array[Int] raise @core.PdfError {
  guard self.pending.is_empty() else { raise @core.XRefExpected }
  let seen : Map[Int, Unit] = Map([])
  let missing : Array[Int] = []
  let boot = mode == "pages"
  let pending : Array[(@syntax.PdfObject, @syntax.PdfObject?, Int)] = []
  if boot {
    self.page_roots.clear()
    pending.push((@syntax.PdfIndirect(self.document.root()), None, 0))
  } else if mode == "page" {
    guard self.page_roots.get(page - 1) is Some(roots) else {
      raise @core.PageTreeExpected
    }
    for root in roots {
      pending.push((root, None, 0))
    }
    let catalog = self.document.lookup_object_or_null(self.document.root())
    if catalog.lookup_immediate(pdf_name_key("/AcroForm")) is Some(form) {
      pending.push((form, None, 0))
    }
    if catalog.lookup_immediate(pdf_name_key("/OCProperties"))
      is Some(properties) {
      pending.push((properties, None, 0))
    }
  } else if mode == "structure" {
    let catalog = self.document.lookup_object_or_null(self.document.root())
    if catalog.lookup_immediate(pdf_name_key("/StructTreeRoot")) is Some(root) {
      pending.push((root, None, 0))
    }
    if catalog.lookup_immediate(pdf_name_key("/Lang")) is Some(lang) {
      pending.push((lang, None, 0))
    }
  } else if mode == "metadata" || mode == "all" {
    pending.push((self.trailer.val, None, 0))
  } else {
    raise @core.SoftError("Unknown range graph")
  }
  let mut visits = 0
  while pending.pop() is Some((object, inherited, depth)) {
    visits += 1
    if depth > 256 || visits > 262144 {
      raise @core.SoftError("Range object graph exceeds traversal budget")
    }
    match object {
      @syntax.PdfIndirect(number) => {
        if seen.contains(number) {
          continue
        }
        seen[number] = ()
        if !self.loaded.contains(number) {
          if self.entries.get(number) is Some((_, entry)) && entry.in_use {
            missing.push(number)
          }
        } else {
          pending.push(
            (self.document.lookup_object_or_null(number), inherited, depth + 1),
          )
        }
      }
      @syntax.PdfArray(values) =>
        for index in 0..<values.length() {
          pending.push(
            (values[values.length() - 1 - index], inherited, depth + 1),
          )
        }
      @syntax.PdfDictionary(values) => {
        let kind = object.lookup_immediate(pdf_name_key("/Type"))
        let leaf = kind == Some(@syntax.PdfNameObject(pdf_name_key("/Page")))
        if (mode == "metadata" || mode == "structure") && leaf {
          continue
        }
        let resources = match
          object.lookup_immediate(pdf_name_key("/Resources")) {
          Some(value) => Some(value)
          None => inherited
        }
        if boot && leaf {
          let roots = [object]
          if resources is Some(resources) {
            roots.push(resources)
          }
          self.page_roots.push(roots)
        }
        for (key, value) in values {
          let key = pdf_annotation_name_text(key)
          let key = if key.has_prefix("/") { key[1:].to_owned() } else { key }
          if boot {
            if [
                "Type", "Pages", "Kids", "MediaBox", "CropBox", "Rotate", "UserUnit",
              ].contains(key) {
              pending.push((value, resources, depth + 1))
            }
          } else {
            if mode != "all" &&
              (
                key == "Pages" ||
                (
                  key == "Kids" &&
                  kind == Some(@syntax.PdfNameObject(pdf_name_key("/Pages")))
                ) ||
                key == "P" ||
                (
                  key == "Parent" &&
                  (
                    leaf ||
                    kind == Some(@syntax.PdfNameObject(pdf_name_key("/Pages")))
                  )
                )
              ) {
              continue
            }
            if mode == "page" && (key == "Fields" || key == "XFA") {
              continue
            }
            // Page hydration owns content and annotation streams. Structure
            // backlinks must not download resources from off-screen pages.
            if (mode == "structure" || mode == "metadata") &&
              (key == "Pg" || key == "Stm" || key == "Obj") {
              continue
            }
            pending.push((value, None, depth + 1))
          }
        }
      }
      @syntax.PdfStreamObject(stream) =>
        pending.push((stream.dictionary, None, depth + 1))
      _ => ()
    }
  }
  self.protected.val = seen
  self.tick.val += 1
  for number in seen.keys() {
    if self.streams.get(number) is Some((size, _)) {
      self.streams[number] = (size, self.tick.val)
    }
  }
  missing
}

///|
pub fn PdfRangeReader::object_loaded(
  self : PdfRangeReader,
  number : Int,
) -> Bool {
  self.loaded.contains(number)
}

///|
pub fn PdfRangeReader::cache_info(self : PdfRangeReader) -> Json {
  {
    "stream_bytes": self.retained.val,
    "stream_budget_bytes": self.stream_budget,
    "stream_entries": self.streams.length(),
    "evictions": self.evictions.val,
  }
}

///|
/// Materialize page records after the requested objects have been installed.
pub fn PdfRangeReader::document_view(
  self : PdfRangeReader,
) -> PdfViewerDocument raise @core.PdfError {
  let (document, pages, reader_observations) = pdf_page_tree_for_viewer(
    self.document,
  )
  {
    source_length: self.length,
    source_bytes: b"",
    source_stream_spans: self.spans,
    document,
    pages,
    optional_content_state: None,
    font_fallbacks: [],
    canvas_resources: pdf_canvas_resource_cache(),
    parsed_fonts: None,
    accessibility_sources: Ref(None),
    reader_observations,
    editor_security: None,
  }
}

///|
/// Resolve an indirect stream length before reading the stream body.
pub fn PdfRangeReader::object_dependencies(
  self : PdfRangeReader,
  bytes : Bytes,
) -> Array[Int] raise @core.PdfError {
  let parsed = pdf_recovery_object(bytes, 0, self.document, header_only=true)
  let mut length = parsed.object
    .lookup_immediate(pdf_name_key("/Length"))
    .unwrap_or(@syntax.PdfNull)
  let visited : Map[Int, Unit] = Map([])
  for ;; {
    match length {
      @syntax.PdfIndirect(number) => {
        if visited.contains(number) || visited.length() >= 64 {
          raise @core.StreamLengthExpected
        }
        visited[number] = ()
        if !self.loaded.contains(number) {
          return [number]
        }
        length = self.document.lookup_object_or_null(number)
      }
      _ => return []
    }
  }
}

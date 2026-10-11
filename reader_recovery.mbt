///|
/// The strict reader may reconstruct only physical objects when an unrelated
/// xref points at an invalid offset. Recover compressed members from the active
/// xref chain, including free entries, instead of scanning every old ObjStm.
fn pdf_recover_compressed_document(
  bytes : Bytes,
  original : @pdflite.PdfDocument,
  source_spans? : Map[Int, PdfByteSpan]? = None,
) -> @pdflite.PdfDocument raise @core.PdfError {
  if original.is_encrypted() {
    raise @core.PageTreeExpected
  }
  let entries : Map[Int, @reader.PdfClassicXRefEntry] = Map([])
  let visited : Map[Int, Unit] = Map([])
  let mut position = Some(@reader.pdf_read_startxref_position(bytes))
  let mut trailer : @syntax.PdfObject? = None
  while position is Some(offset) {
    if visited.contains(offset) || visited.length() >= 1024 {
      raise @core.XRefEntryExpected
    }
    visited[offset] = ()
    let section = pdf_recovery_xref_section(bytes, offset, original)
    match trailer {
      None => trailer = Some(section.trailer)
      Some(current) => {
        let mut merged = current
        if section.trailer is @syntax.PdfDictionary(values) {
          for (key, value) in values {
            if merged.lookup_immediate(key) is None {
              merged = merged.add_dict_entry(key, value)
            }
          }
        }
        trailer = Some(merged)
      }
    }
    // In a hybrid section the stream overrides the classic table from the
    // same revision, but neither may replace an entry from a newer revision.
    if @reader.pdf_trailer_xref_stream_position(section.trailer) is Some(hybrid) {
      let supplement = pdf_recovery_xref_section(bytes, hybrid, original)
      for entry in supplement.entries {
        if !entries.contains(entry.object_number) {
          entries[entry.object_number] = entry
        }
      }
    }
    for entry in section.entries {
      if !entries.contains(entry.object_number) {
        entries[entry.object_number] = entry
      }
    }
    position = @reader.pdf_trailer_prev_position(section.trailer)
  }
  guard trailer is Some(trailer) else { raise @core.TrailerExpected }
  // A partial initial reconstruction can lose /Encrypt along with the stream
  // trailer. Never treat compressed ciphertext as ordinary object syntax.
  if trailer.lookup_immediate(pdf_name_key("/Encrypt")) is Some(_) {
    raise @core.PageTreeExpected
  }
  let document = @pdflite.pdf_document_empty()
  let (major, minor) = original.version()
  document.set_version(major, minor)
  document.set_trailer_dict(trailer)
  match trailer.lookup_immediate(pdf_name_key("/Root")) {
    Some(@syntax.PdfIndirect(root)) => document.set_root(root)
    _ => raise @core.RootExpected
  }
  for (_, entry) in entries {
    if !entry.in_use ||
      entry.object_number <= 0 ||
      entry.object_stream is Some(_) {
      continue
    }
    let stream_start : Ref[Int?] = Ref(None)
    let parsed = pdf_recovery_object(
      bytes,
      entry.offset,
      original,
      stream_start=Some(stream_start),
    ) catch {
      _ => continue
    }
    if parsed.number == entry.object_number &&
      parsed.generation == entry.generation {
      document.add_object_given_number(
        parsed.number,
        parsed.object,
        generation=parsed.generation,
      )
      if source_spans is Some(spans) &&
        stream_start.val is Some(start) &&
        parsed.object is @syntax.PdfStreamObject(stream) {
        let length = @syntax.pdf_stream_data_bytes(stream.data).length()
        spans[parsed.number] = { start, end: start + length, }
      }
    }
  }
  let active = entries.values().collect()
  for (number, references) in @reader.pdf_reader_object_stream_groups(active) {
    let decoded = document.pdf_decode_stream(
      document.lookup_object_or_null(number),
    ) catch {
      _ => continue
    }
    guard decoded is @syntax.PdfStreamObject(stream) else { continue }
    if stream.dictionary.lookup_immediate(pdf_name_key("/Type")) !=
      Some(@syntax.PdfNameObject(pdf_name_key("/ObjStm"))) {
      continue
    }
    guard stream.dictionary.lookup_immediate(pdf_name_key("/N"))
      is Some(@syntax.PdfInteger(count)) else {
      continue
    }
    guard stream.dictionary.lookup_immediate(pdf_name_key("/First"))
      is Some(@syntax.PdfInteger(first)) else {
      continue
    }
    let data = @syntax.pdf_stream_data_bytes(stream.data)
    let pairs = @reader.pdf_object_stream_number_offsets(data, first, count) catch {
      _ => continue
    }
    let ends = @reader.pdf_object_stream_end_offsets(
      pairs,
      data.length(),
      first,
    )
    for (entry, reference) in references {
      guard pairs.get(reference.index) is Some((member_number, start)) else {
        continue
      }
      let end = ends[reference.index]
      if member_number != entry.object_number ||
        start > end ||
        start > data.length() - first ||
        end > data.length() - first {
        continue
      }
      let object = @syntax.pdf_parse_object_from_view(
        data[first + start:first + end],
      ) catch {
        _ => continue
      }
      document.add_object_given_number(member_number, object)
    }
  }
  document
}

///|
fn pdf_recovery_xref_section(
  bytes : Bytes,
  offset : Int,
  document : @pdflite.PdfDocument,
) -> @reader.PdfXRefSection raise @core.PdfError {
  if offset < 0 || offset >= bytes.length() {
    raise @core.XRefExpected
  }
  let cursor = @core.byte_cursor_of_view(bytes)
  cursor.seek_absolute(offset)
  @syntax.pdf_cursor_drop_whitespace(cursor)
  if @syntax.pdf_cursor_matches_ascii_at(cursor, cursor.absolute_position(), [
      120, 114, 101, 102,
    ]) {
    let entries = @reader.pdf_cursor_read_classic_xref_entries(cursor)
    {
      entries,
      trailer: @reader.pdf_cursor_read_trailer_dictionary(cursor),
      stream_object_number: None,
      stream_object_offset: None,
    }
  } else {
    let parsed = pdf_recovery_object(bytes, offset, document)
    guard parsed.object is @syntax.PdfStreamObject(stream) else {
      raise @core.XRefExpected
    }
    if !@reader.pdf_reader_xref_stream_type_ok(stream.dictionary) {
      raise @core.XRefExpected
    }
    guard document.pdf_decode_stream(parsed.object)
      is @syntax.PdfStreamObject(decoded) else {
      raise @core.XRefExpected
    }
    let data = @syntax.pdf_stream_data_bytes(decoded.data)
    {
      entries: @reader.pdf_xref_stream_entries(
        data,
        @reader.pdf_xref_stream_widths(decoded.dictionary),
        @reader.pdf_xref_stream_index_pairs(decoded.dictionary),
      ),
      trailer: @reader.pdf_reader_stream_dictionary_without_xref_keys(
        decoded.dictionary,
      ),
      stream_object_number: Some(parsed.number),
      stream_object_offset: Some(offset),
    }
  }
}

///|
fn pdf_recovery_object(
  bytes : Bytes,
  offset : Int,
  document : @pdflite.PdfDocument,
  stream_start? : Ref[Int?]? = None,
  require_end? : Bool = false,
  header_only? : Bool = false,
) -> @syntax.PdfParsedIndirectObject raise @core.PdfError {
  if offset < 0 || offset >= bytes.length() {
    raise @core.XRefEntryExpected
  }
  let cursor = @core.byte_cursor_of_view(bytes)
  cursor.seek_absolute(offset)
  let tokens : Array[@syntax.PdfLexeme] = []
  // Stop at this object's end marker. Lexing until the next stream would
  // attach that later stream's body to an earlier dictionary such as /Catalog.
  for ;; {
    match @syntax.pdf_cursor_lex_token(cursor) {
      @syntax.StopLexing | @syntax.LexNone => break
      @syntax.LexEndObj as token => {
        tokens.push(token)
        break
      }
      token => tokens.push(token)
    }
  }
  let parsed = @syntax.pdf_parse_indirect_object_prefix_lexemes(tokens)
  if header_only {
    return parsed
  }
  if tokens.last() is Some(@syntax.LexEndObj) {
    return parsed
  }
  if !@syntax.pdf_cursor_matches_ascii_at(cursor, cursor.absolute_position(), [
      115, 116, 114, 101, 97, 109,
    ]) {
    if require_end {
      raise @core.ParseEndObjectExpected
    }
    return parsed
  }
  guard parsed.object is @syntax.PdfDictionary(_) else {
    raise @core.ParseStreamExpected
  }
  cursor.seek_absolute(cursor.absolute_position() + 6)
  // PDF stream data begins after CR, LF, or CRLF; its length is byte based.
  if cursor.peek_byte() == 13 {
    ignore(cursor.read_byte())
    if cursor.peek_byte() == 10 {
      ignore(cursor.read_byte())
    }
  } else if cursor.peek_byte() == 10 {
    ignore(cursor.read_byte())
  } else {
    raise @core.ParseStreamExpected
  }
  guard document.lookup_direct(pdf_name_key("/Length"), parsed.object)
    is Some(@syntax.PdfInteger(length)) else {
    raise @core.StreamLengthExpected
  }
  if length < 0 || length > bytes.length() - cursor.absolute_position() {
    raise @core.StreamDataExpected
  }
  if stream_start is Some(output) {
    output.val = Some(cursor.absolute_position())
  }
  let data = cursor.read_bytes(length)
  @syntax.pdf_cursor_drop_whitespace(cursor)
  @reader.pdf_cursor_consume_ascii(
    cursor,
    [101, 110, 100, 115, 116, 114, 101, 97, 109],
    @core.ParseEndStreamExpected,
  )
  pdf_recovery_drop_trivia(cursor)
  @reader.pdf_cursor_consume_ascii(
    cursor,
    [101, 110, 100, 111, 98, 106],
    @core.ParseEndObjectExpected,
  )
  {
    ..parsed,
    object: @syntax.pdf_stream(parsed.object, @syntax.StreamGot(data)),
  }
}

///|
/// A comment is legal between endstream and endobj. pdflite 0.2.2's stream
/// reader drops that otherwise-valid object, even with a correct /Length.
fn pdf_recovery_drop_trivia(cursor : @core.ByteCursor) -> Unit {
  for ;; {
    @syntax.pdf_cursor_drop_whitespace(cursor)
    if cursor.peek_byte() != 37 {
      break
    }
    ignore(@syntax.pdf_cursor_lex_comment(cursor))
  }
}

///|
fn pdf_reader_has_dropped_page_contents(
  document : @pdflite.PdfDocument,
) -> Bool {
  for number in document.object_numbers() {
    let object = document.lookup_object_or_null(number)
    if object.lookup_immediate(pdf_name_key("/Type")) ==
      Some(@syntax.PdfNameObject(pdf_name_key("/Page"))) {
      match object.lookup_immediate(pdf_name_key("/Contents")) {
        Some(contents) =>
          if pdf_reader_has_dropped_content_reference(document, contents, 0) {
            return true
          }
        None => ()
      }
    }
  }
  false
}

///|
fn pdf_reader_has_dropped_content_reference(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  depth : Int,
) -> Bool {
  if depth >= 32 {
    return false
  }
  match object {
    @syntax.PdfIndirect(number) => {
      let resolved = document.lookup_object_or_null(number)
      resolved == @syntax.PdfNull ||
      pdf_reader_has_dropped_content_reference(document, resolved, depth + 1)
    }
    @syntax.PdfArray(items) =>
      items.any(item => {
        pdf_reader_has_dropped_content_reference(document, item, depth + 1)
      })
    _ => false
  }
}

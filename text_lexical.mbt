///|
/// A half-open byte range. The containing field specifies its coordinate
/// space; decoded-stream offsets must never be interpreted as file offsets.
pub(all) struct PdfByteSpan {
  start : Int
  end : Int
} derive(Eq, Debug, ToJson)

///|
/// One part of a glyph's literal/hex spelling in a decoded content stream.
/// file_span exists only for a verified unfiltered, unencrypted lazy stream.
/// encoded_stream_span is the entire original stream payload, when known;
/// it is not a glyph's compressed/encrypted file position. A code can have
/// several spans (escapes, hex whitespace or concatenated content streams).
pub(all) struct PdfTextByteSpan {
  stream_index : Int
  object_number : Int?
  decoded_stream_span : PdfByteSpan
  file_span : PdfByteSpan?
  encoded_stream_span : PdfByteSpan?
} derive(Eq, Debug, ToJson)

///|
/// Paint-order glyph origins, including glyphs with an empty copied string.
/// logical_source is absent for these empty glyphs. failure explains why a
/// lexical association could not be verified; unavailable offsets are absent.
/// Form identity and decoded charcode bytes remain in string_source.
pub(all) struct PdfTextLexicalSource {
  item_index : Int
  logical_source : PdfTextSourceRange?
  string_source : PdfTextStringSource?
  spans : Array[PdfTextByteSpan]
  failure : String?
} derive(Eq, Debug, ToJson)

///|
priv struct PdfTextLocatedString {
  bytes : Bytes
  spelling : Array[PdfByteSpan]?
}

///|
priv struct PdfTextLocatedStream {
  index : Int
  number : Int?
  start : Int
  end : Int
  file_start : Int?
  encoded : PdfByteSpan?
}

///|
priv struct PdfTextLocatedScope {
  streams : Array[Int?]
  forms : Array[PdfTextFormInvocation]
  frames : Array[PdfTextLocatedStream]
  strings : Map[(Int, Int), PdfTextLocatedString]?
}

///|
/// Only map spelling after pdflite has decoded and validated the token.
/// The recovered bytes are compared again; a lexer-policy mismatch cannot
/// silently create incorrect offsets. Line continuations produce no byte.
fn pdf_text_string_spelling(
  data : BytesView,
  start : Int,
  end : Int,
  expected : Bytes,
) -> Array[PdfByteSpan]? {
  guard expected.length() <= 262144 &&
    start >= 0 &&
    end > start + 1 &&
    end <= data.length() else {
    return None
  }
  let spans : Array[PdfByteSpan] = []
  let decoded : Array[Byte] = []
  let mut position = start + 1
  if data[start] == b'(' && data[end - 1] == b')' {
    while position < end - 1 {
      let first = position
      let mut value = data[position].to_int()
      position += 1
      if value == 92 {
        guard position < end - 1 else { return None }
        value = data[position].to_int()
        position += 1
        if value == 10 || value == 13 {
          if value == 13 && position < end - 1 && data[position] == b'\n' {
            position += 1
          }
          continue
        }
        if value >= 48 && value <= 55 {
          value -= 48
          for _ in 0..<2 {
            guard position < end - 1 &&
              data[position] >= b'0' &&
              data[position] <= b'7' else {
              break
            }
            value = value * 8 + data[position].to_int() - 48
            position += 1
          }
          value = value & 255
        } else {
          value = match value {
            110 => 10
            114 => 13
            116 => 9
            98 => 8
            102 => 12
            _ => value
          }
        }
      }
      decoded.push(value.to_byte())
      spans.push({ start: first, end: position, })
    }
  } else if data[start] == b'<' && data[end - 1] == b'>' {
    let mut high : (Int, Int)? = None
    while position < end - 1 {
      let at = position
      let byte = data[position].to_int()
      position += 1
      if @core.pdf_is_whitespace_byte(byte) {
        continue
      }
      let nibble = match byte {
        48..=57 => byte - 48
        65..=70 => byte - 55
        97..=102 => byte - 87
        _ => return None
      }
      match high {
        Some((first, value)) => {
          decoded.push((value * 16 + nibble).to_byte())
          spans.push({ start: first, end: position, })
          high = None
        }
        None => high = Some((at, nibble))
      }
    }
    if high is Some((first, value)) {
      decoded.push((value * 16).to_byte())
      spans.push({ start: first, end: first + 1, })
    }
  } else {
    return None
  }
  if Bytes::from_array(decoded) == expected {
    Some(spans)
  } else {
    None
  }
}

///|
/// Consume an operand with the existing syntax lexer/parser, remembering only
/// root strings and immediate array strings (TJ operands). Nested objects
/// count as one array member, but their strings are not text operands.
fn pdf_text_located_operand(
  cursor : @core.ByteCursor,
) -> (@syntax.PdfObject, Array[(Int, PdfTextLocatedString)]) raise @core.PdfError {
  let start = cursor.position()
  let first = @syntax.pdf_cursor_lex_token(cursor)
  let tokens = [first]
  let strings : Array[(Int, PdfTextLocatedString)] = []
  if first is @syntax.LexString(bytes) {
    strings.push(
      (
        0,
        {
          bytes,
          spelling: pdf_text_string_spelling(
            cursor.view(),
            start,
            cursor.position(),
            bytes,
          ),
        },
      ),
    )
  }
  let root_array = first == @syntax.LexLeftSquare
  let mut depth = match first {
    @syntax.LexLeftSquare | @syntax.LexLeftDict => 1
    _ => 0
  }
  let mut element_index = 0
  while depth > 0 {
    @syntax.pdf_cursor_drop_whitespace(cursor)
    let start = cursor.position()
    let before = depth
    let token = @syntax.pdf_cursor_lex_token(cursor)
    match token {
      @syntax.StopLexing | @syntax.LexNone => raise @core.ParseObjectExpected
      @syntax.LexComment(_) => continue
      @syntax.LexLeftSquare | @syntax.LexLeftDict => depth += 1
      @syntax.LexRightSquare | @syntax.LexRightDict => depth -= 1
      @syntax.LexString(bytes) if root_array && before == 1 =>
        strings.push(
          (
            element_index,
            {
              bytes,
              spelling: pdf_text_string_spelling(
                cursor.view(),
                start,
                cursor.position(),
                bytes,
              ),
            },
          ),
        )
      _ => ()
    }
    if root_array &&
      ((before == 1 && depth == 1) || (before == 2 && depth == 1)) {
      element_index += 1
    }
    tokens.push(token)
  }
  (@syntax.pdf_parse_single_lexeme_object(tokens), strings)
}

///|
/// Inline-image bytes are owned by pdflite's parser and can already be
/// decompressed in the resulting op. Validate bounded EI candidates using
/// that parser instead of guessing the raw length from the decoded image.
fn pdf_text_inline_end(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  data : BytesView,
  start : Int,
  after_bi : Int,
  expected : @content.PdfContentOp,
) -> Int? {
  let mut candidates = 0
  for index in after_bi..<(data.length() - 1) {
    if data[index] != b'E' ||
      data[index + 1] != b'I' ||
      index == 0 ||
      !@core.pdf_is_whitespace_byte(data[index - 1].to_int()) {
      continue
    }
    let end = index + 2
    if end < data.length() &&
      !@core.pdf_is_whitespace_or_delimiter_byte(data[end].to_int()) {
      continue
    }
    candidates += 1
    guard candidates <= 128 else { return None }
    let parsed = document.parse_content_view_with_resources(
      resources,
      data[start:end],
    ) catch {
      _ => continue
    }
    if parsed == [expected] {
      return Some(end)
    }
  }
  None
}

///|
/// Locate operands, checking every operator against the existing interpreter's
/// parse. This is an opt-in location adapter, not another content parser.
fn pdf_text_locate_strings(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  data : BytesView,
  expected : ArrayView[@content.PdfContentOp],
) -> Map[(Int, Int), PdfTextLocatedString]? raise @core.PdfError {
  guard data.length() <= 8 * 1024 * 1024 && expected.length() <= 262144 else {
    return None
  }
  let cursor = @core.byte_cursor_of_view(data)
  let output : Map[(Int, Int), PdfTextLocatedString] = Map([])
  let operands : Array[@syntax.PdfObject] = []
  let pending : Array[(Int, Int, PdfTextLocatedString)] = []
  let mut operator_index = 0
  let mut section_start = 0
  let mut spelling_bytes = 0
  while cursor.position() < data.length() {
    @syntax.pdf_cursor_drop_whitespace(cursor)
    let start = cursor.position()
    let byte = cursor.peek_byte()
    if byte == @core.pdf_no_more {
      break
    }
    if byte == 37 {
      ignore(@syntax.pdf_cursor_lex_comment(cursor))
      continue
    }
    if operands.is_empty() {
      section_start = start
    }
    if byte == 40 ||
      byte == 60 ||
      byte == 91 ||
      byte == 47 ||
      byte == 43 ||
      byte == 45 ||
      byte == 46 ||
      (byte >= 48 && byte <= 57) {
      let operand_index = operands.length()
      let (object, strings) = pdf_text_located_operand(cursor)
      for (element_index, string) in strings {
        spelling_bytes += string.bytes.length()
        guard spelling_bytes <= 262144 else { return None }
        pending.push((operand_index, element_index, string))
      }
      operands.push(object)
      continue
    }
    let operator = @syntax.pdf_cursor_read_regular_token_view(cursor)
    guard !operator.is_empty() else { return None }
    if operator == b"true" || operator == b"false" || operator == b"null" {
      operands.push(
        if operator == b"null" {
          @syntax.PdfNull
        } else {
          @syntax.PdfBoolean(operator == b"true")
        },
      )
      continue
    }
    guard expected.get(operator_index) is Some(op) else { return None }
    if operator == b"BI" && operands.is_empty() {
      guard pdf_text_inline_end(
          document,
          resources,
          data,
          start,
          cursor.position(),
          op,
        )
        is Some(end) else {
        return None
      }
      cursor.seek(end)
    } else {
      let parsed = match
        @content.pdf_content_parse_known_section(operands[:], operator) {
        Some(parsed) => parsed
        None => {
          let parsed = document.parse_content_view_with_resources(
            resources,
            data[section_start:cursor.position()],
          )
          guard parsed is [single] else { return None }
          single
        }
      }
      guard parsed == op else { return None }
      match op {
        @content.Op_TJ(_) =>
          for (root, element_index, string) in pending {
            if root == 0 {
              output[(operator_index, element_index)] = string
            }
          }
        @content.Op_Tj(_) | @content.Op_quote(_) =>
          for (root, _, string) in pending {
            if root == 0 {
              output[(operator_index, 0)] = string
            }
          }
        @content.Op_double_quote(_, _, _) =>
          for (root, _, string) in pending {
            if root == 2 {
              output[(operator_index, 2)] = string
            }
          }
        _ => ()
      }
    }
    operator_index += 1
    operands.clear()
    pending.clear()
  }
  if operator_index == expected.length() && operands.is_empty() {
    Some(output)
  } else {
    None
  }
}

///|
fn pdf_text_located_scope(
  document : @pdflite.PdfDocument,
  resources : @syntax.PdfObject,
  source : PdfCollectedTextSource,
  source_bytes : Bytes,
) -> PdfTextLocatedScope {
  let frames : Array[PdfTextLocatedStream] = []
  let decoded : Array[Bytes] = []
  let strings = try {
    let mut position = 0
    let mut has_output = false
    for index, object in source.content_objects {
      guard document.direct(object) is @syntax.PdfStreamObject(stream) else {
        raise @core.ParseStreamExpected
      }
      let encoded = match stream.data {
        @syntax.StreamToGet(value) if value.input.view() == source_bytes[:] => {
          let start = value.position +
            value.input.absolute_position() -
            value.input.position()
          if start >= 0 &&
            value.length >= 0 &&
            start <= source_bytes.length() - value.length {
            Some({ start, end: start + value.length, })
          } else {
            None
          }
        }
        _ => None
      }
      let file_start = match
        (
          stream.data,
          stream.dictionary.lookup_immediate(pdf_name_key("/Filter")),
        ) {
        (
          @syntax.StreamToGet(value),
          None
          | Some(@syntax.PdfNull)
          | Some(@syntax.PdfArray([])),
        ) if value.crypt.is_identity() => encoded.map(span => span.start)
        _ => None
      }
      let bytes = document.pdf_decode_stream(object).stream_bytes()
      guard bytes.length() <= 8 * 1024 * 1024 - position else {
        raise @core.ContentOperatorExpected
      }
      if has_output {
        position += 1
      }
      frames.push({
        index,
        number: pdf_text_object_number(object),
        start: position,
        end: position + bytes.length(),
        file_start,
        encoded,
      })
      decoded.push(bytes)
      position += bytes.length()
      if !bytes.is_empty() {
        has_output = true
      }
    }
    let data = @pdflite.pdf_content_concat_streams(decoded[:])
    let ops = document.parse_content_ops_with_resources(
      resources,
      source.content_objects[:],
    )
    pdf_text_locate_strings(document, resources, data[:], ops[:])
  } catch {
    _ => None
  }
  {
    streams: source.string_source.content_streams,
    forms: source.string_source.form_path,
    frames,
    strings,
  }
}

///|
fn pdf_text_spelling_spans(
  scope : PdfTextLocatedScope,
  source : PdfTextStringSource,
) -> Array[PdfTextByteSpan]? {
  guard scope.strings is Some(strings) &&
    strings.get((source.operator_index, source.operand_index)) is Some(string) &&
    string.spelling is Some(spelling) &&
    source.byte_start >= 0 &&
    source.byte_end >= source.byte_start &&
    source.byte_end <= string.bytes.length() &&
    string.bytes[source.byte_start:source.byte_end] == source.bytes[:] else {
    return None
  }
  let output : Array[PdfTextByteSpan] = []
  for span in spelling[source.byte_start:source.byte_end] {
    let mut covered = 0
    for frame in scope.frames {
      let start = span.start.max(frame.start)
      let end = span.end.min(frame.end)
      if start >= end {
        continue
      }
      covered += end - start
      let decoded_stream_span : PdfByteSpan = {
        start: start - frame.start,
        end: end - frame.start,
      }
      output.push({
        stream_index: frame.index,
        object_number: frame.number,
        decoded_stream_span,
        file_span: frame.file_start.map(file => {
          start: file + decoded_stream_span.start,
          end: file + decoded_stream_span.end,
        }),
        encoded_stream_span: frame.encoded,
      })
    }
    // Synthetic concat whitespace cannot be presented as an original byte.
    if covered != span.end - span.start {
      return None
    }
  }
  Some(output)
}

///|
/// Locate original text spelling with the shared PDF lexer/parser. The result
/// includes empty copied glyphs and respects Forms and optional content.
/// Limits or unverified locations are explicit; they do not prevent rendering.
/// Invalid page numbers return None, textless pages return Some([]).
pub fn PdfViewerDocument::text_lexical_sources(
  self : PdfViewerDocument,
  page_number : Int,
) -> Array[PdfTextLexicalSource]? raise @core.PdfError {
  guard self.page(page_number) is Some(page) else { return None }
  let logical : Map[Int, PdfTextSourceRange] = Map([])
  for source in page.text_sources() {
    logical[source.item_index] = source
  }
  let entries = pdf_collected_entries_of_page(
    self.document,
    self.pages[page_number - 1],
    optional_content_view=pdf_optional_content_view(
      self.document,
      self.optional_content_state,
    ),
    collect_text_sources=true,
    font_fallbacks=self.font_fallbacks[:],
  )
  let scopes : Array[PdfTextLocatedScope] = []
  let output : Array[PdfTextLexicalSource] = []
  for index, entry in entries {
    guard entry.entry.object is @pdflite.PdfContentGlyphObject(_, _, _) else {
      continue
    }
    let source = entry.text_source
    let spans = match source {
      Some(captured) => {
        let at = scopes.search_by(scope => {
          scope.streams == captured.string_source.content_streams &&
          scope.forms == captured.string_source.form_path
        })
        let scope = match at {
          Some(at) => scopes[at]
          None => {
            let scope = pdf_text_located_scope(
              self.document,
              entry.resources,
              captured,
              self.source_bytes,
            )
            scopes.push(scope)
            scope
          }
        }
        pdf_text_spelling_spans(scope, captured.string_source)
      }
      None => None
    }
    output.push({
      item_index: index,
      logical_source: logical.get(index),
      string_source: source.map(source => source.string_source),
      spans: spans.unwrap_or([]),
      failure: if spans is None {
        Some("content spelling could not be verified")
      } else {
        None
      },
    })
  }
  Some(output)
}

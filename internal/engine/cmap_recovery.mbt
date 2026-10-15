///|
/// A small token representation used by the viewer-side CMap recovery parser.
///
/// \`pdflite\` intentionally exposes parsed CMap tables, but its signed integer
/// parser rejects some legal four-byte ranges. The viewer keeps the recovery
/// parser private and stores source ranges lazily so malformed or very broad
/// CMaps cannot force an unbounded allocation.
priv enum PdfViewerCMapToken {
  PdfViewerCMapHex(Bytes, UInt)
  PdfViewerCMapWord(Bytes)
  PdfViewerCMapInteger(Int)
  PdfViewerCMapInvalid
}

///|
priv struct PdfViewerCMapEntry {
  first : UInt
  last : UInt
  cid : Int
}

///|
priv struct PdfViewerUnicodeEntry {
  first : UInt
  last : UInt
  unicode : Bytes
}

///|
priv struct PdfViewerCMapDiagnostics {
  mut malformed_tokens : Int
  incomplete_sections : Array[String]
  usecmap_cycle : Bool
  source_unavailable : Bool
}

///|
priv struct PdfViewerCMapRecovery {
  codespaces : Array[@pdflite.PdfCMapCodeSpace]
  cid_entries : Array[PdfViewerCMapEntry]
  notdef_entries : Array[PdfViewerCMapEntry]
  unicode_entries : Array[PdfViewerUnicodeEntry]
  diagnostics : PdfViewerCMapDiagnostics
  source_available : Bool
  mut usecmap : @core.PdfName?
  mut wmode : Int?
}

///|
fn pdf_viewer_cmap_hex_digit(byte : Byte) -> Int? {
  match byte {
    b'0'..=b'9' => Some(byte.to_int() - '0')
    b'A'..=b'F' => Some(byte.to_int() - 'A' + 10)
    b'a'..=b'f' => Some(byte.to_int() - 'a' + 10)
    _ => None
  }
}

///|
fn pdf_viewer_cmap_hex_value(view : BytesView) -> (Bytes, UInt)? {
  // ToUnicode destinations are byte strings, including empty or multi-scalar
  // strings. The UInt is used only after source codes are checked as 1–4 bytes.
  let nibbles : Array[Int] = []
  for byte in view {
    if @core.pdf_is_whitespace_byte(byte.to_int()) {
      continue
    }
    match pdf_viewer_cmap_hex_digit(byte) {
      Some(value) => nibbles.push(value)
      None => return None
    }
  }
  let output : Array[Byte] = Array(capacity=(nibbles.length() + 1) / 2)
  let mut index = 0
  while index < nibbles.length() {
    let high = nibbles[index]
    let low = if index + 1 < nibbles.length() { nibbles[index + 1] } else { 0 }
    output.push((high * 16 + low).to_byte())
    index += 2
  }
  let bytes = Bytes::from_array(output)
  let mut value = 0U
  for byte in bytes {
    value = (value << 8) | byte.to_int().reinterpret_as_uint()
  }
  Some((bytes, value))
}

///|
fn pdf_viewer_cmap_token_int(view : BytesView) -> Int? {
  guard view.length() > 0 else { return None }
  try @core.pdf_parse_ascii_int_view(view) catch {
    _ => None
  } noraise {
    value => Some(value)
  }
}

///|
fn pdf_viewer_cmap_delimiter(value : Int) -> Bool {
  @core.pdf_is_whitespace_or_delimiter_byte(value)
}

///|
fn pdf_viewer_cmap_tokens(data : BytesView) -> Array[PdfViewerCMapToken] {
  let output : Array[PdfViewerCMapToken] = Array(capacity=data.length() / 3)
  let mut index = 0
  while index < data.length() {
    while index < data.length() &&
          @core.pdf_is_whitespace_byte(data[index].to_int()) {
      index += 1
    }
    if index >= data.length() {
      break
    }
    if data[index] is b'%' {
      while index < data.length() &&
            data[index] != b'\n' &&
            data[index] != b'\r' {
        index += 1
      }
      continue
    }
    if index + 1 < data.length() &&
      (
        (data[index] == b'<' && data[index + 1] == b'<') ||
        (data[index] == b'>' && data[index + 1] == b'>')
      ) {
      index += 2
      continue
    }
    if data[index] is b'(' {
      let cursor = @core.byte_cursor_of_view(data[index:])
      ignore(@syntax.pdf_cursor_lex_literal_string(cursor)) catch {
        _ => {
          output.push(PdfViewerCMapInvalid)
          break
        }
      }
      index += cursor.position()
      continue
    }
    if data[index] is b'<' &&
      (index + 1 >= data.length() || data[index + 1] != b'<') {
      let start = index + 1
      let mut stop = start
      while stop < data.length() && data[stop] != b'>' {
        stop += 1
      }
      if stop < data.length() {
        match pdf_viewer_cmap_hex_value(data[start:stop]) {
          Some((bytes, value)) => output.push(PdfViewerCMapHex(bytes, value))
          None => output.push(PdfViewerCMapInvalid)
        }
        index = stop + 1
        continue
      }
      output.push(PdfViewerCMapInvalid)
      index = data.length()
      continue
    }
    if data[index] is (b'[' | b']') {
      output.push(PdfViewerCMapWord(data[index:index + 1].to_owned()))
      index += 1
      continue
    }
    if data[index] is b'/' {
      let start = index
      index += 1
      while index < data.length() &&
            !pdf_viewer_cmap_delimiter(data[index].to_int()) &&
            data[index] != b'%' {
        index += 1
      }
      output.push(PdfViewerCMapWord(data[start:index].to_owned()))
      continue
    }
    let start = index
    while index < data.length() &&
          !pdf_viewer_cmap_delimiter(data[index].to_int()) &&
          data[index] != b'%' {
      index += 1
    }
    if start == index {
      index += 1
      continue
    }
    let word = data[start:index].to_owned()
    match pdf_viewer_cmap_token_int(word[:]) {
      Some(value) => output.push(PdfViewerCMapInteger(value))
      None => output.push(PdfViewerCMapWord(word))
    }
  }
  output
}

///|
fn pdf_viewer_cmap_word_is(token : PdfViewerCMapToken, text : Bytes) -> Bool {
  match token {
    PdfViewerCMapWord(bytes) => bytes == text
    _ => false
  }
}

///|
fn pdf_viewer_cmap_name_of(token : PdfViewerCMapToken) -> @core.PdfName? {
  match token {
    PdfViewerCMapWord(bytes) if bytes.length() > 1 && bytes[0] is b'/' =>
      Some(@core.pdf_name_of_bytes(bytes))
    _ => None
  }
}

///|
fn pdf_viewer_cmap_entry(
  tokens : Array[PdfViewerCMapToken],
  index : Int,
) -> (UInt, UInt, Int, Int)? {
  match (tokens.get(index), tokens.get(index + 1), tokens.get(index + 2)) {
    (
      Some(PdfViewerCMapHex(first_bytes, first)),
      Some(PdfViewerCMapHex(last_bytes, last)),
      Some(PdfViewerCMapInteger(cid)),
    ) if first_bytes.length() > 0 &&
      first_bytes.length() <= 4 &&
      first_bytes.length() == last_bytes.length() =>
      Some((first, last, cid, index + 3))
    _ => None
  }
}

///|
fn pdf_viewer_cmap_char_entry(
  tokens : Array[PdfViewerCMapToken],
  index : Int,
) -> (UInt, Int, Int)? {
  match (tokens.get(index), tokens.get(index + 1)) {
    (Some(PdfViewerCMapHex(bytes, code)), Some(PdfViewerCMapInteger(cid))) if bytes.length() >
      0 &&
      bytes.length() <= 4 => Some((code, cid, index + 2))
    _ => None
  }
}

///|
fn pdf_viewer_unicode_entry(
  tokens : Array[PdfViewerCMapToken],
  index : Int,
) -> (UInt, Bytes, Int)? {
  match (tokens.get(index), tokens.get(index + 1)) {
    (Some(PdfViewerCMapHex(source, code)), Some(PdfViewerCMapHex(bytes, _))) if source.length() >
      0 &&
      source.length() <= 4 => Some((code, bytes, index + 2))
    _ => None
  }
}

///|

///|
fn pdf_viewer_parse_unicode_entries(
  tokens : Array[PdfViewerCMapToken],
  output : Array[PdfViewerUnicodeEntry],
  start : Int,
  end_word : Bytes,
) -> (Int, Bool) {
  let mut index = start
  while index < tokens.length() {
    if pdf_viewer_cmap_word_is(tokens[index], end_word) {
      return (index + 1, true)
    }
    match pdf_viewer_unicode_entry(tokens, index) {
      Some((code, unicode, next)) => {
        output.push({ first: code, last: code, unicode, })
        index = next
      }
      None => index += 1
    }
  }
  (index, false)
}

///|
fn pdf_viewer_parse_unicode_ranges(
  tokens : Array[PdfViewerCMapToken],
  output : Array[PdfViewerUnicodeEntry],
  start : Int,
) -> (Int, Bool) {
  let mut index = start
  while index < tokens.length() {
    if pdf_viewer_cmap_word_is(tokens[index], b"endbfrange") {
      return (index + 1, true)
    }
    match (tokens.get(index), tokens.get(index + 1), tokens.get(index + 2)) {
      (
        Some(PdfViewerCMapHex(first_bytes, first)),
        Some(PdfViewerCMapHex(last_bytes, last)),
        Some(PdfViewerCMapHex(unicode, _)),
      ) if first_bytes.length() > 0 &&
        first_bytes.length() <= 4 &&
        first_bytes.length() == last_bytes.length() &&
        first <= last => {
        output.push({ first, last, unicode, })
        index += 3
      }
      (
        Some(PdfViewerCMapHex(first_bytes, first)),
        Some(PdfViewerCMapHex(last_bytes, last)),
        Some(PdfViewerCMapWord(open)),
      ) if first_bytes.length() > 0 &&
        first_bytes.length() <= 4 &&
        first_bytes.length() == last_bytes.length() &&
        first <= last &&
        open[:] == b"[" => {
        index += 3
        let mut source = first
        let mut exhausted = false
        while index < tokens.length() &&
              !pdf_viewer_cmap_word_is(tokens[index], b"]") {
          match tokens[index] {
            PdfViewerCMapHex(unicode, _) if !exhausted && source <= last => {
              output.push({ first: source, last: source, unicode, })
              if source == last {
                exhausted = true
              } else {
                source += 1U
              }
            }
            _ => ()
          }
          index += 1
        }
        if index < tokens.length() {
          index += 1
        }
      }
      _ => index += 1
    }
  }
  (index, false)
}

///|
fn pdf_viewer_parse_cmap(data : BytesView) -> PdfViewerCMapRecovery {
  let tokens = pdf_viewer_cmap_tokens(data)
  let output = PdfViewerCMapRecovery::{
    codespaces: [],
    cid_entries: [],
    notdef_entries: [],
    unicode_entries: [],
    diagnostics: {
      malformed_tokens: 0,
      incomplete_sections: [],
      usecmap_cycle: false,
      source_unavailable: false,
    },
    source_available: true,
    usecmap: None,
    wmode: None,
  }
  let mut index = 0
  let mut previous_name : @core.PdfName? = None
  for token in tokens {
    if token is PdfViewerCMapInvalid {
      output.diagnostics.malformed_tokens += 1
    }
  }
  while index < tokens.length() {
    let token = tokens[index]
    if pdf_viewer_cmap_word_is(token, b"usecmap") {
      output.usecmap = previous_name
      previous_name = None
      index += 1
      continue
    }
    if pdf_viewer_cmap_word_is(token, b"begincodespacerange") {
      index += 1
      let mut closed = false
      while index < tokens.length() {
        if pdf_viewer_cmap_word_is(tokens[index], b"endcodespacerange") {
          closed = true
          index += 1
          break
        }
        match (tokens.get(index), tokens.get(index + 1)) {
          (
            Some(PdfViewerCMapToken::PdfViewerCMapHex(first_bytes, first)),
            Some(PdfViewerCMapToken::PdfViewerCMapHex(last_bytes, last)),
          ) if first_bytes.length() > 0 &&
            first_bytes.length() <= 4 &&
            first_bytes.length() == last_bytes.length() &&
            first <= last => {
            output.codespaces.push({
              length: first_bytes.length(),
              first: first.reinterpret_as_int(),
              last: last.reinterpret_as_int(),
            })
            index += 2
          }
          _ => index += 1
        }
      }
      if !closed {
        output.diagnostics.incomplete_sections.push("codespacerange")
      }
      previous_name = None
      continue
    }
    if pdf_viewer_cmap_word_is(token, b"beginbfchar") {
      let (next, closed) = pdf_viewer_parse_unicode_entries(
        tokens,
        output.unicode_entries,
        index + 1,
        b"endbfchar",
      )
      index = next
      if !closed {
        output.diagnostics.incomplete_sections.push("bfchar")
      }
      previous_name = None
      continue
    }
    if pdf_viewer_cmap_word_is(token, b"beginbfrange") {
      let (next, closed) = pdf_viewer_parse_unicode_ranges(
        tokens,
        output.unicode_entries,
        index + 1,
      )
      index = next
      if !closed {
        output.diagnostics.incomplete_sections.push("bfrange")
      }
      previous_name = None
      continue
    }
    if pdf_viewer_cmap_word_is(token, b"begincidchar") {
      index += 1
      let mut closed = false
      while index < tokens.length() {
        if pdf_viewer_cmap_word_is(tokens[index], b"endcidchar") {
          closed = true
          index += 1
          break
        }
        match pdf_viewer_cmap_char_entry(tokens, index) {
          Some((code, cid, next)) => {
            output.cid_entries.push({ first: code, last: code, cid, })
            index = next
          }
          None => index += 1
        }
      }
      if !closed {
        output.diagnostics.incomplete_sections.push("cidchar")
      }
      previous_name = None
      continue
    }
    if pdf_viewer_cmap_word_is(token, b"begincidrange") {
      index += 1
      let mut closed = false
      while index < tokens.length() {
        if pdf_viewer_cmap_word_is(tokens[index], b"endcidrange") {
          closed = true
          index += 1
          break
        }
        match pdf_viewer_cmap_entry(tokens, index) {
          Some((first, last, cid, next)) if first <= last => {
            output.cid_entries.push({ first, last, cid, })
            index = next
          }
          _ => index += 1
        }
      }
      if !closed {
        output.diagnostics.incomplete_sections.push("cidrange")
      }
      previous_name = None
      continue
    }
    if pdf_viewer_cmap_word_is(token, b"beginnotdefchar") {
      index += 1
      let mut closed = false
      while index < tokens.length() {
        if pdf_viewer_cmap_word_is(tokens[index], b"endnotdefchar") {
          closed = true
          index += 1
          break
        }
        match pdf_viewer_cmap_char_entry(tokens, index) {
          Some((code, cid, next)) => {
            output.notdef_entries.push({ first: code, last: code, cid, })
            index = next
          }
          None => index += 1
        }
      }
      if !closed {
        output.diagnostics.incomplete_sections.push("notdefchar")
      }
      previous_name = None
      continue
    }
    if pdf_viewer_cmap_word_is(token, b"beginnotdefrange") {
      index += 1
      let mut closed = false
      while index < tokens.length() {
        if pdf_viewer_cmap_word_is(tokens[index], b"endnotdefrange") {
          closed = true
          index += 1
          break
        }
        match pdf_viewer_cmap_entry(tokens, index) {
          Some((first, last, cid, next)) if first <= last => {
            output.notdef_entries.push({ first, last, cid, })
            index = next
          }
          _ => index += 1
        }
      }
      if !closed {
        output.diagnostics.incomplete_sections.push("notdefrange")
      }
      previous_name = None
      continue
    }
    if pdf_viewer_cmap_word_is(token, b"/WMode") {
      match tokens.get(index + 1) {
        Some(PdfViewerCMapToken::PdfViewerCMapInteger(value)) => {
          output.wmode = Some(value)
          index += 1
        }
        _ => ()
      }
      previous_name = None
    } else if pdf_viewer_cmap_name_of(token) is Some(name) {
      previous_name = Some(name)
    } else {
      previous_name = None
    }
    index += 1
  }
  output
}

///|
fn pdf_viewer_cmap_lookup(
  entries : ArrayView[PdfViewerCMapEntry],
  code : Int,
) -> Int? {
  let value = code.reinterpret_as_uint()
  let mut index = entries.length() - 1
  while index >= 0 {
    let entry = entries[index]
    if value >= entry.first && value <= entry.last {
      let offset = value - entry.first
      if offset <= 0x7FFFFFFFU &&
        entry.cid <= 0x7FFFFFFF - offset.reinterpret_as_int() {
        return Some(entry.cid + offset.reinterpret_as_int())
      }
      return None
    }
    index -= 1
  }
  None
}

///|
let pdf_viewer_cmap_recovery_cache : Map[String, PdfViewerCMapRecovery?] = Map([])

///|
fn pdf_viewer_cmap_recovery_cached(bytes : Bytes) -> PdfViewerCMapRecovery {
  let key = @base64.encode(bytes)
  match pdf_viewer_cmap_recovery_cache.get(key) {
    Some(Some(value)) => value
    Some(None) =>
      PdfViewerCMapRecovery::{
        codespaces: [],
        cid_entries: [],
        notdef_entries: [],
        unicode_entries: [],
        diagnostics: {
          malformed_tokens: 0,
          incomplete_sections: [],
          usecmap_cycle: false,
          source_unavailable: true,
        },
        source_available: false,
        usecmap: None,
        wmode: None,
      }
    None => {
      let parsed = pdf_viewer_parse_cmap(bytes[:])
      pdf_viewer_cmap_recovery_cache[key] = Some(parsed)
      parsed
    }
  }
}

///|
fn pdf_viewer_cmap_compose_recovery(
  current : PdfViewerCMapRecovery,
  inherited : PdfViewerCMapRecovery,
) -> PdfViewerCMapRecovery {
  let cid_entries : Array[PdfViewerCMapEntry] = Array(
    capacity=inherited.cid_entries.length() + current.cid_entries.length(),
  )
  for entry in inherited.cid_entries {
    cid_entries.push(entry)
  }
  for entry in current.cid_entries {
    cid_entries.push(entry)
  }
  let notdef_entries : Array[PdfViewerCMapEntry] = Array(
    capacity=inherited.notdef_entries.length() + current.notdef_entries.length(),
  )
  for entry in inherited.notdef_entries {
    notdef_entries.push(entry)
  }
  for entry in current.notdef_entries {
    notdef_entries.push(entry)
  }
  let unicode_entries : Array[PdfViewerUnicodeEntry] = Array(
    capacity=inherited.unicode_entries.length() +
      current.unicode_entries.length(),
  )
  for entry in inherited.unicode_entries {
    unicode_entries.push(entry)
  }
  for entry in current.unicode_entries {
    unicode_entries.push(entry)
  }
  let incomplete_sections : Array[String] = []
  for section in inherited.diagnostics.incomplete_sections {
    incomplete_sections.push(section)
  }
  for section in current.diagnostics.incomplete_sections {
    incomplete_sections.push(section)
  }
  {
    codespaces: if current.codespaces.is_empty() {
      inherited.codespaces
    } else {
      current.codespaces
    },
    cid_entries,
    notdef_entries,
    unicode_entries,
    diagnostics: {
      malformed_tokens: current.diagnostics.malformed_tokens +
      inherited.diagnostics.malformed_tokens,
      incomplete_sections,
      usecmap_cycle: current.diagnostics.usecmap_cycle ||
      inherited.diagnostics.usecmap_cycle,
      source_unavailable: current.diagnostics.source_unavailable ||
      inherited.diagnostics.source_unavailable,
    },
    source_available: current.source_available,
    usecmap: match current.usecmap {
      Some(_) => current.usecmap
      None => inherited.usecmap
    },
    wmode: match current.wmode {
      Some(_) => current.wmode
      None => inherited.wmode
    },
  }
}

///|
fn pdf_viewer_unicode_with_increment(
  unicode : Bytes,
  increment : UInt,
) -> Bytes? {
  let output = unicode.to_array()
  let mut carry = increment
  let mut index = output.length()
  while index > 0 && carry > 0U {
    index -= 1
    let sum = output[index].to_int() + (carry & 0xFFU).reinterpret_as_int()
    output[index] = (sum & 0xFF).to_byte()
    carry = (carry >> 8) + (sum >> 8).reinterpret_as_uint()
  }
  if carry == 0U {
    Some(Bytes::from_array(output))
  } else {
    None
  }
}

///|
fn pdf_viewer_unicode_lookup(
  entries : ArrayView[PdfViewerUnicodeEntry],
  code : Int,
) -> Bytes? {
  let value = code.reinterpret_as_uint()
  let mut index = entries.length() - 1
  while index >= 0 {
    let entry = entries[index]
    if value >= entry.first && value <= entry.last {
      return pdf_viewer_unicode_with_increment(
        entry.unicode,
        value - entry.first,
      )
    }
    index -= 1
  }
  None
}

///|
fn pdf_viewer_cmap_recovery_of_object(
  document : @pdflite.PdfDocument,
  object : @syntax.PdfObject,
  seen : Map[Int, Bool],
) -> PdfViewerCMapRecovery? {
  let number = match object {
    @syntax.PdfIndirect(number) => number
    _ => -1
  }
  if number >= 0 {
    if seen.contains(number) {
      return Some({
        codespaces: [],
        cid_entries: [],
        notdef_entries: [],
        unicode_entries: [],
        diagnostics: {
          malformed_tokens: 0,
          incomplete_sections: [],
          usecmap_cycle: true,
          source_unavailable: false,
        },
        source_available: true,
        usecmap: None,
        wmode: None,
      })
    }
    seen[number] = true
  }
  let bytes = try {
    guard seen.length() <= 64 else {
      raise @core.SoftError("CMap inheritance limit")
    }
    pdf_decode_font_stream_with_recovery(document, object).stream_bytes()
  } catch {
    _ => None
  } noraise {
    value => Some(value)
  }
  match bytes {
    None =>
      Some({
        codespaces: [],
        cid_entries: [],
        notdef_entries: [],
        unicode_entries: [],
        diagnostics: {
          malformed_tokens: 0,
          incomplete_sections: [],
          usecmap_cycle: false,
          source_unavailable: true,
        },
        source_available: false,
        usecmap: None,
        wmode: None,
      })
    Some(bytes) => {
      let current = pdf_viewer_cmap_recovery_cached(bytes)
      let base = match pdf_direct_for_viewer(document, object) {
        Some(@syntax.PdfStreamObject(stream)) =>
          stream.dictionary.lookup_immediate(pdf_name_key("/UseCMap"))
        _ => None
      }
      match base {
        Some(@syntax.PdfIndirect(_)) | Some(@syntax.PdfStreamObject(_)) =>
          match
            pdf_viewer_cmap_recovery_of_object(document, base.unwrap(), seen) {
            Some(inherited) =>
              Some(pdf_viewer_cmap_compose_recovery(current, inherited))
            None => Some(current)
          }
        _ => Some(current)
      }
    }
  }
}

///|
fn pdf_viewer_cmap_recovery_for_font(
  document : @pdflite.PdfDocument,
  font : @pdflite.PdfCIDKeyedFont,
  resource_context? : PdfResourceBuildContext? = None,
) -> PdfViewerCMapRecovery? {
  let number = match font.encoding {
    @pdflite.PdfExternalCMap(number, _) | @pdflite.PdfCMap(number) => number
    _ => return None
  }
  pdf_viewer_cmap_recovery_for_resource(
    document,
    @syntax.PdfIndirect(number),
    resource_context,
  )
}

///|
fn pdf_viewer_cid_of_charcode_with_recovery(
  font : @pdflite.PdfCIDKeyedFont,
  charcode : Int,
  recovery : PdfViewerCMapRecovery?,
) -> Int? {
  match recovery {
    Some(cmap) if !cmap.source_available =>
      pdf_viewer_cid_of_charcode(font, charcode)
    Some(cmap) => {
      match pdf_viewer_cmap_lookup(cmap.cid_entries[:], charcode) {
        Some(cid) => return Some(cid)
        None => ()
      }
      match cmap.usecmap {
        Some(name) =>
          match pdf_builtin_cmap_cid(pdf_cmap_name_text(name), charcode) {
            Some(cid) => return Some(cid)
            None => ()
          }
        None => ()
      }
      match pdf_viewer_cmap_lookup(cmap.notdef_entries[:], charcode) {
        Some(cid) => return Some(cid)
        None => ()
      }
      match pdf_viewer_cid_of_charcode(font, charcode) {
        Some(cid) => Some(cid)
        None if cmap.usecmap is None => Some(0)
        None => None
      }
    }
    None => pdf_viewer_cid_of_charcode(font, charcode)
  }
}

///|
fn pdf_viewer_cid_of_charcode_with_document(
  document : @pdflite.PdfDocument,
  font : @pdflite.PdfCIDKeyedFont,
  charcode : Int,
) -> Int? {
  pdf_viewer_cid_of_charcode_with_recovery(
    font,
    charcode,
    pdf_viewer_cmap_recovery_for_font(document, font),
  )
}

///|
fn pdf_viewer_cmap_effective_parsed(
  font : @pdflite.PdfCIDKeyedFont,
  recovery : PdfViewerCMapRecovery?,
) -> @pdflite.PdfParsedCMap? {
  match font.encoding {
    @pdflite.PdfExternalCMap(_, parsed) =>
      match recovery {
        Some(cmap) => {
          let spaces = if cmap.codespaces.is_empty() {
            parsed.codespaces
          } else {
            cmap.codespaces
          }
          let usecmap = match cmap.usecmap {
            Some(_) => cmap.usecmap
            None => parsed.usecmap
          }
          Some({ ..parsed, codespaces: spaces, usecmap, })
        }
        None => Some(parsed)
      }
    @pdflite.PdfCMap(_) =>
      match recovery {
        Some(cmap) =>
          Some({
            map: [],
            cid_map: [],
            notdef_map: [],
            codespaces: cmap.codespaces,
            usecmap: cmap.usecmap,
            wmode: cmap.wmode,
            cmap_name: None,
            cmap_type: None,
            cid_system_info: None,
          })
        None => None
      }
    _ => None
  }
}

///|
fn pdf_viewer_font_is_vertical_with_recovery(
  font : @pdflite.PdfFont,
  recovery : PdfViewerCMapRecovery?,
) -> Bool {
  match (font, recovery) {
    (
      @pdflite.PdfFontCIDKeyed(
        { encoding: @pdflite.PdfExternalCMap(_, parsed), .. }
      ),
      Some(cmap),
    ) =>
      match (cmap.wmode, parsed.wmode, cmap.usecmap, parsed.usecmap) {
        (Some(mode), _, _, _) => mode == 1
        (_, Some(mode), _, _) => mode == 1
        (_, _, Some(name), _) => pdf_builtin_cmap_is_vertical(name)
        (_, _, _, Some(name)) => pdf_builtin_cmap_is_vertical(name)
        _ => pdf_font_is_vertical(font)
      }
    (@pdflite.PdfFontCIDKeyed({ encoding: @pdflite.PdfCMap(_), .. }), Some(cmap)
    ) =>
      match cmap.wmode {
        Some(mode) => mode == 1
        None =>
          match cmap.usecmap {
            Some(name) => pdf_builtin_cmap_is_vertical(name)
            None => pdf_font_is_vertical(font)
          }
      }
    _ => pdf_font_is_vertical(font)
  }
}

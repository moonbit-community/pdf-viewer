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
}

///|
priv struct PdfViewerCMapEntry {
  first : UInt
  last : UInt
  cid : Int
}

///|
priv struct PdfViewerCMapRecovery {
  codespaces : Array[@pdflite.PdfCMapCodeSpace]
  cid_entries : Array[PdfViewerCMapEntry]
  notdef_entries : Array[PdfViewerCMapEntry]
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
  guard view.length() > 0 && view.length() <= 8 else { return None }
  let nibbles : Array[Int] = []
  for byte in view {
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
          None => ()
        }
        index = stop + 1
        continue
      }
    }
    if data[index] is (b'[' | b']') {
      output.push(PdfViewerCMapWord(data[index:index + 1].to_owned()))
      index += 1
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
fn pdf_viewer_cmap_word_is(token : PdfViewerCMapToken, text : String) -> Bool {
  match token {
    PdfViewerCMapWord(bytes) => bytes[:] == @utf8.encode(text)
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
      Some(PdfViewerCMapHex(_, first)),
      Some(PdfViewerCMapHex(_, last)),
      Some(PdfViewerCMapInteger(cid)),
    ) => Some((first, last, cid, index + 3))
    _ => None
  }
}

///|
fn pdf_viewer_cmap_char_entry(
  tokens : Array[PdfViewerCMapToken],
  index : Int,
) -> (UInt, Int, Int)? {
  match (tokens.get(index), tokens.get(index + 1)) {
    (Some(PdfViewerCMapHex(_, code)), Some(PdfViewerCMapInteger(cid))) =>
      Some((code, cid, index + 2))
    _ => None
  }
}

///|
fn pdf_viewer_parse_cmap(data : BytesView) -> PdfViewerCMapRecovery {
  let tokens = pdf_viewer_cmap_tokens(data)
  let output = PdfViewerCMapRecovery::{
    codespaces: [],
    cid_entries: [],
    notdef_entries: [],
    usecmap: None,
    wmode: None,
  }
  let mut index = 0
  let mut previous_name : @core.PdfName? = None
  while index < tokens.length() {
    let token = tokens[index]
    if pdf_viewer_cmap_word_is(token, "usecmap") {
      output.usecmap = previous_name
      previous_name = None
      index += 1
      continue
    }
    if pdf_viewer_cmap_word_is(token, "begincodespacerange") {
      index += 1
      while index < tokens.length() {
        if pdf_viewer_cmap_word_is(tokens[index], "endcodespacerange") {
          index += 1
          break
        }
        match (tokens.get(index), tokens.get(index + 1)) {
          (
            Some(PdfViewerCMapToken::PdfViewerCMapHex(first_bytes, first)),
            Some(PdfViewerCMapToken::PdfViewerCMapHex(last_bytes, last)),
          ) if first_bytes.length() == last_bytes.length() && first <= last => {
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
      previous_name = None
      continue
    }
    if pdf_viewer_cmap_word_is(token, "begincidchar") {
      index += 1
      while index < tokens.length() {
        if pdf_viewer_cmap_word_is(tokens[index], "endcidchar") {
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
      previous_name = None
      continue
    }
    if pdf_viewer_cmap_word_is(token, "begincidrange") {
      index += 1
      while index < tokens.length() {
        if pdf_viewer_cmap_word_is(tokens[index], "endcidrange") {
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
      previous_name = None
      continue
    }
    if pdf_viewer_cmap_word_is(token, "beginnotdefchar") {
      index += 1
      while index < tokens.length() {
        if pdf_viewer_cmap_word_is(tokens[index], "endnotdefchar") {
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
      previous_name = None
      continue
    }
    if pdf_viewer_cmap_word_is(token, "beginnotdefrange") {
      index += 1
      while index < tokens.length() {
        if pdf_viewer_cmap_word_is(tokens[index], "endnotdefrange") {
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
      previous_name = None
      continue
    }
    if pdf_viewer_cmap_word_is(token, "/WMode") {
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
  let key = @utf8.decode_lossy(bytes[:])
  match pdf_viewer_cmap_recovery_cache.get(key) {
    Some(Some(value)) => value
    Some(None) =>
      PdfViewerCMapRecovery::{
        codespaces: [],
        cid_entries: [],
        notdef_entries: [],
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
  {
    codespaces: if current.codespaces.is_empty() {
      inherited.codespaces
    } else {
      current.codespaces
    },
    cid_entries,
    notdef_entries,
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
      return None
    }
    seen[number] = true
  }
  let bytes = try document.pdf_decode_stream(object).stream_bytes() catch {
    _ => None
  } noraise {
    value => Some(value)
  }
  match bytes {
    None => None
    Some(bytes) => {
      let current = pdf_viewer_cmap_recovery_cached(bytes)
      let base = match document.direct(object) {
        @syntax.PdfStreamObject(stream) =>
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
) -> PdfViewerCMapRecovery? {
  let number = match font.encoding {
    @pdflite.PdfExternalCMap(number, _) | @pdflite.PdfCMap(number) => number
    _ => return None
  }
  pdf_viewer_cmap_recovery_of_object(
    document,
    @syntax.PdfIndirect(number),
    Map([]),
  )
}

///|
fn pdf_viewer_cid_of_charcode_with_recovery(
  font : @pdflite.PdfCIDKeyedFont,
  charcode : Int,
  recovery : PdfViewerCMapRecovery?,
) -> Int? {
  match recovery {
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

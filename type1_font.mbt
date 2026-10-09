///|
/// Raw Type 1 font data used to construct outlines for embedded PDF fonts.
/// Single-FD CID-keyed programs are normalized into the same charstring model;
/// more complex FDArray/CMap cases remain on the normal text fallback path.
priv struct PdfType1Font {
  font_matrix : @geometry.TransformMatrix
  charstrings : Map[String, Bytes]
  subrs : Array[Bytes?]
  builtin_encoding : Map[Int, String]
  outlines : Map[String, Array[PdfCffPathCommand]?]
}

///|
priv struct PdfType1Scanner {
  data : BytesView
  mut position : Int
}

///|
fn pdf_type1_is_space(value : Int) -> Bool {
  value == 0 ||
  value == 9 ||
  value == 10 ||
  value == 12 ||
  value == 13 ||
  value == 32
}

///|
fn pdf_type1_is_delimiter(value : Int) -> Bool {
  value == 0x2F ||
  value == 0x5B ||
  value == 0x5D ||
  value == 0x7B ||
  value == 0x7D ||
  value == 0x28 ||
  value == 0x29
}

///|
fn pdf_type1_next_token(scanner : PdfType1Scanner) -> String? {
  let data = scanner.data
  while scanner.position < data.length() {
    let byte = data[scanner.position].to_int()
    if pdf_type1_is_space(byte) {
      scanner.position += 1
    } else if byte == 0x25 {
      while scanner.position < data.length() &&
            data[scanner.position].to_int() != 10 &&
            data[scanner.position].to_int() != 13 {
        scanner.position += 1
      }
    } else {
      break
    }
  }
  if scanner.position >= data.length() {
    return None
  }
  let start = scanner.position
  let first = data[start].to_int()
  if pdf_type1_is_delimiter(first) {
    scanner.position += 1
    return Some(
      match first {
        0x2F => "/"
        0x5B => "["
        0x5D => "]"
        0x7B => "{"
        0x7D => "}"
        0x28 => "("
        _ => ")"
      },
    )
  }
  while scanner.position < data.length() {
    let byte = data[scanner.position].to_int()
    if pdf_type1_is_space(byte) || pdf_type1_is_delimiter(byte) {
      break
    }
    scanner.position += 1
  }
  Some(@utf8.decode(data[start:scanner.position]) catch { _ => "" })
}

///|
fn pdf_type1_parse_int(token : String?) -> Int? {
  match token {
    Some(value) =>
      try @string.parse_int(value.view()) catch {
        _ => None
      } noraise {
        number => Some(number)
      }
    None => None
  }
}

///|
fn pdf_type1_parse_double(token : String?) -> Double? {
  match token {
    Some(value) =>
      try @string.parse_double(value.view()) catch {
        _ => None
      } noraise {
        number => Some(number)
      }
    None => None
  }
}

///|
fn pdf_type1_find(data : BytesView, needle : String, start : Int) -> Int? {
  if start < 0 || start > data.length() {
    return None
  }
  let bytes = @utf8.encode(needle)
  if bytes.length() == 0 || bytes.length() > data.length() - start {
    return None
  }
  for offset in start..<=(data.length() - bytes.length()) {
    let mut matches = true
    for index in 0..<bytes.length() {
      if data[offset + index] != bytes[index] {
        matches = false
        break
      }
    }
    if matches {
      return Some(offset)
    }
  }
  None
}

///|
fn pdf_type1_decrypt(
  data : BytesView,
  key : Int,
  discard : Int,
) -> Bytes? raise @core.PdfError {
  let output : Array[Int] = []
  let mut state = key
  for byte in data {
    let cipher = byte.to_int()
    let plain = cipher ^ (state >> 8)
    state = ((cipher + state) * 52845 + 22719) & 0xFFFF
    output.push(plain & 255)
  }
  if discard < 0 || output.length() < discard {
    return None
  }
  Some(@core.pdf_bytes_of_int_array(output[discard:]))
}

///|
fn pdf_type1_hex_value(value : Int) -> Int? {
  if value >= 48 && value <= 57 {
    Some(value - 48)
  } else if value >= 65 && value <= 70 {
    Some(value - 55)
  } else if value >= 97 && value <= 102 {
    Some(value - 87)
  } else {
    None
  }
}

///|
fn pdf_type1_ascii_hex(data : BytesView) -> Bytes? raise @core.PdfError {
  let output : Array[Int] = []
  let mut high : Int? = None
  for byte in data {
    let value = byte.to_int()
    if pdf_type1_is_space(value) {
      continue
    }
    match pdf_type1_hex_value(value) {
      Some(nibble) =>
        match high {
          Some(previous) => {
            output.push((previous << 4) | nibble)
            high = None
          }
          None => high = Some(nibble)
        }
      None => break
    }
  }
  Some(@core.pdf_bytes_of_int_array(output))
}

///|
fn pdf_type1_eexec_bytes(
  data : BytesView,
  start : Int,
) -> Bytes? raise @core.PdfError {
  let mut first = start
  while first < data.length() && pdf_type1_is_space(data[first].to_int()) {
    first += 1
  }
  if first >= data.length() {
    return None
  }
  let mut hex_digits = 0
  let mut cursor = first
  let mut looks_hex = true
  while cursor < data.length() && hex_digits < 8 {
    let byte = data[cursor].to_int()
    if pdf_type1_is_space(byte) {
      cursor += 1
      continue
    }
    if pdf_type1_hex_value(byte) is Some(_) {
      hex_digits += 1
      cursor += 1
    } else {
      looks_hex = false
      break
    }
  }
  if looks_hex && hex_digits == 8 {
    pdf_type1_ascii_hex(data[first:])
  } else {
    let output : Array[Int] = []
    for byte in data[first:] {
      output.push(byte.to_int())
    }
    Some(@core.pdf_bytes_of_int_array(output))
  }
}

///|
fn pdf_type1_pfb_parts(data : BytesView) -> (Bytes, Bytes)? {
  if data.length() < 6 || data[0].to_int() != 0x80 {
    return None
  }
  let header : Array[Int] = []
  let encrypted : Array[Int] = []
  let mut offset = 0
  let mut found_eexec = false
  let mut found_binary = false
  while offset + 2 <= data.length() {
    if data[offset].to_int() != 0x80 {
      return None
    }
    let kind = data[offset + 1].to_int()
    offset += 2
    if kind == 3 {
      break
    }
    if offset + 4 > data.length() {
      return None
    }
    let length = data[offset].to_int() |
      (data[offset + 1].to_int() << 8) |
      (data[offset + 2].to_int() << 16) |
      (data[offset + 3].to_int() << 24)
    offset += 4
    if length < 0 || length > data.length() - offset {
      // Some embedded PFB streams omit the final cleartext trailer segment
      // while retaining its original length in the segment header.
      if found_binary && kind == 1 {
        break
      }
      return None
    }
    let segment = data[offset:offset + length]
    if !found_eexec && kind == 1 {
      match pdf_type1_find(segment, "eexec", 0) {
        Some(position) => {
          for byte in segment[:position] {
            header.push(byte.to_int())
          }
          found_eexec = true
        }
        None =>
          for byte in segment {
            header.push(byte.to_int())
          }
      }
    } else if found_eexec && kind == 2 && !found_binary {
      for byte in segment {
        encrypted.push(byte.to_int())
      }
      found_binary = true
    } else if found_eexec && kind == 1 && !found_binary {
      // Some PFB producers keep the encrypted stream in an ASCII-hex record.
      for byte in segment {
        encrypted.push(byte.to_int())
      }
    }
    offset += length
  }
  if !found_eexec || encrypted.is_empty() {
    None
  } else {
    match
      (
        @core.pdf_bytes_of_int_array(header) catch {
          _ => return None
        },
        @core.pdf_bytes_of_int_array(encrypted) catch {
          _ => return None
        },
      ) {
      pair => Some(pair)
    }
  }
}

///|
fn pdf_type1_header_properties(
  data : BytesView,
) -> (@geometry.TransformMatrix, Map[Int, String]) {
  let scanner = PdfType1Scanner::{ data, position: 0, }
  let mut matrix : @geometry.TransformMatrix = {
    a: 0.001,
    b: 0.0,
    c: 0.0,
    d: 0.001,
    e: 0.0,
    f: 0.0,
  }
  let encoding : Map[Int, String] = Map([])
  while pdf_type1_next_token(scanner) is Some(token) {
    if token != "/" {
      continue
    }
    match pdf_type1_next_token(scanner) {
      Some("FontMatrix") => {
        if pdf_type1_next_token(scanner) != Some("[") {
          continue
        }
        let values : Array[Double] = []
        while values.length() < 6 {
          match pdf_type1_parse_double(pdf_type1_next_token(scanner)) {
            Some(value) => values.push(value)
            None => break
          }
        }
        if values.length() == 6 {
          matrix = {
            a: values[0],
            b: values[1],
            c: values[2],
            d: values[3],
            e: values[4],
            f: values[5],
          }
        }
      }
      Some("Encoding") => {
        let value = pdf_type1_next_token(scanner)
        if value == Some("StandardEncoding") {
          for code, name in pdf_cff_standard_encoding {
            if name != "" {
              encoding[code] = name
            }
          }
        } else if value is Some(size) &&
          pdf_type1_parse_int(Some(size)) is Some(_) {
          let mut done = false
          while !done {
            match pdf_type1_next_token(scanner) {
              Some("dup") => {
                let code = pdf_type1_parse_int(pdf_type1_next_token(scanner))
                let slash = pdf_type1_next_token(scanner)
                let name = pdf_type1_next_token(scanner)
                ignore(pdf_type1_next_token(scanner))
                match (code, slash, name) {
                  (Some(code), Some("/"), Some(name)) if code >= 0 &&
                    code <= 255 => encoding[code] = name
                  _ => ()
                }
              }
              Some("def") | None => done = true
              _ => ()
            }
          }
        }
      }
      _ => ()
    }
  }
  (matrix, encoding)
}

///|
fn pdf_type1_read_binary(
  scanner : PdfType1Scanner,
  length : Int,
) -> Bytes? raise @core.PdfError {
  if length < 0 || length > scanner.data.length() {
    return None
  }
  if scanner.position < scanner.data.length() &&
    pdf_type1_is_space(scanner.data[scanner.position].to_int()) {
    let first = scanner.data[scanner.position].to_int()
    scanner.position += 1
    if first == 13 &&
      scanner.position < scanner.data.length() &&
      scanner.data[scanner.position].to_int() == 10 {
      scanner.position += 1
    }
  }
  if length > scanner.data.length() - scanner.position {
    return None
  }
  let values : Array[Int] = []
  for byte in scanner.data[scanner.position:scanner.position + length] {
    values.push(byte.to_int())
  }
  let bytes = @core.pdf_bytes_of_int_array(values)
  scanner.position += length
  Some(bytes)
}

///|
fn pdf_type1_decode_charstring(
  bytes : BytesView,
  len_iv : Int,
) -> Bytes? raise @core.PdfError {
  if len_iv == -1 {
    return Some(bytes.to_owned())
  }
  if len_iv < 0 || len_iv > 32 {
    return None
  }
  pdf_type1_decrypt(bytes, 4330, len_iv)
}

///|
fn pdf_type1_append_number(output : Array[Int], value : Double) -> Unit {
  let integer = value.to_int()
  if value == integer.to_double() && integer >= -1131 && integer <= 1131 {
    if integer >= -107 && integer <= 107 {
      output.push(integer + 139)
    } else if integer >= 108 {
      let adjusted = integer - 108
      output.push(adjusted / 256 + 247)
      output.push(adjusted % 256)
    } else {
      let adjusted = -integer - 108
      output.push(adjusted / 256 + 251)
      output.push(adjusted % 256)
    }
  } else {
    // Type 1's extended number form is a signed 32-bit integer. Type 1
    // procedure sources overwhelmingly use integral design-space values; a
    // fractional value is conservatively rounded at this boundary.
    let integer = value.to_int()
    output.push(255)
    output.push((integer >> 24) & 255)
    output.push((integer >> 16) & 255)
    output.push((integer >> 8) & 255)
    output.push(integer & 255)
  }
}

///|
fn pdf_type1_operator_bytes(token : String) -> Array[Int]? {
  match token {
    "hstem" => Some([1])
    "vstem" => Some([3])
    "vmoveto" => Some([4])
    "rlineto" => Some([5])
    "hlineto" => Some([6])
    "vlineto" => Some([7])
    "rrcurveto" => Some([8])
    "closepath" => Some([9])
    "callsubr" => Some([10])
    "return" => Some([11])
    "hsbw" => Some([13])
    "endchar" => Some([14])
    "rmoveto" => Some([21])
    "hmoveto" => Some([22])
    "vhcurveto" => Some([30])
    "hvcurveto" => Some([31])
    "dotsection" => Some([12, 0])
    "vstem3" => Some([12, 1])
    "hstem3" => Some([12, 2])
    "seac" => Some([12, 6])
    "sbw" => Some([12, 7])
    "div" => Some([12, 12])
    "callothersubr" => Some([12, 16])
    "pop" => Some([12, 17])
    "setcurrentpoint" => Some([12, 33])
    _ => None
  }
}

///|
/// Compile the plain PostScript procedure form accepted by many Type 1
/// producers into the byte-oriented charstring form used by the interpreter.
fn pdf_type1_compile_procedure(
  scanner : PdfType1Scanner,
) -> Bytes? raise @core.PdfError {
  let output : Array[Int] = []
  while pdf_type1_next_token(scanner) is Some(token) {
    if token == "}" {
      return Some(@core.pdf_bytes_of_int_array(output))
    }
    match pdf_type1_parse_double(Some(token)) {
      Some(value) => pdf_type1_append_number(output, value)
      None =>
        match pdf_type1_operator_bytes(token) {
          Some(bytes) => output.append(bytes)
          None =>
            // Procedure wrappers such as `noaccess` are outside the body;
            // unknown operators make the glyph unsafe to interpret.
            return None
        }
    }
  }
  None
}

///|
fn pdf_type1_charstring_body(
  scanner : PdfType1Scanner,
  first : String,
  len_iv : Int,
) -> Bytes? raise @core.PdfError {
  if first == "{" {
    // Procedure form is already cleartext and does not use lenIV.
    pdf_type1_compile_procedure(scanner)
  } else {
    let length = match pdf_type1_parse_int(Some(first)) {
      Some(value) if value >= 0 && value <= scanner.data.length() => value
      _ => return None
    }
    ignore(pdf_type1_next_token(scanner)) // RD, -|, or a producer synonym
    match pdf_type1_read_binary(scanner, length) {
      Some(raw) => pdf_type1_decode_charstring(raw[:], len_iv)
      None => None
    }
  }
}

///|
fn pdf_type1_parse_program(
  data : BytesView,
  matrix : @geometry.TransformMatrix,
  builtin_encoding : Map[Int, String],
) -> PdfType1Font? raise @core.PdfError {
  let scanner = PdfType1Scanner::{ data, position: 0, }
  let charstrings : Map[String, Bytes] = Map([])
  let subrs : Array[Bytes?] = []
  let mut len_iv = 4
  let mut subrs_parsed = false
  let mut charstrings_parsed = false
  let mut budget = 0
  while budget < data.length() {
    budget += 1
    let token = match pdf_type1_next_token(scanner) {
      Some(value) => value
      None => break
    }
    if token != "/" {
      continue
    }
    let name = match pdf_type1_next_token(scanner) {
      Some(value) => value
      None => break
    }
    match name {
      "lenIV" if !charstrings_parsed && !subrs_parsed =>
        match pdf_type1_parse_int(pdf_type1_next_token(scanner)) {
          Some(value) => len_iv = value
          None => ()
        }
      "Subrs" if !subrs_parsed => {
        subrs_parsed = true
        let count = match pdf_type1_parse_int(pdf_type1_next_token(scanner)) {
          Some(value) if value >= 0 && value <= 65536 => value
          _ => continue
        }
        ignore(pdf_type1_next_token(scanner)) // array
        while pdf_type1_next_token(scanner) is Some(token) {
          if token == "/" {
            scanner.position -= 1
            break
          }
          if token != "dup" {
            if token == "noaccess" || token == "end" || token == "def" {
              break
            }
            continue
          }
          let index = pdf_type1_parse_int(pdf_type1_next_token(scanner))
          let first = match pdf_type1_next_token(scanner) {
            Some(value) => value
            None => break
          }
          let body = match pdf_type1_charstring_body(scanner, first, len_iv) {
            Some(value) => value
            None => break
          }
          match index {
            Some(index) if index >= 0 && index < count => {
              while subrs.length() <= index {
                subrs.push(None)
              }
              subrs[index] = Some(body)
            }
            _ => ()
          }
        }
      }
      "CharStrings" if !charstrings_parsed => {
        charstrings_parsed = true
        ignore(pdf_type1_next_token(scanner)) // count
        ignore(pdf_type1_next_token(scanner)) // dict
        ignore(pdf_type1_next_token(scanner)) // dup
        ignore(pdf_type1_next_token(scanner)) // begin
        let mut ended = false
        while !ended {
          match pdf_type1_next_token(scanner) {
            Some("end") | None => ended = true
            Some("/") => {
              let glyph_name = match pdf_type1_next_token(scanner) {
                Some(value) => value
                None => break
              }
              let first = match pdf_type1_next_token(scanner) {
                Some(value) => value
                None => break
              }
              match pdf_type1_charstring_body(scanner, first, len_iv) {
                Some(decoded) => charstrings[glyph_name] = decoded
                None => break
              }
            }
            Some(_) => ()
          }
        }
      }
      _ => ()
    }
  }
  if charstrings.is_empty() || len_iv < -1 || len_iv > 32 {
    None
  } else {
    Some({
      font_matrix: matrix,
      charstrings,
      subrs,
      builtin_encoding,
      outlines: Map([]),
    })
  }
}

///|
fn pdf_type1_parse_font(data : Bytes) -> PdfType1Font? raise @core.PdfError {
  let source = data[:]
  if pdf_type1_is_cid_keyed_source(source) {
    match pdf_type1_parse_cid_font(data) {
      Some(font) => return Some(font)
      None => ()
    }
  }
  let (header, eexec) = match pdf_type1_pfb_parts(source) {
    Some((header, encrypted)) => (header, encrypted)
    None => {
      let marker = match pdf_type1_find(source, "eexec", 0) {
        Some(value) => value
        None => return None
      }
      let encrypted = match pdf_type1_eexec_bytes(source, marker + 5) {
        Some(value) => value
        None => return None
      }
      let header_data : Array[Int] = []
      for byte in source[:marker] {
        header_data.push(byte.to_int())
      }
      let header = @core.pdf_bytes_of_int_array(header_data)
      (header, encrypted)
    }
  }
  let (font_matrix, builtin_encoding) = pdf_type1_header_properties(header[:])
  let decoded = match pdf_type1_decrypt(eexec[:], 55665, 4) {
    Some(value) => value
    None => return None
  }
  pdf_type1_parse_program(decoded[:], font_matrix, builtin_encoding)
}

///|
fn pdf_type1_push_glyph_name(names : Array[String], name : String) -> Bool {
  for existing in names {
    if existing == name {
      return false
    }
  }
  names.push(name)
  true
}

///|
fn pdf_type1_translate_command(
  command : PdfCffPathCommand,
  dx : Double,
  dy : Double,
) -> PdfCffPathCommand {
  match command {
    CffMove(x, y) => CffMove(x + dx, y + dy)
    CffLine(x, y) => CffLine(x + dx, y + dy)
    CffCurve(x1, y1, x2, y2, x, y) =>
      CffCurve(x1 + dx, y1 + dy, x2 + dx, y2 + dy, x + dx, y + dy)
    CffClose => CffClose
  }
}

///|
fn pdf_type1_run_glyph(
  font : PdfType1Font,
  glyph_name : String,
  state : Ref[PdfCffPathState],
  visited : Array[String],
  depth : Int,
) -> Bool {
  if depth > 10 || !pdf_type1_push_glyph_name(visited, glyph_name) {
    return false
  }
  match font.outlines.get(glyph_name) {
    Some(Some(commands)) => {
      state.val = {
        ..state.val,
        commands: [
          for command in commands => command
        ],
      }
      ignore(visited.remove(visited.length() - 1))
      return true
    }
    Some(None) => {
      ignore(visited.remove(visited.length() - 1))
      return false
    }
    None => ()
  }
  let code = match font.charstrings.get(glyph_name) {
    Some(value) => value
    None => {
      ignore(visited.remove(visited.length() - 1))
      font.outlines[glyph_name] = None
      return false
    }
  }
  let lsb = Ref(0.0)
  let flexing = Ref(false)
  let stack : Array[Double] = []
  let valid = pdf_type1_run_charstring(
    font, glyph_name, code, state, stack, lsb, flexing, visited, depth, false,
  )
  ignore(visited.remove(visited.length() - 1))
  if valid {
    font.outlines[glyph_name] = Some(state.val.commands)
  } else {
    font.outlines[glyph_name] = None
  }
  valid
}

///|
fn pdf_type1_run_charstring(
  font : PdfType1Font,
  glyph_name : String,
  code : Bytes,
  state : Ref[PdfCffPathState],
  stack : Array[Double],
  lsb : Ref[Double],
  flexing : Ref[Bool],
  visited : Array[String],
  depth : Int,
  subroutine : Bool,
) -> Bool {
  if depth > 10 {
    return false
  }
  let bytes = code[:]
  let mut offset = 0
  let budget = state.val.budget
  while offset < bytes.length() {
    budget.val -= 1
    if budget.val < 0 {
      return false
    }
    let byte = bytes[offset].to_int()
    if byte >= 32 {
      offset += 1
      let value : Double? = if byte <= 246 {
        Some((byte - 139).to_double())
      } else if byte <= 250 {
        if offset >= bytes.length() {
          None
        } else {
          let result = (byte - 247) * 256 + bytes[offset].to_int() + 108
          offset += 1
          Some(result.to_double())
        }
      } else if byte <= 254 {
        if offset >= bytes.length() {
          None
        } else {
          let result = -((byte - 251) * 256) - bytes[offset].to_int() - 108
          offset += 1
          Some(result.to_double())
        }
      } else if offset <= bytes.length() - 4 {
        match pdf_cff_i32(bytes[:], offset) {
          Some(result) => {
            offset += 4
            Some(result.to_double())
          }
          None => None
        }
      } else {
        None
      }
      match value {
        Some(value) if !value.is_nan() && !value.is_inf() => {
          stack.push(value)
          if stack.length() > 48 {
            return false
          }
        }
        _ => return false
      }
      continue
    }
    offset += 1
    let operator = if byte == 12 {
      if offset >= bytes.length() {
        return false
      }
      let escaped = bytes[offset].to_int()
      offset += 1
      0x0C00 | escaped
    } else {
      byte
    }
    let current = state.val
    match operator {
      1 | 3 | 0x0C01 | 0x0C02 => stack.clear()
      4 => {
        if stack.length() < 1 {
          return false
        }
        if flexing.val {
          let dy = stack.remove(stack.length() - 1)
          stack.push(0.0)
          stack.push(dy)
        } else {
          if stack.length() != 1 {
            return false
          }
          let dy = stack[stack.length() - 1]
          state.val = pdf_cff_move(state.val, 0.0, dy)
          stack.clear()
        }
      }
      5 => {
        if !current.has_subpath || stack.length() < 2 || stack.length() % 2 != 0 {
          return false
        }
        for index in 0..<(stack.length() / 2) {
          state.val = pdf_cff_line(
            state.val,
            stack[index * 2],
            stack[index * 2 + 1],
          )
        }
        stack.clear()
      }
      6 | 7 => {
        if !current.has_subpath || stack.is_empty() {
          return false
        }
        let mut horizontal = operator == 6
        for delta in stack {
          state.val = if horizontal {
            pdf_cff_line(state.val, delta, 0.0)
          } else {
            pdf_cff_line(state.val, 0.0, delta)
          }
          horizontal = !horizontal
        }
        stack.clear()
      }
      8 => {
        if !current.has_subpath || stack.length() < 6 || stack.length() % 6 != 0 {
          return false
        }
        for index in 0..<(stack.length() / 6) {
          let base = index * 6
          state.val = pdf_cff_curve(
            state.val,
            stack[base],
            stack[base + 1],
            stack[base + 2],
            stack[base + 3],
            stack[base + 4],
            stack[base + 5],
          )
        }
        stack.clear()
      }
      9 => {
        state.val = pdf_cff_close_subpath(state.val)
        stack.clear()
      }
      10 => {
        if stack.is_empty() {
          return false
        }
        let value = stack.remove(stack.length() - 1)
        let index = value.to_int()
        if value != index.to_double() ||
          index < 0 ||
          index >= font.subrs.length() {
          return false
        }
        let subr = match font.subrs[index] {
          Some(value) => value
          None => return false
        }
        if !pdf_type1_run_charstring(
            font,
            glyph_name,
            subr,
            state,
            stack,
            lsb,
            flexing,
            visited,
            depth + 1,
            true,
          ) {
          return false
        }
      }
      11 => return subroutine
      13 => {
        if stack.length() < 2 {
          return false
        }
        let side = stack[stack.length() - 2]
        stack.clear()
        lsb.val = side
        // hsbw establishes the current point; it does not paint a move.
        state.val = { ..state.val, x: side, y: 0.0, has_subpath: false, }
      }
      14 => {
        // Type 1 producers sometimes leave width or hinting operands on the
        // stack before endchar. PDF.js discards those operands while emitting
        // the terminator; rejecting the glyph here makes an otherwise valid
        // outline fall back to a host font.
        stack.clear()
        return true
      }
      21 => {
        if stack.length() < 2 {
          return false
        }
        if !flexing.val {
          let base = stack.length() - 2
          state.val = pdf_cff_move(state.val, stack[base], stack[base + 1])
          stack.clear()
        }
      }
      22 => {
        if stack.is_empty() {
          return false
        }
        if flexing.val {
          stack.push(0.0)
        } else {
          state.val = pdf_cff_move(state.val, stack[stack.length() - 1], 0.0)
          stack.clear()
        }
      }
      30 | 31 => {
        if !current.has_subpath ||
          stack.length() < 4 ||
          (stack.length() % 4 != 0 && stack.length() % 4 != 1) {
          return false
        }
        let mut horizontal = operator == 31
        let mut index = 0
        while index + 3 < stack.length() {
          let last_extra = index + 4 == stack.length() - 1
          if horizontal {
            let dx3 = if last_extra { stack[index + 4] } else { 0.0 }
            state.val = pdf_cff_curve(
              state.val,
              stack[index],
              0.0,
              stack[index + 1],
              stack[index + 2],
              dx3,
              stack[index + 3],
            )
          } else {
            let dy3 = if last_extra { stack[index + 4] } else { 0.0 }
            state.val = pdf_cff_curve(
              state.val,
              0.0,
              stack[index],
              stack[index + 1],
              stack[index + 2],
              stack[index + 3],
              dy3,
            )
          }
          index += 4
          horizontal = !horizontal
        }
        stack.clear()
      }
      0x0C06 => {
        if stack.length() < 5 {
          return false
        }
        let base = stack.length() - 5
        let asb = stack[base]
        let dx = stack[base + 1] + lsb.val - asb
        let dy = stack[base + 2]
        let base_code = stack[base + 3].to_int()
        let accent_code = stack[base + 4].to_int()
        if stack[base + 3] != base_code.to_double() ||
          stack[base + 4] != accent_code.to_double() {
          return false
        }
        let base_name = match pdf_cff_standard_encoding.get(base_code) {
          Some(value) if value != "" => value
          _ => return false
        }
        let accent_name = match pdf_cff_standard_encoding.get(accent_code) {
          Some(value) if value != "" => value
          _ => return false
        }
        stack.clear()
        let base_state = Ref(pdf_cff_new_state(state.val.budget))
        if !pdf_type1_run_glyph(font, base_name, base_state, visited, depth + 1) {
          return false
        }
        let accent_state = Ref(pdf_cff_new_state(state.val.budget))
        if !pdf_type1_run_glyph(
            font,
            accent_name,
            accent_state,
            visited,
            depth + 1,
          ) {
          return false
        }
        state.val.commands.append(base_state.val.commands)
        for command in accent_state.val.commands {
          state.val.commands.push(pdf_type1_translate_command(command, dx, dy))
        }
        state.val = {
          ..state.val,
          x: accent_state.val.x + dx,
          y: accent_state.val.y + dy,
          has_subpath: false,
        }
        return true
      }
      0x0C07 => {
        if stack.length() < 4 {
          return false
        }
        let base = stack.length() - 4
        let side_x = stack[base]
        let side_y = stack[base + 1]
        stack.clear()
        lsb.val = side_x
        // sbw establishes the current point without adding a visible path.
        state.val = { ..state.val, x: side_x, y: side_y, has_subpath: false, }
      }
      0x0C0C => {
        if stack.length() < 2 {
          return false
        }
        let base = stack.length() - 2
        let denominator = stack[base + 1]
        if denominator == 0.0 {
          return false
        }
        let result = stack[base] / denominator
        ignore(stack.remove(stack.length() - 1))
        stack[stack.length() - 1] = result
      }
      0x0C10 => {
        if stack.length() < 2 {
          return false
        }
        let othersubr = stack[stack.length() - 1].to_int()
        let count = stack[stack.length() - 2].to_int()
        if count < 0 || count > stack.length() - 2 {
          return false
        }
        if othersubr == 1 && count == 0 {
          flexing.val = true
          stack.clear()
        } else if othersubr == 0 && count == 3 {
          let args_end = stack.length() - 2
          if args_end < 17 || !state.val.has_subpath {
            return false
          }
          let args = stack[args_end - 17:args_end]
          let a = args.length() - 17
          let rpx = args[a]
          let rpy = args[a + 1]
          let bcp1x = args[a + 2]
          let bcp1y = args[a + 3]
          let bcp2x = args[a + 4]
          let bcp2y = args[a + 5]
          let p2x = args[a + 6]
          let p2y = args[a + 7]
          let bcp3x = args[a + 8]
          let bcp3y = args[a + 9]
          let bcp4x = args[a + 10]
          let bcp4y = args[a + 11]
          let p3x = args[a + 12]
          let p3y = args[a + 13]
          let final_x = args[a + 15]
          let final_y = args[a + 16]
          state.val = pdf_cff_curve(
            state.val,
            rpx + bcp1x,
            rpy + bcp1y,
            bcp2x - bcp1x - rpx,
            bcp2y - bcp1y - rpy,
            p2x - bcp2x,
            p2y - bcp2y,
          )
          state.val = pdf_cff_curve(
            state.val,
            bcp3x - p2x,
            bcp3y - p2y,
            bcp4x - bcp3x,
            bcp4y - bcp3y,
            p3x - bcp4x,
            p3y - bcp4y,
          )
          state.val = {
            ..state.val,
            x: state.val.x + final_x - p3x,
            y: state.val.y + final_y - p3y,
          }
          flexing.val = false
          stack.clear()
        } else {
          stack.clear()
        }
      }
      0x0C11 => ()
      0x0C21 =>
        // setcurrentpoint is a hinting-era Type 1 operator. PDF.js ignores
        // it for outline conversion and clears its operands; changing the
        // current point here can shift all following contours.
        stack.clear()
      _ => return false
    }
  }
  subroutine
}

///|
fn pdf_type1_glyph_name(
  document : @pdflite.PdfDocument,
  font : PdfType1Font,
  pdf_font : @pdflite.PdfFont,
  charcode : Int,
) -> String? {
  match pdf_font {
    @pdflite.PdfFontCIDKeyed(cid_font) =>
      match
        pdf_viewer_cid_of_charcode_with_document(document, cid_font, charcode) {
        Some(cid) if cid >= 0 => {
          let name = if cid == 0 { ".notdef" } else { "cid" + cid.to_string() }
          match font.charstrings.get(name) {
            Some(_) => Some(name)
            None => None
          }
        }
        _ => None
      }
    @pdflite.PdfFontSimple(simple) => {
      let name = for (code, value) in simple.encoding.table() {
        if code == charcode {
          let decoded = @utf8.decode(value.bytes()[:]) catch { _ => "" }
          break Some(decoded.strip_prefix("/").unwrap_or(decoded[:]).to_owned())
        }
      } nobreak {
        None
      }
      match name {
        Some(value) => Some(value)
        None => pdf_type1_fallback_glyph_name(font, simple, charcode)
      }
    }
    _ => None
  }
}

///|
fn pdf_type1_fallback_glyph_name(
  font : PdfType1Font,
  simple : @pdflite.PdfSimpleFont,
  charcode : Int,
) -> String? {
  let symbolic = match simple.fontdescriptor {
    Some(descriptor) => (descriptor.flags & 4) != 0
    None => false
  }
  match simple.encoding {
    @pdflite.PdfEncoding::PdfImplicitInFontFile =>
      if symbolic {
        font.builtin_encoding.get(charcode)
      } else {
        pdf_cff_standard_encoding.get(charcode)
      }
    @pdflite.PdfEncoding::PdfCustomEncoding(base, _) =>
      match base {
        @pdflite.PdfEncoding::PdfImplicitInFontFile =>
          if symbolic {
            font.builtin_encoding.get(charcode)
          } else {
            pdf_cff_standard_encoding.get(charcode)
          }
        _ => pdf_type1_encoding_name(base, charcode)
      }
    @pdflite.PdfEncoding::PdfFillUndefinedWithStandard(base) =>
      match pdf_type1_encoding_name(base, charcode) {
        Some(value) => Some(value)
        None => pdf_cff_standard_encoding.get(charcode)
      }
    _ => pdf_cff_standard_encoding.get(charcode)
  }
}

///|
fn pdf_type1_encoding_name(
  encoding : @pdflite.PdfEncoding,
  charcode : Int,
) -> String? {
  for (code, name) in encoding.table() {
    if code == charcode {
      let decoded = @utf8.decode(name.bytes()[:]) catch { _ => "" }
      return Some(decoded.strip_prefix("/").unwrap_or(decoded[:]).to_owned())
    }
  }
  None
}

///|
fn pdf_type1_outline_path(
  font : PdfType1Font,
  glyph_name : String,
  glyph_matrix : @geometry.TransformMatrix,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
) -> String? {
  let commands = match font.outlines.get(glyph_name) {
    Some(Some(value)) => value
    Some(None) => return None
    None => {
      let state = Ref(pdf_cff_new_state(Ref(100000)))
      if !pdf_type1_run_glyph(font, glyph_name, state, [], 0) {
        font.outlines[glyph_name] = None
        return None
      }
      font.outlines[glyph_name] = Some(state.val.commands)
      state.val.commands
    }
  }
  if commands.is_empty() {
    return Some("")
  }
  let matrix = @geometry.transform_matrix_compose(
    glyph_matrix,
    font.font_matrix,
  )
  for value in [matrix.a, matrix.b, matrix.c, matrix.d, matrix.e, matrix.f] {
    if value.is_nan() || value.is_inf() {
      return None
    }
  }
  let path = pdf_cff_svg_path(
    commands[:],
    matrix,
    origin_x,
    origin_y,
    page_height,
  )
  if path == "" {
    None
  } else {
    Some(path)
  }
}

///|
fn pdf_type1_paint_path(
  path : String,
  rendering_mode : Int,
  fill_color : String,
  stroke_color : String,
  fill_alpha : Double,
  stroke_alpha : Double,
) -> String {
  let fill = if pdf_text_mode_fills(rendering_mode) {
    fill_color
  } else {
    "none"
  }
  let stroke = if pdf_text_mode_strokes(rendering_mode) {
    stroke_color
  } else {
    "none"
  }
  let stroke_width = if stroke == "none" { 0.0 } else { 1.0 }
  "<path d=\"" +
  pdf_escape_xml(path) +
  "\" fill=\"" +
  pdf_escape_xml(fill) +
  "\" stroke=\"" +
  pdf_escape_xml(stroke) +
  "\" stroke-width=\"" +
  stroke_width.to_string() +
  "\" fill-opacity=\"" +
  fill_alpha.to_string() +
  "\" stroke-opacity=\"" +
  stroke_alpha.to_string() +
  "\" data-pdf-font-outline=\"type1\"/>"
}

///|
fn pdf_type1_path_of_pdf_glyph(
  document : @pdflite.PdfDocument,
  pdf_font : @pdflite.PdfFont,
  fonts : Map[Int, PdfType1Font?],
  charcode : Int,
  glyph_matrix : @geometry.TransformMatrix?,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
) -> String? {
  let glyph_matrix = match glyph_matrix {
    Some(value) => value
    None => return None
  }
  let number = match pdf_font.embedded_fontfile_number() {
    Some(value) => value
    None => return None
  }
  let font = match fonts.get(number) {
    Some(Some(value)) => value
    Some(None) => return None
    None => {
      let parsed = try {
        let bytes = document
          .pdf_decode_stream(@syntax.PdfIndirect(number))
          .stream_bytes()
        pdf_type1_parse_font(bytes)
      } catch {
        _ => None
      }
      fonts[number] = parsed
      match parsed {
        Some(value) => value
        None => return None
      }
    }
  }
  let glyph_name = match
    pdf_type1_glyph_name(document, font, pdf_font, charcode) {
    Some(value) => value
    None => return None
  }
  pdf_type1_outline_path(
    font, glyph_name, glyph_matrix, origin_x, origin_y, page_height,
  )
}

///|
fn pdf_type1_outline_of_pdf_glyph(
  document : @pdflite.PdfDocument,
  pdf_font : @pdflite.PdfFont,
  fonts : Map[Int, PdfType1Font?],
  charcode : Int,
  glyph_matrix : @geometry.TransformMatrix?,
  rendering_mode : Int,
  fill_color : String,
  stroke_color : String,
  fill_alpha : Double,
  stroke_alpha : Double,
  origin_x : Double,
  origin_y : Double,
  page_height : Double,
) -> String? {
  match
    pdf_type1_path_of_pdf_glyph(
      document, pdf_font, fonts, charcode, glyph_matrix, origin_x, origin_y, page_height,
    ) {
    Some("") => Some("")
    Some(path) =>
      Some(
        pdf_type1_paint_path(
          path, rendering_mode, fill_color, stroke_color, fill_alpha, stroke_alpha,
        ),
      )
    None => None
  }
}

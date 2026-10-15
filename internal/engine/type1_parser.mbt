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

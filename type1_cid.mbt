///|
/// Metadata and offsets declared by a CID-keyed Type 1 PostScript header.
priv struct PdfType1CidHeader {
  font_matrix : @geometry.TransformMatrix
  cid_count : Int
  cid_map_offset : Int
  fd_bytes : Int
  gd_bytes : Int
  subr_map_offset : Int
  sd_bytes : Int
  subr_count : Int
  len_iv : Int
  start_data_length : Int
  start_data_hex : Bool
}

///|
fn pdf_type1_cid_default_header() -> PdfType1CidHeader {
  {
    font_matrix: { a: 0.001, b: 0.0, c: 0.0, d: 0.001, e: 0.0, f: 0.0, },
    cid_count: 0,
    cid_map_offset: -1,
    fd_bytes: 1,
    gd_bytes: 0,
    subr_map_offset: -1,
    sd_bytes: 0,
    subr_count: 0,
    len_iv: 4,
    start_data_length: 0,
    start_data_hex: false,
  }
}

///|
fn pdf_type1_cid_number_array(scanner : PdfType1Scanner) -> Array[Double] {
  if pdf_type1_next_token(scanner) != Some("[") {
    return []
  }
  let output : Array[Double] = []
  while output.length() < 6 {
    match pdf_type1_parse_double(pdf_type1_next_token(scanner)) {
      Some(value) => output.push(value)
      None => break
    }
  }
  ignore(pdf_type1_next_token(scanner))
  output
}

///|
fn pdf_type1_cid_remember_token(tokens : Array[String], token : String) -> Unit {
  tokens.push(token)
  if tokens.length() > 4 {
    ignore(tokens.remove(0))
  }
}

///|
fn pdf_type1_cid_start_data_header(
  data : BytesView,
) -> (PdfType1CidHeader, Int)? {
  let scanner = PdfType1Scanner::{ data, position: 0, }
  let mut header = pdf_type1_cid_default_header()
  let previous : Array[String] = []
  while pdf_type1_next_token(scanner) is Some(token) {
    if token == "StartData" {
      if previous.length() != 4 ||
        previous[0] != "(" ||
        previous[2] != ")" ||
        (previous[1] != "Binary" && previous[1] != "Hex") {
        return None
      }
      for char in previous[3].iter() {
        if char < '0' || char > '9' {
          return None
        }
      }
      let length = match pdf_type1_parse_int(Some(previous[3])) {
        Some(value) => value
        None => return None
      }
      if length <= 0 {
        return None
      }
      header = {
        ..header,
        start_data_length: length,
        start_data_hex: previous[1] == "Hex",
      }
      return Some((header, scanner.position))
    }
    pdf_type1_cid_remember_token(previous, token)
    if token != "/" {
      continue
    }
    let name = match pdf_type1_next_token(scanner) {
      Some(value) => value
      None => break
    }
    pdf_type1_cid_remember_token(previous, name)
    match name {
      "FontMatrix" => {
        let values = pdf_type1_cid_number_array(scanner)
        if values.length() == 6 {
          header = {
            ..header,
            font_matrix: {
              a: values[0],
              b: values[1],
              c: values[2],
              d: values[3],
              e: values[4],
              f: values[5],
            },
          }
        }
      }
      "CIDCount" =>
        match pdf_type1_parse_int(pdf_type1_next_token(scanner)) {
          Some(value) => header = { ..header, cid_count: value, }
          None => ()
        }
      "CIDMapOffset" =>
        match pdf_type1_parse_int(pdf_type1_next_token(scanner)) {
          Some(value) => header = { ..header, cid_map_offset: value, }
          None => ()
        }
      "FDArray" =>
        if pdf_type1_parse_int(pdf_type1_next_token(scanner)) != Some(1) ||
          pdf_type1_next_token(scanner) != Some("array") {
          // Reading more than one private dictionary would mix lenIV/subrs.
          return None
        }
      "FDBytes" =>
        match pdf_type1_parse_int(pdf_type1_next_token(scanner)) {
          Some(value) => header = { ..header, fd_bytes: value, }
          None => ()
        }
      "GDBytes" =>
        match pdf_type1_parse_int(pdf_type1_next_token(scanner)) {
          Some(value) => header = { ..header, gd_bytes: value, }
          None => ()
        }
      "SubrMapOffset" =>
        match pdf_type1_parse_int(pdf_type1_next_token(scanner)) {
          Some(value) => header = { ..header, subr_map_offset: value, }
          None => ()
        }
      "SDBytes" =>
        match pdf_type1_parse_int(pdf_type1_next_token(scanner)) {
          Some(value) => header = { ..header, sd_bytes: value, }
          None => ()
        }
      "SubrCount" =>
        match pdf_type1_parse_int(pdf_type1_next_token(scanner)) {
          Some(value) => header = { ..header, subr_count: value, }
          None => ()
        }
      "lenIV" =>
        match pdf_type1_parse_int(pdf_type1_next_token(scanner)) {
          Some(value) => header = { ..header, len_iv: value, }
          None => ()
        }
      _ => ()
    }
  }
  None
}

///|
fn pdf_type1_cid_data_after_separator(data : BytesView, position : Int) -> Int? {
  if position < 0 || position > data.length() {
    return None
  }
  if position >= data.length() {
    return Some(position)
  }
  if !pdf_type1_is_space(data[position].to_int()) {
    return Some(position)
  }
  let mut cursor = position + 1
  if data[position].to_int() == 13 &&
    cursor < data.length() &&
    data[cursor].to_int() == 10 {
    cursor += 1
  }
  Some(cursor)
}

///|
fn pdf_type1_cid_start_data_bytes(
  data : BytesView,
  position : Int,
  declared_length : Int,
  is_hex : Bool,
) -> Bytes? raise @core.PdfError {
  let first = match pdf_type1_cid_data_after_separator(data, position) {
    Some(value) => value
    None => return None
  }
  if declared_length <= 0 || first > data.length() {
    return None
  }
  if !is_hex {
    let available = data.length() - first
    let length = if declared_length > available {
      available
    } else {
      declared_length
    }
    let output : Array[Int] = []
    for byte in data[first:first + length] {
      output.push(byte.to_int())
    }
    return Some(@core.pdf_bytes_of_int_array(output))
  }
  if declared_length > (data.length() - first) / 2 {
    return None
  }
  let output : Array[Int] = Array(capacity=declared_length)
  let mut high : Int? = None
  for byte in data[first:] {
    let value = byte.to_int()
    match pdf_type1_hex_value(value) {
      Some(nibble) =>
        match high {
          Some(previous) => {
            output.push((previous << 4) | nibble)
            high = None
            if output.length() == declared_length {
              break
            }
          }
          None => high = Some(nibble)
        }
      None => ()
    }
  }
  if output.length() != declared_length {
    return None
  }
  Some(@core.pdf_bytes_of_int_array(output))
}

///|
fn pdf_type1_cid_read_uint(data : BytesView, offset : Int, width : Int) -> Int? {
  if width < 0 ||
    width > 4 ||
    offset < 0 ||
    offset > data.length() ||
    width > data.length() - offset {
    return None
  }
  if width == 4 && data[offset].to_int() >= 0x80 {
    // Byte offsets must fit the signed Int used by BytesView slicing.
    return None
  }
  let mut value = 0
  for byte in data[offset:offset + width] {
    value = (value << 8) | byte.to_int()
  }
  Some(value)
}

///|
fn pdf_type1_cid_empty_charstring() -> Bytes raise @core.PdfError {
  // A zero-width endchar is the same fallback used by pdf.js for missing CIDs.
  @core.pdf_bytes_of_int_array([14])
}

///|
/// Parse the binary program described by Adobe TechNote 5014.
fn pdf_type1_parse_cid_font(data : Bytes) -> PdfType1Font? raise @core.PdfError {
  let source = data[:]
  let (header, position) = match pdf_type1_cid_start_data_header(source) {
    Some(value) => value
    None => return None
  }
  if header.cid_count <= 0 ||
    header.cid_map_offset < 0 ||
    header.fd_bytes < 0 ||
    header.fd_bytes > 4 ||
    header.gd_bytes < 1 ||
    header.gd_bytes > 4 ||
    header.len_iv < -1 ||
    header.len_iv > 32 ||
    header.subr_count < 0 {
    return None
  }
  let binary = match
    pdf_type1_cid_start_data_bytes(
      source,
      position,
      header.start_data_length,
      header.start_data_hex,
    ) {
    Some(value) => value
    None => return None
  }
  let bytes = binary[:]
  let entry_size = header.fd_bytes + header.gd_bytes
  if entry_size <= 0 ||
    header.cid_map_offset > bytes.length() ||
    header.cid_count >= (bytes.length() - header.cid_map_offset) / entry_size {
    return None
  }
  if header.fd_bytes > 0 {
    for cid in 0..<header.cid_count {
      let fd = match
        pdf_type1_cid_read_uint(
          bytes,
          header.cid_map_offset + cid * entry_size,
          header.fd_bytes,
        ) {
        Some(value) => value
        None => return None
      }
      if fd != 0 {
        // Multiple FDArray entries need different private dictionaries/subrs.
        return None
      }
    }
  }

  let subrs : Array[Bytes?] = []
  if header.subr_count > 0 {
    if header.subr_map_offset < 0 ||
      header.sd_bytes < 1 ||
      header.sd_bytes > 4 ||
      header.subr_map_offset > bytes.length() ||
      header.subr_count >=
      (bytes.length() - header.subr_map_offset) / header.sd_bytes {
      return None
    }
    let offsets : Array[Int] = []
    for index in 0..<=header.subr_count {
      let offset = match
        pdf_type1_cid_read_uint(
          bytes,
          header.subr_map_offset + index * header.sd_bytes,
          header.sd_bytes,
        ) {
        Some(value) => value
        None => return None
      }
      offsets.push(offset)
    }
    for index in 0..<header.subr_count {
      let start = offsets[index]
      let end = offsets[index + 1]
      if start > end || start > bytes.length() || end > bytes.length() {
        subrs.push(Some(@core.pdf_bytes_of_int_array([])))
        continue
      }
      let decoded = match
        pdf_type1_decode_charstring(bytes[start:end], header.len_iv) {
        Some(value) => value
        None => {
          subrs.push(Some(@core.pdf_bytes_of_int_array([])))
          continue
        }
      }
      subrs.push(Some(decoded))
    }
  }

  let charstrings : Map[String, Bytes] = Map([])
  let fallback = pdf_type1_cid_empty_charstring()
  let mut previous_offset = match
    pdf_type1_cid_read_uint(
      bytes,
      header.cid_map_offset + header.fd_bytes,
      header.gd_bytes,
    ) {
    Some(value) => value
    None => return None
  }
  for cid in 0..<header.cid_count {
    let next_offset = match
      pdf_type1_cid_read_uint(
        bytes,
        header.cid_map_offset + (cid + 1) * entry_size + header.fd_bytes,
        header.gd_bytes,
      ) {
      Some(value) => value
      None => return None
    }
    let name = if cid == 0 { ".notdef" } else { "cid" + cid.to_string() }
    if next_offset > previous_offset && next_offset <= bytes.length() {
      let decoded = match
        pdf_type1_decode_charstring(
          bytes[previous_offset:next_offset],
          header.len_iv,
        ) {
        Some(value) => value
        None => return None
      }
      charstrings[name] = decoded
    } else {
      charstrings[name] = match charstrings.get(".notdef") {
        Some(value) => value
        None => fallback
      }
    }
    previous_offset = next_offset
  }
  Some({
    font_matrix: header.font_matrix,
    charstrings,
    subrs,
    builtin_encoding: Map([]),
    outlines: Map([]),
  })
}

///|
fn pdf_type1_is_cid_keyed_source(data : BytesView) -> Bool {
  if data.length() < 2 || data[0].to_int() != 0x25 || data[1].to_int() != 0x21 {
    return false
  }
  let limit = if data.length() > 2048 { 2048 } else { data.length() }
  pdf_type1_find(data[:limit], "Resource-CIDFont", 0) is Some(_) ||
  pdf_type1_find(data[:limit], "/CIDFontType", 0) is Some(_)
}
